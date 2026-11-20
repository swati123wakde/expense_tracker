/// Half-open date range [start, end).
class DateRange {
  const DateRange(this.start, this.end);

  final DateTime start;
  final DateTime end;

  bool contains(DateTime d) => !d.isBefore(start) && d.isBefore(end);

  int get startMs => start.millisecondsSinceEpoch;
  int get endMs => end.millisecondsSinceEpoch;

  /// Number of calendar days covered by the range.
  int get dayCount => DateUtilsX.daysBetween(start, end);

  @override
  bool operator ==(Object other) =>
      other is DateRange && other.start == start && other.end == end;

  @override
  int get hashCode => Object.hash(start, end);

  @override
  String toString() => 'DateRange($start, $end)';
}

class DateUtilsX {
  DateUtilsX._();

  static DateTime startOfDay(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Weeks start on Monday.
  static DateTime startOfWeek(DateTime d) {
    final day = startOfDay(d);
    return DateTime(day.year, day.month, day.day - (day.weekday - DateTime.monday));
  }

  static DateTime startOfMonth(DateTime d) => DateTime(d.year, d.month);

  static DateTime startOfYear(DateTime d) => DateTime(d.year);

  static int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

  /// Adds months keeping the day-of-month where possible and clamping
  /// otherwise (Jan 31 + 1 month = Feb 28/29). Preserves time of day.
  static DateTime addMonthsClamped(DateTime d, int months) {
    final totalMonths = d.year * 12 + (d.month - 1) + months;
    final year = totalMonths ~/ 12;
    final month = totalMonths % 12 + 1;
    final maxDay = daysInMonth(year, month);
    final day = d.day > maxDay ? maxDay : d.day;
    return DateTime(year, month, day, d.hour, d.minute, d.second, d.millisecond);
  }

  /// Calendar-day difference, safe across DST changes.
  static int daysBetween(DateTime a, DateTime b) {
    final ua = DateTime.utc(a.year, a.month, a.day);
    final ub = DateTime.utc(b.year, b.month, b.day);
    return ub.difference(ua).inDays;
  }

  static DateRange today(DateTime now) {
    final s = startOfDay(now);
    return DateRange(s, DateTime(s.year, s.month, s.day + 1));
  }

  static DateRange day(DateTime d) => today(d);

  static DateRange thisWeek(DateTime now) {
    final s = startOfWeek(now);
    return DateRange(s, DateTime(s.year, s.month, s.day + 7));
  }

  static DateRange lastWeek(DateTime now) {
    final s = startOfWeek(now);
    return DateRange(DateTime(s.year, s.month, s.day - 7), s);
  }

  static DateRange month(DateTime anyDayInMonth) {
    final s = startOfMonth(anyDayInMonth);
    return DateRange(s, DateTime(s.year, s.month + 1));
  }

  static DateRange lastMonth(DateTime now) =>
      month(DateTime(now.year, now.month - 1));

  static DateRange year(DateTime now) =>
      DateRange(DateTime(now.year), DateTime(now.year + 1));

  /// String key "yyyy-MM-dd" matching SQLite strftime('%Y-%m-%d').
  static String dayKey(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static DateTime parseDayKey(String key) {
    final parts = key.split('-');
    return DateTime(int.parse(parts[0]), int.parse(parts[1]), int.parse(parts[2]));
  }

  static const List<String> monthNames = [
    'January', 'February', 'March', 'April', 'May', 'June', 'July', //
    'August', 'September', 'October', 'November', 'December',
  ];

  static String monthName(int month) => monthNames[month - 1];
}
