import 'package:flutter/foundation.dart';

import '../app/dependencies.dart';
import '../core/services/app_lock_service.dart';
import '../data/models/app_settings.dart';

/// App lock state machine. When enabled the app starts locked and re-locks
/// after [grace] in the background; nothing financial renders while locked.
class AppLockProvider extends ChangeNotifier {
  AppLockProvider(this._deps, {required bool enabled, required bool biometricEnabled, this.grace = const Duration(seconds: 30)})
      : _enabled = enabled,
        _biometricEnabled = biometricEnabled,
        _locked = enabled;

  final AppDependencies _deps;
  final Duration grace;

  bool _enabled;
  bool _biometricEnabled;
  bool _locked;
  bool biometricAvailable = false;
  bool obscured = false;
  int _failedAttempts = 0;
  DateTime? _lockedOutUntil;
  DateTime? _backgroundAt;

  AppLockService get _service => _deps.lock;

  bool get enabled => _enabled;
  bool get biometricEnabled => _biometricEnabled && biometricAvailable;
  bool get locked => _enabled && _locked;
  int get failedAttempts => _failedAttempts;

  Duration? get lockoutRemaining {
    final until = _lockedOutUntil;
    if (until == null) return null;
    final left = until.difference(_deps.clock.now());
    return left.isNegative ? null : left;
  }

  Future<void> init() async {
    biometricAvailable = await _service.biometrics.isAvailable();
    if (_enabled && !await _service.hasPin()) {
      // Inconsistent state (e.g. keystore cleared): don't lock the user out.
      _enabled = false;
      _locked = false;
      await _deps.settings.set(SettingsKeys.appLockEnabled, 'false', notify: false);
    }
    notifyListeners();
  }

  // Lifecycle -----------------------------------------------------------------

  void onHidden() {
    _backgroundAt ??= _deps.clock.now();
    if (_enabled && !obscured) {
      obscured = true;
      notifyListeners();
    }
  }

  void onResumed() {
    final since = _backgroundAt;
    _backgroundAt = null;
    var changed = obscured;
    obscured = false;
    if (_enabled && since != null && _deps.clock.now().difference(since) >= grace) {
      _locked = true;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  // Unlock --------------------------------------------------------------------

  Future<bool> unlockWithPin(String pin) async {
    if (lockoutRemaining != null) return false;
    final ok = await _service.verifyPin(pin);
    if (ok) {
      _failedAttempts = 0;
      _locked = false;
    } else {
      _failedAttempts++;
      if (_failedAttempts >= AppLockService.maxAttempts) {
        _lockedOutUntil = _deps.clock.now().add(AppLockService.lockoutDuration);
        _failedAttempts = 0;
      }
    }
    notifyListeners();
    return ok;
  }

  Future<bool> unlockWithBiometrics() async {
    if (!biometricEnabled) return false;
    final ok = await _service.biometrics.authenticate('Unlock Expense Manager');
    if (ok) {
      _locked = false;
      _failedAttempts = 0;
      notifyListeners();
    }
    return ok;
  }

  // Configuration -------------------------------------------------------------

  Future<void> enable(String pin) async {
    await _service.setPin(pin);
    _enabled = true;
    _locked = false;
    await _deps.settings.set(SettingsKeys.appLockEnabled, 'true');
    notifyListeners();
  }

  Future<bool> disable(String pin) async {
    if (!await _service.verifyPin(pin)) return false;
    await _service.clearPin();
    _enabled = false;
    _biometricEnabled = false;
    await _deps.settings.set(SettingsKeys.appLockEnabled, 'false');
    await _deps.settings.set(SettingsKeys.biometricEnabled, 'false');
    notifyListeners();
    return true;
  }

  Future<bool> setBiometricEnabled(bool value) async {
    if (value) {
      // Confirm the user can actually pass biometrics before relying on it.
      final ok = await _service.biometrics.authenticate('Confirm to enable biometric unlock');
      if (!ok) return false;
    }
    _biometricEnabled = value;
    await _deps.settings.set(SettingsKeys.biometricEnabled, '$value');
    notifyListeners();
    return true;
  }
}
