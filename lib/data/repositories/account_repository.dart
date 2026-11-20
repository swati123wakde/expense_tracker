import 'package:sqflite_common/sqlite_api.dart';

import '../../core/constants/defaults.dart';
import '../../core/services/data_change_bus.dart';
import '../../core/utils/clock.dart';
import '../../core/utils/id_generator.dart';
import '../local/sync_tables.dart';
import '../local/syncable_dao.dart';
import '../models/account.dart';
import '../models/enums.dart';
import '../models/row_utils.dart';
import 'current_user.dart';

class AccountRepository {
  AccountRepository(this._db, this._bus, this._user, this._clock)
      : dao = SyncableDao(_db, SyncTables.accounts, _clock);

  final Database _db;
  final DataChangeBus _bus;
  final CurrentUser _user;
  final Clock _clock;
  final SyncableDao dao;

  Future<void> seedDefaults(String currency) async {
    final batch = _db.batch();
    for (final a in Defaults.accounts) {
      batch.insert(
        SyncTables.accounts.table,
        {
          'id': a.id,
          'user_id': _user.id,
          'name': a.name,
          'type': a.type.name,
          'currency': currency,
          'icon': a.icon,
          'color': a.color,
          'archived': 0,
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

  Future<List<AccountEntity>> all({bool includeArchived = false}) async {
    final rows = await _db.query(
      SyncTables.accounts.table,
      where: includeArchived ? 'deleted_at IS NULL' : 'deleted_at IS NULL AND archived = 0',
      orderBy: 'created_at ASC, name COLLATE NOCASE ASC',
    );
    return rows.map(AccountEntity.fromRow).toList();
  }

  Future<AccountEntity?> byId(String id) async {
    final row = await dao.find(id);
    return row == null ? null : AccountEntity.fromRow(row);
  }

  /// Per-account income/expense totals computed in SQL (one pass).
  Future<List<AccountBalance>> balances({bool includeArchived = false}) async {
    final rows = await _db.rawQuery('''
      SELECT a.*,
        COALESCE(SUM(CASE WHEN t.type = 'income' THEN t.amount_minor END), 0) AS income_total,
        COALESCE(SUM(CASE WHEN t.type = 'expense' THEN t.amount_minor END), 0) AS expense_total
      FROM accounts a
      LEFT JOIN transactions t ON t.account_id = a.id AND t.deleted_at IS NULL
      WHERE a.deleted_at IS NULL ${includeArchived ? '' : 'AND a.archived = 0'}
      GROUP BY a.id
      ORDER BY a.created_at ASC, a.name COLLATE NOCASE ASC''');
    return rows
        .map(
          (r) => AccountBalance(
            account: AccountEntity.fromRow(r),
            incomeMinor: RowReader.int_(r['income_total']),
            expenseMinor: RowReader.int_(r['expense_total']),
          ),
        )
        .toList();
  }

  Future<AccountEntity> create({
    required String name,
    required AccountType type,
    required String currency,
    required String icon,
    required int color,
  }) async {
    final trimmed = name.trim();
    if (trimmed.isEmpty) throw ArgumentError('Account name is required');
    final now = _clock.now();
    final entity = AccountEntity(
      id: IdGenerator.newId(),
      userId: _user.id,
      name: trimmed,
      type: type,
      currency: currency,
      icon: icon,
      color: color,
      createdAt: now,
      updatedAt: now,
    );
    await dao.insertNew(entity.toRow());
    _bus.emit({SyncTables.accounts.table});
    return entity;
  }

  Future<void> update(AccountEntity account) async {
    await dao.updateFields(account.id, {
      'name': account.name.trim(),
      'type': account.type.name,
      'currency': account.currency,
      'icon': account.icon,
      'color': account.color,
      'archived': account.archived ? 1 : 0,
    });
    _bus.emit({SyncTables.accounts.table});
  }

  Future<int> transactionCount(String accountId) async {
    final r = await _db.rawQuery(
      'SELECT COUNT(*) AS c FROM transactions WHERE account_id = ? AND deleted_at IS NULL',
      [accountId],
    );
    return RowReader.int_(r.first['c']);
  }

  /// Accounts with transactions can only be archived, so history stays intact.
  Future<void> delete(String id) async {
    if (await transactionCount(id) > 0) {
      throw StateError('This account has transactions. Archive it instead.');
    }
    await dao.softDelete(id);
    _bus.emit({SyncTables.accounts.table});
  }

  Future<void> setArchived(String id, bool archived) async {
    await dao.updateFields(id, {'archived': archived ? 1 : 0});
    _bus.emit({SyncTables.accounts.table});
  }
}
