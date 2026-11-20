import '../app/dependencies.dart';
import '../core/finance/aggregates.dart';
import '../core/finance/analytics_calculator.dart';
import '../core/finance/balance_calculator.dart';
import '../core/finance/budget_calculator.dart';
import '../core/finance/insights_engine.dart';
import '../core/services/data_change_bus.dart';
import '../core/utils/date_utils.dart';
import '../core/utils/money.dart';
import '../data/models/budget.dart';
import '../data/models/transaction.dart';
import 'bus_aware_notifier.dart';

/// Everything the dashboard shows, computed from local data only.
class DashboardProvider extends BusAwareNotifier {
  DashboardProvider(this._deps)
      : super(_deps.bus, {...Tables.synced, Tables.settings, Tables.exchangeRates});

  final AppDependencies _deps;

  BalanceSummary balance = BalanceSummary.empty;
  int monthIncomeMinor = 0;
  int monthExpenseMinor = 0;
  BudgetStatus? budget;
  List<TransactionView> recent = const [];
  List<Bucket> monthlyOverview = const [];
  List<Insight> insights = const [];
  String baseCurrency = 'USD';
  bool approximateRates = false;
  DateTime now = DateTime.now();

  String format(int minor) => Money.format(minor, baseCurrency);

  @override
  Future<void> reload() async {
    now = _deps.clock.now();
    final converter = await _deps.currency.converter();
    baseCurrency = converter.baseCurrency;

    final balances = await _deps.accounts.balances(includeArchived: true);
    balance = BalanceCalculator.summarize(balances, converter);
    approximateRates = converter.fetchedAt == null || balance.hasUnconvertibleCurrency;

    // One aggregate query covers the 6-month overview and the insight windows.
    final overviewStart = DateTime(now.year, now.month - 5);
    final insightsStart = InsightsEngine.requiredStart(now);
    final from = overviewStart.isBefore(insightsStart) ? overviewStart : insightsStart;
    final to = DateTime(now.year, now.month + 1);
    final aggregates = Aggregate.convertAll(
      await _deps.transactions.dailyAggregates(from, to, baseCurrency),
      converter,
    );

    final month = DateUtilsX.month(now);
    final monthRows = aggregates.within(month.start, month.end).toList();
    monthIncomeMinor = monthRows.incomeTotal;
    monthExpenseMinor = monthRows.expenseTotal;

    final overall = await _deps.budgets.overall();
    budget = overall == null
        ? null
        : BudgetCalculator.status(
            budgetId: BudgetEntity.overallId,
            limitMinor: overall.amountMinor,
            spentMinor: monthExpenseMinor,
          );

    monthlyOverview = AnalyticsCalculator.buildBuckets(
      aggregates,
      DateRange(overviewStart, to),
      BucketGranularity.month,
      AnalyticsPeriod.year,
    );

    final categories = await _deps.categories.all(includeArchived: true);
    insights = InsightsEngine.generate(
      aggregates: aggregates,
      now: now,
      monthlyBudgetMinor: overall?.amountMinor ?? 0,
      categoryNames: {for (final c in categories) c.id: c.name},
      format: format,
    );

    recent = await _deps.transactions.recent(8, fallbackCurrency: baseCurrency);
  }

  String? get budgetWarning {
    final b = budget;
    if (b == null) return null;
    return BudgetCalculator.warningMessage(
      b,
      monthName: DateUtilsX.monthName(now.month),
      format: format,
    );
  }
}
