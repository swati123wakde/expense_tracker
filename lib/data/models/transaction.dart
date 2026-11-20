import 'enums.dart';
import 'row_utils.dart';

class TransactionEntity {
  const TransactionEntity({
    required this.id,
    required this.type,
    required this.amountMinor,
    required this.categoryId,
    required this.accountId,
    required this.occurredAt,
    required this.createdAt,
    required this.updatedAt,
    this.userId,
    this.note = '',
    this.attachmentPath,
    this.recurringRuleId,
    this.isFavorite = false,
    this.deletedAt,
    this.syncStatus = SyncStatus.pendingCreate,
  });

  factory TransactionEntity.fromRow(Map<String, Object?> r) {
    final meta = SyncMeta.fromRow(r);
    return TransactionEntity(
      id: meta.id,
      userId: meta.userId,
      type: TransactionType.parse(r['type']),
      amountMinor: RowReader.int_(r['amount_minor']),
      categoryId: RowReader.str(r['category_id']),
      accountId: RowReader.str(r['account_id']),
      note: RowReader.str(r['note']),
      occurredAt: RowReader.date(r['occurred_at']),
      attachmentPath: RowReader.strOrNull(r['attachment_path']),
      recurringRuleId: RowReader.strOrNull(r['recurring_rule_id']),
      isFavorite: RowReader.bool_(r['is_favorite']),
      createdAt: meta.createdAt,
      updatedAt: meta.updatedAt,
      deletedAt: meta.deletedAt,
      syncStatus: meta.syncStatus,
    );
  }

  final String id;
  final String? userId;
  final TransactionType type;

  /// Always positive; [type] decides the sign.
  final int amountMinor;
  final String categoryId;
  final String accountId;
  final String note;
  final DateTime occurredAt;
  final String? attachmentPath;
  final String? recurringRuleId;
  final bool isFavorite;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;

  bool get isIncome => type == TransactionType.income;
  int get signedAmountMinor => isIncome ? amountMinor : -amountMinor;

  Map<String, Object?> toRow() => {
        'id': id,
        'user_id': userId,
        'type': type.name,
        'amount_minor': amountMinor,
        'category_id': categoryId,
        'account_id': accountId,
        'note': note,
        'occurred_at': occurredAt.millisecondsSinceEpoch,
        'attachment_path': attachmentPath,
        'recurring_rule_id': recurringRuleId,
        'is_favorite': isFavorite ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'deleted_at': deletedAt?.millisecondsSinceEpoch,
      };

  TransactionEntity copyWith({
    TransactionType? type,
    int? amountMinor,
    String? categoryId,
    String? accountId,
    String? note,
    DateTime? occurredAt,
    String? attachmentPath,
    bool clearAttachment = false,
    String? recurringRuleId,
    bool? isFavorite,
    DateTime? updatedAt,
    DateTime? deletedAt,
    bool clearDeletedAt = false,
    SyncStatus? syncStatus,
    String? userId,
  }) =>
      TransactionEntity(
        id: id,
        userId: userId ?? this.userId,
        type: type ?? this.type,
        amountMinor: amountMinor ?? this.amountMinor,
        categoryId: categoryId ?? this.categoryId,
        accountId: accountId ?? this.accountId,
        note: note ?? this.note,
        occurredAt: occurredAt ?? this.occurredAt,
        attachmentPath: clearAttachment ? null : (attachmentPath ?? this.attachmentPath),
        recurringRuleId: recurringRuleId ?? this.recurringRuleId,
        isFavorite: isFavorite ?? this.isFavorite,
        createdAt: createdAt,
        updatedAt: updatedAt ?? this.updatedAt,
        deletedAt: clearDeletedAt ? null : (deletedAt ?? this.deletedAt),
        syncStatus: syncStatus ?? this.syncStatus,
      );
}

/// Input for creating or editing a transaction from the UI.
class TransactionDraft {
  const TransactionDraft({
    required this.type,
    required this.amountMinor,
    required this.categoryId,
    required this.accountId,
    required this.occurredAt,
    this.note = '',
    this.attachmentPath,
    this.recurrence,
  });

  final TransactionType type;
  final int amountMinor;
  final String categoryId;
  final String accountId;
  final DateTime occurredAt;
  final String note;
  final String? attachmentPath;

  /// When non-null a recurring rule is created alongside the transaction.
  final RecurrenceFrequency? recurrence;

  /// Returns a human readable validation error or null when valid.
  String? validate() {
    if (amountMinor <= 0) return 'Amount must be greater than zero';
    if (amountMinor > 100000000000) return 'Amount is too large';
    if (categoryId.isEmpty) return 'Choose a category';
    if (accountId.isEmpty) return 'Choose an account';
    if (note.length > 500) return 'Note is too long';
    return null;
  }
}

/// Transaction joined with display information for lists.
class TransactionView {
  const TransactionView({
    required this.transaction,
    required this.categoryName,
    required this.categoryIcon,
    required this.categoryColor,
    required this.accountName,
    required this.currency,
  });

  factory TransactionView.fromRow(Map<String, Object?> r, String fallbackCurrency) =>
      TransactionView(
        transaction: TransactionEntity.fromRow(r),
        categoryName: RowReader.str(r['category_name'], 'Uncategorized'),
        categoryIcon: RowReader.str(r['category_icon'], 'other'),
        categoryColor: RowReader.int_(r['category_color'], 0xFF757575),
        accountName: RowReader.str(r['account_name'], 'Unknown account'),
        currency: RowReader.str(r['account_currency'], fallbackCurrency),
      );

  final TransactionEntity transaction;
  final String categoryName;
  final String categoryIcon;
  final int categoryColor;
  final String accountName;
  final String currency;

  String get id => transaction.id;
}
