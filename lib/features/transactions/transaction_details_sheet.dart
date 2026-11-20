import 'dart:io';

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/theme/app_theme.dart';
import '../../data/models/enums.dart';
import '../../data/models/transaction.dart';
import '../../providers/transactions_provider.dart';
import '../common/common_widgets.dart';
import 'add_edit_transaction_screen.dart';

class TransactionDetailsSheet extends StatelessWidget {
  const TransactionDetailsSheet({super.key, required this.view});

  final TransactionView view;

  static Future<void> show(BuildContext context, TransactionView view) => showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        builder: (_) => TransactionDetailsSheet(view: view),
      );

  @override
  Widget build(BuildContext context) {
    final t = view.transaction;
    final provider = context.read<TransactionsProvider>();
    final scheme = Theme.of(context).colorScheme;
    final rootContext = Navigator.of(context).context;

    Widget row(IconData icon, String label, String value) => ListTile(
          dense: true,
          contentPadding: EdgeInsets.zero,
          leading: Icon(icon, color: scheme.onSurfaceVariant),
          title: Text(label, style: Theme.of(context).textTheme.bodySmall),
          subtitle: Text(value, style: Theme.of(context).textTheme.bodyLarge),
        );

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CategoryAvatar(icon: view.categoryIcon, color: view.categoryColor, size: 52),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(view.categoryName, style: Theme.of(context).textTheme.titleMedium),
                    Text(
                      t.type == TransactionType.income ? 'Income' : 'Expense',
                      style: TextStyle(color: scheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
              AmountText(
                amountMinor: t.amountMinor,
                currency: view.currency,
                type: t.type,
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ],
          ),
          const SizedBox(height: Spacing.md),
          if (t.note.isNotEmpty) row(Icons.notes, 'Note', t.note),
          row(Icons.account_balance_wallet_outlined, 'Account', view.accountName),
          row(Icons.event, 'Date', DateFormat('EEEE, d MMMM y • h:mm a').format(t.occurredAt)),
          if (t.recurringRuleId != null) row(Icons.repeat, 'Recurring', 'Created by a recurring rule'),
          row(
            t.syncStatus == SyncStatus.synced ? Icons.cloud_done_outlined : Icons.cloud_upload_outlined,
            'Sync',
            t.syncStatus == SyncStatus.synced ? 'Synced' : 'Waiting to sync',
          ),
          if (t.attachmentPath != null && File(t.attachmentPath!).existsSync())
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(12),
                child: Image.file(File(t.attachmentPath!), height: 180, width: double.infinity, fit: BoxFit.cover),
              ),
            ),
          const SizedBox(height: Spacing.md),
          Row(
            children: [
              IconButton.filledTonal(
                tooltip: t.isFavorite ? 'Unfavorite' : 'Favorite',
                icon: Icon(t.isFavorite ? Icons.star_rounded : Icons.star_outline_rounded),
                onPressed: () {
                  provider.toggleFavorite(t);
                  Navigator.pop(context);
                },
              ),
              const SizedBox(width: 8),
              Expanded(
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Delete'),
                  style: OutlinedButton.styleFrom(foregroundColor: scheme.error),
                  onPressed: () async {
                    final ok = await confirmDialog(
                      context,
                      title: 'Delete transaction?',
                      message: 'You can undo this right after deleting.',
                      confirmLabel: 'Delete',
                      destructive: true,
                    );
                    if (!ok || !context.mounted) return;
                    Navigator.pop(context);
                    final previous = await provider.delete(t.id);
                    if (previous != null && rootContext.mounted) {
                      showSnack(
                        rootContext,
                        'Transaction deleted',
                        action: SnackBarAction(label: 'Undo', onPressed: () => provider.undoDelete(previous)),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: FilledButton.icon(
                  icon: const Icon(Icons.edit),
                  label: const Text('Edit'),
                  onPressed: () {
                    Navigator.pop(context);
                    AddEditTransactionScreen.open(rootContext, existing: t);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
