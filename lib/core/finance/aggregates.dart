import '../../data/models/enums.dart';
import 'currency_converter.dart';

/// One row of the grouped SQL aggregate used by dashboard and analytics:
/// SUM(amount) per (day, type, category, currency).
class DailyAggregate {
  const DailyAggregate({
    required this.day,
    required this.type,
    required this.categoryId,
    required this.currency,
    required this.totalMinor,
    this.count = 1,
  });

  final DateTime day;
  final TransactionType type;
  final String categoryId;
  final String currency;
  final int totalMinor;
  final int count;

  bool get isExpense => type == TransactionType.expense;
}

/// Aggregate converted into the base currency (currency dimension removed).
class Aggregate {
  const Aggregate({
    required this.day,
    required this.type,
    required this.categoryId,
    required this.amountMinor,
    this.count = 1,
  });

  final DateTime day;
  final TransactionType type;
  final String categoryId;
  final int amountMinor;
  final int count;

  bool get isExpense => type == TransactionType.expense;
  bool get isIncome => type == TransactionType.income;

  static List<Aggregate> convertAll(
    Iterable<DailyAggregate> rows,
    CurrencyConverter converter,
  ) =>
      [
        for (final r in rows)
          Aggregate(
            day: r.day,
            type: r.type,
            categoryId: r.categoryId,
            amountMinor: converter.convert(r.totalMinor, r.currency),
            count: r.count,
          ),
      ];
}

/// Small helpers for summing aggregates inside a date window.
extension AggregateSums on Iterable<Aggregate> {
  Iterable<Aggregate> within(DateTime start, DateTime end) =>
      where((a) => !a.day.isBefore(start) && a.day.isBefore(end));

  int get expenseTotal =>
      where((a) => a.isExpense).fold(0, (sum, a) => sum + a.amountMinor);

  int get incomeTotal =>
      where((a) => a.isIncome).fold(0, (sum, a) => sum + a.amountMinor);

  /// Expense per category, sorted descending by amount.
  List<MapEntry<String, int>> expenseByCategory() {
    final map = <String, int>{};
    for (final a in where((a) => a.isExpense)) {
      map[a.categoryId] = (map[a.categoryId] ?? 0) + a.amountMinor;
    }
    final entries = map.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    return entries;
  }
}
