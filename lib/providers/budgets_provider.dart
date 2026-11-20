import 'dart:async';

import '../app/dependencies.dart';
import '../core/finance/aggregates.dart';
import '../core/finance/budget_calculator.dart';
import '../core/services/data_change_bus.dart';
import '../core/utils/date_utils.dart';
import '../core/utils/money.dart';
import '../data/models/budget.dart';
import 'bus_aware_notifier.dart';

class CategoryBudgetView {
  const CategoryBudgetView({required this.budget, required this.status, required this.categoryName});
  final BudgetEntity budget;
  final BudgetStatus status;
  final String categoryName;
}

/// Monthly budget + per-category budgets with live progress. After each
/// refresh it asks [AlertService] whether a threshold notification is due.
class BudgetsProvider extends BusAwareNotifier {
  BudgetsProvider(this._deps)
      : super(_deps.bus, {Tables.budgets, Tables.transactions, Tables.categories, Tables.accounts, Tables.settings, Tables.exchangeRates});

  final AppDependencies _deps;

  BudgetStatus? overall;
  List<CategoryBudgetView> categoryBudgets = const [];
  Map<String, int> spentByCategory = const {};
  String baseCurrency = 'USD';
  DateTime now = DateTime.now();

  String format(int minor) => Money.format(minor, baseCurrency);
  String get monthName => DateUtilsX.monthName(now.month);

  @override
  Future<void> reload() async {
    now = _deps.clock.now();
    final converter = await _deps.currency.converter();
    baseCurrency = converter.baseCurrency;
    final month = DateUtilsX.month(now);
    final rows = Aggregate.convertAll(
      await _deps.transactions.dailyAggregates(month.start, month.end, baseCurrency),
      converter,
    );
    spentByCategory = {for (final e in rows.expenseByCategory()) e.key: e.value};
    final totalSpent = rows.expenseTotal;

    final budgets = await _deps.budgets.all();
    final categories = {for (final c in await _deps.categories.all(includeArchived: true)) c.id: c.name};

    overall = null;
    final perCategory = <CategoryBudgetView>[];
    for (final b in budgets) {
      if (b.isOverall) {
        overall = BudgetCalculator.status(budgetId: b.id, limitMinor: b.amountMinor, spentMinor: totalSpent);
      } else {
        final catId = b.categoryId!;
        perCategory.add(
          CategoryBudgetView(
            budget: b,
            categoryName: categories[catId] ?? 'Uncategorized',
            status: BudgetCalculator.status(
              budgetId: b.id,
              categoryId: catId,
              limitMinor: b.amountMinor,
              spentMinor: spentByCategory[catId] ?? 0,
            ),
          ),
        );
      }
    }
    perCategory.sort((a, b) => b.status.percentUsed.compareTo(a.status.percentUsed));
    categoryBudgets = perCategory;

    unawaited(_deps.alerts.checkBudgets(
      now: now,
      format: format,
      budgets: [
        if (overall != null) (status: overall!, categoryName: null),
        for (final c in perCategory) (status: c.status, categoryName: c.categoryName),
      ],
    ));
  }

  String? warningFor(BudgetStatus s, {String? categoryName}) => BudgetCalculator.warningMessage(
        s,
        monthName: monthName,
        format: format,
        categoryName: categoryName,
      );

  Future<void> setOverall(int amountMinor) => _deps.budgets.setOverall(amountMinor);

  Future<void> setCategoryBudget(String categoryId, int amountMinor) =>
      _deps.budgets.setForCategory(categoryId, amountMinor);

  Future<void> remove(String budgetId) => _deps.budgets.remove(budgetId);
}
