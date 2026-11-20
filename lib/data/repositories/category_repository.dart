import 'package:sqflite_common/sqlite_api.dart';

import '../../core/constants/defaults.dart';
import '../../core/services/data_change_bus.dart';
import '../../core/utils/clock.dart';
import '../../core/utils/id_generator.dart';
import '../local/sync_tables.dart';
import '../local/syncable_dao.dart';
import '../models/category.dart';
import '../models/enums.dart';
import 'current_user.dart';

class CategoryRepository {
  CategoryRepository(this._db, this._bus, this._user, this._clock)
      : dao = SyncableDao(_db, SyncTables.categories, _clock);

  final Database _db;
  final DataChangeBus _bus;
  final CurrentUser _user;
  final Clock _clock;
  final SyncableDao dao;

  /// Seeds built-in categories. INSERT OR IGNORE keeps user edits intact and
  /// timestamps of 0 make any cloud copy win during the first merge.
  Future<void> seedDefaults() async {
    final batch = _db.batch();
    var order = 0;
    for (final c in Defaults.categories) {
      batch.insert(
        SyncTables.categories.table,
        {
          'id': c.id,
          'user_id': _user.id,
          'name': c.name,
          'type': c.type.name,
          'icon': c.icon,
          'color': c.color,
          'is_custom': 0,
          'archived': 0,
          'sort_order': order++,
          'created_at': 0,
          'updated_at': 0,
          'deleted_at': null,
          'sync_status': SyncStatus.pendingCreate.name,
          'sync_base': null,
        },
        conflictAlgorithm: ConflictAlgorithm.ignore,
      );
    }
    await batch.commit(noResult: true);
  }

  Future<List<CategoryEntity>> all({bool includeArchived = false, TransactionType? type}) async {
    final where = <String>['deleted_at IS NULL'];
    final args = <Object?>[];
    if (!includeArchived) where.add('archived = 0');
    if (type != null) {
      where.add('type = ?');
      args.add(type.name);
    }
    final rows = await _db.query(
      SyncTables.categories.table,
      where: where.join(' AND '),
      whereArgs: args,
      orderBy: 'is_custom ASC, sort_order ASC, name COLLATE NOCASE ASC',
    );
    return rows.map(CategoryEntity.fromRow).toList();
  }

  Future<CategoryEntity?> byId(String id) async {
    final row = await dao.find(id);
    return row == null ? null : CategoryEntity.fromRow(row);
  }

  Future<CategoryEntity> create({
    required String name,
    required TransactionType type,
    required String icon,
    required int color,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Category name is required');
    final now = _clock.now();
    final entity = CategoryEntity(
      id: IdGenerator.newId(),
      userId: _user.id,
      name: trimmed,
      type: type,
      icon: icon,
      color: color,
      isCustom: true,
      sortOrder: 1000,
      createdAt: now,
      updatedAt: now,
    );
    await dao.insertNew(entity.toRow());
    _bus.emit({SyncTables.categories.table});
    return entity;
  }

  Future<void> update(CategoryEntity category) async {
    await dao.updateFields(category.id, {
      'name': category.name.trim(),
      'type': category.type.name,
      'icon': category.icon,
      'color': category.color,
      'archived': category.archived ? 1 : 0,
    });
    _bus.emit({SyncTables.categories.table});
  }

  Future<void> setArchived(String id, bool archived) async {
    await dao.updateFields(id, {'archived': archived ? 1 : 0});
    _bus.emit({SyncTables.categories.table});
  }
}
