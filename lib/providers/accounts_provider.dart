import '../app/dependencies.dart';
import '../core/finance/balance_calculator.dart';
import '../core/finance/currency_converter.dart';
import '../core/services/data_change_bus.dart';
import '../data/models/account.dart';
import '../data/models/enums.dart';
import '../data/models/transaction.dart';
import 'bus_aware_notifier.dart';

class AccountsProvider extends BusAwareNotifier {
  AccountsProvider(this._deps)
      : super(_deps.bus, {Tables.accounts, Tables.transactions, Tables.settings, Tables.exchangeRates});

  final AppDependencies _deps;

  List<AccountEntity> accounts = const [];
  List<AccountBalance> balances = const [];
  BalanceSummary summary = BalanceSummary.empty;
  CurrencyConverter converter = CurrencyConverter.identity('USD');

  String get baseCurrency => converter.baseCurrency;

  List<AccountEntity> get active => accounts.where((a) => !a.archived).toList();

  AccountEntity? byId(String id) {
    for (final a in accounts) {
      if (a.id == id) return a;
    }
    return null;
  }

  @override
  Future<void> reload() async {
    converter = await _deps.currency.converter();
    accounts = await _deps.accounts.all(includeArchived: true);
    balances = await _deps.accounts.balances(includeArchived: true);
    summary = BalanceCalculator.summarize(balances, converter);
  }

  /// Creates an account; an opening balance is recorded as an income
  /// transaction so Total Balance = Income - Expenses always holds.
  Future<void> create({
    required String name,
    required AccountType type,
    required String currency,
    required String icon,
    required int color,
    int openingBalanceMinor = 0,
  }) async {
    final account = await _deps.accounts.create(
      name: name,
      type: type,
      currency: currency,
      icon: icon,
      color: color,
    );
    if (openingBalanceMinor > 0) {
      await _deps.transactions.create(
        TransactionDraft(
          type: TransactionType.income,
          amountMinor: openingBalanceMinor,
          categoryId: 'cat_other_income',
          accountId: account.id,
          occurredAt: _deps.clock.now(),
          note: 'Opening balance',
        ),
      );
    }
  }

  Future<void> update(AccountEntity account) => _deps.accounts.update(account);

  Future<void> setArchived(String id, bool archived) => _deps.accounts.setArchived(id, archived);

  /// Throws [StateError] with a user-facing message if the account is in use.
  Future<void> delete(String id) => _deps.accounts.delete(id);

  Future<int> transactionCount(String id) => _deps.accounts.transactionCount(id);
}
