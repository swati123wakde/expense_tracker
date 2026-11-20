import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';

/// Abstraction so sync can be tested with simulated network changes.
abstract class ConnectivityService {
  Future<bool> isOnline();
  Stream<bool> get onStatusChange;
  void dispose() {}
}

class PlusConnectivityService implements ConnectivityService {
  PlusConnectivityService([Connectivity? connectivity])
      : _connectivity = connectivity ?? Connectivity();

  final Connectivity _connectivity;

  static bool _online(List<ConnectivityResult> results) =>
      results.any((r) => r != ConnectivityResult.none);

  @override
  Future<bool> isOnline() async {
    try {
      return _online(await _connectivity.checkConnectivity());
    } catch (_) {
      return false;
    }
  }

  @override
  Stream<bool> get onStatusChange =>
      _connectivity.onConnectivityChanged.map(_online).distinct();

  @override
  void dispose() {}
}

/// Manually controlled connectivity for tests and demos.
class FakeConnectivityService implements ConnectivityService {
  FakeConnectivityService({bool online = true}) : _online = online;

  bool _online;
  final StreamController<bool> _controller = StreamController<bool>.broadcast();

  bool get online => _online;

  set online(bool value) {
    if (_online == value) return;
    _online = value;
    if (!_controller.isClosed) _controller.add(value);
  }

  @override
  Future<bool> isOnline() async => _online;

  @override
  Stream<bool> get onStatusChange => _controller.stream;

  /// Intentionally keeps the controller open: tests reuse one simulated
  /// network across simulated app restarts.
  @override
  void dispose() {}
}
