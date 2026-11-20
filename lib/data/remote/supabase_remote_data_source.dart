import 'package:supabase_flutter/supabase_flutter.dart';

import 'remote_data_source.dart';

/// Supabase/PostgREST implementation. Row Level Security on every table
/// (see supabase/schema.sql) guarantees a user only ever reads or writes rows
/// where user_id = auth.uid(); the explicit user_id filter is defence in depth.
class SupabaseRemoteDataSource implements RemoteDataSource {
  SupabaseRemoteDataSource(this._client);

  final SupabaseClient _client;

  /// Re-read a small window before the cursor so rows committed slightly out
  /// of order by concurrent writers are never missed. Re-applying an already
  /// seen row is a no-op for the merge.
  static const overlap = Duration(seconds: 5);

  @override
  Future<RemotePage> fetchChanges(
    String table, {
    required String userId,
    required int sinceMs,
    required int offset,
    required int limit,
  }) async {
    try {
      final since = DateTime.fromMillisecondsSinceEpoch(
        sinceMs <= 0 ? 0 : sinceMs - overlap.inMilliseconds,
        isUtc: true,
      ).toIso8601String();
      final List<Map<String, dynamic>> data = await _client
          .from(table)
          .select()
          .eq('user_id', userId)
          .gt('server_updated_at', since)
          .order('server_updated_at', ascending: true)
          .order('id', ascending: true)
          .range(offset, offset + limit - 1);

      int? maxServer;
      final rows = <Map<String, Object?>>[];
      for (final raw in data) {
        final row = Map<String, Object?>.from(raw);
        final server = row.remove('server_updated_at');
        if (server is String) {
          final ms = DateTime.parse(server).millisecondsSinceEpoch;
          if (maxServer == null || ms > maxServer) maxServer = ms;
        }
        rows.add(row);
      }
      return RemotePage(rows, maxServer);
    } on PostgrestException catch (e) {
      throw RemoteException(e.message, isAuthError: e.code == '401' || e.code == 'PGRST301');
    } on AuthException catch (e) {
      throw RemoteException(e.message, isAuthError: true);
    }
  }

  @override
  Future<void> upsert(String table, List<Map<String, Object?>> rows, {required String userId}) async {
    if (rows.isEmpty) return;
    try {
      final payload = [
        for (final r in rows) {...r, 'user_id': userId},
      ];
      await _client.from(table).upsert(payload, onConflict: 'user_id,id');
    } on PostgrestException catch (e) {
      throw RemoteException(e.message, isAuthError: e.code == '401' || e.code == 'PGRST301');
    } on AuthException catch (e) {
      throw RemoteException(e.message, isAuthError: true);
    }
  }
}
