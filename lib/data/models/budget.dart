import 'enums.dart';
import 'row_utils.dart';

/// A monthly spending limit. [categoryId] == null is the overall monthly budget.
///
/// Ids are deterministic ('budget_overall', 'budget_cat_<id>') so two devices
/// creating the "same" budget converge on a single record during sync.
class BudgetEntity {
  const BudgetEntity({
    required this.id,
    required this.amountMinor,
    required this.createdAt,
    required this.updatedAt,
    this.categoryId,
    this.userId,
    this.deletedAt,
    this.syncStatus = SyncStatus.pendingCreate,
  });

  factory BudgetEntity.fromRow(Map<String, Object?> r) {
    final meta = SyncMeta.fromRow(r);
    return BudgetEntity(
      id: meta.id,
      userId: meta.userId,
      categoryId: RowReader.strOrNull(r['category_id']),
      amountMinor: RowReader.int_(r['amount_minor']),
      createdAt: meta.createdAt,
      updatedAt: meta.updatedAt,
      deletedAt: meta.deletedAt,
      syncStatus: meta.syncStatus,
    );
  }

  static const String overallId = 'budget_overall';
  static String idForCategory(String categoryId) => 'budget_cat_$categoryId';

  final String id;
  final String? userId;
  final String? categoryId;
  final int amountMinor;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;

  bool get isOverall => categoryId == null;

  Map<String, Object?> toRow() => {
        'id': id,
        'user_id': userId,
        'category_id': categoryId,
        'amount_minor': amountMinor,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'deleted_at': deletedAt?.millisecondsSinceEpoch,
      };
}
