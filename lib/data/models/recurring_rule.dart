import 'enums.dart';
import 'row_utils.dart';

/// Template for transactions that repeat (rent, salary, subscriptions...).
class RecurringRule {
  const RecurringRule({
    required this.id,
    required this.type,
    required this.amountMinor,
    required this.categoryId,
    required this.accountId,
    required this.frequency,
    required this.startAt,
    required this.nextDueAt,
    required this.createdAt,
    required this.updatedAt,
    this.note = '',
    this.endAt,
    this.occurrencesGenerated = 0,
    this.active = true,
    this.userId,
    this.deletedAt,
    this.syncStatus = SyncStatus.pendingCreate,
  });

  factory RecurringRule.fromRow(Map<String, Object?> r) {
    final meta = SyncMeta.fromRow(r);
    return RecurringRule(
      id: meta.id,
      userId: meta.userId,
      type: TransactionType.parse(r['type']),
      amountMinor: RowReader.int_(r['amount_minor']),
      categoryId: RowReader.str(r['category_id']),
      accountId: RowReader.str(r['account_id']),
      note: RowReader.str(r['note']),
      frequency: RecurrenceFrequency.parse(r['frequency']),
      startAt: RowReader.date(r['start_at']),
      endAt: RowReader.dateOrNull(r['end_at']),
      occurrencesGenerated: RowReader.int_(r['occurrences_generated']),
      nextDueAt: RowReader.date(r['next_due_at']),
      active: RowReader.bool_(r['active']),
      createdAt: meta.createdAt,
      updatedAt: meta.updatedAt,
      deletedAt: meta.deletedAt,
      syncStatus: meta.syncStatus,
    );
  }

  final String id;
  final String? userId;
  final TransactionType type;
  final int amountMinor;
  final String categoryId;
  final String accountId;
  final String note;
  final RecurrenceFrequency frequency;
  final DateTime startAt;
  final DateTime? endAt;

  /// How many occurrences (index 0..n-1) have already been materialised.
  final int occurrencesGenerated;
  final DateTime nextDueAt;
  final bool active;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;

  Map<String, Object?> toRow() => {
        'id': id,
        'user_id': userId,
        'type': type.name,
        'amount_minor': amountMinor,
        'category_id': categoryId,
        'account_id': accountId,
        'note': note,
        'frequency': frequency.name,
        'start_at': startAt.millisecondsSinceEpoch,
        'end_at': endAt?.millisecondsSinceEpoch,
        'occurrences_generated': occurrencesGenerated,
        'next_due_at': nextDueAt.millisecondsSinceEpoch,
        'active': active ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'deleted_at': deletedAt?.millisecondsSinceEpoch,
      };
}
