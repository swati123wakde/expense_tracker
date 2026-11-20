import 'package:sqflite_common/sqlite_api.dart';

import '../../core/services/data_change_bus.dart';
import '../../core/utils/clock.dart';
import '../../core/utils/id_generator.dart';
import '../local/sync_tables.dart';
import '../local/syncable_dao.dart';
import '../models/goal.dart';
import 'current_user.dart';

class GoalRepository {
  GoalRepository(this._db, this._bus, this._user, this._clock)
      : dao = SyncableDao(_db, SyncTables.goals, _clock);

  final Database _db;
  final DataChangeBus _bus;
  final CurrentUser _user;
  final Clock _clock;
  final SyncableDao dao;

  String get _table => SyncTables.goals.table;

  Future<List<GoalEntity>> all() async {
    final rows = await _db.query(
      _table,
      where: 'deleted_at IS NULL',
      orderBy: 'CASE WHEN saved_minor >= target_minor THEN 1 ELSE 0 END, target_date IS NULL, target_date ASC',
    );
    return rows.map(GoalEntity.fromRow).toList();
  }

  Future<GoalEntity> create({
    required String name,
    required int targetMinor,
    int savedMinor = 0,
    DateTime? targetDate,
    required String icon,
    required int color,
  }) async {
    _validate(name, targetMinor, savedMinor);
    final now = _clock.now();
    final goal = GoalEntity(
      id: IdGenerator.newId(),
      userId: _user.id,
      name: name.trim(),
      targetMinor: targetMinor,
      savedMinor: savedMinor,
      targetDate: targetDate,
      icon: icon,
      color: color,
      createdAt: now,
      updatedAt: now,
    );
    await dao.insertNew(goal.toRow());
    _bus.emit({_table});
    return goal;
  }

  Future<void> update(
    String id, {
    required String name,
    required int targetMinor,
    required int savedMinor,
    DateTime? targetDate,
    required String icon,
    required int color,
  }) async {
    _validate(name, targetMinor, savedMinor);
    await dao.updateFields(id, {
      'name': name.trim(),
      'target_minor': targetMinor,
      'saved_minor': savedMinor,
      'target_date': targetDate?.millisecondsSinceEpoch,
      'icon': icon,
      'color': color,
    });
    _bus.emit({_table});
  }

  /// Adds (or withdraws, when negative) money from a goal. Only the
  /// saved_minor field changes, so concurrent edits of the name on another
  /// device merge cleanly.
  Future<void> contribute(String id, int deltaMinor) async {
    final row = await dao.find(id);
    if (row == null) throw StateError('Goal not found');
    final goal = GoalEntity.fromRow(row);
    final next = goal.savedMinor + deltaMinor;
    await dao.updateFields(id, {'saved_minor': next < 0 ? 0 : next});
    _bus.emit({_table});
  }

  Future<void> delete(String id) async {
    await dao.softDelete(id);
    _bus.emit({_table});
  }

  void _validate(String name, int target, int saved) {
    if (name.trim().isEmpty) throw ArgumentError('Goal name is required');
    if (target <= 0) throw ArgumentError('Target must be greater than zero');
    if (saved < 0) throw ArgumentError('Saved amount cannot be negative');
  }
}
