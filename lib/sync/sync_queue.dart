import 'package:sqflite_common/sqlite_api.dart';

import '../core/utils/clock.dart';
import '../data/local/sync_tables.dart';
import '../data/local/syncable_dao.dart';

/// The outbound queue is implicit: every row whose sync_status is not
/// `synced` is pending. Deriving the queue from the rows themselves means it
/// can never drift out of step with the data and survives restarts for free.
class SyncQueue {
  SyncQueue(Database db, Clock clock)
      : _daos = {for (final s in SyncTables.all) s.table: SyncableDao(db, s, clock)};

  final Map<String, SyncableDao> _daos;

  SyncableDao dao(String table) => _daos[table]!;

  Iterable<SyncableDao> get all => SyncTables.all.map((s) => _daos[s.table]!);

  Future<int> pendingCount() async {
    var total = 0;
    for (final d in all) {
      total += await d.pendingCount();
    }
    return total;
  }

  Future<Map<String, int>> pendingByTable() async => {
        for (final d in all) d.table: await d.pendingCount(),
      };

  /// Next batch of pending rows for [table], oldest edit first.
  Future<List<Map<String, Object?>>> nextBatch(String table, {int limit = 200}) =>
      dao(table).pending(limit: limit);

  Future<void> claimForUser(String userId) async {
    for (final d in all) {
      await d.claimForUser(userId);
    }
  }
}
