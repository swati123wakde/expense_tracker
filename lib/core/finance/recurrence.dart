import '../../data/models/enums.dart';
import '../utils/date_utils.dart';

/// Pure date maths for recurring transactions.
///
/// Occurrence n is always computed from the original start date (not from the
/// previous occurrence) so monthly rules anchored on the 31st land on the last
/// day of short months and then return to the 31st.
class Recurrence {
  Recurrence._();

  static DateTime occurrence(DateTime start, RecurrenceFrequency f, int index) {
    switch (f) {
      case RecurrenceFrequency.daily:
        return DateTime(start.year, start.month, start.day + index, start.hour, start.minute);
      case RecurrenceFrequency.weekly:
        return DateTime(start.year, start.month, start.day + 7 * index, start.hour, start.minute);
      case RecurrenceFrequency.monthly:
        return DateUtilsX.addMonthsClamped(start, index);
      case RecurrenceFrequency.yearly:
        return DateUtilsX.addMonthsClamped(start, 12 * index);
    }
  }

  /// Indexes of occurrences in [fromIndex, ...) that are due at [now]
  /// (occurrence <= now) and not past [endAt]. Capped by [maxCatchUp] so a
  /// daily rule on a device that was off for years can't flood the database.
  static List<int> dueIndexes({
    required DateTime start,
    required RecurrenceFrequency frequency,
    required int fromIndex,
    required DateTime now,
    DateTime? endAt,
    int maxCatchUp = 366,
  }) {
    final result = <int>[];
    var i = fromIndex;
    while (result.length < maxCatchUp) {
      final when = occurrence(start, frequency, i);
      if (when.isAfter(now)) break;
      if (endAt != null && when.isAfter(endAt)) break;
      result.add(i);
      i++;
    }
    return result;
  }

  /// Deterministic transaction id for occurrence [index] of [ruleId], so two
  /// devices materialising the same occurrence produce the same record.
  static String transactionId(String ruleId, int index) => 'rec_${ruleId}_$index';
}
