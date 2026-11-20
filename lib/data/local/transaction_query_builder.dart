import '../../core/utils/money.dart';
import '../models/transaction_filter.dart';

class SqlQuery {
  const SqlQuery(this.sql, this.args);
  final String sql;
  final List<Object?> args;
}

/// Translates a [TransactionFilter] into parameterised SQL. Pure and
/// unit-tested; every filter group is ANDed so they combine freely
/// (e.g. Expense + Food + This Month).
class TransactionQueryBuilder {
  TransactionQueryBuilder._();

  static const String _from = '''
FROM transactions t
LEFT JOIN categories c ON c.id = t.category_id
LEFT JOIN accounts a ON a.id = t.account_id''';

  static const String selectView = '''
SELECT t.*, c.name AS category_name, c.icon AS category_icon, c.color AS category_color,
       a.name AS account_name, a.currency AS account_currency
$_from''';

  static SqlQuery where(TransactionFilter f) {
    final clauses = <String>['t.deleted_at IS NULL'];
    final args = <Object?>[];

    if (f.type != null) {
      clauses.add('t.type = ?');
      args.add(f.type!.name);
    }
    if (f.categoryIds.isNotEmpty) {
      clauses.add('t.category_id IN (${_placeholders(f.categoryIds.length)})');
      args.addAll(f.categoryIds);
    }
    if (f.accountIds.isNotEmpty) {
      clauses.add('t.account_id IN (${_placeholders(f.accountIds.length)})');
      args.addAll(f.accountIds);
    }
    if (f.from != null) {
      clauses.add('t.occurred_at >= ?');
      args.add(f.from!.millisecondsSinceEpoch);
    }
    if (f.to != null) {
      clauses.add('t.occurred_at < ?');
      args.add(f.to!.millisecondsSinceEpoch);
    }
    if (f.minAmountMinor != null) {
      clauses.add('t.amount_minor >= ?');
      args.add(f.minAmountMinor);
    }
    if (f.maxAmountMinor != null) {
      clauses.add('t.amount_minor <= ?');
      args.add(f.maxAmountMinor);
    }
    if (f.favoritesOnly) {
      clauses.add('t.is_favorite = 1');
    }

    final q = f.query.trim();
    if (q.isNotEmpty) {
      final like = '%${escapeLike(q)}%';
      final search = <String>[
        r"t.note LIKE ? ESCAPE '\'",
        r"c.name LIKE ? ESCAPE '\'",
      ];
      args
        ..add(like)
        ..add(like);
      final amount = Money.parseToMinor(q);
      if (amount != null) {
        search.add('t.amount_minor = ?');
        args.add(amount.abs());
      }
      clauses.add('(${search.join(' OR ')})');
    }

    return SqlQuery(clauses.join(' AND '), args);
  }

  /// One page of results ordered newest first using keyset pagination, which
  /// stays O(page) at any depth (no OFFSET scans over 10k+ rows).
  static SqlQuery page(TransactionFilter f, {PageCursor? after, int limit = 40}) {
    final w = where(f);
    final args = [...w.args];
    var sql = '$selectView\nWHERE ${w.sql}';
    if (after != null) {
      sql += ' AND (t.occurred_at < ? OR (t.occurred_at = ? AND t.id < ?))';
      args.addAll([after.occurredAtMs, after.occurredAtMs, after.id]);
    }
    sql += '\nORDER BY t.occurred_at DESC, t.id DESC LIMIT ?';
    args.add(limit);
    return SqlQuery(sql, args);
  }

  static SqlQuery count(TransactionFilter f) {
    final w = where(f);
    return SqlQuery('SELECT COUNT(*) AS c $_from WHERE ${w.sql}', w.args);
  }

  /// Totals for the current filter (shown above the history list).
  static SqlQuery totals(TransactionFilter f) {
    final w = where(f);
    return SqlQuery(
      'SELECT t.type AS type, a.currency AS currency, SUM(t.amount_minor) AS total '
      '$_from WHERE ${w.sql} GROUP BY t.type, a.currency',
      w.args,
    );
  }

  static String escapeLike(String input) =>
      input.replaceAll(r'\', r'\\').replaceAll('%', r'\%').replaceAll('_', r'\_');

  static String _placeholders(int n) => List.filled(n, '?').join(',');
}
