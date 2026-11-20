import 'package:flutter/material.dart';

/// Device-local preferences. Stored in the encrypted settings table.
class AppSettings {
  const AppSettings({
    this.themeMode = ThemeMode.system,
    this.baseCurrency = 'USD',
    this.notificationsEnabled = true,
    this.appLockEnabled = false,
    this.biometricEnabled = false,
    this.guestMode = false,
    this.lastSyncAt,
  });

  final ThemeMode themeMode;
  final String baseCurrency;
  final bool notificationsEnabled;
  final bool appLockEnabled;
  final bool biometricEnabled;
  final bool guestMode;
  final DateTime? lastSyncAt;

  AppSettings copyWith({
    ThemeMode? themeMode,
    String? baseCurrency,
    bool? notificationsEnabled,
    bool? appLockEnabled,
    bool? biometricEnabled,
    bool? guestMode,
    DateTime? lastSyncAt,
  }) =>
      AppSettings(
        themeMode: themeMode ?? this.themeMode,
        baseCurrency: baseCurrency ?? this.baseCurrency,
        notificationsEnabled: notificationsEnabled ?? this.notificationsEnabled,
        appLockEnabled: appLockEnabled ?? this.appLockEnabled,
        biometricEnabled: biometricEnabled ?? this.biometricEnabled,
        guestMode: guestMode ?? this.guestMode,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
      );
}

class SettingsKeys {
  SettingsKeys._();

  static const themeMode = 'theme_mode';
  static const baseCurrency = 'base_currency';
  static const notificationsEnabled = 'notifications_enabled';
  static const appLockEnabled = 'app_lock_enabled';
  static const biometricEnabled = 'biometric_enabled';
  static const guestMode = 'guest_mode';
  static const lastSyncAt = 'last_sync_at';
  static const ratesFetchedAt = 'rates_fetched_at';
  static String syncCursor(String table) => 'sync_cursor_$table';
  static String budgetAlert(String budgetId, String monthKey) =>
      'alert_${budgetId}_$monthKey';
  static String recurringReminder(String ruleId, int index) =>
      'reminder_${ruleId}_$index';
}
