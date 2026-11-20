import 'dart:async';

enum ChangeOrigin { local, sync }

class DataChange {
  const DataChange(this.tables, this.origin);

  final Set<String> tables;
  final ChangeOrigin origin;

  bool touches(String table) => tables.contains(table);
  bool touchesAny(Iterable<String> t) => t.any(tables.contains);
}

/// Repositories publish which tables changed; providers refresh and the sync
/// engine schedules an upload. This keeps the UI reading from the local DB
/// while still reacting to background sync merges.
class DataChangeBus {
  final StreamController<DataChange> _controller = StreamController<DataChange>.broadcast();

  Stream<DataChange> get stream => _controller.stream;

  void emit(Set<String> tables, {ChangeOrigin origin = ChangeOrigin.local}) {
    if (tables.isEmpty || _controller.isClosed) return;
    _controller.add(DataChange(tables, origin));
  }

  Future<void> dispose() => _controller.close();
}

class Tables {
  Tables._();

  static const transactions = 'transactions';
  static const categories = 'categories';
  static const accounts = 'accounts';
  static const budgets = 'budgets';
  static const goals = 'goals';
  static const recurringRules = 'recurring_rules';
  static const settings = 'settings';
  static const exchangeRates = 'exchange_rates';

  static const synced = [accounts, categories, transactions, budgets, goals, recurringRules];
}
