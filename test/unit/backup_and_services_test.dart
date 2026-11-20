import 'dart:convert';

import 'package:expense_manager/core/finance/budget_calculator.dart';
import 'package:expense_manager/core/services/app_lock_service.dart';
import 'package:expense_manager/core/services/secure_store.dart';
import 'package:expense_manager/core/utils/money.dart';
import 'package:expense_manager/data/models/enums.dart';
import 'package:expense_manager/data/models/transaction_filter.dart';
import 'package:expense_manager/data/repositories/backup_repository.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_harness.dart';

void main() {
  group('JSON backup', () {
    test('export has the documented shape and round-trips into a fresh device', () async {
      final a = await TestEnv.create();
      await a.addExpense(2500, note: 'Lunch');
      await a.addIncome(250000, note: 'Monthly Salary');
      await a.deps.budgets.setOverall(200000);
      await a.deps.goals.create(name: 'Laptop', targetMinor: 150000, savedMinor: 85000, icon: 'laptop', color: 1);

      final json = await a.deps.backup.exportJson();
      final doc = jsonDecode(json) as Map<String, dynamic>;
      expect(doc['version'], 1);
      for (final key in ['transactions', 'categories', 'accounts', 'budgets', 'goals', 'settings']) {
        expect(doc.containsKey(key), isTrue, reason: key);
      }
      expect((doc['transactions'] as List).length, 2);

      final b = await TestEnv.create();
      final summary = await b.deps.backup.importJson(json);
      expect(summary.counts['transactions'], 2);
      expect(await b.deps.transactions.count(TransactionFilter.none), 2);
      expect((await b.deps.budgets.overall())!.amountMinor, 200000);
      expect((await b.deps.goals.all()).single.name, 'Laptop');
      await a.dispose();
      await b.dispose();
    });

    test('invalid backup is rejected before the database is modified', () async {
      final env = await TestEnv.create();
      await env.addExpense(100);
      final bad = jsonEncode({
        'version': 1,
        'transactions': [
          {
            'id': 'x',
            'type': 'expense',
            'amount_minor': 500,
            'category_id': 'cat_food',
            'account_id': 'missing_account',
            'occurred_at': 1,
            'updated_at': 1,
          },
          {'id': 'y', 'type': 'bogus', 'amount_minor': -1},
        ],
        'categories': [],
        'accounts': [],
        'budgets': [],
        'goals': [],
        'settings': {},
      });
      await expectLater(env.deps.backup.importJson(bad), throwsA(isA<BackupValidationException>()));
      expect(await env.deps.transactions.count(TransactionFilter.none), 1);

      await expectLater(env.deps.backup.importJson('not json'), throwsA(isA<BackupValidationException>()));
      await env.dispose();
    });

    test('validator reports precise problems', () {
      final errors = BackupValidator.validate({
        'version': 99,
        'transactions': 'nope',
        'categories': [],
        'accounts': [],
        'budgets': [],
        'goals': [],
      });
      expect(errors, contains('Unsupported backup version 99.'));
      expect(errors, contains('"transactions" must be a list.'));
    });
  });

  group('CSV export', () {
    test('matches the documented format and respects filters', () async {
      final env = await TestEnv.create();
      await env.addExpense(2500, note: 'Lunch', at: DateTime(2026, 7, 1, 12));
      await env.addIncome(250000, note: 'Monthly Salary', at: DateTime(2026, 7, 2, 9));
      await env.addExpense(900, note: 'Bus, downtown', categoryId: 'cat_travel', at: DateTime(2026, 7, 3));

      final all = await env.deps.backup.exportCsv(TransactionFilter.none);
      final lines = all.trim().split('\n');
      expect(lines.first, 'Date,Type,Category,Account,Amount,Note');
      expect(lines, contains('2026-07-01,Expense,Food,Cash,25,Lunch'));
      expect(lines, contains('2026-07-02,Income,Salary,Bank Account,2500,Monthly Salary'));
      expect(lines, contains('2026-07-03,Expense,Travel,Cash,9,"Bus, downtown"'));

      final foodOnly = await env.deps.backup.exportCsv(
        TransactionFilter(
          type: TransactionType.expense,
          categoryIds: const {'cat_food'},
          from: DateTime(2026, 7),
          to: DateTime(2026, 8),
        ),
      );
      expect(foodOnly.trim().split('\n').length, 2);
      await env.dispose();
    });

    test('escapes quotes and neutralises formulas', () {
      expect(BackupRepository.csvEscape('say "hi"'), '"say ""hi"""');
      expect(BackupRepository.csvEscape('=SUM(A1)'), "'=SUM(A1)");
    });
  });

  group('App lock', () {
    test('PIN is hashed and verified', () async {
      final store = InMemorySecureStore();
      final lock = AppLockService(store, NoBiometricAuthenticator());
      await lock.setPin('4821');
      expect(store.values.values.any((v) => v.contains('4821')), isFalse);
      expect(await lock.verifyPin('4821'), isTrue);
      expect(await lock.verifyPin('0000'), isFalse);
      await expectLater(() => lock.setPin('12'), throwsArgumentError);
    });
  });

  group('Budget alerts', () {
    test('notifies once per threshold per month', () async {
      final env = await TestEnv.create();
      String fmt(int m) => Money.format(m, 'USD');
      Future<List<String>> check(int spent) => env.deps.alerts.checkBudgets(
            now: env.clock.now(),
            format: fmt,
            budgets: [
              (status: BudgetCalculator.status(budgetId: 'budget_overall', limitMinor: 1000, spentMinor: spent), categoryName: null),
            ],
          );
      expect(await check(600), isEmpty); // 50% is in-app only
      expect(await check(800), ['You have used 75% of your July budget.']);
      expect(await check(820), isEmpty); // same threshold, no repeat
      expect(await check(1100), [r'Budget exceeded by $1.00.']);
      expect(env.notifications.shown.length, 2);
      await env.dispose();
    });
  });
}
