import 'package:expense_manager/data/models/enums.dart';
import 'package:expense_manager/data/models/transaction.dart';
import 'package:expense_manager/data/models/transaction_filter.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_harness.dart';

void main() {
  late TestEnv env;

  setUp(() async => env = await TestEnv.create());
  tearDown(() async => env.dispose());

  group('seeding', () {
    test('default categories and accounts exist exactly once', () async {
      final cats = await env.deps.categories.all();
      expect(cats.where((c) => c.type == TransactionType.expense).map((c) => c.name),
          containsAll(['Food', 'Travel', 'Shopping', 'Bills', 'Rent', 'Entertainment', 'Health', 'Education', 'Subscription', 'Other']));
      expect(cats.where((c) => c.type == TransactionType.income).map((c) => c.name),
          containsAll(['Salary', 'Freelance', 'Business', 'Investment', 'Gift', 'Other']));
      await env.deps.seedIfNeeded();
      expect((await env.deps.categories.all()).length, cats.length);
      expect((await env.deps.accounts.all()).map((a) => a.id), ['acc_cash', 'acc_bank']);
    });
  });

  group('TransactionRepository', () {
    test('create stores locally with pendingCreate status', () async {
      final t = await env.addExpense(2500, note: 'Lunch');
      final stored = await env.deps.transactions.byId(t.id);
      expect(stored!.amountMinor, 2500);
      expect(stored.syncStatus, SyncStatus.pendingCreate);
      expect(stored.note, 'Lunch');
    });

    test('rejects invalid drafts', () async {
      await expectLater(
        () => env.deps.transactions.create(TransactionDraft(
          type: TransactionType.expense,
          amountMinor: 0,
          categoryId: 'cat_food',
          accountId: 'acc_cash',
          occurredAt: DateTime(2026),
        )),
        throwsArgumentError,
      );
    });

    test('update keeps pendingCreate until first sync, then pendingUpdate', () async {
      final t = await env.addExpense(2000);
      await env.deps.transactions.update(
        t.id,
        TransactionDraft(
          type: TransactionType.expense,
          amountMinor: 2500,
          categoryId: 'cat_food',
          accountId: 'acc_cash',
          occurredAt: t.occurredAt,
        ),
      );
      expect((await env.deps.transactions.byId(t.id))!.syncStatus, SyncStatus.pendingCreate);

      // Simulate a completed upload.
      final row = (await env.deps.transactions.dao.find(t.id))!;
      await env.deps.transactions.dao.markSynced(t.id, row['updated_at'] as int, row);
      env.clock.advance(const Duration(seconds: 1));
      await env.deps.transactions.setFavorite(t.id, true);
      expect((await env.deps.transactions.byId(t.id))!.syncStatus, SyncStatus.pendingUpdate);
    });

    test('delete is soft (tombstone kept for sync) and undo restores', () async {
      final t = await env.addExpense(1000);
      final previous = await env.deps.transactions.delete(t.id);
      expect(await env.deps.transactions.byId(t.id), isNull);
      final raw = await env.deps.transactions.dao.find(t.id);
      expect(raw!['deleted_at'], isNotNull);
      expect(raw['sync_status'], SyncStatus.pendingDelete.name);

      await env.deps.transactions.restore(previous!);
      final restored = await env.deps.transactions.byId(t.id);
      expect(restored, isNotNull);
      expect(restored!.amountMinor, 1000);
    });

    test('filters combine and search by note, category and amount', () async {
      await env.addExpense(2500, note: 'Lunch', categoryId: 'cat_food');
      await env.addExpense(4000, note: 'Taxi', categoryId: 'cat_travel');
      await env.addIncome(250000, note: 'Monthly Salary');
      await env.addExpense(1200, note: 'Old snack', categoryId: 'cat_food', at: DateTime(2026, 5, 1));

      Future<List<String>> notes(TransactionFilter f) async =>
          (await env.deps.transactions.page(f)).map((v) => v.transaction.note).toList();

      final july = TransactionFilter(
        type: TransactionType.expense,
        categoryIds: const {'cat_food'},
        from: DateTime(2026, 7),
        to: DateTime(2026, 8),
      );
      expect(await notes(july), ['Lunch']);
      expect(await notes(const TransactionFilter(query: 'taxi')), ['Taxi']);
      expect(await notes(const TransactionFilter(query: 'Travel')), ['Taxi']);
      expect(await notes(const TransactionFilter(query: '25')), ['Lunch']);
      expect(await notes(const TransactionFilter(accountIds: {'acc_bank'})), ['Monthly Salary']);
      expect(await notes(const TransactionFilter(minAmountMinor: 2000, maxAmountMinor: 5000)), containsAll(['Lunch', 'Taxi']));
      expect(await env.deps.transactions.count(const TransactionFilter(type: TransactionType.expense)), 3);
    });

    test('keyset pagination walks 10k rows without duplicates', () async {
      await env.deps.transactions.seedDemoData(count: 10000, seed: 7);
      expect(await env.deps.transactions.count(TransactionFilter.none), 10000);

      final seen = <String>{};
      PageCursor? cursor;
      var pages = 0;
      while (true) {
        final page = await env.deps.transactions.page(TransactionFilter.none, after: cursor, limit: 500);
        if (page.isEmpty) break;
        for (final v in page) {
          expect(seen.add(v.id), isTrue);
        }
        final last = page.last.transaction;
        cursor = PageCursor(last.occurredAt.millisecondsSinceEpoch, last.id);
        pages++;
      }
      expect(seen.length, 10000);
      expect(pages, 20);
    });

    test('daily aggregates group by day/type/category/currency', () async {
      await env.addExpense(1000, at: DateTime(2026, 7, 1, 9));
      await env.addExpense(500, at: DateTime(2026, 7, 1, 20));
      await env.addIncome(9000, at: DateTime(2026, 7, 2));
      final rows = await env.deps.transactions.dailyAggregates(DateTime(2026, 7), DateTime(2026, 8), 'USD');
      final food = rows.firstWhere((r) => r.categoryId == 'cat_food');
      expect(food.totalMinor, 1500);
      expect(food.count, 2);
      expect(food.day, DateTime(2026, 7, 1));
    });
  });

  group('AccountRepository', () {
    test('balances are computed per account', () async {
      await env.addIncome(10000, accountId: 'acc_bank');
      await env.addExpense(2500, accountId: 'acc_bank');
      await env.addExpense(700, accountId: 'acc_cash');
      final balances = {for (final b in await env.deps.accounts.balances()) b.account.id: b.balanceMinor};
      expect(balances['acc_bank'], 7500);
      expect(balances['acc_cash'], -700);
    });

    test('accounts with transactions cannot be deleted', () async {
      await env.addExpense(100, accountId: 'acc_cash');
      await expectLater(() => env.deps.accounts.delete('acc_cash'), throwsStateError);
    });
  });

  group('Budget & goals', () {
    test('budgets use deterministic ids and zero removes them', () async {
      await env.deps.budgets.setOverall(200000);
      await env.deps.budgets.setForCategory('cat_food', 40000);
      expect((await env.deps.budgets.overall())!.amountMinor, 200000);
      expect((await env.deps.budgets.all()).length, 2);
      await env.deps.budgets.setOverall(0);
      expect(await env.deps.budgets.overall(), isNull);
    });

    test('goal contributions never go negative', () async {
      final g = await env.deps.goals.create(name: 'Laptop', targetMinor: 150000, savedMinor: 85000, icon: 'laptop', color: 1);
      expect(g.progress, closeTo(0.5667, 0.001));
      await env.deps.goals.contribute(g.id, -100000);
      expect((await env.deps.goals.all()).single.savedMinor, 0);
    });
  });

  group('Recurring', () {
    test('creates due occurrences idempotently with deterministic ids', () async {
      final rule = await env.deps.recurring.createFromDraft(
        TransactionDraft(
          type: TransactionType.expense,
          amountMinor: 1500,
          categoryId: 'cat_subscription',
          accountId: 'acc_bank',
          occurredAt: DateTime(2026, 5, 20, 9),
          note: 'Netflix',
        ),
        RecurrenceFrequency.monthly,
      );
      // May 20, Jun 20, Jul 20 09:00 are all <= now (Jul 20 10:00).
      expect(await env.deps.transactions.count(const TransactionFilter(query: 'Netflix')), 3);
      expect(await env.deps.recurring.processDue(), 0);
      final updated = await env.deps.recurring.byId(rule.id);
      expect(updated!.occurrencesGenerated, 3);
      expect(updated.nextDueAt, DateTime(2026, 8, 20, 9));

      env.clock.advance(const Duration(days: 32));
      expect(await env.deps.recurring.processDue(), 1);
      expect(await env.deps.transactions.byId('rec_${rule.id}_3'), isNotNull);
    });
  });
}
