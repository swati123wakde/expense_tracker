import 'package:flutter/material.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../../core/services/data_change_bus.dart';
import '../models/app_settings.dart';

/// Device-local key/value preferences stored in the encrypted database.
class SettingsRepository {
  SettingsRepository(this._db, this._bus);

  final Database _db;
  final DataChangeBus _bus;

  Future<String?> get(String key) async {
    final rows = await _db.query(Tables.settings, where: 'key = ?', whereArgs: [key], limit: 1);
    return rows.isEmpty ? null : rows.first['value'] as String?;
  }

  Future<void> set(String key, String? value, {bool notify = true}) async {
    await _db.insert(
      Tables.settings,
      {'key': key, 'value': value},
      conflictAlgorithm: ConflictAlgorithm.replace,
    );
    if (notify) _bus.emit({Tables.settings});
  }

  Future<int?> getInt(String key) async => int.tryParse(await get(key) ?? '');

  Future<void> setInt(String key, int value, {bool notify = false}) =>
      set(key, value.toString(), notify: notify);

  Future<bool> getBool(String key, {bool fallback = false}) async {
    final v = await get(key);
    return v == null ? fallback : v == 'true';
  }

  Future<AppSettings> load() async {
    final rows = await _db.query(Tables.settings);
    final map = {for (final r in rows) r['key'] as String: r['value'] as String?};
    bool b(String k, bool fallback) => map[k] == null ? fallback : map[k] == 'true';
    final lastSync = int.tryParse(map[SettingsKeys.lastSyncAt] ?? '');
    return AppSettings(
      themeMode: _parseTheme(map[SettingsKeys.themeMode]),
      baseCurrency: map[SettingsKeys.baseCurrency] ?? 'USD',
      notificationsEnabled: b(SettingsKeys.notificationsEnabled, true),
      appLockEnabled: b(SettingsKeys.appLockEnabled, false),
      biometricEnabled: b(SettingsKeys.biometricEnabled, false),
      guestMode: b(SettingsKeys.guestMode, false),
      lastSyncAt: lastSync == null ? null : DateTime.fromMillisecondsSinceEpoch(lastSync),
    );
  }

  Future<void> saveThemeMode(ThemeMode mode) => set(SettingsKeys.themeMode, mode.name);

  /// Exportable (non-secret, non-device-state) settings for JSON backup.
  Future<Map<String, String?>> exportable() async {
    const keys = [
      SettingsKeys.themeMode,
      SettingsKeys.baseCurrency,
      SettingsKeys.notificationsEnabled,
    ];
    return {for (final k in keys) k: await get(k)};
  }

  static ThemeMode _parseTheme(String? v) => ThemeMode.values.firstWhere(
        (m) => m.name == v,
        orElse: () => ThemeMode.system,
      );
}
