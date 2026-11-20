/// A page of cloud rows changed after a cursor.
class RemotePage {
  const RemotePage(this.rows, this.maxServerUpdatedAtMs);

  /// Rows with content columns only (server bookkeeping removed).
  final List<Map<String, Object?>> rows;

  /// Highest server-assigned modification time in this page (ms), or null.
  final int? maxServerUpdatedAtMs;
}

/// Cloud persistence used exclusively by the sync engine. The UI and
/// repositories never call this directly.
abstract class RemoteDataSource {
  /// Rows of [table] modified on the server after [sinceMs] (server clock),
  /// ordered by modification time, paginated with [offset]/[limit].
  Future<RemotePage> fetchChanges(
    String table, {
    required String userId,
    required int sinceMs,
    required int offset,
    required int limit,
  });

  /// Inserts or updates rows (keyed by user_id + id). Tombstones are just
  /// rows with deleted_at set.
  Future<void> upsert(String table, List<Map<String, Object?>> rows, {required String userId});
}

class RemoteException implements Exception {
  RemoteException(this.message, {this.isAuthError = false});
  final String message;
  final bool isAuthError;

  @override
  String toString() => 'RemoteException: $message';
}
