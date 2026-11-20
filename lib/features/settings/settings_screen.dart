import 'dart:convert';
import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../app/dependencies.dart';
import '../../core/constants/defaults.dart';
import '../../core/theme/app_theme.dart';
import '../../data/models/transaction_filter.dart';
import '../../data/repositories/backup_repository.dart';
import '../../providers/app_lock_provider.dart';
import '../../providers/auth_provider.dart';
import '../../providers/settings_provider.dart';
import '../../providers/sync_provider.dart';
import '../accounts/accounts_screen.dart';
import '../budgets/budgets_screen.dart';
import '../categories/categories_screen.dart';
import '../common/common_widgets.dart';
import '../goals/goals_screen.dart';
import '../lock/lock_screen.dart';
import '../recurring/recurring_screen.dart';
import 'export_helper.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final settings = context.watch<SettingsProvider>();
    final s = settings.settings;
    final lock = context.watch<AppLockProvider>();
    final auth = context.watch<AuthProvider>();
    final sync = context.watch<SyncProvider>();
    void push(Widget page) => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 100),
        children: [
          const _Header('Appearance'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<ThemeMode>(
              key: const Key('themeSelector'),
              segments: const [
                ButtonSegment(value: ThemeMode.system, label: Text('System'), icon: Icon(Icons.brightness_auto)),
                ButtonSegment(value: ThemeMode.light, label: Text('Light'), icon: Icon(Icons.light_mode)),
                ButtonSegment(value: ThemeMode.dark, label: Text('Dark'), icon: Icon(Icons.dark_mode)),
              ],
              selected: {s.themeMode},
              onSelectionChanged: (v) => settings.setThemeMode(v.first),
            ),
          ),
          const _Header('Preferences'),
          ListTile(
            leading: const Icon(Icons.currency_exchange),
            title: const Text('Base currency'),
            subtitle: Text('${s.baseCurrency} — totals and analytics are shown in this currency'),
            onTap: () => _pickCurrency(context, settings),
          ),
          ListTile(
            leading: const Icon(Icons.pie_chart_outline),
            title: const Text('Monthly & category budgets'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => push(const BudgetsScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.category_outlined),
            title: const Text('Categories'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => push(const CategoriesScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.account_balance_wallet_outlined),
            title: const Text('Accounts & wallets'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => push(const AccountsScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.repeat),
            title: const Text('Recurring transactions'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => push(const RecurringScreen()),
          ),
          ListTile(
            leading: const Icon(Icons.savings_outlined),
            title: const Text('Savings goals'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => push(const GoalsScreen()),
          ),
          SwitchListTile(
            secondary: const Icon(Icons.notifications_outlined),
            title: const Text('Notifications'),
            subtitle: const Text('Budget alerts and upcoming bill reminders'),
            value: s.notificationsEnabled,
            onChanged: settings.setNotificationsEnabled,
          ),
          const _Header('Security'),
          SwitchListTile(
            secondary: const Icon(Icons.lock_outline),
            title: const Text('App lock'),
            subtitle: const Text('Require a PIN to open the app'),
            value: lock.enabled,
            onChanged: (v) => _toggleLock(context, lock, v),
          ),
          if (lock.enabled && lock.biometricAvailable)
            SwitchListTile(
              secondary: const Icon(Icons.fingerprint),
              title: const Text('Biometric unlock'),
              subtitle: const Text('Fingerprint or face authentication'),
              value: lock.biometricEnabled,
              onChanged: (v) async {
                final ok = await lock.setBiometricEnabled(v);
                if (!ok && context.mounted) showSnack(context, 'Biometric authentication failed', error: true);
              },
            ),
          const _Header('Data'),
          ListTile(
            leading: const Icon(Icons.upload_file),
            title: const Text('Export backup (JSON)'),
            onTap: () => ExportHelper.exportJson(context),
          ),
          ListTile(
            leading: const Icon(Icons.download),
            title: const Text('Import backup (JSON)'),
            subtitle: const Text('Validated before anything is changed'),
            onTap: () => _import(context),
          ),
          ListTile(
            leading: const Icon(Icons.table_chart_outlined),
            title: const Text('Export all transactions (CSV)'),
            subtitle: const Text('Tip: export from Transactions to apply filters'),
            onTap: () => ExportHelper.exportCsv(context, TransactionFilter.none),
          ),
          ListTile(
            leading: const Icon(Icons.speed),
            title: const Text('Generate 10,000 demo transactions'),
            subtitle: const Text('Performance stress test'),
            onTap: () => _seedDemo(context),
          ),
          ListTile(
            leading: Icon(Icons.delete_forever_outlined, color: Theme.of(context).colorScheme.error),
            title: Text('Reset local data', style: TextStyle(color: Theme.of(context).colorScheme.error)),
            subtitle: const Text('Removes all data stored on this device'),
            onTap: () => _reset(context),
          ),
          const _Header('Cloud sync'),
          if (!auth.isCloudAvailable)
            const ListTile(
              leading: Icon(Icons.cloud_off),
              title: Text('Local-only mode'),
              subtitle: Text('This build has no cloud backend configured'),
            )
          else if (auth.user == null)
            ListTile(
              leading: const Icon(Icons.login),
              title: const Text('Sign in to sync'),
              subtitle: const Text('Back up and sync across devices'),
              onTap: auth.leaveGuestMode,
            )
          else ...[
            ListTile(
              leading: const Icon(Icons.person_outline),
              title: Text(auth.user!.email ?? 'Signed in'),
              subtitle: Text(sync.state.label),
            ),
            ListTile(
              leading: const Icon(Icons.sync),
              title: const Text('Sync now'),
              subtitle: Text(
                sync.state.lastSyncAt == null
                    ? 'Never synced'
                    : 'Last sync ${DateFormat('d MMM, h:mm a').format(sync.state.lastSyncAt!)}',
              ),
              onTap: sync.syncNow,
            ),
            ListTile(
              leading: const Icon(Icons.logout),
              title: const Text('Log out'),
              onTap: () => _logout(context, auth),
            ),
          ],
          const SizedBox(height: Spacing.lg),
          Center(
            child: Text(
              'Expense Manager • data encrypted on device',
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _pickCurrency(BuildContext context, SettingsProvider settings) async {
    final picked = await showModalBottomSheet<String>(
      context: context,
      isScrollControlled: true,
      builder: (ctx) => DraggableScrollableSheet(
        expand: false,
        builder: (ctx, controller) => ListView(
          controller: controller,
          children: [
            for (final c in Defaults.currencies)
              ListTile(
                title: Text(c),
                trailing: c == settings.baseCurrency ? const Icon(Icons.check) : null,
                onTap: () => Navigator.pop(ctx, c),
              ),
          ],
        ),
      ),
    );
    if (picked != null) await settings.setBaseCurrency(picked);
  }

  Future<void> _toggleLock(BuildContext context, AppLockProvider lock, bool enable) async {
    if (enable) {
      final pin = await showSetPinDialog(context);
      if (pin == null) return;
      await lock.enable(pin);
      if (context.mounted) showSnack(context, 'App lock enabled');
    } else {
      final pin = await showVerifyPinDialog(context);
      if (pin == null) return;
      final ok = await lock.disable(pin);
      if (context.mounted) showSnack(context, ok ? 'App lock disabled' : 'Incorrect PIN', error: !ok);
    }
  }

  Future<void> _import(BuildContext context) async {
    final deps = context.read<AppDependencies>();
    try {
      final result = await FilePicker.platform.pickFiles(type: FileType.custom, allowedExtensions: ['json'], withData: true);
      if (result == null || result.files.isEmpty) return;
      final file = result.files.single;
      final content = file.bytes != null
          ? utf8.decode(file.bytes!)
          : await File(file.path!).readAsString();
      if (!context.mounted) return;
      final ok = await confirmDialog(
        context,
        title: 'Import backup?',
        message: 'Records in the backup will be added or will replace matching records on this device.',
        confirmLabel: 'Import',
      );
      if (!ok) return;
      final summary = await deps.backup.importJson(content);
      if (context.mounted) showSnack(context, 'Imported ${summary.total} records');
    } on BackupValidationException catch (e) {
      if (!context.mounted) return;
      await showDialog<void>(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Invalid backup'),
          content: SingleChildScrollView(child: Text('Nothing was changed.\n\n${e.errors.take(8).join('\n')}')),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('OK'))],
        ),
      );
    } catch (e) {
      if (context.mounted) showSnack(context, 'Import failed', error: true);
    }
  }

  Future<void> _seedDemo(BuildContext context) async {
    final deps = context.read<AppDependencies>();
    final ok = await confirmDialog(
      context,
      title: 'Generate demo data?',
      message: 'Adds 10,000 random transactions spread over two years. Use "Reset local data" to remove them.',
      confirmLabel: 'Generate',
    );
    if (!ok || !context.mounted) return;
    showSnack(context, 'Generating 10,000 transactions…');
    final sw = Stopwatch()..start();
    await deps.transactions.seedDemoData();
    if (context.mounted) showSnack(context, 'Done in ${sw.elapsedMilliseconds} ms');
  }

  Future<void> _reset(BuildContext context) async {
    final deps = context.read<AppDependencies>();
    final ok = await confirmDialog(
      context,
      title: 'Reset local data?',
      message: 'All transactions, accounts, budgets and goals on this device will be deleted. '
          'Data already synced to the cloud is not affected and will download again.',
      confirmLabel: 'Reset',
      destructive: true,
    );
    if (!ok) return;
    await deps.resetLocalData(); // also clears sync cursors, so cloud data re-downloads
    if (context.mounted) showSnack(context, 'Local data reset');
    await deps.sync.syncNow();
  }

  Future<void> _logout(BuildContext context, AuthProvider auth) async {
    final pending = await auth.pendingChanges();
    if (!context.mounted) return;
    final ok = await confirmDialog(
      context,
      title: 'Log out?',
      message: pending > 0
          ? '$pending changes have not synced yet and will be lost. Connect to the internet and sync first to keep them.'
          : 'Your data stays safe in the cloud and is removed from this device.',
      confirmLabel: 'Log out',
      destructive: pending > 0,
    );
    if (ok) await auth.signOut();
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title);
  final String title;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 4),
        child: Text(
          title.toUpperCase(),
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                letterSpacing: 1.1,
              ),
        ),
      );
}
