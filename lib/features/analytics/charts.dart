import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';

import '../../core/finance/analytics_calculator.dart';
import '../../core/theme/app_theme.dart';
import '../../core/utils/money.dart';

/// Grouped bars: income vs expense per bucket.
class IncomeExpenseBarChart extends StatelessWidget {
  const IncomeExpenseBarChart({super.key, required this.buckets, required this.currency, this.height = 200});

  final List<Bucket> buckets;
  final String currency;
  final double height;

  @override
  Widget build(BuildContext context) {
    final colors = FinanceColors.of(context);
    final scheme = Theme.of(context).colorScheme;
    final maxValue = buckets.fold<int>(1, (m, b) {
      final v = b.incomeMinor > b.expenseMinor ? b.incomeMinor : b.expenseMinor;
      return v > m ? v : m;
    });
    final rodWidth = buckets.length > 20 ? 3.0 : (buckets.length > 8 ? 6.0 : 10.0);
    final labelEvery = buckets.length > 16 ? (buckets.length / 8).ceil() : 1;

    return SizedBox(
      height: height,
      child: BarChart(
        BarChartData(
          maxY: maxValue * 1.15 / 100,
          alignment: BarChartAlignment.spaceAround,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(color: scheme.outlineVariant.withValues(alpha: 0.4), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                getTitlesWidget: (value, meta) => Text(
                  Money.compact((value * 100).round(), currency),
                  style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 24,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (i < 0 || i >= buckets.length || i % labelEvery != 0) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(buckets[i].label, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                  );
                },
              ),
            ),
          ),
          barTouchData: BarTouchData(
            touchTooltipData: BarTouchTooltipData(
              getTooltipColor: (_) => scheme.inverseSurface,
              getTooltipItem: (group, groupIndex, rod, rodIndex) => BarTooltipItem(
                '${rodIndex == 0 ? 'Income' : 'Expense'}\n${Money.format((rod.toY * 100).round(), currency)}',
                TextStyle(color: scheme.onInverseSurface, fontSize: 12),
              ),
            ),
          ),
          barGroups: [
            for (var i = 0; i < buckets.length; i++)
              BarChartGroupData(
                x: i,
                barsSpace: 2,
                barRods: [
                  BarChartRodData(
                    toY: buckets[i].incomeMinor / 100,
                    color: colors.income,
                    width: rodWidth,
                    borderRadius: BorderRadius.circular(3),
                  ),
                  BarChartRodData(
                    toY: buckets[i].expenseMinor / 100,
                    color: colors.expense,
                    width: rodWidth,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

/// Spending trend line (expenses per bucket).
class SpendingTrendChart extends StatelessWidget {
  const SpendingTrendChart({super.key, required this.buckets, required this.currency, this.height = 180});

  final List<Bucket> buckets;
  final String currency;
  final double height;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = FinanceColors.of(context).expense;
    final labelEvery = buckets.length > 12 ? (buckets.length / 6).ceil() : 1;
    final maxY = buckets.fold<int>(1, (m, b) => b.expenseMinor > m ? b.expenseMinor : m) * 1.2 / 100;

    return SizedBox(
      height: height,
      child: LineChart(
        LineChartData(
          minY: 0,
          maxY: maxY,
          gridData: FlGridData(
            show: true,
            drawVerticalLine: false,
            getDrawingHorizontalLine: (_) => FlLine(color: scheme.outlineVariant.withValues(alpha: 0.4), strokeWidth: 1),
          ),
          borderData: FlBorderData(show: false),
          titlesData: FlTitlesData(
            topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
            leftTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                reservedSize: 44,
                getTitlesWidget: (value, meta) => Text(
                  Money.compact((value * 100).round(), currency),
                  style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant),
                ),
              ),
            ),
            bottomTitles: AxisTitles(
              sideTitles: SideTitles(
                showTitles: true,
                interval: 1,
                reservedSize: 24,
                getTitlesWidget: (value, meta) {
                  final i = value.toInt();
                  if (value != i.toDouble() || i < 0 || i >= buckets.length || i % labelEvery != 0) {
                    return const SizedBox.shrink();
                  }
                  return Padding(
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(buckets[i].label, style: TextStyle(fontSize: 10, color: scheme.onSurfaceVariant)),
                  );
                },
              ),
            ),
          ),
          lineTouchData: LineTouchData(
            touchTooltipData: LineTouchTooltipData(
              getTooltipColor: (_) => scheme.inverseSurface,
              getTooltipItems: (spots) => [
                for (final s in spots)
                  LineTooltipItem(
                    Money.format((s.y * 100).round(), currency),
                    TextStyle(color: scheme.onInverseSurface, fontSize: 12),
                  ),
              ],
            ),
          ),
          lineBarsData: [
            LineChartBarData(
              isCurved: true,
              preventCurveOverShooting: true,
              color: color,
              barWidth: 3,
              dotData: FlDotData(show: buckets.length <= 12),
              belowBarData: BarAreaData(
                show: true,
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [color.withValues(alpha: 0.25), color.withValues(alpha: 0.0)],
                ),
              ),
              spots: [
                for (var i = 0; i < buckets.length; i++) FlSpot(i.toDouble(), buckets[i].expenseMinor / 100),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

/// Donut chart of expenses by category with a centre total.
class CategoryDonutChart extends StatefulWidget {
  const CategoryDonutChart({
    super.key,
    required this.values,
    required this.colors,
    required this.centerLabel,
    required this.centerValue,
    this.size = 200,
  });

  final List<double> values;
  final List<Color> colors;
  final String centerLabel;
  final String centerValue;
  final double size;

  @override
  State<CategoryDonutChart> createState() => _CategoryDonutChartState();
}

class _CategoryDonutChartState extends State<CategoryDonutChart> {
  int? _touched;

  @override
  Widget build(BuildContext context) {
    final total = widget.values.fold<double>(0, (a, b) => a + b);
    return SizedBox(
      height: widget.size,
      child: Stack(
        alignment: Alignment.center,
        children: [
          PieChart(
            PieChartData(
              sectionsSpace: 2,
              centerSpaceRadius: widget.size * 0.3,
              pieTouchData: PieTouchData(
                touchCallback: (event, response) {
                  if (!event.isInterestedForInteractions || response?.touchedSection == null) {
                    if (_touched != null) setState(() => _touched = null);
                    return;
                  }
                  setState(() => _touched = response!.touchedSection!.touchedSectionIndex);
                },
              ),
              sections: [
                for (var i = 0; i < widget.values.length; i++)
                  PieChartSectionData(
                    value: widget.values[i],
                    color: widget.colors[i],
                    radius: _touched == i ? widget.size * 0.2 : widget.size * 0.16,
                    showTitle: total > 0 && widget.values[i] / total >= 0.08,
                    title: total > 0 ? '${(widget.values[i] * 100 / total).round()}%' : '',
                    titleStyle: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
                  ),
              ],
            ),
          ),
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.centerLabel, style: Theme.of(context).textTheme.bodySmall),
              Text(widget.centerValue, style: Theme.of(context).textTheme.titleMedium),
            ],
          ),
        ],
      ),
    );
  }
}
