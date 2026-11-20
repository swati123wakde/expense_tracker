import 'package:flutter/material.dart';

import '../app/dependencies.dart';
import '../core/services/data_change_bus.dart';
import '../data/models/app_settings.dart';
import 'bus_aware_notifier.dart';

class SettingsProvider extends BusAwareNotifier {
  SettingsProvider(this._deps, {AppSettings? initial})
      : settings = initial ?? const AppSettings(),
        super(_deps.bus, {Tables.settings}) {
    if (initial != null) status = LoadStatus.ready;
  }

  final AppDependencies _deps;
  AppSettings settings;

  ThemeMode get themeMode => settings.themeMode;
  String get baseCurrency => settings.baseCurrency;

  @override
  Future<void> reload() async {
    settings = await _deps.settings.load();
  }

  Future<void> setThemeMode(ThemeMode mode) async {
    settings = settings.copyWith(themeMode: mode);
    notifySafely(); // instant UI response; persisted below
    await _deps.settings.saveThemeMode(mode);
  }

  Future<void> setBaseCurrency(String currency) async {
    settings = settings.copyWith(baseCurrency: currency);
    notifySafely();
    await _deps.settings.set(SettingsKeys.baseCurrency, currency);
  }

  Future<void> setNotificationsEnabled(bool enabled) async {
    settings = settings.copyWith(notificationsEnabled: enabled);
    notifySafely();
    await _deps.settings.set(SettingsKeys.notificationsEnabled, '$enabled');
    if (enabled) await _deps.notifications.requestPermission();
  }

  Future<void> setGuestMode(bool guest) async {
    settings = settings.copyWith(guestMode: guest);
    notifySafely();
    await _deps.settings.set(SettingsKeys.guestMode, '$guest');
  }
}
