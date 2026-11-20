import '../utils/date_utils.dart';
import 'aggregates.dart';

enum InsightKind {
  weekTrend,
  topCategory,
  budgetUsage,
  monthTrend,
  dailyAverage,
  projection,
  savingsRate,
  noData,
}

enum InsightTone { positive, neutral, warning, negative }

class Insight {
  const Insight(this.kind, this.message, this.tone);

  final InsightKind kind;
  final String message;
  final InsightTone tone;

  @override
  String toString() => 'Insight($kind, $message)';
}

/// Generates human-readable insights purely from the user's local data.
/// No network, no hard-coded figures: every number is derived from
/// [aggregates] (already converted to the base currency).
class InsightsEngine {
  InsightsEngine._();

  /// Earliest date the engine needs data from (for the caller's query).
  static DateTime requiredStart(DateTime now) {
    final lastMonth = DateUtilsX.lastMonth(now).start;
    final lastWeek = DateUtilsX.lastWeek(now).start;
    return lastMonth.isBefore(lastWeek) ? lastMonth : lastWeek;
  }

  static List<Insight> generate({
    required List<Aggregate> aggregates,
    required DateTime now,
    required int monthlyBudgetMinor,
    required Map<String, String> categoryNames,
    required String Function(int minor) format,
  }) {
    final insights = <Insight>[];
    final today = DateUtilsX.startOfDay(now);
    final tomorrow = DateTime(today.year, today.month, today.day + 1);

    // --- Week over week (same number of elapsed days) ---
    final weekStart = DateUtilsX.startOfWeek(now);
    final weekDays = DateUtilsX.daysBetween(weekStart, tomorrow);
    final lastWeekStart = DateTime(weekStart.year, weekStart.month, weekStart.day - 7);
    final lastWeekEnd = DateTime(lastWeekStart.year, lastWeekStart.month, lastWeekStart.day + weekDays);
    final thisWeek = aggregates.within(weekStart, tomorrow).expenseTotal;
    final lastWeek = aggregates.within(lastWeekStart, lastWeekEnd).expenseTotal;

    // --- Month to date vs same span last month ---
    final monthStart = DateUtilsX.startOfMonth(now);
    final monthDays = DateUtilsX.daysBetween(monthStart, tomorrow);
    final lastMonth = DateUtilsX.lastMonth(now);
    var lastMonthEnd = DateTime(lastMonth.start.year, lastMonth.start.month, lastMonth.start.day + monthDays);
    if (lastMonthEnd.isAfter(lastMonth.end)) lastMonthEnd = lastMonth.end;
    final monthRows = aggregates.within(monthStart, tomorrow).toList();
    final thisMonthExpense = monthRows.expenseTotal;
    final thisMonthIncome = monthRows.incomeTotal;
    final lastMonthExpense = aggregates.within(lastMonth.start, lastMonthEnd).expenseTotal;

    if (thisMonthExpense == 0 && thisMonthIncome == 0 && thisWeek == 0 && lastWeek == 0) {
      return const [
        Insight(
          InsightKind.noData,
          'Add a few transactions this month to unlock personalised insights.',
          InsightTone.neutral,
        ),
      ];
    }

    final weekChange = percentChange(thisWeek, lastWeek);
    if (weekChange != null && weekChange != 0) {
      final more = weekChange > 0;
      insights.add(
        Insight(
          InsightKind.weekTrend,
          'You spent ${weekChange.abs()}% ${more ? 'more' : 'less'} this week than last week.',
          more ? InsightTone.warning : InsightTone.positive,
        ),
      );
    }

    final byCategory = monthRows.expenseByCategory();
    if (byCategory.isNotEmpty && thisMonthExpense > 0) {
      final top = byCategory.first;
      final name = categoryNames[top.key] ?? 'Uncategorized';
      final share = (top.value * 100 / thisMonthExpense).round();
      insights.add(
        Insight(
          InsightKind.topCategory,
          '$name is your highest expense category this month ($share% of spending).',
          InsightTone.neutral,
        ),
      );
    }

    if (monthlyBudgetMinor > 0) {
      final used = (thisMonthExpense * 100 / monthlyBudgetMinor).round();
      insights.add(
        Insight(
          InsightKind.budgetUsage,
          used > 100
              ? 'You have exceeded your monthly budget by ${format(thisMonthExpense - monthlyBudgetMinor)}.'
              : 'You have spent $used% of your monthly budget.',
          used >= 100
              ? InsightTone.negative
              : used >= 75
                  ? InsightTone.warning
                  : InsightTone.neutral,
        ),
      );
    }

    final monthChange = percentChange(thisMonthExpense, lastMonthExpense);
    if (monthChange != null && monthChange != 0) {
      final up = monthChange > 0;
      insights.add(
        Insight(
          InsightKind.monthTrend,
          'Your spending ${up ? 'increased' : 'decreased'} by ${monthChange.abs()}% compared with last month.',
          up ? InsightTone.warning : InsightTone.positive,
        ),
      );
    }

    if (thisMonthExpense > 0) {
      final avg = (thisMonthExpense / monthDays).round();
      insights.add(
        Insight(
          InsightKind.dailyAverage,
          'Your average daily spending this month is ${format(avg)}.',
          InsightTone.neutral,
        ),
      );

      final daysInMonth = DateUtilsX.daysInMonth(now.year, now.month);
      final projected = (thisMonthExpense / monthDays * daysInMonth).round();
      if (monthlyBudgetMinor > 0 && projected > monthlyBudgetMinor && thisMonthExpense <= monthlyBudgetMinor && monthDays < daysInMonth) {
        insights.add(
          Insight(
            InsightKind.projection,
            'At this pace you will spend ${format(projected)} this month, '
            '${format(projected - monthlyBudgetMinor)} over budget.',
            InsightTone.warning,
          ),
        );
      }
    }

    if (thisMonthIncome > 0) {
      final rate = ((thisMonthIncome - thisMonthExpense) * 100 / thisMonthIncome).round();
      insights.add(
        Insight(
          InsightKind.savingsRate,
          rate >= 0
              ? 'You have saved $rate% of your income this month.'
              : 'You are spending ${rate.abs()}% more than you earned this month.',
          rate >= 20
              ? InsightTone.positive
              : rate >= 0
                  ? InsightTone.neutral
                  : InsightTone.negative,
        ),
      );
    }

    return insights;
  }

  /// Rounded percentage change from [previous] to [current]; null when there
  /// is no baseline to compare with.
  static int? percentChange(int current, int previous) {
    if (previous <= 0) return null;
    return ((current - previous) * 100 / previous).round();
  }
}
