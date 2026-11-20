import 'package:sqflite_common/sqlite_api.dart';

import '../../core/finance/recurrence.dart';
import '../../core/services/data_change_bus.dart';
import '../../core/utils/clock.dart';
import '../../core/utils/id_generator.dart';
import '../local/sync_tables.dart';
import '../local/syncable_dao.dart';
import '../models/enums.dart';
import '../models/recurring_rule.dart';
import '../models/transaction.dart';
import 'current_user.dart';
import 'transaction_repository.dart';

class RecurringRepository {
  RecurringRepository(this._db, this._bus, this._user, this._clock, this._transactions)
      : dao = SyncableDao(_db, SyncTables.recurringRules, _clock);

  final Database _db;
  final DataChangeBus _bus;
  final CurrentUser _user;
  final Clock _clock;
  final TransactionRepository _transactions;
  final SyncableDao dao;

  String get _table => SyncTables.recurringRules.table;

  Future<List<RecurringRule>> all() async {
    final rows = await _db.query(
      _table,
      where: 'deleted_at IS NULL',
      orderBy: 'active DESC, next_due_at ASC',
    );
    return rows.map(RecurringRule.fromRow).toList();
  }

  /// Creates a rule from the Add Transaction form and materialises every
  /// occurrence that is already due (usually just the first one).
  Future<RecurringRule> createFromDraft(TransactionDraft draft, RecurrenceFrequency frequency) async {
    final error = draft.validate();
    if (error != null) throw ArgumentError(error);
    final now = _clock.now();
    final rule = RecurringRule(
      id: IdGenerator.newId(),
      userId: _user.id,
      type: draft.type,
      amountMinor: draft.amountMinor,
      categoryId: draft.categoryId,
      accountId: draft.accountId,
      note: draft.note.trim(),
      frequency: frequency,
      startAt: draft.occurredAt,
      nextDueAt: draft.occurredAt,
      createdAt: now,
      updatedAt: now,
    );
    await dao.insertNew(rule.toRow());
    await processDue();
    _bus.emit({_table, 'transactions'});
    return (await byId(rule.id))!;
  }

  Future<RecurringRule?> byId(String id) async {
    final row = await dao.find(id);
    return row == null ? null : RecurringRule.fromRow(row);
  }

  Future<void> update(
    String id, {
    required int amountMinor,
    required String note,
    required String categoryId,
    required String accountId,
    required bool active,
  }) async {
    if (amountMinor <= 0) throw ArgumentError('Amount must be greater than zero');
    await dao.updateFields(id, {
      'amount_minor': amountMinor,
      'note': note.trim(),
      'category_id': categoryId,
      'account_id': accountId,
      'active': active ? 1 : 0,
    });
    _bus.emit({_table});
  }

  Future<void> setActive(String id, bool active) async {
    await dao.updateFields(id, {'active': active ? 1 : 0});
    _bus.emit({_table});
  }

  /// Stops future occurrences; already created transactions are kept.
  Future<void> delete(String id) async {
    await dao.softDelete(id);
    _bus.emit({_table});
  }

  /// Materialises every due occurrence of every active rule. Safe to call
  /// repeatedly and on several devices: occurrence ids are deterministic.
  Future<int> processDue() async {
    final now = _clock.now();
    final rules = (await all()).where((r) => r.active && !r.nextDueAt.isAfter(now)).toList();
    var created = 0;
    for (final rule in rules) {
      final indexes = Recurrence.dueIndexes(
        start: rule.startAt,
        frequency: rule.frequency,
        fromIndex: rule.occurrencesGenerated,
        now: now,
        endAt: rule.endAt,
      );
      if (indexes.isEmpty) continue;
      await _db.transaction((txn) async {
        for (final i in indexes) {
          final inserted = await _transactions.createIfAbsent(
            TransactionDraft(
              type: rule.type,
              amountMinor: rule.amountMinor,
              categoryId: rule.categoryId,
              accountId: rule.accountId,
              occurredAt: Recurrence.occurrence(rule.startAt, rule.frequency, i),
              note: rule.note,
            ),
            Recurrence.transactionId(rule.id, i),
            rule.id,
            exec: txn,
          );
          if (inserted) created++;
        }
        final nextIndex = indexes.last + 1;
        final ended = rule.endAt != null &&
            Recurrence.occurrence(rule.startAt, rule.frequency, nextIndex).isAfter(rule.endAt!);
        await dao.updateFields(
          rule.id,
          {
            'occurrences_generated': nextIndex,
            'next_due_at': Recurrence.occurrence(rule.startAt, rule.frequency, nextIndex).millisecondsSinceEpoch,
            if (ended) 'active': 0,
          },
          exec: txn,
        );
      });
    }
    if (created > 0 || rules.isNotEmpty) _bus.emit({_table, 'transactions'});
    return created;
  }

  /// Active rules whose next occurrence falls inside [window] from now.
  Future<List<RecurringRule>> upcoming(Duration window) async {
    final now = _clock.now();
    final limit = now.add(window);
    return (await all())
        .where((r) => r.active && r.nextDueAt.isAfter(now) && !r.nextDueAt.isAfter(limit))
        .toList();
  }
}
