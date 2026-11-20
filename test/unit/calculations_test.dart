import 'package:expense_manager/core/finance/aggregates.dart';
import 'package:expense_manager/core/finance/analytics_calculator.dart';
import 'package:expense_manager/core/finance/balance_calculator.dart';
import 'package:expense_manager/core/finance/budget_calculator.dart';
import 'package:expense_manager/core/finance/currency_converter.dart';
import 'package:expense_manager/core/finance/recurrence.dart';
import 'package:expense_manager/core/utils/money.dart';
import 'package:expense_manager/data/models/account.dart';
import 'package:expense_manager/data/models/enums.dart';
import 'package:flutter_test/flutter_test.dart';

AccountBalance _acc(String id, String currency, int income, int expense) => AccountBalance(
      account: AccountEntity(
        id: id,
        name: id,
        type: AccountType.bank,
        currency: currency,
        icon: 'bank',
        color: 0,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
      incomeMinor: income,
      expenseMinor: expense,
    );

Aggregate _agg(DateTime day, TransactionType type, int amount, [String cat = 'cat_food']) =>
    Aggregate(day: day, type: type, categoryId: cat, amountMinor: amount);

void main() {
  group('Money', () {
    test('parses user input into minor units', () {
      expect(Money.parseToMinor('12'), 1200);
      expect(Money.parseToMinor('12.5'), 1250);
      expect(Money.parseToMinor('1,234.56'), 123456);
      expect(Money.parseToMinor('0.07'), 7);
      expect(Money.parseToMinor('12.345'), isNull);
      expect(Money.parseToMinor('abc'), isNull);
      expect(Money.parseToMinor(''), isNull);
    });

    test('formats decimal strings without float drift', () {
      expect(Money.toDecimalString(2500), '25');
      expect(Money.toDecimalString(1250), '12.5');
      expect(Money.toDecimalString(1205), '12.05');
      expect(Money.toDecimalString(-99), '-0.99');
      expect(Money.format(145000, 'USD'), r'$1,450.00');
    });
  });

  group('BalanceCalculator', () {
    test('Total Balance = Total Income - Total Expenses', () {
      final summary = BalanceCalculator.summarize(
        [_acc('a', 'USD', 250000, 45000), _acc('b', 'USD', 10000, 5000)],
        CurrencyConverter.identity('USD'),
      );
      expect(summary.totalIncomeMinor, 260000);
      expect(summary.totalExpenseMinor, 50000);
      expect(summary.balanceMinor, 210000);
      expect(summary.convertedBalances['a'], 205000);
    });

    test('converts foreign-currency accounts into the base currency', () {
      final converter = CurrencyConverter(baseCurrency: 'USD', ratesPerUsd: {'EUR': 0.5});
      final summary = BalanceCalculator.summarize([_acc('eur', 'EUR', 1000, 0)], converter);
      expect(summary.totalIncomeMinor, 2000); // €10 = $20 at 0.5 EUR/USD
      expect(summary.hasUnconvertibleCurrency, isFalse);
    });

    test('flags currencies without a cached rate', () {
      final summary = BalanceCalculator.summarize(
        [_acc('x', 'XYZ', 100, 0)],
        CurrencyConverter.identity('USD'),
      );
      expect(summary.hasUnconvertibleCurrency, isTrue);
    });

    test('empty account list gives zero balance', () {
      expect(BalanceCalculator.summarize([], CurrencyConverter.identity('USD')).balanceMinor, 0);
    });
  });

  group('BudgetCalculator', () {
    test('matches the spec example (2000 / 1450 / 550 / 72.5%)', () {
      final s = BudgetCalculator.status(budgetId: 'b', limitMinor: 200000, spentMinor: 145000);
      expect(s.remainingMinor, 55000);
      expect(s.percentUsed, closeTo(72.5, 0.001));
      expect(s.reachedThreshold, 50);
      expect(s.isExceeded, isFalse);
    });

    test('reports each warning threshold', () {
      int? at(int spent) => BudgetCalculator.status(budgetId: 'b', limitMinor: 1000, spentMinor: spent).reachedThreshold;
      expect(at(499), isNull);
      expect(at(500), 50);
      expect(at(750), 75);
      expect(at(900), 90);
      expect(at(1000), 100);
    });

    test('warning messages', () {
      String fmt(int m) => Money.format(m, 'USD');
      final s90 = BudgetCalculator.status(budgetId: 'b', limitMinor: 1000, spentMinor: 900);
      expect(
        BudgetCalculator.warningMessage(s90, monthName: 'July', format: fmt),
        'You have used 90% of your July budget.',
      );
      final over = BudgetCalculator.status(budgetId: 'b', limitMinor: 200000, spentMinor: 212500);
      expect(BudgetCalculator.warningMessage(over, monthName: 'July', format: fmt), r'Budget exceeded by $125.00.');
      expect(over.exceededByMinor, 12500);
      expect(BudgetCalculator.severity(over), BudgetSeverity.exceeded);
      final low = BudgetCalculator.status(budgetId: 'b', limitMinor: 1000, spentMinor: 100);
      expect(BudgetCalculator.warningMessage(low, monthName: 'July', format: fmt), isNull);
    });

    test('progress is clamped for the UI', () {
      final s = BudgetCalculator.status(budgetId: 'b', limitMinor: 100, spentMinor: 300);
      expect(s.progress, 1.0);
      expect(s.percentUsed, 300);
    });
  });

  group('AnalyticsCalculator', () {
    final now = DateTime(2026, 7, 15, 12);

    test('month totals, net savings, category shares', () {
      final rows = [
        _agg(DateTime(2026, 7, 1), TransactionType.income, 300000, 'cat_salary'),
        _agg(DateTime(2026, 7, 2), TransactionType.expense, 6000, 'cat_food'),
        _agg(DateTime(2026, 7, 3), TransactionType.expense, 4000, 'cat_travel'),
        _agg(DateTime(2026, 6, 30), TransactionType.expense, 99999, 'cat_food'), // outside
      ];
      final r = AnalyticsCalculator.compute(aggregates: rows, period: AnalyticsPeriod.month, now: now);
      expect(r.incomeMinor, 300000);
      expect(r.expenseMinor, 10000);
      expect(r.netSavingsMinor, 290000);
      expect(r.categoryShares.first.categoryId, 'cat_food');
      expect(r.categoryShares.first.share, closeTo(0.6, 0.0001));
      expect(r.buckets.length, 31); // one bar per day of July
      expect(r.buckets[1].expenseMinor, 6000);
      expect(r.averageDailyExpenseMinor, (10000 / 15).round());
    });

    test('bucket granularity per period', () {
      expect(AnalyticsCalculator.compute(aggregates: const [], period: AnalyticsPeriod.week, now: now).buckets.length, 7);
      expect(AnalyticsCalculator.compute(aggregates: const [], period: AnalyticsPeriod.year, now: now).buckets.length, 12);
      final q = AnalyticsCalculator.compute(aggregates: const [], period: AnalyticsPeriod.threeMonths, now: now);
      expect(q.range.start, DateTime(2026, 5, 1));
      expect(q.range.end, DateTime(2026, 8, 1));
      expect(q.buckets.length, inInclusiveRange(13, 14));
    });

    test('savings rate', () {
      final rows = [
        _agg(DateTime(2026, 7, 1), TransactionType.income, 1000),
        _agg(DateTime(2026, 7, 1), TransactionType.expense, 750),
      ];
      final r = AnalyticsCalculator.compute(aggregates: rows, period: AnalyticsPeriod.month, now: now);
      expect(r.savingsRate, closeTo(0.25, 0.0001));
    });
  });

  group('Recurrence', () {
    test('monthly rules anchored on the 31st clamp and recover', () {
      final start = DateTime(2026, 1, 31, 9);
      expect(Recurrence.occurrence(start, RecurrenceFrequency.monthly, 1), DateTime(2026, 2, 28, 9));
      expect(Recurrence.occurrence(start, RecurrenceFrequency.monthly, 2), DateTime(2026, 3, 31, 9));
    });

    test('due indexes stop at now and endAt', () {
      final start = DateTime(2026, 7, 1);
      final due = Recurrence.dueIndexes(
        start: start,
        frequency: RecurrenceFrequency.weekly,
        fromIndex: 0,
        now: DateTime(2026, 7, 20),
      );
      expect(due, [0, 1, 2]); // Jul 1, 8, 15
      final ended = Recurrence.dueIndexes(
        start: start,
        frequency: RecurrenceFrequency.daily,
        fromIndex: 0,
        now: DateTime(2026, 7, 20),
        endAt: DateTime(2026, 7, 3),
      );
      expect(ended, [0, 1, 2]);
    });

    test('yearly and catch-up cap', () {
      expect(Recurrence.occurrence(DateTime(2024, 2, 29), RecurrenceFrequency.yearly, 1), DateTime(2025, 2, 28));
      final capped = Recurrence.dueIndexes(
        start: DateTime(2020),
        frequency: RecurrenceFrequency.daily,
        fromIndex: 0,
        now: DateTime(2026),
        maxCatchUp: 10,
      );
      expect(capped.length, 10);
    });

    test('deterministic occurrence ids', () {
      expect(Recurrence.transactionId('r1', 3), 'rec_r1_3');
    });
  });
}
