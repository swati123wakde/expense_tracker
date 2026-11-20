import '../utils/date_utils.dart';
import 'aggregates.dart';

enum AnalyticsPeriod {
  week('Week'),
  month('Month'),
  threeMonths('3 Months'),
  year('Year');

  const AnalyticsPeriod(this.label);
  final String label;

  /// Calendar window that contains [now].
  DateRange range(DateTime now) {
    switch (this) {
      case AnalyticsPeriod.week:
        return DateUtilsX.thisWeek(now);
      case AnalyticsPeriod.month:
        return DateUtilsX.month(now);
      case AnalyticsPeriod.threeMonths:
        final start = DateTime(now.year, now.month - 2);
        return DateRange(start, DateTime(now.year, now.month + 1));
      case AnalyticsPeriod.year:
        return DateUtilsX.year(now);
    }
  }

  BucketGranularity get granularity {
    switch (this) {
      case AnalyticsPeriod.week:
      case AnalyticsPeriod.month:
        return BucketGranularity.day;
      case AnalyticsPeriod.threeMonths:
        return BucketGranularity.week;
      case AnalyticsPeriod.year:
        return BucketGranularity.month;
    }
  }
}

enum BucketGranularity { day, week, month }

class Bucket {
  const Bucket({
    required this.start,
    required this.end,
    required this.label,
    required this.incomeMinor,
    required this.expenseMinor,
  });

  final DateTime start;
  final DateTime end;
  final String label;
  final int incomeMinor;
  final int expenseMinor;

  int get netMinor => incomeMinor - expenseMinor;
}

class CategoryShare {
  const CategoryShare(this.categoryId, this.amountMinor, this.share);
  final String categoryId;
  final int amountMinor;

  /// 0..1 fraction of total expenses.
  final double share;
}

class AnalyticsResult {
  const AnalyticsResult({
    required this.range,
    required this.incomeMinor,
    required this.expenseMinor,
    required this.categoryShares,
    required this.buckets,
    required this.averageDailyExpenseMinor,
    required this.transactionCount,
  });

  final DateRange range;
  final int incomeMinor;
  final int expenseMinor;
  final List<CategoryShare> categoryShares;
  final List<Bucket> buckets;
  final int averageDailyExpenseMinor;
  final int transactionCount;

  int get netSavingsMinor => incomeMinor - expenseMinor;

  /// Savings as a fraction of income (can be negative); null with no income.
  double? get savingsRate => incomeMinor <= 0 ? null : netSavingsMinor / incomeMinor;

  bool get isEmpty => transactionCount == 0;
}

class AnalyticsCalculator {
  AnalyticsCalculator._();

  static const _weekdayShort = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _monthShort = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];

  static AnalyticsResult compute({
    required List<Aggregate> aggregates,
    required AnalyticsPeriod period,
    required DateTime now,
  }) {
    final range = period.range(now);
    final rows = aggregates.within(range.start, range.end).toList();
    final income = rows.incomeTotal;
    final expense = rows.expenseTotal;

    final byCategory = rows.expenseByCategory();
    final shares = [
      for (final e in byCategory)
        CategoryShare(e.key, e.value, expense == 0 ? 0 : e.value / expense),
    ];

    final buckets = buildBuckets(rows, range, period.granularity, period);

    // Average over elapsed days only (a month that's 10 days in divides by 10).
    final today = DateUtilsX.startOfDay(now);
    final elapsedEnd = today.isBefore(range.end)
        ? DateTime(today.year, today.month, today.day + 1)
        : range.end;
    final rawDays = DateUtilsX.daysBetween(range.start, elapsedEnd);
    final elapsedDays = rawDays < 1 ? 1 : rawDays;

    return AnalyticsResult(
      range: range,
      incomeMinor: income,
      expenseMinor: expense,
      categoryShares: shares,
      buckets: buckets,
      averageDailyExpenseMinor: (expense / elapsedDays).round(),
      transactionCount: rows.fold(0, (s, a) => s + a.count),
    );
  }

  static List<Bucket> buildBuckets(
    List<Aggregate> rows,
    DateRange range,
    BucketGranularity g,
    AnalyticsPeriod period,
  ) {
    final starts = <DateTime>[];
    var cursor = range.start;
    if (g == BucketGranularity.week) cursor = DateUtilsX.startOfWeek(cursor);
    while (cursor.isBefore(range.end)) {
      starts.add(cursor);
      cursor = _next(cursor, g);
    }

    final buckets = <Bucket>[];
    for (var i = 0; i < starts.length; i++) {
      final s = starts[i];
      final e = i + 1 < starts.length ? starts[i + 1] : _next(s, g);
      final inBucket = rows.where((a) => !a.day.isBefore(s) && a.day.isBefore(e));
      buckets.add(
        Bucket(
          start: s,
          end: e,
          label: _label(s, g, period),
          incomeMinor: inBucket.incomeTotal,
          expenseMinor: inBucket.expenseTotal,
        ),
      );
    }
    return buckets;
  }

  static DateTime _next(DateTime d, BucketGranularity g) {
    switch (g) {
      case BucketGranularity.day:
        return DateTime(d.year, d.month, d.day + 1);
      case BucketGranularity.week:
        return DateTime(d.year, d.month, d.day + 7);
      case BucketGranularity.month:
        return DateTime(d.year, d.month + 1);
    }
  }

  static String _label(DateTime d, BucketGranularity g, AnalyticsPeriod p) {
    switch (g) {
      case BucketGranularity.day:
        return p == AnalyticsPeriod.week ? _weekdayShort[d.weekday - 1] : '${d.day}';
      case BucketGranularity.week:
        return '${d.day} ${_monthShort[d.month - 1]}';
      case BucketGranularity.month:
        return _monthShort[d.month - 1];
    }
  }
}
