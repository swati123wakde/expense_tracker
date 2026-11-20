import 'enums.dart';

/// Helpers for reading loosely-typed SQLite / JSON rows safely.
class RowReader {
  RowReader._();

  static int int_(Object? v, [int fallback = 0]) {
    if (v == null) return fallback;
    if (v is int) return v;
    if (v is num) return v.toInt();
    if (v is String) return int.tryParse(v) ?? num.tryParse(v)?.toInt() ?? fallback;
    if (v is bool) return v ? 1 : 0;
    return fallback;
  }

  static int? intOrNull(Object? v) => v == null ? null : int_(v);

  static String str(Object? v, [String fallback = '']) => v?.toString() ?? fallback;

  static String? strOrNull(Object? v) => v?.toString();

  static bool bool_(Object? v) => int_(v) != 0;

  static DateTime date(Object? v) => DateTime.fromMillisecondsSinceEpoch(int_(v));

  static DateTime? dateOrNull(Object? v) =>
      v == null ? null : DateTime.fromMillisecondsSinceEpoch(int_(v));
}

/// Metadata shared by every synchronised entity.
class SyncMeta {
  const SyncMeta({
    required this.id,
    required this.userId,
    required this.createdAt,
    required this.updatedAt,
    required this.deletedAt,
    required this.syncStatus,
  });

  factory SyncMeta.fromRow(Map<String, Object?> r) => SyncMeta(
        id: RowReader.str(r['id']),
        userId: RowReader.strOrNull(r['user_id']),
        createdAt: RowReader.date(r['created_at']),
        updatedAt: RowReader.date(r['updated_at']),
        deletedAt: RowReader.dateOrNull(r['deleted_at']),
        syncStatus: SyncStatus.parse(r['sync_status']),
      );

  final String id;
  final String? userId;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;

  bool get isDeleted => deletedAt != null;

  Map<String, Object?> toRow() => {
        'id': id,
        'user_id': userId,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'deleted_at': deletedAt?.millisecondsSinceEpoch,
      };
}
