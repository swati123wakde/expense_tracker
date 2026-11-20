import '../../data/models/account.dart';
import 'currency_converter.dart';

class BalanceSummary {
  const BalanceSummary({
    required this.totalIncomeMinor,
    required this.totalExpenseMinor,
    required this.accounts,
    required this.convertedBalances,
    this.hasUnconvertibleCurrency = false,
  });

  static const empty = BalanceSummary(
    totalIncomeMinor: 0,
    totalExpenseMinor: 0,
    accounts: [],
    convertedBalances: {},
  );

  /// All amounts below are in the base currency.
  final int totalIncomeMinor;
  final int totalExpenseMinor;

  /// Per-account balances in the account's own currency.
  final List<AccountBalance> accounts;

  /// accountId -> balance converted to the base currency.
  final Map<String, int> convertedBalances;

  /// True when an account currency had no cached exchange rate.
  final bool hasUnconvertibleCurrency;

  /// Total Balance = Total Income - Total Expenses.
  int get balanceMinor => totalIncomeMinor - totalExpenseMinor;
}

class BalanceCalculator {
  BalanceCalculator._();

  static BalanceSummary summarize(
    List<AccountBalance> accounts,
    CurrencyConverter converter,
  ) {
    var income = 0;
    var expense = 0;
    var unconvertible = false;
    final converted = <String, int>{};
    for (final a in accounts) {
      final currency = a.account.currency;
      if (!converter.canConvert(currency)) unconvertible = true;
      final inc = converter.convert(a.incomeMinor, currency);
      final exp = converter.convert(a.expenseMinor, currency);
      income += inc;
      expense += exp;
      converted[a.account.id] = inc - exp;
    }
    return BalanceSummary(
      totalIncomeMinor: income,
      totalExpenseMinor: expense,
      accounts: accounts,
      convertedBalances: converted,
      hasUnconvertibleCurrency: unconvertible,
    );
  }
}
