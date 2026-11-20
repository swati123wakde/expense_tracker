import 'dart:math';

import 'package:sqflite_common/sqlite_api.dart';

import '../../core/constants/defaults.dart';
import '../../core/finance/aggregates.dart';
import '../../core/services/data_change_bus.dart';
import '../../core/utils/clock.dart';
import '../../core/utils/date_utils.dart';
import '../../core/utils/id_generator.dart';
import '../local/sync_tables.dart';
import '../local/syncable_dao.dart';
import '../local/transaction_query_builder.dart';
import '../models/enums.dart';
import '../models/row_utils.dart';
import '../models/transaction.dart';
import '../models/transaction_filter.dart';
import 'current_user.dart';

/// Single entry point for transaction reads/writes. All reads hit the local
/// encrypted database; the cloud is never queried from here.
class TransactionRepository {
  TransactionRepository(this._db, this._bus, this._user, this._clock)
      : dao = SyncableDao(_db, SyncTables.transactions, _clock);

  final Database _db;
  final DataChangeBus _bus;
  final CurrentUser _user;
  final Clock _clock;
  final SyncableDao dao;

  static const _table = 'transactions';

  // ---------------------------------------------------------------------------
  // Writes
  // ---------------------------------------------------------------------------

  Future<TransactionEntity> create(
    TransactionDraft draft, {
    String? id,
    String? recurringRuleId,
    DatabaseExecutor? exec,
    bool notify = true,
  }) async {
    final error = draft.validate();
    if (error != null) throw ArgumentError(error);
    final now = _clock.now();
    final entity = TransactionEntity(
      id: id ?? IdGenerator.newId(),
      userId: _user.id,
      type: draft.type,
      amountMinor: draft.amountMinor,
      categoryId: draft.categoryId,
      accountId: draft.accountId,
      note: draft.note.trim(),
      occurredAt: draft.occurredAt,
      attachmentPath: draft.attachmentPath,
      recurringRuleId: recurringRuleId,
      createdAt: now,
      updatedAt: now,
    );
    final row = entity.toRow();
    if (exec != null) {
      await dao.insertNew(row, exec: exec);
    } else {
      await dao.insertNew(row);
    }
    if (notify) _bus.emit({_table});
    return entity;
  }

  /// Inserts a transaction only if no record with [id] exists (deterministic
  /// ids from recurring rules make this idempotent across devices).
  Future<bool> createIfAbsent(TransactionDraft draft, String id, String recurringRuleId, {DatabaseExecutor? exec}) async {
    final existing = await dao.find(id, exec: exec);
    if (existing != null) return false;
    await create(draft, id: id, recurringRuleId: recurringRuleId, exec: exec, notify: false);
    return true;
  }

  Future<TransactionEntity> update(String id, TransactionDraft draft) async {
    final error = draft.validate();
    if (error != null) throw ArgumentError(error);
    await dao.updateFields(id, {
      'type': draft.type.name,
      'amount_minor': draft.amountMinor,
      'category_id': draft.categoryId,
      'account_id': draft.accountId,
      'note': draft.note.trim(),
      'occurred_at': draft.occurredAt.millisecondsSinceEpoch,
      'attachment_path': draft.attachmentPath,
    });
    _bus.emit({_table});
    return (await byId(id))!;
  }

  Future<void> setFavorite(String id, bool favorite) async {
    await dao.updateFields(id, {'is_favorite': favorite ? 1 : 0});
    _bus.emit({_table});
  }

  /// Soft-deletes and returns the previous state so the UI can offer Undo.
  Future<TransactionEntity?> delete(String id) async {
    final before = await byId(id);
    if (before == null) return null;
    await dao.softDelete(id);
    _bus.emit({_table});
    return before;
  }

  /// Undo for [delete]: restores the record exactly as it was (as a new local
  /// edit, so the restoration also syncs).
  Future<void> restore(TransactionEntity previous) async {
    await dao.saveLocal(previous.copyWith(clearDeletedAt: true).toRow());
    _bus.emit({_table});
  }

  // ---------------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------------

  Future<TransactionEntity?> byId(String id) async {
    final row = await dao.find(id);
    if (row == null || row['deleted_at'] != null) return null;
    return TransactionEntity.fromRow(row);
  }

  Future<List<TransactionView>> page(
    TransactionFilter filter, {
    PageCursor? after,
    int limit = 40,
    String fallbackCurrency = 'USD',
  }) async {
    final q = TransactionQueryBuilder.page(filter, after: after, limit: limit);
    final rows = await _db.rawQuery(q.sql, q.args);
    return rows.map((r) => TransactionView.fromRow(r, fallbackCurrency)).toList();
  }

  Future<List<TransactionView>> recent(int count, {String fallbackCurrency = 'USD'}) =>
      page(TransactionFilter.none, limit: count, fallbackCurrency: fallbackCurrency);

  Future<int> count(TransactionFilter filter) async {
    final q = TransactionQueryBuilder.count(filter);
    final rows = await _db.rawQuery(q.sql, q.args);
    return RowReader.int_(rows.first['c']);
  }

  /// Raw (type, currency, total) rows for a filter.
  Future<List<({TransactionType type, String currency, int total})>> totals(
    TransactionFilter filter,
    String fallbackCurrency,
  ) async {
    final q = TransactionQueryBuilder.totals(filter);
    final rows = await _db.rawQuery(q.sql, q.args);
    return [
      for (final r in rows)
        (
          type: TransactionType.parse(r['type']),
          currency: RowReader.str(r['currency'], fallbackCurrency),
          total: RowReader.int_(r['total']),
        ),
    ];
  }

  /// Streams every matching row in pages (CSV export of 10k+ rows without
  /// loading them all at once).
  Stream<TransactionView> iterate(TransactionFilter filter, {String fallbackCurrency = 'USD'}) async* {
    PageCursor? cursor;
    while (true) {
      final batch = await page(filter, after: cursor, limit: 500, fallbackCurrency: fallbackCurrency);
      for (final v in batch) {
        yield v;
      }
      if (batch.length < 500) break;
      final last = batch.last.transaction;
      cursor = PageCursor(last.occurredAt.millisecondsSinceEpoch, last.id);
    }
  }

  /// SUM(amount) grouped by local day, type, category and currency within a
  /// date window. Feeds the dashboard, analytics and insights calculators.
  Future<List<DailyAggregate>> dailyAggregates(DateTime from, DateTime to, String baseCurrency) async {
    final rows = await _db.rawQuery('''
      SELECT strftime('%Y-%m-%d', t.occurred_at / 1000, 'unixepoch', 'localtime') AS day,
             t.type AS type, t.category_id AS category_id,
             COALESCE(a.currency, ?) AS currency,
             SUM(t.amount_minor) AS total, COUNT(*) AS cnt
      FROM transactions t
      LEFT JOIN accounts a ON a.id = t.account_id
      WHERE t.deleted_at IS NULL AND t.occurred_at >= ? AND t.occurred_at < ?
      GROUP BY day, t.type, t.category_id, a.currency''', [
      baseCurrency,
      from.millisecondsSinceEpoch,
      to.millisecondsSinceEpoch,
    ]);
    return [
      for (final r in rows)
        DailyAggregate(
          day: DateUtilsX.parseDayKey(r['day'] as String),
          type: TransactionType.parse(r['type']),
          categoryId: RowReader.str(r['category_id']),
          currency: RowReader.str(r['currency'], baseCurrency),
          totalMinor: RowReader.int_(r['total']),
          count: RowReader.int_(r['cnt'], 1),
        ),
    ];
  }

  /// Seeds [count] realistic transactions for the 10k performance demo.
  /// Inserted in one SQL transaction with batched statements.
  Future<void> seedDemoData({int count = 10000, int? seed}) async {
    final random = Random(seed ?? 42);
    final expense = Defaults.categories.where((c) => c.type == TransactionType.expense).toList();
    final income = Defaults.categories.where((c) => c.type == TransactionType.income).toList();
    final accounts = Defaults.accounts.map((a) => a.id).toList();
    const notes = ['Lunch', 'Groceries', 'Taxi', 'Coffee', 'Movie night', 'Pharmacy', 'Books', 'Gift', 'Fuel', ''];
    final now = _clock.now();
    await _db.transaction((txn) async {
      var batch = txn.batch();
      for (var i = 0; i < count; i++) {
        final isIncome = random.nextInt(10) == 0;
        final cat = isIncome ? income[random.nextInt(income.length)] : expense[random.nextInt(expense.length)];
        final occurred = now.subtract(Duration(minutes: random.nextInt(60 * 24 * 730)));
        final ts = _clock.nowMs();
        batch.insert(_table, {
          'id': IdGenerator.newId(),
          'user_id': _user.id,
          'type': isIncome ? 'income' : 'expense',
          'amount_minor': isIncome ? 50000 + random.nextInt(300000) : 100 + random.nextInt(15000),
          'category_id': cat.id,
          'account_id': accounts[random.nextInt(accounts.length)],
          'note': notes[random.nextInt(notes.length)],
          'occurred_at': occurred.millisecondsSinceEpoch,
          'is_favorite': 0,
          'created_at': ts,
          'updated_at': ts,
          'sync_status': SyncStatus.pendingCreate.name,
        });
        if (i % 1000 == 999) {
          await batch.commit(noResult: true);
          batch = txn.batch();
        }
      }
      await batch.commit(noResult: true);
    });
    _bus.emit({_table});
  }
}
