import '../app/dependencies.dart';
import '../core/finance/aggregates.dart';
import '../core/finance/analytics_calculator.dart';
import '../core/services/data_change_bus.dart';
import 'bus_aware_notifier.dart';

class AnalyticsProvider extends BusAwareNotifier {
  AnalyticsProvider(this._deps)
      : super(_deps.bus, {Tables.transactions, Tables.categories, Tables.accounts, Tables.settings, Tables.exchangeRates});

  final AppDependencies _deps;

  AnalyticsPeriod period = AnalyticsPeriod.month;
  AnalyticsResult? result;
  String baseCurrency = 'USD';

  Future<void> setPeriod(AnalyticsPeriod p) async {
    if (p == period) return;
    period = p;
    await load();
  }

  @override
  Future<void> reload() async {
    final now = _deps.clock.now();
    final converter = await _deps.currency.converter();
    baseCurrency = converter.baseCurrency;
    final range = period.range(now);
    final rows = await _deps.transactions.dailyAggregates(range.start, range.end, baseCurrency);
    result = AnalyticsCalculator.compute(
      aggregates: Aggregate.convertAll(rows, converter),
      period: period,
      now: now,
    );
  }
}
