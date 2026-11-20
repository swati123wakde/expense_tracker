import 'package:expense_manager/data/local/transaction_query_builder.dart';
import 'package:expense_manager/data/models/enums.dart';
import 'package:expense_manager/data/models/transaction_filter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('empty filter only excludes soft-deleted rows', () {
    final q = TransactionQueryBuilder.where(TransactionFilter.none);
    expect(q.sql, 't.deleted_at IS NULL');
    expect(q.args, isEmpty);
  });

  test('filters combine with AND (Expense + Food + This Month)', () {
    final from = DateTime(2026, 7);
    final to = DateTime(2026, 8);
    final q = TransactionQueryBuilder.where(
      TransactionFilter(type: TransactionType.expense, categoryIds: const {'cat_food'}, from: from, to: to),
    );
    expect(q.sql, contains('t.type = ?'));
    expect(q.sql, contains('t.category_id IN (?)'));
    expect(q.sql, contains('t.occurred_at >= ?'));
    expect(q.sql, contains('t.occurred_at < ?'));
    expect(q.args, ['expense', 'cat_food', from.millisecondsSinceEpoch, to.millisecondsSinceEpoch]);
  });

  test('search matches note, category or exact amount', () {
    final q = TransactionQueryBuilder.where(const TransactionFilter(query: '25'));
    expect(q.sql, contains('t.note LIKE ?'));
    expect(q.sql, contains('c.name LIKE ?'));
    expect(q.sql, contains('t.amount_minor = ?'));
    expect(q.args, ['%25%', '%25%', 2500]);

    final text = TransactionQueryBuilder.where(const TransactionFilter(query: 'coffee'));
    expect(text.sql, isNot(contains('amount_minor = ?')));
  });

  test('LIKE wildcards in user input are escaped', () {
    expect(TransactionQueryBuilder.escapeLike('50%_off'), r'50\%\_off');
  });

  test('keyset pagination adds a stable cursor clause', () {
    final q = TransactionQueryBuilder.page(TransactionFilter.none, after: const PageCursor(1000, 'abc'), limit: 20);
    expect(q.sql, contains('(t.occurred_at < ? OR (t.occurred_at = ? AND t.id < ?))'));
    expect(q.sql, contains('ORDER BY t.occurred_at DESC, t.id DESC LIMIT ?'));
    expect(q.args, [1000, 1000, 'abc', 20]);
  });

  test('amount range', () {
    final q = TransactionQueryBuilder.where(const TransactionFilter(minAmountMinor: 100, maxAmountMinor: 500));
    expect(q.args, [100, 500]);
  });
}
