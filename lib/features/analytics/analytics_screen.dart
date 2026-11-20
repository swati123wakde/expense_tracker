import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../core/finance/analytics_calculator.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';
import '../../providers/analytics_provider.dart';
import '../../providers/bus_aware_notifier.dart';
import '../../providers/categories_provider.dart';
import '../common/common_widgets.dart';
import 'charts.dart';

class AnalyticsScreen extends StatelessWidget {
  const AnalyticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final a = context.watch<AnalyticsProvider>();
    return Scaffold(
      appBar: AppBar(title: const Text('Analytics')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: SizedBox(
              width: double.infinity,
              child: SegmentedButton<AnalyticsPeriod>(
                showSelectedIcon: false,
                segments: [
                  for (final p in AnalyticsPeriod.values) ButtonSegment(value: p, label: Text(p.label)),
                ],
                selected: {a.period},
                onSelectionChanged: (s) => a.setPeriod(s.first),
              ),
            ),
          ),
          Expanded(child: _content(context, a)),
        ],
      ),
    );
  }

  Widget _content(BuildContext context, AnalyticsProvider a) {
    if (a.status == LoadStatus.error) return ErrorState(message: a.error ?? '', onRetry: a.load);
    final r = a.result;
    if (r == null || a.isLoading && r.range != a.period.range(DateTime.now())) {
      return const Padding(padding: EdgeInsets.all(16), child: ListSkeleton());
    }
    final fmt = DateFormat('d MMM y');
    final categories = context.watch<CategoriesProvider>();
    final colors = FinanceColors.of(context);
    String money(int v) => Money.format(v, a.baseCurrency);

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: ListView(
        key: ValueKey(a.period),
        padding: Spacing.page,
        children: [
          Text(
            '${fmt.format(r.range.start)} – ${fmt.format(r.range.end.subtract(const Duration(days: 1)))}',
            style: Theme.of(context).textTheme.bodySmall,
          ),
          const SizedBox(height: Spacing.sm),
          GridView.count(
            crossAxisCount: MediaQuery.sizeOf(context).width > 600 ? 4 : 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.9,
            children: [
              _Kpi(label: 'Income', value: money(r.incomeMinor), color: colors.income),
              _Kpi(label: 'Expenses', value: money(r.expenseMinor), color: colors.expense),
              _Kpi(
                label: 'Net savings',
                value: money(r.netSavingsMinor),
                color: r.netSavingsMinor >= 0 ? colors.income : colors.expense,
                footnote: r.savingsRate == null ? null : '${(r.savingsRate! * 100).round()}% of income',
              ),
              _Kpi(label: 'Avg. daily spend', value: money(r.averageDailyExpenseMinor)),
            ],
          ),
          if (r.isEmpty)
            const Padding(
              padding: EdgeInsets.only(top: 32),
              child: EmptyState(
                icon: Icons.insights,
                title: 'No data for this period',
                message: 'Transactions you add will be analysed here.',
              ),
            )
          else ...[
            const SectionHeader(title: 'Spending by category'),
            AppCard(
              child: r.categoryShares.isEmpty
                  ? const Padding(padding: EdgeInsets.all(16), child: Text('No expenses in this period'))
                  : Column(
                      children: [
                        CategoryDonutChart(
                          values: [for (final s in r.categoryShares) s.amountMinor / 100],
                          colors: [for (final s in r.categoryShares) Color(categories.byId[s.categoryId]?.color ?? 0xFF757575)],
                          centerLabel: 'Total spent',
                          centerValue: Money.compact(r.expenseMinor, a.baseCurrency),
                        ),
                        const SizedBox(height: 12),
                        for (final s in r.categoryShares.take(8))
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 6),
                            child: Row(
                              children: [
                                CategoryAvatar(
                                  icon: categories.byId[s.categoryId]?.icon ?? 'other',
                                  color: categories.byId[s.categoryId]?.color ?? 0xFF757575,
                                  size: 32,
                                ),
                                const SizedBox(width: 10),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          Expanded(child: Text(categories.nameOf(s.categoryId))),
                                          Text(money(s.amountMinor), style: const TextStyle(fontWeight: FontWeight.w600)),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      ClipRRect(
                                        borderRadius: BorderRadius.circular(4),
                                        child: LinearProgressIndicator(
                                          value: s.share,
                                          minHeight: 6,
                                          color: Color(categories.byId[s.categoryId]?.color ?? 0xFF757575),
                                          backgroundColor: Theme.of(context).colorScheme.surfaceContainerHighest,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 10),
                                SizedBox(
                                  width: 40,
                                  child: Text('${(s.share * 100).round()}%', textAlign: TextAlign.end),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
            ),
            const SectionHeader(title: 'Income vs expenses'),
            AppCard(child: IncomeExpenseBarChart(buckets: r.buckets, currency: a.baseCurrency)),
            SectionHeader(title: '${_granularityLabel(a.period)} spending trend'),
            AppCard(child: SpendingTrendChart(buckets: r.buckets, currency: a.baseCurrency)),
          ],
        ],
      ),
    );
  }

  static String _granularityLabel(AnalyticsPeriod p) => switch (p.granularity) {
        BucketGranularity.day => 'Daily',
        BucketGranularity.week => 'Weekly',
        BucketGranularity.month => 'Monthly',
      };
}

class _Kpi extends StatelessWidget {
  const _Kpi({required this.label, required this.value, this.color, this.footnote});

  final String label;
  final String value;
  final Color? color;
  final String? footnote;

  @override
  Widget build(BuildContext context) => AppCard(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(label, style: Theme.of(context).textTheme.bodySmall),
            const SizedBox(height: 4),
            FittedBox(
              fit: BoxFit.scaleDown,
              alignment: Alignment.centerLeft,
              child: Text(value, style: Theme.of(context).textTheme.titleLarge?.copyWith(color: color)),
            ),
            if (footnote != null) Text(footnote!, style: Theme.of(context).textTheme.labelSmall),
          ],
        ),
      );
}
