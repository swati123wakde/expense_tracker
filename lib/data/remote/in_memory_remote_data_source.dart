import 'remote_data_source.dart';

/// A faithful in-memory stand-in for the cloud used by tests and the offline
/// demo: per-user isolation, server-assigned modification times, upserts
/// keyed on (user_id, id), and a switch to simulate outages.
class InMemoryRemoteDataSource implements RemoteDataSource {
  InMemoryRemoteDataSource({int Function()? serverClock})
      : _serverClock = serverClock ?? (() => DateTime.now().millisecondsSinceEpoch);

  final int Function() _serverClock;

  /// table -> "userId|id" -> row (including user_id and server_updated_at)
  final Map<String, Map<String, Map<String, Object?>>> _tables = {};

  /// Fail every request (simulates the server being unreachable).
  bool failRequests = false;

  /// Fail only uploads (e.g. a rejected write) while reads still work.
  bool failUpserts = false;
  int upsertCalls = 0;
  int _lastServerMs = 0;

  int _tick() {
    final now = _serverClock();
    _lastServerMs = now > _lastServerMs ? now : _lastServerMs + 1;
    return _lastServerMs;
  }

  List<Map<String, Object?>> rowsFor(String table, String userId) => [
        for (final r in (_tables[table] ?? const <String, Map<String, Object?>>{}).values)
          if (r['user_id'] == userId) Map<String, Object?>.from(r)..remove('server_updated_at'),
      ];

  Map<String, Object?>? row(String table, String userId, String id) {
    final r = _tables[table]?['$userId|$id'];
    return r == null ? null : (Map<String, Object?>.from(r)..remove('server_updated_at'));
  }

  /// Simulates another device writing directly to the cloud.
  void serverWrite(String table, String userId, Map<String, Object?> row) {
    _tables.putIfAbsent(table, () => {})['$userId|${row['id']}'] = {
      ...row,
      'user_id': userId,
      'server_updated_at': _tick(),
    };
  }

  @override
  Future<RemotePage> fetchChanges(
    String table, {
    required String userId,
    required int sinceMs,
    required int offset,
    required int limit,
  }) async {
    if (failRequests) throw RemoteException('Simulated network failure');
    final matching = (_tables[table]?.values ?? const <Map<String, Object?>>[])
        .where((r) => r['user_id'] == userId && (r['server_updated_at'] as int) > sinceMs)
        .toList()
      ..sort((a, b) {
        final c = (a['server_updated_at'] as int).compareTo(b['server_updated_at'] as int);
        return c != 0 ? c : (a['id'] as String).compareTo(b['id'] as String);
      });
    final page = matching.skip(offset).take(limit).toList();
    int? maxServer;
    final rows = <Map<String, Object?>>[];
    for (final r in page) {
      final copy = Map<String, Object?>.from(r);
      final s = copy.remove('server_updated_at') as int;
      if (maxServer == null || s > maxServer) maxServer = s;
      rows.add(copy);
    }
    return RemotePage(rows, maxServer);
  }

  @override
  Future<void> upsert(String table, List<Map<String, Object?>> rows, {required String userId}) async {
    if (failRequests || failUpserts) throw RemoteException('Simulated upload failure');
    upsertCalls++;
    for (final r in rows) {
      serverWrite(table, userId, r);
    }
  }
}
