import 'dart:async';

import '../app/dependencies.dart';
import '../core/services/data_change_bus.dart';
import '../core/utils/money.dart';
import '../data/models/recurring_rule.dart';
import 'bus_aware_notifier.dart';

class RecurringProvider extends BusAwareNotifier {
  RecurringProvider(this._deps)
      : super(_deps.bus, {Tables.recurringRules, Tables.accounts, Tables.categories});

  final AppDependencies _deps;

  List<RecurringRule> rules = const [];
  Map<String, String> accountCurrency = const {};

  String currencyOf(RecurringRule r) => accountCurrency[r.accountId] ?? 'USD';

  /// Monthly-equivalent cost of active recurring expenses (subscription tracker).
  int get monthlyCommitmentMinor {
    var total = 0;
    for (final r in rules.where((r) => r.active && r.type.name == 'expense')) {
      switch (r.frequency.name) {
        case 'daily':
          total += r.amountMinor * 30;
        case 'weekly':
          total += (r.amountMinor * 52 / 12).round();
        case 'monthly':
          total += r.amountMinor;
        case 'yearly':
          total += (r.amountMinor / 12).round();
      }
    }
    return total;
  }

  @override
  Future<void> reload() async {
    rules = await _deps.recurring.all();
    final accounts = await _deps.accounts.all(includeArchived: true);
    accountCurrency = {for (final a in accounts) a.id: a.currency};
  }

  /// Materialises due occurrences and schedules "due tomorrow" reminders.
  /// Called on startup and whenever the app returns to the foreground.
  Future<int> processDue() async {
    final created = await _deps.recurring.processDue();
    final upcoming = await _deps.recurring.upcoming(const Duration(hours: 48));
    final categories = await _deps.categories.all(includeArchived: true);
    final accounts = await _deps.accounts.all(includeArchived: true);
    final currency = {for (final a in accounts) a.id: a.currency};
    unawaited(_deps.alerts.checkUpcoming(
      now: _deps.clock.now(),
      upcoming: upcoming,
      categoryNames: {for (final c in categories) c.id: c.name},
      formatAmount: (r) => Money.format(r.amountMinor, currency[r.accountId] ?? 'USD'),
    ));
    return created;
  }

  Future<void> setActive(String id, bool active) => _deps.recurring.setActive(id, active);

  Future<void> update(
    String id, {
    required int amountMinor,
    required String note,
    required String categoryId,
    required String accountId,
    required bool active,
  }) =>
      _deps.recurring.update(
        id,
        amountMinor: amountMinor,
        note: note,
        categoryId: categoryId,
        accountId: accountId,
        active: active,
      );

  Future<void> delete(String id) => _deps.recurring.delete(id);
}
