import 'dart:async';

import 'package:supabase_flutter/supabase_flutter.dart' as sb;

class AuthUser {
  const AuthUser({required this.id, this.email});
  final String id;
  final String? email;
}

class AuthFailure implements Exception {
  AuthFailure(this.message);
  final String message;

  @override
  String toString() => message;
}

abstract class AuthService {
  /// False when no cloud backend is configured (local-only build).
  bool get isCloudAvailable;
  AuthUser? get currentUser;
  Stream<AuthUser?> get userChanges;

  Future<AuthUser> signIn(String email, String password);

  /// Returns the user, or null when email confirmation is required first.
  Future<AuthUser?> signUp(String email, String password);
  Future<void> signOut();
}

class SupabaseAuthService implements AuthService {
  SupabaseAuthService(this._client);

  final sb.SupabaseClient _client;

  @override
  bool get isCloudAvailable => true;

  static AuthUser? _map(sb.User? u) => u == null ? null : AuthUser(id: u.id, email: u.email);

  @override
  AuthUser? get currentUser => _map(_client.auth.currentUser);

  @override
  Stream<AuthUser?> get userChanges =>
      _client.auth.onAuthStateChange.map((s) => _map(s.session?.user));

  @override
  Future<AuthUser> signIn(String email, String password) async {
    try {
      final res = await _client.auth.signInWithPassword(email: email.trim(), password: password);
      final user = _map(res.user);
      if (user == null) throw AuthFailure('Sign in failed. Please try again.');
      return user;
    } on sb.AuthException catch (e) {
      throw AuthFailure(e.message);
    } catch (e) {
      if (e is AuthFailure) rethrow;
      throw AuthFailure('Could not reach the server. Check your connection.');
    }
  }

  @override
  Future<AuthUser?> signUp(String email, String password) async {
    try {
      final res = await _client.auth.signUp(email: email.trim(), password: password);
      return res.session == null ? null : _map(res.user);
    } on sb.AuthException catch (e) {
      throw AuthFailure(e.message);
    } catch (e) {
      throw AuthFailure('Could not reach the server. Check your connection.');
    }
  }

  @override
  Future<void> signOut() async {
    try {
      await _client.auth.signOut();
    } catch (_) {
      // Offline sign-out still clears the local session.
    }
  }
}

/// Used when the app is built without Supabase credentials, and in tests.
class LocalAuthService implements AuthService {
  LocalAuthService({this.cloud = false, AuthUser? initialUser}) : _user = initialUser;

  final bool cloud;
  AuthUser? _user;
  final StreamController<AuthUser?> _controller = StreamController<AuthUser?>.broadcast();
  final Map<String, String> _accounts = {};

  @override
  bool get isCloudAvailable => cloud;

  @override
  AuthUser? get currentUser => _user;

  @override
  Stream<AuthUser?> get userChanges => _controller.stream;

  @override
  Future<AuthUser> signIn(String email, String password) async {
    final stored = _accounts[email];
    if (stored != null && stored != password) throw AuthFailure('Invalid login credentials');
    _accounts[email] = password;
    _user = AuthUser(id: 'user-${email.hashCode.abs()}', email: email);
    _controller.add(_user);
    return _user!;
  }

  @override
  Future<AuthUser?> signUp(String email, String password) => signIn(email, password);

  @override
  Future<void> signOut() async {
    _user = null;
    _controller.add(null);
  }
}
