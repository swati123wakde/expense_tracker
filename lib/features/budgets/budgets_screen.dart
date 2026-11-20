import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/finance/budget_calculator.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/enums.dart';
import '../../providers/budgets_provider.dart';
import '../../providers/bus_aware_notifier.dart';
import '../../providers/categories_provider.dart';
import '../common/amount_dialog.dart';
import '../common/common_widgets.dart';

class BudgetsScreen extends StatelessWidget {
  const BudgetsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final b = context.watch<BudgetsProvider>();
    final categories = context.watch<CategoriesProvider>();

    Future<void> editOverall() async {
      final amount = await showAmountDialog(
        context,
        title: 'Monthly budget',
        currency: b.baseCurrency,
        initialMinor: b.overall?.limitMinor,
        allowZero: true,
      );
      if (amount != null) await b.setOverall(amount);
    }

    Future<void> addCategoryBudget() async {
      final existing = {for (final c in b.categoryBudgets) c.budget.categoryId};
      final options = categories.active(TransactionType.expense).where((c) => !existing.contains(c.id)).toList();
      if (options.isEmpty) {
        showSnack(context, 'Every expense category already has a budget');
        return;
      }
      final categoryId = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            children: [
              const ListTile(title: Text('Choose a category')),
              for (final c in options)
                ListTile(
                  leading: CategoryAvatar(icon: c.icon, color: c.color, size: 36),
                  title: Text(c.name),
                  onTap: () => Navigator.pop(ctx, c.id),
                ),
            ],
          ),
        ),
      );
      if (categoryId == null || !context.mounted) return;
      final amount = await showAmountDialog(
        context,
        title: '${categories.nameOf(categoryId)} budget',
        currency: b.baseCurrency,
      );
      if (amount != null) await b.setCategoryBudget(categoryId, amount);
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Budgets')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: addCategoryBudget,
        icon: const Icon(Icons.add),
        label: const Text('Category budget'),
      ),
      body: b.status == LoadStatus.error
          ? ErrorState(message: b.error ?? '', onRetry: b.load)
          : b.isLoading
              ? const Padding(padding: EdgeInsets.all(16), child: ListSkeleton(count: 4))
              : ListView(
                  padding: Spacing.page,
                  children: [
                    Text('${b.monthName} overview', style: Theme.of(context).textTheme.bodySmall),
                    const SizedBox(height: 8),
                    if (b.overall == null)
                      AppCard(
                        onTap: editOverall,
                        child: const ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Icons.pie_chart_outline),
                          title: Text('Set a monthly budget'),
                          subtitle: Text('Get warnings at 50%, 75%, 90% and 100%'),
                          trailing: Icon(Icons.add),
                        ),
                      )
                    else
                      BudgetStatusCard(
                        title: 'Monthly budget',
                        status: b.overall!,
                        format: b.format,
                        warning: b.warningFor(b.overall!),
                        onEdit: editOverall,
                      ),
                    const SectionHeader(title: 'Category budgets'),
                    if (b.categoryBudgets.isEmpty)
                      const EmptyState(
                        icon: Icons.category_outlined,
                        title: 'No category budgets',
                        message: 'Limit spending per category, e.g. Food \$400 / month.',
                      ),
                    for (final c in b.categoryBudgets)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: BudgetStatusCard(
                          title: c.categoryName,
                          icon: categories.byId[c.budget.categoryId]?.icon,
                          color: categories.byId[c.budget.categoryId]?.color,
                          status: c.status,
                          format: b.format,
                          warning: b.warningFor(c.status, categoryName: c.categoryName),
                          onEdit: () async {
                            final amount = await showAmountDialog(
                              context,
                              title: '${c.categoryName} budget',
                              currency: b.baseCurrency,
                              initialMinor: c.budget.amountMinor,
                            );
                            if (amount != null) await b.setCategoryBudget(c.budget.categoryId!, amount);
                          },
                          onDelete: () => b.remove(c.budget.id),
                        ),
                      ),
                  ],
                ),
    );
  }
}

class BudgetStatusCard extends StatelessWidget {
  const BudgetStatusCard({
    super.key,
    required this.title,
    required this.status,
    required this.format,
    this.warning,
    this.icon,
    this.color,
    this.onEdit,
    this.onDelete,
  });

  final String title;
  final BudgetStatus status;
  final String Function(int) format;
  final String? warning;
  final String? icon;
  final int? color;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = FinanceColors.of(context);
    final s = status;
    return AppCard(
      onTap: onEdit,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              if (icon != null) ...[
                CategoryAvatar(icon: icon!, color: color ?? 0xFF757575, size: 34),
                const SizedBox(width: 10),
              ],
              Expanded(child: Text(title, style: Theme.of(context).textTheme.titleMedium)),
              Text('${s.percentUsed.toStringAsFixed(1)}%', style: Theme.of(context).textTheme.labelLarge),
              if (onDelete != null)
                IconButton(
                  tooltip: 'Remove budget',
                  icon: const Icon(Icons.delete_outline),
                  onPressed: onDelete,
                ),
            ],
          ),
          const SizedBox(height: 10),
          BudgetProgressBar(progress: s.progress, percentUsed: s.percentUsed),
          const SizedBox(height: 8),
          Text(
            'Budget ${format(s.limitMinor)} • Spent ${format(s.spentMinor)} • '
            '${s.isExceeded ? 'Over ${format(s.exceededByMinor)}' : 'Left ${format(s.remainingMinor)}'}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          if (warning != null) ...[
            const SizedBox(height: 8),
            Row(
              children: [
                Icon(Icons.warning_amber_rounded, size: 16, color: s.isExceeded ? colors.expense : colors.warning),
                const SizedBox(width: 6),
                Expanded(child: Text(warning!, style: Theme.of(context).textTheme.bodySmall)),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
