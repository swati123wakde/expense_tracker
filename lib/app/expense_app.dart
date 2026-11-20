import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/theme/app_theme.dart';
import '../data/models/app_settings.dart';
import '../features/auth/auth_screen.dart';
import '../features/lock/lock_screen.dart';
import '../features/shell/home_shell.dart';
import '../providers/accounts_provider.dart';
import '../providers/analytics_provider.dart';
import '../providers/app_lock_provider.dart';
import '../providers/auth_provider.dart';
import '../providers/budgets_provider.dart';
import '../providers/categories_provider.dart';
import '../providers/dashboard_provider.dart';
import '../providers/goals_provider.dart';
import '../providers/recurring_provider.dart';
import '../providers/settings_provider.dart';
import '../providers/sync_provider.dart';
import '../providers/transactions_provider.dart';
import 'dependencies.dart';

class ExpenseApp extends StatelessWidget {
  const ExpenseApp({
    super.key,
    required this.deps,
    required this.initialSettings,
    this.startBackgroundServices = true,
  });

  final AppDependencies deps;
  final AppSettings initialSettings;

  /// Tests disable sync timers / rate fetching to keep runs deterministic.
  final bool startBackgroundServices;

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        Provider<AppDependencies>.value(value: deps),
        ChangeNotifierProvider(create: (_) => SettingsProvider(deps, initial: initialSettings)),
        ChangeNotifierProvider(create: (_) => AuthProvider(deps, guestMode: initialSettings.guestMode)),
        ChangeNotifierProvider(create: (_) => SyncProvider(deps.sync)),
        ChangeNotifierProvider(
          create: (_) => AppLockProvider(
            deps,
            enabled: initialSettings.appLockEnabled,
            biometricEnabled: initialSettings.biometricEnabled,
          )..init(),
        ),
        // Data providers are lazy: they are only created (and only read the
        // database) once an unlocked screen asks for them.
        ChangeNotifierProvider(create: (_) => CategoriesProvider(deps)..load()),
        ChangeNotifierProvider(create: (_) => AccountsProvider(deps)..load()),
        ChangeNotifierProvider(create: (_) => TransactionsProvider(deps)..load()),
        ChangeNotifierProvider(create: (_) => DashboardProvider(deps)..load()),
        ChangeNotifierProvider(create: (_) => AnalyticsProvider(deps)..load()),
        ChangeNotifierProvider(create: (_) => BudgetsProvider(deps)..load()),
        ChangeNotifierProvider(create: (_) => GoalsProvider(deps)..load()),
        ChangeNotifierProvider(create: (_) => RecurringProvider(deps)..load()),
      ],
      child: Selector<SettingsProvider, ThemeMode>(
        selector: (_, s) => s.themeMode,
        builder: (context, mode, _) => MaterialApp(
          title: 'Expense Manager',
          debugShowCheckedModeBanner: false,
          theme: AppTheme.light(),
          darkTheme: AppTheme.dark(),
          themeMode: mode,
          themeAnimationDuration: const Duration(milliseconds: 300),
          home: AppGate(startBackgroundServices: startBackgroundServices),
        ),
      ),
    );
  }
}

/// Decides what to show (lock → auth → app) and owns app-lifecycle hooks.
class AppGate extends StatefulWidget {
  const AppGate({super.key, this.startBackgroundServices = true});

  final bool startBackgroundServices;

  @override
  State<AppGate> createState() => _AppGateState();
}

class _AppGateState extends State<AppGate> {
  late final AppLifecycleListener _lifecycle;
  bool _servicesStarted = false;

  @override
  void initState() {
    super.initState();
    _lifecycle = AppLifecycleListener(
      onInactive: () => context.read<AppLockProvider>().onHidden(),
      onHide: () => context.read<AppLockProvider>().onHidden(),
      onResume: _onResume,
    );
    // Offline-first: the first frame renders from the local DB; background
    // work (sync, recurring, rates) starts only afterwards.
    WidgetsBinding.instance.addPostFrameCallback((_) => _startServices());
  }

  @override
  void dispose() {
    _lifecycle.dispose();
    super.dispose();
  }

  Future<void> _startServices() async {
    if (_servicesStarted || !mounted) return;
    _servicesStarted = true;
    final deps = context.read<AppDependencies>();
    final recurring = context.read<RecurringProvider>();
    await recurring.processDue();
    if (!widget.startBackgroundServices) return;
    unawaited(deps.sync.start());
    unawaited(_refreshRates(deps));
    unawaited(deps.notifications.requestPermission());
  }

  Future<void> _refreshRates(AppDependencies deps) async {
    if (await deps.connectivity.isOnline()) await deps.rates.refreshIfStale();
  }

  void _onResume() {
    if (!mounted) return;
    context.read<AppLockProvider>().onResumed();
    final deps = context.read<AppDependencies>();
    unawaited(context.read<RecurringProvider>().processDue());
    if (widget.startBackgroundServices) {
      unawaited(deps.sync.syncNow());
      unawaited(_refreshRates(deps));
    }
  }

  @override
  Widget build(BuildContext context) {
    final lock = context.watch<AppLockProvider>();
    final auth = context.watch<AuthProvider>();

    final Widget child;
    if (lock.locked) {
      child = const LockScreen(key: ValueKey('lock'));
    } else if (!auth.canEnterApp) {
      child = const AuthScreen(key: ValueKey('auth'));
    } else {
      child = const HomeShell(key: ValueKey('home'));
    }

    return Stack(
      children: [
        AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: child),
        // Hide balances in the app switcher when app lock is on.
        if (lock.obscured)
          Positioned.fill(
            child: ColoredBox(
              color: Theme.of(context).colorScheme.surface,
              child: Center(child: Icon(Icons.lock, size: 48, color: Theme.of(context).colorScheme.primary)),
            ),
          ),
      ],
    );
  }
}
