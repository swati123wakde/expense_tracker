import 'package:expense_manager/core/services/connectivity_service.dart';
import 'package:expense_manager/data/models/enums.dart';
import 'package:expense_manager/data/models/transaction.dart';
import 'package:expense_manager/data/remote/in_memory_remote_data_source.dart';
import 'package:expense_manager/sync/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_harness.dart';

void main() {
  const user = 'user-a';

  Future<TestEnv> device(InMemoryRemoteDataSource cloud, {String userId = user, bool online = true}) =>
      TestEnv.create(
        remote: cloud,
        cloud: true,
        userId: userId,
        connectivity: FakeConnectivityService(online: online),
      );

  test('local create is uploaded and marked synced', () async {
    final cloud = InMemoryRemoteDataSource();
    final a = await device(cloud);
    final t = await a.addExpense(2500, note: 'Lunch');

    final report = await a.deps.sync.syncNow();
    expect(report!.pushed, greaterThan(0));
    expect(cloud.row('transactions', user, t.id)!['amount_minor'], 2500);
    expect((await a.deps.transactions.byId(t.id))!.syncStatus, SyncStatus.synced);
    expect(a.deps.sync.state.pendingCount, 0);
    expect(a.deps.sync.state.label, '✓ Synced');
    await a.dispose();
  });

  test('offline: nothing is uploaded and status says changes will sync later', () async {
    final cloud = InMemoryRemoteDataSource();
    final a = await device(cloud, online: false);
    await a.addExpense(100);
    await a.addExpense(200);
    await a.deps.sync.syncNow();
    expect(cloud.rowsFor('transactions', user), isEmpty);
    await a.deps.sync.refreshPendingCount();
    expect(a.deps.sync.state.online, isFalse);
    expect(a.deps.sync.state.label, startsWith('Offline • '));
    expect(a.deps.sync.state.label, endsWith('changes will sync later'));
    await a.dispose();
  });

  test('cloud changes are pulled incrementally into another device', () async {
    final cloud = InMemoryRemoteDataSource();
    final a = await device(cloud);
    final b = await device(cloud);
    final t = await a.addExpense(4200, note: 'Dinner');
    await a.deps.sync.syncNow();

    await b.deps.sync.syncNow();
    final onB = await b.deps.transactions.byId(t.id);
    expect(onB!.note, 'Dinner');
    expect(onB.syncStatus, SyncStatus.synced);

    // Second sync only fetches rows changed after the stored cursor.
    final report = await b.deps.sync.syncNow();
    expect(report!.pulled, 0);
    await a.dispose();
    await b.dispose();
  });

  test('deletes propagate as tombstones and do not reappear', () async {
    final cloud = InMemoryRemoteDataSource();
    final a = await device(cloud);
    final b = await device(cloud);
    final t = await a.addExpense(999, note: 'Mistake');
    await a.deps.sync.syncNow();
    await b.deps.sync.syncNow();
    expect(await b.deps.transactions.byId(t.id), isNotNull);

    await a.deps.transactions.delete(t.id);
    await a.deps.sync.syncNow();
    expect(cloud.row('transactions', user, t.id)!['deleted_at'], isNotNull);

    await b.deps.sync.syncNow();
    expect(await b.deps.transactions.byId(t.id), isNull);
    // A full re-sync on A must not resurrect it.
    await a.deps.sync.syncNow();
    expect(await a.deps.transactions.byId(t.id), isNull);
    await a.dispose();
    await b.dispose();
  });

  test('field-level merge: note edited on A, amount edited on B, both survive', () async {
    final cloud = InMemoryRemoteDataSource();
    final a = await device(cloud);
    final b = await device(cloud);
    final t = await a.addExpense(2000, note: 'Food');
    await a.deps.sync.syncNow();
    await b.deps.sync.syncNow();

    Future<void> edit(TestEnv env, {int? amount, String? note}) async {
      final cur = (await env.deps.transactions.byId(t.id))!;
      env.clock.advance(const Duration(minutes: 1));
      await env.deps.transactions.update(
        t.id,
        TransactionDraft(
          type: cur.type,
          amountMinor: amount ?? cur.amountMinor,
          categoryId: cur.categoryId,
          accountId: cur.accountId,
          occurredAt: cur.occurredAt,
          note: note ?? cur.note,
        ),
      );
    }

    await edit(a, note: 'Team lunch'); // offline on A
    await edit(b, amount: 3000); // B edits the amount

    await b.deps.sync.syncNow(); // B uploads amount
    await a.deps.sync.syncNow(); // A pulls amount, merges, uploads note
    await b.deps.sync.syncNow(); // B pulls merged record

    for (final env in [a, b]) {
      final r = (await env.deps.transactions.byId(t.id))!;
      expect(r.amountMinor, 3000);
      expect(r.note, 'Team lunch');
      expect(r.syncStatus, SyncStatus.synced);
    }
    final c = cloud.row('transactions', user, t.id)!;
    expect(c['amount_minor'], 3000);
    expect(c['note'], 'Team lunch');
    await a.dispose();
    await b.dispose();
  });

  test('same-field conflict resolves by last write (Food $20 → $25 vs → $30)', () async {
    final cloud = InMemoryRemoteDataSource();
    final a = await device(cloud);
    final b = await device(cloud);
    final t = await a.addExpense(2000);
    await a.deps.sync.syncNow();
    await b.deps.sync.syncNow();

    final cur = (await a.deps.transactions.byId(t.id))!;
    TransactionDraft withAmount(int v) => TransactionDraft(
          type: cur.type,
          amountMinor: v,
          categoryId: cur.categoryId,
          accountId: cur.accountId,
          occurredAt: cur.occurredAt,
        );
    a.clock.advance(const Duration(minutes: 1));
    await a.deps.transactions.update(t.id, withAmount(2500));
    b.clock.advance(const Duration(minutes: 2)); // B edits later
    await b.deps.transactions.update(t.id, withAmount(3000));

    await a.deps.sync.syncNow();
    await b.deps.sync.syncNow();
    await a.deps.sync.syncNow();

    expect((await a.deps.transactions.byId(t.id))!.amountMinor, 3000);
    expect((await b.deps.transactions.byId(t.id))!.amountMinor, 3000);
    expect(cloud.row('transactions', user, t.id)!['amount_minor'], 3000);
    await a.dispose();
    await b.dispose();
  });

  test('cloud unreachable: sync fails without touching local data', () async {
    final cloud = InMemoryRemoteDataSource()..failRequests = true;
    final a = await device(cloud);
    final t = await a.addExpense(500);
    await a.deps.sync.syncNow();
    expect(a.deps.sync.state.phase, SyncPhase.failed);
    expect(a.deps.sync.state.label, '⚠ Sync failed');
    expect((await a.deps.transactions.byId(t.id))!.syncStatus.isPending, isTrue);

    cloud.failRequests = false;
    await a.deps.sync.syncNow();
    expect((await a.deps.transactions.byId(t.id))!.syncStatus, SyncStatus.synced);
    expect(a.deps.sync.state.phase, SyncPhase.idle);
    await a.dispose();
  });

  test('rejected upload marks rows failed and they retry later', () async {
    final cloud = InMemoryRemoteDataSource()..failUpserts = true;
    final a = await device(cloud);
    final t = await a.addExpense(500);
    await a.deps.sync.syncNow();
    final raw = await a.deps.transactions.dao.find(t.id);
    // Accounts upload first and fail, so later tables stay pending; retry
    // must still deliver everything.
    expect(raw!['sync_status'], isNot(SyncStatus.synced.name));
    final accounts = await a.deps.accounts.dao.find('acc_cash');
    expect(accounts!['sync_status'], SyncStatus.failed.name);

    cloud.failUpserts = false;
    await a.deps.sync.syncNow();
    expect((await a.deps.transactions.byId(t.id))!.syncStatus, SyncStatus.synced);
    expect(cloud.row('accounts', user, 'acc_cash'), isNotNull);
    await a.dispose();
  });

  test('users are isolated in the cloud', () async {
    final cloud = InMemoryRemoteDataSource();
    final a = await device(cloud, userId: 'alice');
    final b = await device(cloud, userId: 'bob');
    final t = await a.addExpense(123, note: 'Private');
    await a.deps.sync.syncNow();
    await b.deps.sync.syncNow();
    expect(await b.deps.transactions.byId(t.id), isNull);
    expect(cloud.rowsFor('transactions', 'bob'), isEmpty);
    await a.dispose();
    await b.dispose();
  });

  test('sync is disabled for guests / local-only builds', () async {
    final local = await TestEnv.create();
    expect(await local.deps.sync.syncNow(), isNull);
    expect(local.deps.sync.state.phase, SyncPhase.disabled);
    expect(local.deps.sync.state.label, 'Local only');
    await local.dispose();
  });
}
