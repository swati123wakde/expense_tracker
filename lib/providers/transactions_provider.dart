import '../app/dependencies.dart';
import '../core/services/data_change_bus.dart';
import '../data/models/enums.dart';
import '../data/models/transaction.dart';
import '../data/models/transaction_filter.dart';
import 'bus_aware_notifier.dart';

/// Transaction history (filtered, paginated) plus create/edit/delete.
/// Pages are fetched with keyset pagination so 10k+ rows never live in memory
/// at once; the list grows only as the user scrolls.
class TransactionsProvider extends BusAwareNotifier {
  TransactionsProvider(this._deps, {this.pageSize = 40})
      : super(_deps.bus, {Tables.transactions, Tables.categories, Tables.accounts});

  final AppDependencies _deps;
  final int pageSize;

  TransactionFilter _filter = TransactionFilter.none;
  TransactionFilter get filter => _filter;

  List<TransactionView> items = const [];
  bool hasMore = false;
  bool loadingMore = false;
  int totalCount = 0;
  int filteredIncomeMinor = 0;
  int filteredExpenseMinor = 0;
  String baseCurrency = 'USD';
  int _generation = 0;

  @override
  Future<void> reload() async {
    final generation = ++_generation;
    final converter = await _deps.currency.converter();
    // Keep the user's scroll depth when refreshing after an edit.
    final limit = items.length > pageSize ? items.length : pageSize;
    final page = await _deps.transactions.page(
      _filter,
      limit: limit + 1,
      fallbackCurrency: converter.baseCurrency,
    );
    final count = await _deps.transactions.count(_filter);
    final totals = await _deps.transactions.totals(_filter, converter.baseCurrency);
    if (generation != _generation) return;
    baseCurrency = converter.baseCurrency;
    hasMore = page.length > limit;
    items = hasMore ? page.sublist(0, limit) : page;
    totalCount = count;
    filteredIncomeMinor = 0;
    filteredExpenseMinor = 0;
    for (final t in totals) {
      final v = converter.convert(t.total, t.currency);
      if (t.type == TransactionType.income) {
        filteredIncomeMinor += v;
      } else {
        filteredExpenseMinor += v;
      }
    }
  }

  Future<void> loadMore() async {
    if (!hasMore || loadingMore || items.isEmpty) return;
    loadingMore = true;
    notifySafely();
    final generation = _generation;
    try {
      final last = items.last.transaction;
      final page = await _deps.transactions.page(
        _filter,
        after: PageCursor(last.occurredAt.millisecondsSinceEpoch, last.id),
        limit: pageSize + 1,
        fallbackCurrency: baseCurrency,
      );
      if (generation != _generation) return;
      hasMore = page.length > pageSize;
      items = [...items, ...(hasMore ? page.sublist(0, pageSize) : page)];
    } finally {
      loadingMore = false;
      notifySafely();
    }
  }

  Future<void> setFilter(TransactionFilter filter) async {
    if (filter == _filter) return;
    _filter = filter;
    items = const [];
    status = LoadStatus.loading; // show skeleton, not a flash of "no results"
    notifySafely();
    await load();
  }

  Future<void> setQuery(String query) => setFilter(_filter.copyWith(query: query));

  Future<void> clearFilters() => setFilter(TransactionFilter(query: _filter.query));

  // ---------------------------------------------------------------------------
  // Mutations. Each writes locally first; providers refresh via the change bus
  // and the sync engine uploads in the background.
  // ---------------------------------------------------------------------------

  Future<void> add(TransactionDraft draft) async {
    final recurrence = draft.recurrence;
    if (recurrence != null) {
      await _deps.recurring.createFromDraft(draft, recurrence);
    } else {
      await _deps.transactions.create(draft);
    }
  }

  Future<void> update(String id, TransactionDraft draft) async {
    await _deps.transactions.update(id, draft);
  }

  /// Removes the row from the visible list synchronously (so swipe-to-delete
  /// animations never see a stale item) and soft-deletes it in the database.
  Future<TransactionEntity?> delete(String id) {
    if (items.any((v) => v.id == id)) {
      items = items.where((v) => v.id != id).toList();
      if (totalCount > 0) totalCount--;
      notifySafely();
    }
    return _deps.transactions.delete(id);
  }

  Future<void> undoDelete(TransactionEntity previous) => _deps.transactions.restore(previous);

  Future<void> toggleFavorite(TransactionEntity t) => _deps.transactions.setFavorite(t.id, !t.isFavorite);

  Future<TransactionEntity?> byId(String id) => _deps.transactions.byId(id);
}
