import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../core/services/alert_service.dart';
import '../core/services/app_lock_service.dart';
import '../core/services/connectivity_service.dart';
import '../core/services/currency_context.dart';
import '../core/services/data_change_bus.dart';
import '../core/services/exchange_rate_service.dart';
import '../core/services/notification_service.dart';
import '../core/services/secure_store.dart';
import '../core/utils/clock.dart';
import '../data/local/app_database.dart';
import '../data/local/encrypted_database_opener.dart';
import '../data/models/app_settings.dart';
import '../data/remote/auth_service.dart';
import '../data/remote/remote_data_source.dart';
import '../data/remote/supabase_remote_data_source.dart';
import '../data/repositories/account_repository.dart';
import '../data/repositories/backup_repository.dart';
import '../data/repositories/budget_repository.dart';
import '../data/repositories/category_repository.dart';
import '../data/repositories/current_user.dart';
import '../data/repositories/goal_repository.dart';
import '../data/repositories/recurring_repository.dart';
import '../data/repositories/settings_repository.dart';
import '../data/repositories/transaction_repository.dart';
import '../sync/sync_service.dart';
import 'app_config.dart';

/// Composition root. Everything is created once here and injected, so tests
/// can swap the database, cloud, connectivity, clock and platform services.
class AppDependencies {
  AppDependencies._({
    required this.database,
    required this.clock,
    required this.bus,
    required this.currentUser,
    required this.settings,
    required this.accounts,
    required this.categories,
    required this.transactions,
    required this.budgets,
    required this.goals,
    required this.recurring,
    required this.backup,
    required this.auth,
    required this.remote,
    required this.connectivity,
    required this.sync,
    required this.notifications,
    required this.alerts,
    required this.rates,
    required this.currency,
    required this.lock,
  });

  final AppDatabase database;
  final Clock clock;
  final DataChangeBus bus;
  final CurrentUser currentUser;
  final SettingsRepository settings;
  final AccountRepository accounts;
  final CategoryRepository categories;
  final TransactionRepository transactions;
  final BudgetRepository budgets;
  final GoalRepository goals;
  final RecurringRepository recurring;
  final BackupRepository backup;
  final AuthService auth;
  final RemoteDataSource? remote;
  final ConnectivityService connectivity;
  final SyncService sync;
  final NotificationService notifications;
  final AlertService alerts;
  final ExchangeRateService rates;
  final CurrencyContext currency;
  final AppLockService lock;

  static const _seededKey = 'seeded_v1';

  static Future<AppDependencies> create({
    required AppDatabase database,
    required AuthService auth,
    required ConnectivityService connectivity,
    required NotificationService notifications,
    required RateSource rateSource,
    required SecureStore secureStore,
    required BiometricAuthenticator biometrics,
    RemoteDataSource? remote,
    Clock clock = const Clock(),
    Duration syncDebounce = const Duration(seconds: 2),
  }) async {
    final db = database.db;
    final bus = DataChangeBus();
    final user = CurrentUser()..id = auth.currentUser?.id;
    final settings = SettingsRepository(db, bus);
    final transactions = TransactionRepository(db, bus, user, clock);
    final rates = ExchangeRateService(db, rateSource, bus);
    final deps = AppDependencies._(
      database: database,
      clock: clock,
      bus: bus,
      currentUser: user,
      settings: settings,
      accounts: AccountRepository(db, bus, user, clock),
      categories: CategoryRepository(db, bus, user, clock),
      transactions: transactions,
      budgets: BudgetRepository(db, bus, user, clock),
      goals: GoalRepository(db, bus, user, clock),
      recurring: RecurringRepository(db, bus, user, clock, transactions),
      backup: BackupRepository(db, bus, user, clock, settings, transactions),
      auth: auth,
      remote: remote,
      connectivity: connectivity,
      sync: SyncService(
        db: db,
        remote: remote,
        auth: auth,
        connectivity: connectivity,
        settings: settings,
        bus: bus,
        clock: clock,
        debounce: syncDebounce,
      ),
      notifications: notifications,
      alerts: AlertService(settings, notifications),
      rates: rates,
      currency: CurrencyContext(settings, rates, bus),
      lock: AppLockService(secureStore, biometrics),
    );
    await deps.seedIfNeeded();
    return deps;
  }

  /// Real device wiring: SQLCipher DB with a keystore-held key, Supabase if
  /// configured. Nothing here waits on the network.
  static Future<AppDependencies> production() async {
    final secureStore = FlutterSecureStore();
    final key = await DatabaseKeyProvider(secureStore).obtainKey();
    final path = await EncryptedDatabaseOpener.defaultPath();
    final database = await AppDatabase.open(EncryptedDatabaseOpener.withPassword(key), path);

    AuthService auth = LocalAuthService();
    RemoteDataSource? remote;
    if (AppConfig.hasCloud) {
      try {
        // Session restore is local; the timeout guards against a slow
        // platform channel so startup can never hang on the cloud.
        await Supabase.initialize(url: AppConfig.supabaseUrl, anonKey: AppConfig.supabaseAnonKey)
            .timeout(const Duration(seconds: 4));
        final client = Supabase.instance.client;
        auth = SupabaseAuthService(client);
        remote = SupabaseRemoteDataSource(client);
      } catch (e) {
        debugPrint('Cloud unavailable at startup, running local-only: $e');
      }
    }

    final notifications = LocalNotificationService();
    unawaited(notifications.init());

    return create(
      database: database,
      auth: auth,
      remote: remote,
      connectivity: PlusConnectivityService(),
      notifications: notifications,
      rateSource: OpenErApiRateSource(),
      secureStore: secureStore,
      biometrics: LocalAuthBiometricAuthenticator(),
    );
  }

  Future<void> seedIfNeeded() async {
    if (await settings.get(_seededKey) == 'true') return;
    final base = await settings.get(SettingsKeys.baseCurrency) ?? 'USD';
    await settings.set(SettingsKeys.baseCurrency, base, notify: false);
    await categories.seedDefaults();
    await accounts.seedDefaults(base);
    await settings.set(_seededKey, 'true', notify: false);
  }

  /// Wipes every local row (used by logout and "Reset local data") and seeds
  /// a fresh default dataset. Device-level preferences such as theme survive.
  Future<void> resetLocalData({bool keepPreferences = true}) async {
    final prefs = keepPreferences ? await settings.load() : null;
    await database.clearAll();
    if (prefs != null) {
      await settings.set(SettingsKeys.themeMode, prefs.themeMode.name, notify: false);
      await settings.set(SettingsKeys.baseCurrency, prefs.baseCurrency, notify: false);
      await settings.set(SettingsKeys.appLockEnabled, '${prefs.appLockEnabled}', notify: false);
      await settings.set(SettingsKeys.biometricEnabled, '${prefs.biometricEnabled}', notify: false);
      await settings.set(SettingsKeys.notificationsEnabled, '${prefs.notificationsEnabled}', notify: false);
      await settings.set(SettingsKeys.guestMode, '${prefs.guestMode}', notify: false);
    }
    await seedIfNeeded();
    bus.emit({...Tables.synced, Tables.settings});
  }

  Future<void> dispose() async {
    await sync.dispose();
    await currency.dispose();
    connectivity.dispose();
    await bus.dispose();
    await database.close();
  }
}
