import 'dart:async';

import 'package:flutter/foundation.dart';

import '../core/services/data_change_bus.dart';

enum LoadStatus { initial, loading, ready, error }

/// Base for providers that read from the local DB and must refresh when the
/// tables they depend on change (local edits or background sync merges).
/// Multiple changes in the same event-loop turn coalesce into one reload.
abstract class BusAwareNotifier extends ChangeNotifier {
  BusAwareNotifier(DataChangeBus bus, this.watchedTables) {
    _sub = bus.stream.listen((change) {
      if (change.touchesAny(watchedTables)) scheduleReload();
    });
  }

  final Set<String> watchedTables;
  late final StreamSubscription<DataChange> _sub;
  bool _scheduled = false;
  bool _disposed = false;

  LoadStatus status = LoadStatus.initial;
  String? error;

  bool get isLoading => status == LoadStatus.initial || status == LoadStatus.loading;
  bool get isDisposed => _disposed;

  @protected
  Future<void> reload();

  /// Loads data, tracking status and surfacing errors instead of throwing.
  Future<void> load() async {
    if (status != LoadStatus.ready) {
      status = LoadStatus.loading;
      notifySafely();
    }
    try {
      await reload();
      status = LoadStatus.ready;
      error = null;
    } catch (e, st) {
      debugPrint('$runtimeType load failed: $e\n$st');
      status = LoadStatus.error;
      error = 'Something went wrong while loading data.';
    }
    notifySafely();
  }

  void scheduleReload() {
    if (_scheduled || _disposed) return;
    _scheduled = true;
    scheduleMicrotask(() {
      _scheduled = false;
      if (!_disposed) unawaited(load());
    });
  }

  void notifySafely() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_sub.cancel());
    super.dispose();
  }
}
