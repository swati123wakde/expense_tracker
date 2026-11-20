import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/constants/category_icons.dart';
import '../../core/finance/budget_calculator.dart';
import '../../core/finance/insights_engine.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../data/models/enums.dart';
import '../../providers/accounts_provider.dart';
import '../../providers/bus_aware_notifier.dart';
import '../../providers/dashboard_provider.dart';
import '../accounts/accounts_screen.dart';
import '../analytics/charts.dart';
import '../budgets/budgets_screen.dart';
import '../common/common_widgets.dart';
import '../common/sync_status_chip.dart';
import '../goals/goals_screen.dart';
import '../recurring/recurring_screen.dart';
import '../transactions/add_edit_transaction_screen.dart';
import '../transactions/transaction_details_sheet.dart';
import '../transactions/transaction_tile.dart';

class DashboardScreen extends StatelessWidget {
  const DashboardScreen({super.key, this.onSeeAllTransactions});

  final VoidCallback? onSeeAllTransactions;

  @override
  Widget build(BuildContext context) {
    final d = context.watch<DashboardProvider>();

    return Scaffold(
      appBar: AppBar(
        title: const Text('Overview'),
        actions: const [Padding(padding: EdgeInsets.only(right: 12), child: SyncStatusChip())],
      ),
      body: RefreshIndicator(
        onRefresh: d.load,
        child: _body(context, d),
      ),
    );
  }

  Widget _body(BuildContext context, DashboardProvider d) {
    if (d.status == LoadStatus.error) {
      return ListView(children: [ErrorState(message: d.error ?? '', onRetry: d.load)]);
    }
    if (d.isLoading) return const _DashboardSkeleton();

    return ListView(
      key: const Key('dashboardList'),
      padding: Spacing.page,
      children: [
        _BalanceCard(d: d),
        const SizedBox(height: Spacing.md),
        _QuickActions(),
        const SizedBox(height: Spacing.md),
        _BudgetCard(d: d),
        if (d.insights.isNotEmpty) ...[
          const SectionHeader(title: 'Smart insights'),
          _InsightsCarousel(insights: d.insights),
        ],
        const SectionHeader(title: 'Income vs expenses'),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  _Legend(color: FinanceColors.of(context).income, label: 'Income'),
                  const SizedBox(width: 16),
                  _Legend(color: FinanceColors.of(context).expense, label: 'Expenses'),
                  const Spacer(),
                  Text('Last 6 months', style: Theme.of(context).textTheme.bodySmall),
                ],
              ),
              const SizedBox(height: 12),
              IncomeExpenseBarChart(buckets: d.monthlyOverview, currency: d.baseCurrency, height: 180),
            ],
          ),
        ),
        const _AccountsStrip(),
        SectionHeader(title: 'Recent transactions', action: 'See all', onAction: onSeeAllTransactions),
        if (d.recent.isEmpty)
          AppCard(
            child: EmptyState(
              icon: Icons.receipt_long,
              title: 'No transactions yet',
              message: 'Your latest activity will appear here.',
              actionLabel: 'Add transaction',
              onAction: () => AddEditTransactionScreen.open(context),
            ),
          )
        else
          Card(
            child: Column(
              children: [
                for (final v in d.recent)
                  TransactionTile(view: v, dense: true, onTap: () => TransactionDetailsSheet.show(context, v)),
              ],
            ),
          ),
      ],
    );
  }
}

class _BalanceCard extends StatelessWidget {
  const _BalanceCard({required this.d});
  final DashboardProvider d;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final onColor = scheme.onPrimary;
    final b = d.balance;
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(Spacing.radius + 4),
        gradient: LinearGradient(
          colors: [scheme.primary, Color.lerp(scheme.primary, scheme.tertiary, 0.6)!],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Total balance', style: TextStyle(color: onColor.withValues(alpha: 0.85))),
              if (d.approximateRates) ...[
                const SizedBox(width: 6),
                Tooltip(
                  message: 'Includes accounts converted with cached or approximate exchange rates',
                  child: Icon(Icons.info_outline, size: 16, color: onColor.withValues(alpha: 0.85)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 6),
          TweenAnimationBuilder<double>(
            tween: Tween(begin: 0, end: b.balanceMinor.toDouble()),
            duration: const Duration(milliseconds: 700),
            curve: Curves.easeOutCubic,
            builder: (context, value, _) => Text(
              Money.format(value.round(), d.baseCurrency),
              key: const Key('totalBalance'),
              style: Theme.of(context).textTheme.headlineLarge?.copyWith(color: onColor),
            ),
          ),
          const SizedBox(height: 18),
          Row(
            children: [
              Expanded(child: _Stat(label: 'Total income', value: d.format(b.totalIncomeMinor), icon: Icons.south_west, color: onColor)),
              Expanded(child: _Stat(label: 'Total expenses', value: d.format(b.totalExpenseMinor), icon: Icons.north_east, color: onColor)),
            ],
          ),
          const SizedBox(height: 12),
          Divider(color: onColor.withValues(alpha: 0.2), height: 1),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(child: _Stat(label: 'This month in', value: d.format(d.monthIncomeMinor), color: onColor, small: true)),
              Expanded(child: _Stat(label: 'This month out', value: d.format(d.monthExpenseMinor), color: onColor, small: true)),
            ],
          ),
        ],
      ),
    );
  }
}

class _Stat extends StatelessWidget {
  const _Stat({required this.label, required this.value, required this.color, this.icon, this.small = false});

  final String label;
  final String value;
  final Color color;
  final IconData? icon;
  final bool small;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          if (icon != null) ...[
            CircleAvatar(
              radius: 14,
              backgroundColor: color.withValues(alpha: 0.18),
              child: Icon(icon, size: 16, color: color),
            ),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label, style: TextStyle(color: color.withValues(alpha: 0.8), fontSize: 12)),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: color, fontWeight: FontWeight.w700, fontSize: small ? 14 : 16),
                ),
              ],
            ),
          ),
        ],
      );
}

class _QuickActions extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    void push(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
    final items = <(IconData, String, VoidCallback)>[
      (Icons.remove_circle_outline, 'Expense', () => AddEditTransactionScreen.open(context)),
      (Icons.add_circle_outline, 'Income', () => Navigator.of(context).push(MaterialPageRoute<bool>(
            fullscreenDialog: true,
            builder: (_) => const AddEditTransactionScreen(initialType: TransactionType.income),
          ))),
      (Icons.account_balance_wallet_outlined, 'Accounts', () => push(const AccountsScreen())),
      (Icons.savings_outlined, 'Goals', () => push(const GoalsScreen())),
      (Icons.repeat, 'Recurring', () => push(const RecurringScreen())),
    ];
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        for (final (icon, label, onTap) in items)
          Expanded(
            child: InkWell(
              borderRadius: BorderRadius.circular(16),
              onTap: onTap,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Column(
                  children: [
                    CircleAvatar(
                      radius: 22,
                      backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
                      child: Icon(icon, color: Theme.of(context).colorScheme.onSecondaryContainer),
                    ),
                    const SizedBox(height: 6),
                    Text(label, style: Theme.of(context).textTheme.labelSmall),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _BudgetCard extends StatelessWidget {
  const _BudgetCard({required this.d});
  final DashboardProvider d;

  @override
  Widget build(BuildContext context) {
    final b = d.budget;
    void open() => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const BudgetsScreen()));
    if (b == null) {
      return AppCard(
        onTap: open,
        child: Row(
          children: [
            const Icon(Icons.pie_chart_outline),
            const SizedBox(width: 12),
            const Expanded(child: Text('Set a monthly budget to track your spending')),
            Icon(Icons.chevron_right, color: Theme.of(context).colorScheme.onSurfaceVariant),
          ],
        ),
      );
    }
    final warning = d.budgetWarning;
    final severity = BudgetCalculator.severity(b);
    final colors = FinanceColors.of(context);
    return AppCard(
      key: const Key('budgetCard'),
      onTap: open,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Text('Monthly budget', style: Theme.of(context).textTheme.titleMedium),
              const Spacer(),
              Text('${b.percentUsed.toStringAsFixed(1)}% used', style: Theme.of(context).textTheme.labelLarge),
            ],
          ),
          const SizedBox(height: 12),
          BudgetProgressBar(progress: b.progress, percentUsed: b.percentUsed),
          const SizedBox(height: 12),
          Row(
            children: [
              _MiniStat(label: 'Budget', value: d.format(b.limitMinor)),
              _MiniStat(label: 'Spent', value: d.format(b.spentMinor)),
              _MiniStat(
                label: b.isExceeded ? 'Over by' : 'Remaining',
                value: d.format(b.isExceeded ? b.exceededByMinor : b.remainingMinor),
                color: b.isExceeded ? colors.expense : null,
              ),
            ],
          ),
          if (warning != null) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: (severity == BudgetSeverity.exceeded || severity == BudgetSeverity.critical
                        ? colors.expense
                        : colors.warning)
                    .withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(10),
              ),
              child: Row(
                children: [
                  Icon(Icons.warning_amber_rounded, size: 18, color: colors.warning),
                  const SizedBox(width: 8),
                  Expanded(child: Text(warning, key: const Key('budgetWarning'))),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  const _MiniStat({required this.label, required this.value, this.color});
  final String label;
  final String value;
  final Color? color;

  @override
  Widget build(BuildContext context) => Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            Text(
              value,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(color: color),
            ),
          ],
        ),
      );
}

class _InsightsCarousel extends StatelessWidget {
  const _InsightsCarousel({required this.insights});
  final List<Insight> insights;

  @override
  Widget build(BuildContext context) {
    final colors = FinanceColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 112,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        itemCount: insights.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final insight = insights[i];
          final (IconData icon, Color color) = switch (insight.tone) {
            InsightTone.positive => (Icons.trending_down, colors.income),
            InsightTone.warning => (Icons.trending_up, colors.warning),
            InsightTone.negative => (Icons.error_outline, colors.expense),
            InsightTone.neutral => (Icons.lightbulb_outline, scheme.primary),
          };
          return SizedBox(
            width: 260,
            child: AppCard(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  CircleAvatar(
                    radius: 18,
                    backgroundColor: color.withValues(alpha: 0.15),
                    child: Icon(icon, color: color, size: 20),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      insight.message,
                      maxLines: 4,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _AccountsStrip extends StatelessWidget {
  const _AccountsStrip();

  @override
  Widget build(BuildContext context) {
    final accounts = context.watch<AccountsProvider>();
    final balances = accounts.balances.where((b) => !b.account.archived).toList();
    if (balances.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SectionHeader(
          title: 'Accounts',
          action: 'Manage',
          onAction: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const AccountsScreen())),
        ),
        SizedBox(
          height: 96,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: balances.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (context, i) {
              final b = balances[i];
              return SizedBox(
                width: 170,
                child: AppCard(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Icon(AppIcons.of(b.account.icon), size: 18, color: Color(b.account.color)),
                          const SizedBox(width: 6),
                          Expanded(
                            child: Text(b.account.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                          ),
                        ],
                      ),
                      const Spacer(),
                      Text(
                        Money.format(b.balanceMinor, b.account.currency),
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) => Row(
        children: [
          Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: BoxShape.circle)),
          const SizedBox(width: 6),
          Text(label, style: Theme.of(context).textTheme.bodySmall),
        ],
      );
}

class _DashboardSkeleton extends StatelessWidget {
  const _DashboardSkeleton();

  @override
  Widget build(BuildContext context) => ListView(
        padding: Spacing.page,
        children: const [
          Skeleton(height: 190, radius: 24),
          SizedBox(height: 16),
          Skeleton(height: 70, radius: 16),
          SizedBox(height: 16),
          Skeleton(height: 130, radius: 20),
          SizedBox(height: 24),
          ListSkeleton(count: 4),
        ],
      );
}
