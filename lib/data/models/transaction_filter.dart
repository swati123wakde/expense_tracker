import 'package:collection/collection.dart';

import 'enums.dart';

/// Combinable filter for transaction history, CSV export and counts.
/// Dates are a half-open range [from, to).
class TransactionFilter {
  const TransactionFilter({
    this.type,
    this.categoryIds = const {},
    this.accountIds = const {},
    this.from,
    this.to,
    this.minAmountMinor,
    this.maxAmountMinor,
    this.query = '',
    this.favoritesOnly = false,
  });

  static const TransactionFilter none = TransactionFilter();

  final TransactionType? type;
  final Set<String> categoryIds;
  final Set<String> accountIds;
  final DateTime? from;
  final DateTime? to;
  final int? minAmountMinor;
  final int? maxAmountMinor;
  final String query;
  final bool favoritesOnly;

  bool get isEmpty => activeCount == 0 && query.trim().isEmpty;

  /// Number of active filter groups (search excluded), for the filter badge.
  int get activeCount =>
      (type != null ? 1 : 0) +
      (categoryIds.isNotEmpty ? 1 : 0) +
      (accountIds.isNotEmpty ? 1 : 0) +
      (from != null || to != null ? 1 : 0) +
      (minAmountMinor != null || maxAmountMinor != null ? 1 : 0) +
      (favoritesOnly ? 1 : 0);

  TransactionFilter copyWith({
    TransactionType? type,
    bool clearType = false,
    Set<String>? categoryIds,
    Set<String>? accountIds,
    DateTime? from,
    DateTime? to,
    bool clearDates = false,
    int? minAmountMinor,
    int? maxAmountMinor,
    bool clearAmounts = false,
    String? query,
    bool? favoritesOnly,
  }) =>
      TransactionFilter(
        type: clearType ? null : (type ?? this.type),
        categoryIds: categoryIds ?? this.categoryIds,
        accountIds: accountIds ?? this.accountIds,
        from: clearDates ? null : (from ?? this.from),
        to: clearDates ? null : (to ?? this.to),
        minAmountMinor: clearAmounts ? null : (minAmountMinor ?? this.minAmountMinor),
        maxAmountMinor: clearAmounts ? null : (maxAmountMinor ?? this.maxAmountMinor),
        query: query ?? this.query,
        favoritesOnly: favoritesOnly ?? this.favoritesOnly,
      );

  static const _setEq = SetEquality<String>();

  @override
  bool operator ==(Object other) =>
      other is TransactionFilter &&
      other.type == type &&
      _setEq.equals(other.categoryIds, categoryIds) &&
      _setEq.equals(other.accountIds, accountIds) &&
      other.from == from &&
      other.to == to &&
      other.minAmountMinor == minAmountMinor &&
      other.maxAmountMinor == maxAmountMinor &&
      other.query == query &&
      other.favoritesOnly == favoritesOnly;

  @override
  int get hashCode => Object.hash(
        type,
        _setEq.hash(categoryIds),
        _setEq.hash(accountIds),
        from,
        to,
        minAmountMinor,
        maxAmountMinor,
        query,
        favoritesOnly,
      );
}

/// Keyset pagination cursor: (occurredAt, id) of the last row of a page.
class PageCursor {
  const PageCursor(this.occurredAtMs, this.id);
  final int occurredAtMs;
  final String id;
}
