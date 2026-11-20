import '../../data/models/enums.dart';

class DefaultCategory {
  const DefaultCategory(this.id, this.name, this.type, this.icon, this.color);
  final String id;
  final String name;
  final TransactionType type;
  final String icon;
  final int color;
}

class DefaultAccount {
  const DefaultAccount(this.id, this.name, this.type, this.icon, this.color);
  final String id;
  final String name;
  final AccountType type;
  final String icon;
  final int color;
}

/// Built-in data seeded on first launch. Ids are deterministic so every
/// device seeds identical records and sync merges them instead of creating
/// duplicates.
class Defaults {
  Defaults._();

  static const List<DefaultCategory> categories = [
    DefaultCategory('cat_food', 'Food', TransactionType.expense, 'food', 0xFFEF6C00),
    DefaultCategory('cat_travel', 'Travel', TransactionType.expense, 'travel', 0xFF1E88E5),
    DefaultCategory('cat_shopping', 'Shopping', TransactionType.expense, 'shopping', 0xFF8E24AA),
    DefaultCategory('cat_bills', 'Bills', TransactionType.expense, 'bills', 0xFFE53935),
    DefaultCategory('cat_rent', 'Rent', TransactionType.expense, 'rent', 0xFF6D4C41),
    DefaultCategory('cat_entertainment', 'Entertainment', TransactionType.expense, 'entertainment', 0xFFD81B60),
    DefaultCategory('cat_health', 'Health', TransactionType.expense, 'health', 0xFF43A047),
    DefaultCategory('cat_education', 'Education', TransactionType.expense, 'education', 0xFF3949AB),
    DefaultCategory('cat_subscription', 'Subscription', TransactionType.expense, 'subscription', 0xFF00897B),
    DefaultCategory('cat_other_expense', 'Other', TransactionType.expense, 'other', 0xFF757575),
    DefaultCategory('cat_salary', 'Salary', TransactionType.income, 'salary', 0xFF2E7D32),
    DefaultCategory('cat_freelance', 'Freelance', TransactionType.income, 'freelance', 0xFF00ACC1),
    DefaultCategory('cat_business', 'Business', TransactionType.income, 'business', 0xFF5E35B1),
    DefaultCategory('cat_investment', 'Investment', TransactionType.income, 'investment', 0xFFF9A825),
    DefaultCategory('cat_gift', 'Gift', TransactionType.income, 'gift', 0xFFC0CA33),
    DefaultCategory('cat_other_income', 'Other', TransactionType.income, 'other', 0xFF757575),
  ];

  static const List<DefaultAccount> accounts = [
    DefaultAccount('acc_cash', 'Cash', AccountType.cash, 'cash', 0xFF43A047),
    DefaultAccount('acc_bank', 'Bank Account', AccountType.bank, 'bank', 0xFF1E88E5),
  ];

  static const List<String> currencies = [
    'USD', 'EUR', 'GBP', 'INR', 'JPY', 'CAD', 'AUD', 'CHF', 'CNY', 'SGD', //
    'AED', 'SAR', 'BRL', 'MXN', 'ZAR', 'SEK', 'NOK', 'NZD', 'HKD', 'KRW',
  ];

  /// Approximate fallback rates (units per USD) used only until the first
  /// successful online refresh; flagged as approximate in the UI.
  static const Map<String, double> fallbackRatesPerUsd = {
    'USD': 1.0, 'EUR': 0.92, 'GBP': 0.79, 'INR': 83.5, 'JPY': 150.0, //
    'CAD': 1.36, 'AUD': 1.52, 'CHF': 0.88, 'CNY': 7.2, 'SGD': 1.34,
    'AED': 3.67, 'SAR': 3.75, 'BRL': 5.0, 'MXN': 17.5, 'ZAR': 18.5,
    'SEK': 10.5, 'NOK': 10.6, 'NZD': 1.65, 'HKD': 7.8, 'KRW': 1350.0,
  };
}
