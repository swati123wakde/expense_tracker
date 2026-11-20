import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../data/models/recurring_rule.dart';
import '../../providers/bus_aware_notifier.dart';
import '../../providers/categories_provider.dart';
import '../../providers/recurring_provider.dart';
import '../common/amount_dialog.dart';
import '../common/common_widgets.dart';
import '../transactions/add_edit_transaction_screen.dart';

class RecurringScreen extends StatelessWidget {
  const RecurringScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final p = context.watch<RecurringProvider>();
    final categories = context.watch<CategoriesProvider>();
    final fmt = DateFormat('d MMM y');

    return Scaffold(
      appBar: AppBar(title: const Text('Recurring & subscriptions')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => AddEditTransactionScreen.open(context),
        icon: const Icon(Icons.add),
        label: const Text('New'),
      ),
      body: p.status == LoadStatus.error
          ? ErrorState(message: p.error ?? '', onRetry: p.load)
          : p.isLoading
              ? const Padding(padding: EdgeInsets.all(16), child: ListSkeleton(count: 3))
              : p.rules.isEmpty
                  ? const EmptyState(
                      icon: Icons.repeat,
                      title: 'No recurring transactions',
                      message: 'Turn on "Recurring" when adding rent, salary or subscriptions like Netflix.',
                    )
                  : ListView(
                      padding: Spacing.page,
                      children: [
                        AppCard(
                          color: Theme.of(context).colorScheme.tertiaryContainer,
                          child: Text(
                            'Recurring expenses cost about '
                            '${Money.format(p.monthlyCommitmentMinor, p.rules.isEmpty ? 'USD' : p.currencyOf(p.rules.first))} per month',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        const SizedBox(height: 12),
                        for (final r in p.rules)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 10),
                            child: AppCard(
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                              child: ListTile(
                                contentPadding: EdgeInsets.zero,
                                leading: CategoryAvatar(
                                  icon: categories.byId[r.categoryId]?.icon ?? 'other',
                                  color: categories.byId[r.categoryId]?.color ?? 0xFF757575,
                                ),
                                title: Text(r.note.isNotEmpty ? r.note : categories.nameOf(r.categoryId)),
                                subtitle: Text(
                                  '${Money.format(r.amountMinor, p.currencyOf(r))} • ${r.frequency.label}\n'
                                  '${r.active ? 'Next: ${fmt.format(r.nextDueAt)}' : 'Paused'}',
                                ),
                                isThreeLine: true,
                                trailing: Switch(
                                  value: r.active,
                                  onChanged: (v) => p.setActive(r.id, v),
                                ),
                                onTap: () => _actions(context, r),
                              ),
                            ),
                          ),
                      ],
                    ),
    );
  }

  Future<void> _actions(BuildContext context, RecurringRule r) async {
    final p = context.read<RecurringProvider>();
    final action = await showModalBottomSheet<String>(
      context: context,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: const Text('Change amount'),
              onTap: () => Navigator.pop(ctx, 'amount'),
            ),
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('Stop & delete rule'),
              subtitle: const Text('Transactions already created are kept'),
              onTap: () => Navigator.pop(ctx, 'delete'),
            ),
          ],
        ),
      ),
    );
    if (!context.mounted) return;
    if (action == 'amount') {
      final v = await showAmountDialog(context, title: 'New amount', currency: p.currencyOf(r), initialMinor: r.amountMinor);
      if (v != null) {
        await p.update(r.id, amountMinor: v, note: r.note, categoryId: r.categoryId, accountId: r.accountId, active: r.active);
      }
    } else if (action == 'delete') {
      final ok = await confirmDialog(
        context,
        title: 'Delete recurring rule?',
        message: 'No new transactions will be created.',
        confirmLabel: 'Delete',
        destructive: true,
      );
      if (ok) await p.delete(r.id);
    }
  }
}
