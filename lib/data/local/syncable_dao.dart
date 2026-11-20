import 'dart:convert';

import 'package:sqflite_common/sqlite_api.dart';

import '../../core/utils/clock.dart';
import '../models/enums.dart';
import 'sync_tables.dart';

/// Generic local persistence for a synced table. Every write goes through
/// here so sync bookkeeping (updated_at, sync_status, soft deletion) is
/// applied uniformly and can never be forgotten by a repository.
class SyncableDao {
  SyncableDao(this.db, this.spec, this.clock);

  final Database db;
  final SyncTableSpec spec;
  final Clock clock;

  String get table => spec.table;

  /// Status for a locally modified row. A row that has never been agreed with
  /// the cloud (no sync_base) is still a create, whatever happens to it.
  static SyncStatus localStatus({required bool deleted, required bool everSynced}) {
    if (deleted) return SyncStatus.pendingDelete;
    return everSynced ? SyncStatus.pendingUpdate : SyncStatus.pendingCreate;
  }

  Future<Map<String, Object?>?> find(String id, {DatabaseExecutor? exec}) async {
    final rows = await (exec ?? db).query(table, where: 'id = ?', whereArgs: [id], limit: 1);
    return rows.isEmpty ? null : Map<String, Object?>.from(rows.first);
  }

  /// Inserts a brand-new local record (pendingCreate).
  Future<void> insertNew(Map<String, Object?> row, {DatabaseExecutor? exec}) async {
    final data = Map<String, Object?>.from(row)
      ..['sync_status'] = SyncStatus.pendingCreate.name
      ..['sync_base'] = null;
    await (exec ?? db).insert(table, data, conflictAlgorithm: ConflictAlgorithm.abort);
  }

  /// Inserts or overwrites a record's content as a local edit, preserving its
  /// sync history (used by edits that replace a whole entity and by restore).
  Future<void> saveLocal(Map<String, Object?> row, {DatabaseExecutor? exec}) async {
    final executor = exec ?? db;
    final id = row['id'] as String;
    final existing = await find(id, exec: executor);
    final now = clock.nowMs();
    final data = Map<String, Object?>.from(row)..['updated_at'] = now;
    if (existing == null) {
      data['created_at'] ??= now;
      data['sync_status'] = SyncStatus.pendingCreate.name;
      data['sync_base'] = null;
      await executor.insert(table, data);
      return;
    }
    data.remove('sync_base');
    data['created_at'] = existing['created_at'];
    data['sync_status'] = localStatus(
      deleted: data['deleted_at'] != null,
      everSynced: existing['sync_base'] != null,
    ).name;
    await executor.update(table, data, where: 'id = ?', whereArgs: [id]);
  }

  /// Applies a partial local edit.
  Future<void> updateFields(String id, Map<String, Object?> changes, {DatabaseExecutor? exec}) async {
    final executor = exec ?? db;
    final existing = await find(id, exec: executor);
    if (existing == null) throw StateError('$table/$id not found');
    final deleted = changes.containsKey('deleted_at')
        ? changes['deleted_at'] != null
        : existing['deleted_at'] != null;
    final data = Map<String, Object?>.from(changes)
      ..remove('id')
      ..remove('created_at')
      ..remove('sync_base')
      ..['updated_at'] = clock.nowMs()
      ..['sync_status'] = localStatus(deleted: deleted, everSynced: existing['sync_base'] != null).name;
    await executor.update(table, data, where: 'id = ?', whereArgs: [id]);
  }

  /// Soft delete: the tombstone is uploaded so other devices learn about it.
  Future<void> softDelete(String id, {DatabaseExecutor? exec}) =>
      updateFields(id, {'deleted_at': clock.nowMs()}, exec: exec);

  // ---------------------------------------------------------------------------
  // Sync support
  // ---------------------------------------------------------------------------

  Future<List<Map<String, Object?>>> pending({int limit = 200}) async {
    final rows = await db.query(
      table,
      where: 'sync_status != ?',
      whereArgs: [SyncStatus.synced.name],
      orderBy: 'updated_at ASC',
      limit: limit,
    );
    return rows.map((r) => Map<String, Object?>.from(r)).toList();
  }

  Future<int> pendingCount() async {
    final r = await db.rawQuery(
      'SELECT COUNT(*) AS c FROM $table WHERE sync_status != ?',
      [SyncStatus.synced.name],
    );
    return (r.first['c'] as num?)?.toInt() ?? 0;
  }

  /// Marks a row as synced only if it wasn't edited while the upload was in
  /// flight (optimistic check on updated_at). Returns whether it was marked.
  Future<bool> markSynced(String id, int uploadedUpdatedAt, Map<String, Object?> content) async {
    final count = await db.update(
      table,
      {
        'sync_status': SyncStatus.synced.name,
        'sync_base': jsonEncode(content),
      },
      where: 'id = ? AND updated_at = ?',
      whereArgs: [id, uploadedUpdatedAt],
    );
    return count > 0;
  }

  Future<void> markFailed(Iterable<String> ids) async {
    if (ids.isEmpty) return;
    final list = ids.toList();
    final placeholders = List.filled(list.length, '?').join(',');
    await db.rawUpdate(
      'UPDATE $table SET sync_status = ? WHERE id IN ($placeholders)',
      [SyncStatus.failed.name, ...list],
    );
  }

  /// Writes the result of applying a cloud record.
  Future<void> writeFromSync({
    required Map<String, Object?> content,
    required Map<String, Object?> base,
    required SyncStatus status,
    required bool exists,
    DatabaseExecutor? exec,
  }) async {
    final executor = exec ?? db;
    final data = Map<String, Object?>.from(content)
      ..['sync_status'] = status.name
      ..['sync_base'] = jsonEncode(base);
    if (exists) {
      await executor.update(table, data, where: 'id = ?', whereArgs: [content['id']]);
    } else {
      await executor.insert(table, data, conflictAlgorithm: ConflictAlgorithm.replace);
    }
  }

  static Map<String, Object?>? decodeBase(Object? raw) {
    if (raw is! String || raw.isEmpty) return null;
    final decoded = jsonDecode(raw);
    return decoded is Map ? Map<String, Object?>.from(decoded) : null;
  }

  /// Assigns rows created before login to the signed-in user.
  Future<int> claimForUser(String userId) =>
      db.rawUpdate('UPDATE $table SET user_id = ? WHERE user_id IS NULL', [userId]);
}
