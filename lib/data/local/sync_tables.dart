import '../../core/services/data_change_bus.dart';

/// Describes a table that participates in cloud sync.
///
/// [columns] are the "content" columns mirrored 1:1 in the cloud. Local-only
/// columns (sync_status, sync_base, attachment_path...) are never uploaded.
class SyncTableSpec {
  const SyncTableSpec(this.table, this.columns);

  final String table;
  final List<String> columns;

  static const metadataColumns = {'id', 'user_id', 'created_at', 'updated_at'};

  /// Fields that take part in field-level conflict resolution.
  List<String> get mergeFields =>
      columns.where((c) => !metadataColumns.contains(c)).toList(growable: false);

  /// Extracts only the synced columns from a full local row.
  Map<String, Object?> content(Map<String, Object?> row) => {
        for (final c in columns) c: row[c],
      };
}

class SyncTables {
  SyncTables._();

  static const _meta = ['id', 'user_id', 'created_at', 'updated_at', 'deleted_at'];

  static const accounts = SyncTableSpec(Tables.accounts, [
    ..._meta,
    'name', 'type', 'currency', 'icon', 'color', 'archived', //
  ]);

  static const categories = SyncTableSpec(Tables.categories, [
    ..._meta,
    'name', 'type', 'icon', 'color', 'is_custom', 'archived', 'sort_order', //
  ]);

  static const transactions = SyncTableSpec(Tables.transactions, [
    ..._meta,
    'type', 'amount_minor', 'category_id', 'account_id', 'note', 'occurred_at', //
    'recurring_rule_id', 'is_favorite',
  ]);

  static const budgets = SyncTableSpec(Tables.budgets, [
    ..._meta,
    'category_id', 'amount_minor', //
  ]);

  static const goals = SyncTableSpec(Tables.goals, [
    ..._meta,
    'name', 'target_minor', 'saved_minor', 'target_date', 'icon', 'color', //
  ]);

  static const recurringRules = SyncTableSpec(Tables.recurringRules, [
    ..._meta,
    'type', 'amount_minor', 'category_id', 'account_id', 'note', 'frequency', //
    'start_at', 'end_at', 'occurrences_generated', 'next_due_at', 'active',
  ]);

  /// Upload/download order: parents before children.
  static const all = [accounts, categories, budgets, goals, recurringRules, transactions];

  static SyncTableSpec byName(String table) => all.firstWhere((s) => s.table == table);
}
