// Headless integration tests of the full data stack (real SQLite file,
// repositories, sync engine, simulated cloud and network). They run on CI
// with `flutter test`; the on-device UI version lives in integration_test/.

import 'package:expense_manager/core/services/connectivity_service.dart';
import 'package:expense_manager/data/models/enums.dart';
import 'package:expense_manager/data/models/transaction.dart';
import 'package:expense_manager/data/models/transaction_filter.dart';
import 'package:expense_manager/data/remote/in_memory_remote_data_source.dart';
import 'package:flutter_test/flutter_test.dart';

import '../helpers/test_harness.dart';

void main() {
  const user = 'user-1';

  test('Create → View → Edit → Delete', () async {
    final env = await TestEnv.create();
    final t = await env.addExpense(2000, note: 'Groceries');

    var page = await env.deps.transactions.page(TransactionFilter.none);
    expect(page.single.transaction.note, 'Groceries');
    expect(page.single.categoryName, 'Food');
    expect(page.single.accountName, 'Cash');

    await env.deps.transactions.update(
      t.id,
      TransactionDraft(
        type: TransactionType.expense,
        amountMinor: 2600,
        categoryId: 'cat_shopping',
        accountId: 'acc_bank',
        occurredAt: t.occurredAt,
        note: 'Groceries + snacks',
      ),
    );
    page = await env.deps.transactions.page(TransactionFilter.none);
    expect(page.single.transaction.amountMinor, 2600);
    expect(page.single.categoryName, 'Shopping');

    final balances = {for (final b in await env.deps.accounts.balances()) b.account.id: b.balanceMinor};
    expect(balances['acc_bank'], -2600);
    expect(balances['acc_cash'], 0);

    await env.deps.transactions.delete(t.id);
    expect(await env.deps.transactions.page(TransactionFilter.none), isEmpty);
    await env.dispose();
  });

  test('Offline → Create → Restart → Still exists → Online → Sync → Cloud has it', () async {
    final cloud = InMemoryRemoteDataSource();
    final network = FakeConnectivityService(online: false);

    // 1. Device is offline; user has existing (already synced) data.
    var env = await TestEnv.create(remote: cloud, cloud: true, userId: user, connectivity: network);
    final path = env.path;
    network.online = true;
    final existing = await env.addExpense(1500, note: 'Synced earlier');
    final toDelete = await env.addExpense(700, note: 'Will be deleted');
    await env.deps.sync.syncNow();
    network.online = false;

    // 2. Offline: view, add, edit, delete.
    expect(await env.deps.transactions.count(TransactionFilter.none), 2);
    final created = await env.addExpense(4200, note: 'Offline dinner');
    await env.deps.transactions.update(
      created.id,
      TransactionDraft(
        type: TransactionType.expense,
        amountMinor: 4500,
        categoryId: 'cat_food',
        accountId: 'acc_cash',
        occurredAt: created.occurredAt,
        note: 'Offline dinner (tip)',
      ),
    );
    await env.deps.transactions.delete(toDelete.id);
    expect(await env.deps.sync.syncNow(), isNull, reason: 'no sync while offline');
    expect(cloud.row('transactions', user, created.id), isNull);

    // 3. Close the app and reopen it on the same database file.
    await env.dispose();
    env = await TestEnv.create(path: path, remote: cloud, cloud: true, userId: user, connectivity: network);

    // 4. All offline changes survived the restart.
    final afterRestart = await env.deps.transactions.page(TransactionFilter.none);
    expect(afterRestart.map((v) => v.transaction.note), containsAll(['Synced earlier', 'Offline dinner (tip)']));
    expect(afterRestart.any((v) => v.id == toDelete.id), isFalse);
    expect(await env.deps.sync.queue.pendingCount(), 2);

    // 5. Internet restored → pending changes synchronise.
    network.online = true;
    await env.deps.sync.syncNow();
    expect(cloud.row('transactions', user, created.id)!['amount_minor'], 4500);
    expect(cloud.row('transactions', user, toDelete.id)!['deleted_at'], isNotNull);
    expect(cloud.row('transactions', user, existing.id)!['note'], 'Synced earlier');
    expect(await env.deps.sync.queue.pendingCount(), 0);
    expect(env.deps.sync.state.label, '✓ Synced');
    await env.dispose();
  });
}
