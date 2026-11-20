import 'package:expense_manager/data/local/sync_tables.dart';
import 'package:expense_manager/sync/conflict_resolver.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> tx({
  int amount = 2000,
  String note = 'Lunch',
  String category = 'cat_food',
  int updatedAt = 1000,
  int? deletedAt,
}) =>
    {
      'id': 't1',
      'user_id': 'u1',
      'created_at': 500,
      'updated_at': updatedAt,
      'deleted_at': deletedAt,
      'type': 'expense',
      'amount_minor': amount,
      'category_id': category,
      'account_id': 'acc_cash',
      'note': note,
      'occurred_at': 100,
      'recurring_rule_id': null,
      'is_favorite': 0,
    };

void main() {
  final fields = SyncTables.transactions.mergeFields;

  test('non-conflicting edits on both devices are both kept (field-level merge)', () {
    final base = tx();
    final local = tx(note: 'Team lunch', updatedAt: 2000); // device A edits note
    final remote = tx(amount: 3000, updatedAt: 3000); // device B edits amount
    final out = ConflictResolver.merge(base: base, local: local, remote: remote, fields: fields);
    expect(out.merged['note'], 'Team lunch');
    expect(out.merged['amount_minor'], 3000);
    expect(out.conflictedFields, isEmpty);
    expect(out.needsUpload, isTrue, reason: 'cloud lacks the local note change');
    expect(out.merged['updated_at'], 3000);
  });

  test('same field changed on both sides falls back to last-write-wins', () {
    final base = tx(amount: 2000);
    // Device A: 20 → 25 at t=2000, Device B: 20 → 30 at t=3000.
    final local = tx(amount: 2500, updatedAt: 2000);
    final remote = tx(amount: 3000, updatedAt: 3000);
    final out = ConflictResolver.merge(base: base, local: local, remote: remote, fields: fields);
    expect(out.merged['amount_minor'], 3000);
    expect(out.conflictedFields, ['amount_minor']);
    expect(out.needsUpload, isFalse);

    final newerLocal = tx(amount: 2500, updatedAt: 4000);
    final out2 = ConflictResolver.merge(base: base, local: newerLocal, remote: remote, fields: fields);
    expect(out2.merged['amount_minor'], 2500);
    expect(out2.needsUpload, isTrue);
  });

  test('LWW ties are resolved identically on both devices', () {
    final base = tx();
    final a = tx(note: 'A', updatedAt: 5000);
    final b = tx(note: 'B', updatedAt: 5000);
    final onA = ConflictResolver.merge(base: base, local: a, remote: b, fields: fields);
    final onB = ConflictResolver.merge(base: base, local: b, remote: a, fields: fields);
    expect(onA.merged['note'], onB.merged['note']);
  });

  test('a delete on one device survives an edit on another', () {
    final base = tx();
    final local = tx(deletedAt: 2500, updatedAt: 2500);
    final remote = tx(note: 'edited elsewhere', updatedAt: 3000);
    final out = ConflictResolver.merge(base: base, local: local, remote: remote, fields: fields);
    expect(out.merged['deleted_at'], 2500);
    expect(out.merged['note'], 'edited elsewhere');
    expect(out.needsUpload, isTrue);
  });

  test('identical edits are not conflicts', () {
    final base = tx();
    final out = ConflictResolver.merge(
      base: base,
      local: tx(amount: 999, updatedAt: 2000),
      remote: tx(amount: 999, updatedAt: 2100),
      fields: fields,
    );
    expect(out.conflictedFields, isEmpty);
    expect(out.needsUpload, isFalse);
  });

  test('without a base, differing fields use LWW (seeded records)', () {
    final local = tx(note: 'Default', updatedAt: 0);
    final remote = tx(note: 'Renamed', updatedAt: 9000);
    final out = ConflictResolver.merge(base: null, local: local, remote: remote, fields: fields);
    expect(out.merged['note'], 'Renamed');
    expect(out.needsUpload, isFalse);
  });

  test('created_at keeps the earliest value', () {
    final local = {...tx(), 'created_at': 100};
    final remote = {...tx(), 'created_at': 300};
    final out = ConflictResolver.merge(base: tx(), local: local, remote: remote, fields: fields);
    expect(out.merged['created_at'], 100);
  });
}
