import 'dart:async';

import 'package:flutter/foundation.dart';

import '../sync/sync_service.dart';

class SyncProvider extends ChangeNotifier {
  SyncProvider(this._service) : _state = _service.state {
    _sub = _service.states.listen((s) {
      _state = s;
      notifyListeners();
    });
  }

  final SyncService _service;
  late final StreamSubscription<SyncState> _sub;
  SyncState _state;

  SyncState get state => _state;
  bool get isEnabled => _service.isEnabled;

  Future<void> syncNow() => _service.syncNow();

  @override
  void dispose() {
    unawaited(_sub.cancel());
    super.dispose();
  }
}
