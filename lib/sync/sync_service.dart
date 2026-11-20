import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:sqflite_common/sqlite_api.dart';

import '../core/services/connectivity_service.dart';
import '../core/services/data_change_bus.dart';
import '../core/utils/clock.dart';
import '../data/local/sync_tables.dart';
import '../data/local/syncable_dao.dart';
import '../data/models/app_settings.dart';
import '../data/models/enums.dart';
import '../data/remote/auth_service.dart';
import '../data/remote/remote_data_source.dart';
import '../data/repositories/settings_repository.dart';
import 'conflict_resolver.dart';
import 'sync_queue.dart';

enum SyncPhase { disabled, idle, syncing, failed }

@immutable
class SyncState {
  const SyncState({
    this.phase = SyncPhase.idle,
    this.online = true,
    this.pendingCount = 0,
    this.lastSyncAt,
    this.error,
  });

  final SyncPhase phase;
  final bool online;
  final int pendingCount;
  final DateTime? lastSyncAt;
  final String? error;

  SyncState copyWith({
    SyncPhase? phase,
    bool? online,
    int? pendingCount,
    DateTime? lastSyncAt,
    String? error,
    bool clearError = false,
  }) =>
      SyncState(
        phase: phase ?? this.phase,
        online: online ?? this.online,
        pendingCount: pendingCount ?? this.pendingCount,
        lastSyncAt: lastSyncAt ?? this.lastSyncAt,
        error: clearError ? null : (error ?? this.error),
      );

  /// Human friendly status line, e.g. "Offline • 3 changes will sync later".
  String get label {
    if (phase == SyncPhase.disabled) return 'Local only';
    if (!online) {
      return pendingCount == 0
          ? 'Offline'
          : 'Offline • $pendingCount ${pendingCount == 1 ? 'change' : 'changes'} will sync later';
    }
    switch (phase) {
      case SyncPhase.syncing:
        return '↻ Syncing...';
      case SyncPhase.failed:
        return '⚠ Sync failed';
      case SyncPhase.idle:
      case SyncPhase.disabled:
        return pendingCount > 0
            ? '☁ $pendingCount ${pendingCount == 1 ? 'change' : 'changes'} waiting'
            : '✓ Synced';
    }
  }
}

class SyncReport {
  int pulled = 0;
  int pushed = 0;
  int conflicts = 0;
  int merged = 0;

  @override
  String toString() => 'SyncReport(pulled: $pulled, pushed: $pushed, merged: $merged, conflicts: $conflicts)';
}

/// Bidirectional sync engine.
///
/// Local → cloud: rows with a pending sync_status are upserted in batches and
/// marked synced only if they were not edited mid-flight.
/// Cloud → local: rows changed on the server since the stored per-table
/// cursor are fetched page by page and merged (see [ConflictResolver]).
///
/// Order per run: pull (merge remote edits into pending local rows) then
/// push (upload the merged result). Sync never blocks the UI: it runs after
/// the first frame, in the background, and failures only change [state].
class SyncService {
  SyncService({
    required this.db,
    required this.remote,
    required this.auth,
    required this.connectivity,
    required this.settings,
    required this.bus,
    required this.clock,
    this.debounce = const Duration(seconds: 2),
    this.periodic = const Duration(minutes: 5),
    this.pageSize = 500,
    this.pushBatchSize = 200,
  }) : queue = SyncQueue(db, clock) {
    _state = SyncState(phase: isEnabled ? SyncPhase.idle : SyncPhase.disabled);
  }

  final Database db;
  final RemoteDataSource? remote;
  final AuthService auth;
  final ConnectivityService connectivity;
  final SettingsRepository settings;
  final DataChangeBus bus;
  final Clock clock;
  final Duration debounce;
  final Duration periodic;
  final int pageSize;
  final int pushBatchSize;
  final SyncQueue queue;

  final StreamController<SyncState> _states = StreamController<SyncState>.broadcast();
  SyncState _state = const SyncState();
  SyncState get state => _state;
  Stream<SyncState> get states => _states.stream;

  StreamSubscription<bool>? _connSub;
  StreamSubscription<DataChange>? _busSub;
  Timer? _debounceTimer;
  Timer? _periodicTimer;
  Timer? _retryTimer;
  int _failures = 0;
  Future<SyncReport?>? _running;
  bool _rerunRequested = false;
  bool _started = false;

  bool get isEnabled => remote != null && auth.isCloudAvailable && auth.currentUser != null;

  void _emit(SyncState s) {
    _state = s;
    if (!_states.isClosed) _states.add(s);
  }

  /// Wires triggers and performs an initial sync. Call after first frame.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    final online = await connectivity.isOnline();
    final last = await settings.getInt(SettingsKeys.lastSyncAt);
    _emit(_state.copyWith(
      online: online,
      phase: isEnabled ? SyncPhase.idle : SyncPhase.disabled,
      pendingCount: await queue.pendingCount(),
      lastSyncAt: last == null ? null : DateTime.fromMillisecondsSinceEpoch(last),
    ));

    _connSub = connectivity.onStatusChange.listen((isOnline) {
      _emit(_state.copyWith(online: isOnline));
      if (isOnline) unawaited(syncNow());
    });
    _busSub = bus.stream.listen(_onLocalChange);
    _periodicTimer = Timer.periodic(periodic, (_) => unawaited(syncNow()));
    unawaited(syncNow());
  }

  void _onLocalChange(DataChange change) {
    if (change.origin != ChangeOrigin.local) return;
    if (!change.touchesAny(Tables.synced)) return;
    unawaited(refreshPendingCount());
    if (!isEnabled) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () => unawaited(syncNow()));
  }

  Future<void> refreshPendingCount() async {
    try {
      _emit(_state.copyWith(pendingCount: await queue.pendingCount()));
    } catch (_) {
      // Database closed during shutdown.
    }
  }

  /// Re-evaluates enablement after login/logout.
  Future<void> onAuthChanged() async {
    final user = auth.currentUser;
    if (user != null) await queue.claimForUser(user.id);
    _emit(_state.copyWith(
      phase: isEnabled ? SyncPhase.idle : SyncPhase.disabled,
      pendingCount: await queue.pendingCount(),
      clearError: true,
    ));
    if (isEnabled) unawaited(syncNow());
  }

  /// Runs a sync if possible. Concurrent calls coalesce into one extra run.
  Future<SyncReport?> syncNow() {
    if (_running != null) {
      _rerunRequested = true;
      return _running!;
    }
    final future = _run().whenComplete(() {
      _running = null;
      if (_rerunRequested) {
        _rerunRequested = false;
        unawaited(syncNow());
      }
    });
    _running = future;
    return future;
  }

  Future<SyncReport?> _run() async {
    final source = remote;
    final user = auth.currentUser;
    if (source == null || !auth.isCloudAvailable || user == null) {
      _emit(_state.copyWith(phase: SyncPhase.disabled));
      return null;
    }
    final online = await connectivity.isOnline();
    if (!online) {
      _emit(_state.copyWith(online: false, pendingCount: await queue.pendingCount()));
      return null;
    }

    _emit(_state.copyWith(phase: SyncPhase.syncing, online: true, clearError: true));
    final report = SyncReport();
    try {
      final changedTables = <String>{};
      for (final spec in SyncTables.all) {
        final pulled = await _pull(spec, source, user.id, report);
        if (pulled > 0) changedTables.add(spec.table);
      }
      for (final spec in SyncTables.all) {
        await _push(spec, source, user.id, report);
      }
      final now = clock.now();
      await settings.setInt(SettingsKeys.lastSyncAt, now.millisecondsSinceEpoch);
      _failures = 0;
      _retryTimer?.cancel();
      _emit(_state.copyWith(
        phase: SyncPhase.idle,
        lastSyncAt: now,
        pendingCount: await queue.pendingCount(),
      ));
      if (changedTables.isNotEmpty) bus.emit(changedTables, origin: ChangeOrigin.sync);
      return report;
    } catch (e, st) {
      debugPrint('Sync failed: $e\n$st');
      _failures++;
      final message = e is RemoteException && e.isAuthError
          ? 'Session expired. Please sign in again.'
          : 'Sync failed. Will retry automatically.';
      _emit(_state.copyWith(
        phase: SyncPhase.failed,
        error: message,
        pendingCount: await queue.pendingCount(),
      ));
      _scheduleRetry();
      return report;
    }
  }

  void _scheduleRetry() {
    if (!_started) return;
    _retryTimer?.cancel();
    final exponent = _failures < 1 ? 0 : (_failures > 6 ? 5 : _failures - 1);
    final seconds = 15 * (1 << exponent);
    _retryTimer = Timer(Duration(seconds: seconds), () => unawaited(syncNow()));
  }

  // ---------------------------------------------------------------------------
  // Cloud → Local
  // ---------------------------------------------------------------------------

  Future<int> _pull(SyncTableSpec spec, RemoteDataSource source, String userId, SyncReport report) async {
    final cursorKey = SettingsKeys.syncCursor(spec.table);
    final cursor = await settings.getInt(cursorKey) ?? 0;
    var maxSeen = cursor;
    var offset = 0;
    var applied = 0;
    while (true) {
      final page = await source.fetchChanges(
        spec.table,
        userId: userId,
        sinceMs: cursor,
        offset: offset,
        limit: pageSize,
      );
      if (page.rows.isNotEmpty) {
        applied += await applyRemoteRows(spec, page.rows, report);
      }
      final pageMax = page.maxServerUpdatedAtMs;
      if (pageMax != null && pageMax > maxSeen) maxSeen = pageMax;
      if (page.rows.length < pageSize) break;
      offset += pageSize;
    }
    if (maxSeen != cursor) await settings.setInt(cursorKey, maxSeen);
    return applied;
  }

  /// Applies cloud rows to the local database in one transaction.
  /// Exposed for tests of the merge pipeline.
  Future<int> applyRemoteRows(SyncTableSpec spec, List<Map<String, Object?>> rows, SyncReport report) async {
    final dao = queue.dao(spec.table);
    var applied = 0;
    await db.transaction((txn) async {
      for (final raw in rows) {
        final remoteContent = spec.content(raw);
        final id = remoteContent['id'];
        if (id is! String) continue;
        final local = await dao.find(id, exec: txn);

        if (local != null &&
            SyncStatus.parse(local['sync_status']) == SyncStatus.synced &&
            _sameContent(spec, spec.content(local), remoteContent)) {
          continue; // Echo of our own upload or an unchanged row.
        }

        if (local == null || SyncStatus.parse(local['sync_status']) == SyncStatus.synced) {
          await dao.writeFromSync(
            content: remoteContent,
            base: remoteContent,
            status: SyncStatus.synced,
            exists: local != null,
            exec: txn,
          );
          applied++;
          report.pulled++;
          continue;
        }

        // Local row has unsynced edits: three-way merge.
        final outcome = ConflictResolver.merge(
          base: SyncableDao.decodeBase(local['sync_base']),
          local: spec.content(local),
          remote: remoteContent,
          fields: spec.mergeFields,
        );
        report.merged++;
        report.conflicts += outcome.conflictedFields.length;
        if (outcome.needsUpload) {
          final deleted = outcome.merged['deleted_at'] != null;
          await dao.writeFromSync(
            content: outcome.merged,
            base: remoteContent,
            status: deleted ? SyncStatus.pendingDelete : SyncStatus.pendingUpdate,
            exists: true,
            exec: txn,
          );
        } else {
          await dao.writeFromSync(
            content: remoteContent,
            base: remoteContent,
            status: SyncStatus.synced,
            exists: true,
            exec: txn,
          );
        }
        applied++;
        report.pulled++;
      }
    });
    return applied;
  }

  static bool _sameContent(SyncTableSpec spec, Map<String, Object?> a, Map<String, Object?> b) {
    for (final c in spec.columns) {
      if (c == 'user_id') continue;
      if (a[c] != b[c]) return false;
    }
    return true;
  }

  // ---------------------------------------------------------------------------
  // Local → Cloud
  // ---------------------------------------------------------------------------

  Future<void> _push(SyncTableSpec spec, RemoteDataSource source, String userId, SyncReport report) async {
    final dao = queue.dao(spec.table);
    final attempted = <String>{};
    for (var guard = 0; guard < 1000; guard++) {
      final rows = (await dao.pending(limit: pushBatchSize))
          .where((r) => !attempted.contains(r['id']))
          .toList();
      if (rows.isEmpty) return;
      final payload = [
        for (final r in rows) {...spec.content(r), 'user_id': userId},
      ];
      try {
        await source.upsert(spec.table, payload, userId: userId);
      } catch (e) {
        await dao.markFailed(rows.map((r) => r['id'] as String));
        rethrow;
      }
      for (var i = 0; i < rows.length; i++) {
        final id = rows[i]['id'] as String;
        attempted.add(id);
        final marked = await dao.markSynced(id, rows[i]['updated_at'] as int, payload[i]);
        if (marked) report.pushed++;
      }
    }
  }

  Future<void> dispose() async {
    _started = false;
    _debounceTimer?.cancel();
    _periodicTimer?.cancel();
    _retryTimer?.cancel();
    await _connSub?.cancel();
    await _busSub?.cancel();
    await _states.close();
  }
}
