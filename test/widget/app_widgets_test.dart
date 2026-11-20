import 'package:expense_manager/data/models/enums.dart';
import 'package:expense_manager/data/models/transaction_filter.dart';
import 'package:expense_manager/features/transactions/filter_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/widget_harness.dart';

void main() {
  group('Dashboard', () {
    testWidgets('shows balance, totals and recent transactions from local data', (tester) async {
      await pumpExpenseApp(tester, seed: (env) async {
        await env.addIncome(300000, note: 'Monthly Salary');
        await env.addExpense(2500, note: 'Lunch');
      });

      expect(find.text('Overview'), findsOneWidget);
      expect(find.byKey(const Key('totalBalance')), findsOneWidget);
      expect(find.text(r'$2,975.00'), findsOneWidget);
      expect(find.text(r'$3,000.00'), findsWidgets); // total income
      expect(find.text('Lunch'), findsOneWidget);
      expect(find.text('Monthly Salary'), findsOneWidget);
      expect(find.text('Smart insights'), findsOneWidget);
    });

    testWidgets('empty state when there is no data', (tester) async {
      await pumpExpenseApp(tester);
      expect(find.text('No transactions yet'), findsOneWidget);
      expect(find.text(r'$0.00'), findsWidgets);
    });
  });

  group('Add transaction', () {
    testWidgets('validates and saves an expense locally', (tester) async {
      final env = await pumpExpenseApp(tester);

      await tester.tap(find.byKey(const Key('addTransactionFab')));
      await settle(tester);
      expect(find.text('Add transaction'), findsOneWidget);

      // Saving without input shows validation errors.
      await tester.tap(find.byKey(const Key('saveTransaction')));
      await settle(tester);
      expect(find.text('Enter a valid amount'), findsOneWidget);
      expect(find.text('Choose a category'), findsOneWidget);

      await tester.enterText(find.byKey(const Key('amountField')), '12.50');
      await tester.ensureVisible(find.byKey(const Key('category_cat_food')));
      await tester.tap(find.byKey(const Key('category_cat_food')));
      await tester.enterText(find.byKey(const Key('noteField')), 'Sandwich');
      await tester.tap(find.byKey(const Key('saveTransaction')));
      await settle(tester);

      final saved = (await tester.runAsync(() => env.deps.transactions.page(TransactionFilter.none)))!;
      expect(saved.single.transaction.amountMinor, 1250);
      expect(saved.single.transaction.type, TransactionType.expense);
      expect(saved.single.transaction.note, 'Sandwich');
      // Back on the dashboard, which refreshed from the local DB.
      expect(find.text('Overview'), findsOneWidget);
      expect(find.text('Sandwich'), findsOneWidget);
    });
  });

  group('Transaction filters', () {
    testWidgets('type + category filters combine', (tester) async {
      await pumpExpenseApp(tester, seed: (env) async {
        await env.addExpense(2500, note: 'Lunch', categoryId: 'cat_food');
        await env.addExpense(4000, note: 'Taxi', categoryId: 'cat_travel');
        await env.addIncome(250000, note: 'Salary July');
      });

      await tester.tap(find.byKey(const Key('nav_Transactions')));
      await settle(tester);
      expect(find.text('Lunch'), findsOneWidget);
      expect(find.text('Taxi'), findsOneWidget);
      expect(find.text('Salary July'), findsOneWidget);

      await tester.tap(find.byKey(const Key('openFilters')));
      await settle(tester);
      final sheet = find.byType(FilterSheet);
      await tester.tap(find.descendant(of: sheet, matching: find.text('Expense')));
      await settle(tester);
      await tester.ensureVisible(find.byKey(const Key('filter_cat_cat_food')));
      await tester.tap(find.byKey(const Key('filter_cat_cat_food')));
      await settle(tester);
      await tester.tap(find.byKey(const Key('applyFilters')));
      await settle(tester);

      expect(find.text('Lunch'), findsOneWidget);
      expect(find.text('Taxi'), findsNothing);
      expect(find.text('Salary July'), findsNothing);
      expect(find.textContaining('1 results'), findsOneWidget);
    });

    testWidgets('search by note', (tester) async {
      await pumpExpenseApp(tester, seed: (env) async {
        await env.addExpense(2500, note: 'Lunch');
        await env.addExpense(4000, note: 'Taxi', categoryId: 'cat_travel');
      });
      await tester.tap(find.byKey(const Key('nav_Transactions')));
      await settle(tester);
      await tester.enterText(find.byKey(const Key('searchField')), 'taxi');
      await tester.pump(const Duration(milliseconds: 350));
      await settle(tester);
      expect(find.text('Taxi'), findsOneWidget);
      expect(find.text('Lunch'), findsNothing);
    });
  });

  group('Theme switching', () {
    testWidgets('dark mode applies immediately and is persisted', (tester) async {
      final env = await pumpExpenseApp(tester);
      await tester.tap(find.byKey(const Key('nav_Settings')));
      await settle(tester);

      await tester.tap(find.text('Dark'));
      await settle(tester);
      expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, ThemeMode.dark);
      expect(Theme.of(tester.element(find.text('Settings').first)).brightness, Brightness.dark);

      final stored = (await tester.runAsync(() => env.deps.settings.load()))!;
      expect(stored.themeMode, ThemeMode.dark);

      await tester.tap(find.text('Light'));
      await settle(tester);
      expect(tester.widget<MaterialApp>(find.byType(MaterialApp)).themeMode, ThemeMode.light);
    });
  });

  group('Budget warnings', () {
    testWidgets('shows the 90% warning on the dashboard', (tester) async {
      await pumpExpenseApp(tester, seed: (env) async {
        await env.deps.budgets.setOverall(10000);
        await env.addExpense(9000, note: 'Groceries');
      });
      expect(find.byKey(const Key('budgetCard')), findsOneWidget);
      expect(find.text('You have used 90% of your July budget.'), findsOneWidget);
      expect(find.text('90.0% used'), findsOneWidget);
    });

    testWidgets('shows the over-budget message', (tester) async {
      await pumpExpenseApp(tester, seed: (env) async {
        await env.deps.budgets.setOverall(10000);
        await env.addExpense(11250);
      });
      expect(find.text(r'Budget exceeded by $12.50.'), findsOneWidget);
    });
  });
}
