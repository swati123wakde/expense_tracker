import 'dart:async';

import 'package:flutter/foundation.dart';

import '../app/dependencies.dart';
import '../data/models/app_settings.dart';
import '../data/remote/auth_service.dart';

class AuthProvider extends ChangeNotifier {
  AuthProvider(this._deps, {required bool guestMode})
      : _user = _deps.auth.currentUser,
        _guest = guestMode {
    _sub = _deps.auth.userChanges.listen(_onUserChanged);
  }

  final AppDependencies _deps;
  late final StreamSubscription<AuthUser?> _sub;
  AuthUser? _user;
  bool _guest;
  bool busy = false;
  String? error;
  String? info;

  AuthUser? get user => _user;
  bool get isCloudAvailable => _deps.auth.isCloudAvailable;
  bool get isGuest => _guest;

  /// The main app is shown once the user signed in, chose guest mode, or
  /// when the build has no cloud backend at all.
  bool get canEnterApp => !isCloudAvailable || _user != null || _guest;

  void _onUserChanged(AuthUser? user) {
    if (user?.id == _user?.id) return;
    _user = user;
    _deps.currentUser.id = user?.id;
    unawaited(_deps.sync.onAuthChanged());
    notifyListeners();
  }

  Future<bool> signIn(String email, String password) => _run(() async {
        final user = await _deps.auth.signIn(email, password);
        await _enterAs(user);
      });

  Future<bool> signUp(String email, String password) => _run(() async {
        final user = await _deps.auth.signUp(email, password);
        if (user == null) {
          info = 'Check your inbox to confirm your email, then sign in.';
          return;
        }
        await _enterAs(user);
      });

  Future<void> _enterAs(AuthUser user) async {
    _user = user;
    _guest = false;
    _deps.currentUser.id = user.id;
    await _deps.settings.set(SettingsKeys.guestMode, 'false', notify: false);
    await _deps.sync.onAuthChanged();
  }

  Future<void> continueAsGuest() async {
    _guest = true;
    await _deps.settings.set(SettingsKeys.guestMode, 'true', notify: false);
    notifyListeners();
  }

  /// Leaves guest mode so the sign-in screen is shown. Local data is kept and
  /// will be attached to the account the user signs in with.
  Future<void> leaveGuestMode() async {
    _guest = false;
    await _deps.settings.set(SettingsKeys.guestMode, 'false', notify: false);
    notifyListeners();
  }

  /// Signs out and removes this user's data from the device so the next
  /// account can never see it. Unsynced changes are lost, so the UI warns
  /// first using [pendingChanges].
  Future<void> signOut() async {
    busy = true;
    notifyListeners();
    try {
      await _deps.auth.signOut();
      _user = null;
      _guest = false;
      _deps.currentUser.id = null;
      await _deps.resetLocalData();
      await _deps.settings.set(SettingsKeys.guestMode, 'false', notify: false);
      await _deps.sync.onAuthChanged();
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  Future<int> pendingChanges() => _deps.sync.queue.pendingCount();

  Future<bool> _run(Future<void> Function() action) async {
    busy = true;
    error = null;
    info = null;
    notifyListeners();
    try {
      await action();
      return error == null;
    } on AuthFailure catch (e) {
      error = e.message;
      return false;
    } catch (e) {
      error = 'Something went wrong. Please try again.';
      return false;
    } finally {
      busy = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    unawaited(_sub.cancel());
    super.dispose();
  }
}
