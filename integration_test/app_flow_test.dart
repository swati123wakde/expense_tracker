// On-device end-to-end tests (real SQLCipher database, real UI).
// Run with:  flutter test integration_test -d <device-id>
//
// The cloud and the network are simulated so the offline → restart → online
// scenario is deterministic; everything else is the production stack.

import 'dart:io';

import 'package:expense_manager/app/dependencies.dart';
import 'package:expense_manager/app/expense_app.dart';
import 'package:expense_manager/core/services/app_lock_service.dart';
import 'package:expense_manager/core/services/connectivity_service.dart';
import 'package:expense_manager/core/services/exchange_rate_service.dart';
import 'package:expense_manager/core/services/notification_service.dart';
import 'package:expense_manager/core/services/secure_store.dart';
import 'package:expense_manager/data/local/app_database.dart';
import 'package:expense_manager/data/local/encrypted_database_opener.dart';
import 'package:expense_manager/data/models/transaction_filter.dart';
import 'package:expense_manager/data/remote/auth_service.dart';
import 'package:expense_manager/data/remote/in_memory_remote_data_source.dart';
import 'package:expense_manager/features/common/common_widgets.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:path/path.dart' as p;

class _StaticRates implements RateSource {
  @override
  Future<Map<String, double>> fetchRatesPerUsd() async => {'USD': 1.0};
}

Future<AppDependencies> _boot({
  required String path,
  required InMemoryRemoteDataSource cloud,
  required FakeConnectivityService network,
}) async {
  final db = await AppDatabase.open(EncryptedDatabaseOpener.withPassword('integration-test-key'), path);
  return AppDependencies.create(
    database: db,
    auth: LocalAuthService(cloud: true, initialUser: const AuthUser(id: 'it-user', email: 'it@example.com')),
    remote: cloud,
    connectivity: network,
    notifications: RecordingNotificationService(),
    rateSource: _StaticRates(),
    secureStore: InMemorySecureStore(),
    biometrics: NoBiometricAuthenticator(),
  );
}

Future<void> _pumpApp(WidgetTester tester, AppDependencies deps) async {
  final settings = await deps.settings.load();
  await tester.pumpWidget(ExpenseApp(deps: deps, initialSettings: settings));
  await tester.pumpAndSettle();
}

Future<void> _addExpense(WidgetTester tester, String amount, String note) async {
  await tester.tap(find.byKey(const Key('addTransactionFab')));
  await tester.pumpAndSettle();
  await tester.enterText(find.byKey(const Key('amountField')), amount);
  await tester.ensureVisible(find.byKey(const Key('category_cat_food')));
  await tester.tap(find.byKey(const Key('category_cat_food')));
  await tester.enterText(find.byKey(const Key('noteField')), note);
  await tester.tap(find.byKey(const Key('saveTransaction')));
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  Skeleton.animate = false;

  testWidgets('Create → View → Edit → Delete (with undo)', (tester) async {
    final dir = await Directory.systemTemp.createTemp('it_crud');
    final deps = await _boot(
      path: p.join(dir.path, 'crud.db'),
      cloud: InMemoryRemoteDataSource(),
      network: FakeConnectivityService(online: false),
    );
    await _pumpApp(tester, deps);

    await _addExpense(tester, '20', 'Groceries');
    await tester.tap(find.byKey(const Key('nav_Transactions')));
    await tester.pumpAndSettle();
    expect(find.text('Groceries'), findsOneWidget);

    // Swipe right → edit.
    await tester.drag(find.text('Groceries'), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Edit transaction'), findsOneWidget);
    await tester.enterText(find.byKey(const Key('amountField')), '25');
    await tester.enterText(find.byKey(const Key('noteField')), 'Groceries edited');
    await tester.tap(find.byKey(const Key('saveTransaction')));
    await tester.pumpAndSettle();
    expect(find.text('Groceries edited'), findsOneWidget);

    // Swipe left → delete, then undo.
    await tester.drag(find.text('Groceries edited'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Groceries edited'), findsNothing);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(find.text('Groceries edited'), findsOneWidget);

    await tester.drag(find.text('Groceries edited'), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(await deps.transactions.count(TransactionFilter.none), 0);

    await tester.pumpWidget(const SizedBox.shrink());
    await deps.dispose();
  });

  testWidgets('Offline → create → restart → still there → online → synced', (tester) async {
    final dir = await Directory.systemTemp.createTemp('it_offline');
    final path = p.join(dir.path, 'offline.db');
    final cloud = InMemoryRemoteDataSource();
    final network = FakeConnectivityService(online: false);

    var deps = await _boot(path: path, cloud: cloud, network: network);
    await _pumpApp(tester, deps);
    await _addExpense(tester, '42', 'Offline purchase');
    expect(find.text('Offline purchase'), findsOneWidget);
    expect(cloud.rowsFor('transactions', 'it-user'), isEmpty);

    // "Close" the app and reopen it on the same encrypted database.
    await tester.pumpWidget(const SizedBox.shrink());
    await deps.dispose();
    deps = await _boot(path: path, cloud: cloud, network: network);
    await _pumpApp(tester, deps);
    expect(find.text('Offline purchase'), findsOneWidget);
    expect(find.textContaining('will sync later'), findsWidgets);

    // Internet restored → background sync uploads pending changes.
    network.online = true;
    await tester.pumpAndSettle(const Duration(seconds: 1));
    await deps.sync.syncNow();
    await tester.pumpAndSettle();
    final uploaded = cloud.rowsFor('transactions', 'it-user');
    expect(uploaded.map((r) => r['note']), contains('Offline purchase'));
    expect(find.text('Synced'), findsWidgets);

    await tester.pumpWidget(const SizedBox.shrink());
    await deps.dispose();
  });
}
