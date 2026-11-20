import 'package:expense_manager/core/finance/aggregates.dart';
import 'package:expense_manager/core/finance/insights_engine.dart';
import 'package:expense_manager/core/utils/money.dart';
import 'package:expense_manager/data/models/enums.dart';
import 'package:flutter_test/flutter_test.dart';

Aggregate _e(DateTime d, int amount, [String cat = 'cat_food']) =>
    Aggregate(day: d, type: TransactionType.expense, categoryId: cat, amountMinor: amount);

void main() {
  // Wednesday 15 July 2026 → week started Monday 13 July.
  final now = DateTime(2026, 7, 15, 18);
  String fmt(int m) => Money.format(m, 'USD');
  const names = {'cat_food': 'Food', 'cat_travel': 'Travel'};

  List<Insight> run(List<Aggregate> rows, {int budget = 0}) => InsightsEngine.generate(
        aggregates: rows,
        now: now,
        monthlyBudgetMinor: budget,
        categoryNames: names,
        format: fmt,
      );

  Insight? find(List<Insight> list, InsightKind kind) {
    for (final i in list) {
      if (i.kind == kind) return i;
    }
    return null;
  }

  test('no data produces a single onboarding insight', () {
    final result = run(const []);
    expect(result.single.kind, InsightKind.noData);
  });

  test('week over week compares equal elapsed days', () {
    final rows = [
      _e(DateTime(2026, 7, 13), 6000), // this week Mon
      _e(DateTime(2026, 7, 6), 5000), // last week Mon (same span)
      _e(DateTime(2026, 7, 10), 99999), // last week Fri: outside comparable span
    ];
    final insight = find(run(rows), InsightKind.weekTrend)!;
    expect(insight.message, 'You spent 20% more this week than last week.');
    expect(insight.tone, InsightTone.warning);
  });

  test('top category and its share are computed from data', () {
    final rows = [
      _e(DateTime(2026, 7, 2), 3000, 'cat_food'),
      _e(DateTime(2026, 7, 3), 1000, 'cat_travel'),
    ];
    expect(
      find(run(rows), InsightKind.topCategory)!.message,
      'Food is your highest expense category this month (75% of spending).',
    );
  });

  test('budget usage', () {
    final rows = [_e(DateTime(2026, 7, 2), 150000)];
    expect(find(run(rows, budget: 200000), InsightKind.budgetUsage)!.message, 'You have spent 75% of your monthly budget.');
  });

  test('month over month uses the same number of days', () {
    final rows = [
      _e(DateTime(2026, 7, 5), 8800), // this month to date
      _e(DateTime(2026, 6, 5), 10000), // last month, within first 15 days
      _e(DateTime(2026, 6, 25), 50000), // last month, outside comparable window
    ];
    expect(
      find(run(rows), InsightKind.monthTrend)!.message,
      'Your spending decreased by 12% compared with last month.',
    );
  });

  test('average daily spending', () {
    final rows = [_e(DateTime(2026, 7, 1), 27000)]; // $270 over 15 days = $18
    expect(find(run(rows), InsightKind.dailyAverage)!.message, r'Your average daily spending this month is $18.00.');
  });

  test('projection warns before the budget is exceeded', () {
    final rows = [_e(DateTime(2026, 7, 1), 150000)]; // $1,500 in 15 days → ~$3,100
    final projection = find(run(rows, budget: 200000), InsightKind.projection);
    expect(projection, isNotNull);
    expect(projection!.tone, InsightTone.warning);
  });

  test('percentChange has no baseline for zero', () {
    expect(InsightsEngine.percentChange(100, 0), isNull);
    expect(InsightsEngine.percentChange(120, 100), 20);
    expect(InsightsEngine.percentChange(88, 100), -12);
  });
}
