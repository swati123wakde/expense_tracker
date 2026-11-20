enum TransactionType {
  income,
  expense;

  String get label => this == income ? 'Income' : 'Expense';

  static TransactionType parse(Object? value) =>
      value == 'income' ? TransactionType.income : TransactionType.expense;
}

/// Lifecycle of a locally stored record relative to the cloud copy.
enum SyncStatus {
  synced,
  pendingCreate,
  pendingUpdate,
  pendingDelete,
  failed;

  bool get isPending => this != SyncStatus.synced;

  static SyncStatus parse(Object? value) => SyncStatus.values.firstWhere(
        (s) => s.name == value,
        orElse: () => SyncStatus.pendingUpdate,
      );
}

enum AccountType {
  cash('Cash'),
  bank('Bank Account'),
  creditCard('Credit Card'),
  wallet('Wallet'),
  savings('Savings Account');

  const AccountType(this.label);
  final String label;

  static AccountType parse(Object? value) => AccountType.values.firstWhere(
        (t) => t.name == value,
        orElse: () => AccountType.cash,
      );
}

enum RecurrenceFrequency {
  daily('Daily'),
  weekly('Weekly'),
  monthly('Monthly'),
  yearly('Yearly');

  const RecurrenceFrequency(this.label);
  final String label;

  static RecurrenceFrequency parse(Object? value) =>
      RecurrenceFrequency.values.firstWhere(
        (f) => f.name == value,
        orElse: () => RecurrenceFrequency.monthly,
      );
}
