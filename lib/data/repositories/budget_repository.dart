import 'package:sqflite_common/sqlite_api.dart';

import '../../core/services/data_change_bus.dart';
import '../../core/utils/clock.dart';
import '../local/sync_tables.dart';
import '../local/syncable_dao.dart';
import '../models/budget.dart';
import 'current_user.dart';

class BudgetRepository {
  BudgetRepository(this._db, this._bus, this._user, this._clock)
      : dao = SyncableDao(_db, SyncTables.budgets, _clock);

  final Database _db;
  final DataChangeBus _bus;
  final CurrentUser _user;
  final Clock _clock;
  final SyncableDao dao;

  String get _table => SyncTables.budgets.table;

  Future<List<BudgetEntity>> all() async {
    final rows = await _db.query(_table, where: 'deleted_at IS NULL');
    return rows.map(BudgetEntity.fromRow).toList();
  }

  Future<BudgetEntity?> overall() async {
    final row = await dao.find(BudgetEntity.overallId);
    if (row == null || row['deleted_at'] != null) return null;
    return BudgetEntity.fromRow(row);
  }

  Future<void> setOverall(int amountMinor) => _set(BudgetEntity.overallId, null, amountMinor);

  Future<void> setForCategory(String categoryId, int amountMinor) =>
      _set(BudgetEntity.idForCategory(categoryId), categoryId, amountMinor);

  Future<void> _set(String id, String? categoryId, int amountMinor) async {
    if (amountMinor < 0) throw ArgumentError('Budget cannot be negative');
    if (amountMinor == 0) return remove(id);
    final now = _clock.now();
    final entity = BudgetEntity(
      id: id,
      userId: _user.id,
      categoryId: categoryId,
      amountMinor: amountMinor,
      createdAt: now,
      updatedAt: now,
    );
    await dao.saveLocal(entity.toRow());
    _bus.emit({_table});
  }

  Future<void> remove(String id) async {
    final existing = await dao.find(id);
    if (existing == null || existing['deleted_at'] != null) return;
    await dao.softDelete(id);
    _bus.emit({_table});
  }
}
