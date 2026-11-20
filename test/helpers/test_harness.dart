import 'dart:io';

import 'package:expense_manager/app/dependencies.dart';
import 'package:expense_manager/core/services/app_lock_service.dart';
import 'package:expense_manager/core/services/connectivity_service.dart';
import 'package:expense_manager/core/services/exchange_rate_service.dart';
import 'package:expense_manager/core/services/notification_service.dart';
import 'package:expense_manager/core/services/secure_store.dart';
import 'package:expense_manager/core/utils/clock.dart';
import 'package:expense_manager/data/local/app_database.dart';
import 'package:expense_manager/data/models/enums.dart';
import 'package:expense_manager/data/models/transaction.dart';
import 'package:expense_manager/data/remote/auth_service.dart';
import 'package:expense_manager/data/remote/in_memory_remote_data_source.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Opens databases with sqflite_common_ffi in the test isolate (no
/// background isolate, so it also works inside `testWidgets` fake async).
/// Production uses SQLCipher; the schema and SQL are identical.
DatabaseOpener ffiOpener() {
  sqfliteFfiInit();
  return (path, options) => databaseFactoryFfiNoIsolate.openDatabase(path, options: options);
}

String tempDbPath([String name = 'test.db']) =>
    p.join(Directory.systemTemp.createTempSync('expense_test_').path, name);

class FakeRateSource implements RateSource {
  FakeRateSource([this.rates = const {'USD': 1.0, 'EUR': 0.5, 'INR': 80.0}]);
  final Map<String, double> rates;

  @override
  Future<Map<String, double>> fetchRatesPerUsd() async => rates;
}

class TestEnv {
  TestEnv._({
    required this.deps,
    required this.path,
    required this.clock,
    required this.remote,
    required this.connectivity,
    required this.auth,
    required this.notifications,
  });

  final AppDependencies deps;
  final String path;
  final FixedClock clock;
  final InMemoryRemoteDataSource remote;
  final FakeConnectivityService connectivity;
  final LocalAuthService auth;
  final RecordingNotificationService notifications;

  static final DateTime defaultNow = DateTime(2026, 7, 20, 10, 0);

  /// Creates a fully wired app graph backed by a real SQLite file.
  /// Pass the same [path] to simulate an app restart, and the same [remote]
  /// to simulate several devices sharing one cloud account.
  static Future<TestEnv> create({
    String? path,
    FixedClock? clock,
    InMemoryRemoteDataSource? remote,
    FakeConnectivityService? connectivity,
    String? userId,
    bool cloud = false,
  }) async {
    final dbPath = path ?? tempDbPath();
    final c = clock ?? FixedClock(defaultNow);
    final r = remote ?? InMemoryRemoteDataSource(serverClock: () => c.nowMs());
    final conn = connectivity ?? FakeConnectivityService(online: true);
    final auth = LocalAuthService(
      cloud: cloud,
      initialUser: userId == null ? null : AuthUser(id: userId, email: '$userId@example.com'),
    );
    final notifications = RecordingNotificationService();
    final database = await AppDatabase.open(ffiOpener(), dbPath);
    final deps = await AppDependencies.create(
      database: database,
      auth: auth,
      remote: cloud ? r : null,
      connectivity: conn,
      notifications: notifications,
      rateSource: FakeRateSource(),
      secureStore: InMemorySecureStore(),
      biometrics: NoBiometricAuthenticator(),
      clock: c,
      syncDebounce: const Duration(milliseconds: 10),
    );
    return TestEnv._(
      deps: deps,
      path: dbPath,
      clock: c,
      remote: r,
      connectivity: conn,
      auth: auth,
      notifications: notifications,
    );
  }

  Future<void> dispose() => deps.dispose();

  Future<TransactionEntity> addExpense(
    int amountMinor, {
    String categoryId = 'cat_food',
    String accountId = 'acc_cash',
    String note = '',
    DateTime? at,
  }) =>
      deps.transactions.create(
        TransactionDraft(
          type: TransactionType.expense,
          amountMinor: amountMinor,
          categoryId: categoryId,
          accountId: accountId,
          occurredAt: at ?? clock.now(),
          note: note,
        ),
      );

  Future<TransactionEntity> addIncome(
    int amountMinor, {
    String categoryId = 'cat_salary',
    String accountId = 'acc_bank',
    String note = '',
    DateTime? at,
  }) =>
      deps.transactions.create(
        TransactionDraft(
          type: TransactionType.income,
          amountMinor: amountMinor,
          categoryId: categoryId,
          accountId: accountId,
          occurredAt: at ?? clock.now(),
          note: note,
        ),
      );
}
