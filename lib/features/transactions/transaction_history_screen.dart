import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../data/models/transaction.dart';
import '../../data/models/transaction_filter.dart';
import '../../providers/bus_aware_notifier.dart';
import '../../providers/transactions_provider.dart';
import '../common/common_widgets.dart';
import '../common/sync_status_chip.dart';
import '../settings/export_helper.dart';
import 'add_edit_transaction_screen.dart';
import 'filter_sheet.dart';
import 'transaction_details_sheet.dart';
import 'transaction_tile.dart';

class TransactionHistoryScreen extends StatefulWidget {
  const TransactionHistoryScreen({super.key});

  @override
  State<TransactionHistoryScreen> createState() => _TransactionHistoryScreenState();
}

class _TransactionHistoryScreenState extends State<TransactionHistoryScreen> {
  final _search = TextEditingController();
  final _scroll = ScrollController();
  Timer? _debounce;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
    _search.text = context.read<TransactionsProvider>().filter.query;
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scroll.position.pixels > _scroll.position.maxScrollExtent - 600) {
      context.read<TransactionsProvider>().loadMore();
    }
  }

  void _onSearchChanged(String value) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) context.read<TransactionsProvider>().setQuery(value);
    });
  }

  Future<void> _openFilters() async {
    final provider = context.read<TransactionsProvider>();
    final result = await FilterSheet.show(context, provider.filter);
    if (result != null) await provider.setFilter(result);
  }

  Future<void> _delete(TransactionView view) async {
    final provider = context.read<TransactionsProvider>();
    final previous = await provider.delete(view.id);
    if (!mounted || previous == null) return;
    showSnack(
      context,
      'Transaction deleted',
      action: SnackBarAction(label: 'Undo', onPressed: () => provider.undoDelete(previous)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final provider = context.watch<TransactionsProvider>();
    final filter = provider.filter;
    final colors = FinanceColors.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Transactions'),
        actions: [
          const Padding(padding: EdgeInsets.only(right: 4), child: SyncStatusChip()),
          IconButton(
            tooltip: 'Export CSV',
            icon: const Icon(Icons.ios_share),
            onPressed: () => ExportHelper.exportCsv(context, filter),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    key: const Key('searchField'),
                    controller: _search,
                    onChanged: _onSearchChanged,
                    textInputAction: TextInputAction.search,
                    decoration: InputDecoration(
                      hintText: 'Search note, category or amount',
                      prefixIcon: const Icon(Icons.search),
                      suffixIcon: _search.text.isEmpty
                          ? null
                          : IconButton(
                              icon: const Icon(Icons.clear),
                              onPressed: () {
                                _search.clear();
                                provider.setQuery('');
                              },
                            ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Badge(
                  isLabelVisible: filter.activeCount > 0,
                  label: Text('${filter.activeCount}'),
                  child: IconButton.filledTonal(
                    key: const Key('openFilters'),
                    tooltip: 'Filters',
                    icon: const Icon(Icons.tune),
                    onPressed: _openFilters,
                  ),
                ),
              ],
            ),
          ),
          if (!filter.isEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      '${provider.totalCount} results • '
                      'In ${Money.format(provider.filteredIncomeMinor, provider.baseCurrency)} • '
                      'Out ${Money.format(provider.filteredExpenseMinor, provider.baseCurrency)}',
                      key: const Key('filterSummary'),
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  ),
                  if (filter.activeCount > 0)
                    TextButton(onPressed: provider.clearFilters, child: const Text('Clear')),
                ],
              ),
            ),
          Expanded(child: _buildList(provider, colors)),
        ],
      ),
    );
  }

  Widget _buildList(TransactionsProvider provider, FinanceColors colors) {
    if (provider.status == LoadStatus.error) {
      return ErrorState(message: provider.error ?? 'Could not load transactions', onRetry: provider.load);
    }
    if (provider.isLoading && provider.items.isEmpty) {
      return const Padding(padding: EdgeInsets.all(16), child: ListSkeleton());
    }
    if (provider.items.isEmpty) {
      return provider.filter.isEmpty
          ? EmptyState(
              icon: Icons.receipt_long,
              title: 'No transactions yet',
              message: 'Tap + to record your first income or expense.',
              actionLabel: 'Add transaction',
              onAction: () => AddEditTransactionScreen.open(context),
            )
          : EmptyState(
              icon: Icons.search_off,
              title: 'No matching transactions',
              message: 'Try a different search or clear some filters.',
              actionLabel: 'Clear filters',
              onAction: () {
                _search.clear();
                provider.setFilter(TransactionFilter.none);
              },
            );
    }

    final count = provider.items.length + (provider.hasMore ? 1 : 0);
    return RefreshIndicator(
      onRefresh: provider.load,
      child: ListView.builder(
        key: const Key('transactionList'),
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.only(bottom: 100),
        itemCount: count,
        itemBuilder: (context, index) {
          if (index >= provider.items.length) {
            return const Padding(
              padding: EdgeInsets.all(16),
              child: Center(child: CircularProgressIndicator()),
            );
          }
          final view = provider.items[index];
          return Dismissible(
            key: ValueKey(view.id),
            background: _SwipeBackground(
              color: Theme.of(context).colorScheme.primary,
              icon: Icons.edit,
              label: 'Edit',
              alignment: Alignment.centerLeft,
            ),
            secondaryBackground: _SwipeBackground(
              color: colors.expense,
              icon: Icons.delete,
              label: 'Delete',
              alignment: Alignment.centerRight,
            ),
            confirmDismiss: (direction) async {
              if (direction == DismissDirection.startToEnd) {
                await AddEditTransactionScreen.open(context, existing: view.transaction);
                return false;
              }
              return true;
            },
            onDismissed: (_) => _delete(view),
            child: TransactionTile(
              view: view,
              onTap: () => TransactionDetailsSheet.show(context, view),
            ),
          );
        },
      ),
    );
  }
}

class _SwipeBackground extends StatelessWidget {
  const _SwipeBackground({
    required this.color,
    required this.icon,
    required this.label,
    required this.alignment,
  });

  final Color color;
  final IconData icon;
  final String label;
  final Alignment alignment;

  @override
  Widget build(BuildContext context) => Container(
        color: color,
        alignment: alignment,
        padding: const EdgeInsets.symmetric(horizontal: 24),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, color: Colors.white),
            const SizedBox(width: 8),
            Text(label, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w600)),
          ],
        ),
      );
}
