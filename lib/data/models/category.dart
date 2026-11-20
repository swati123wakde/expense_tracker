import 'enums.dart';
import 'row_utils.dart';

class CategoryEntity {
  const CategoryEntity({
    required this.id,
    required this.name,
    required this.type,
    required this.icon,
    required this.color,
    required this.createdAt,
    required this.updatedAt,
    this.userId,
    this.isCustom = false,
    this.archived = false,
    this.sortOrder = 0,
    this.deletedAt,
    this.syncStatus = SyncStatus.pendingCreate,
  });

  factory CategoryEntity.fromRow(Map<String, Object?> r) {
    final meta = SyncMeta.fromRow(r);
    return CategoryEntity(
      id: meta.id,
      userId: meta.userId,
      name: RowReader.str(r['name']),
      type: TransactionType.parse(r['type']),
      icon: RowReader.str(r['icon'], 'other'),
      color: RowReader.int_(r['color'], 0xFF757575),
      isCustom: RowReader.bool_(r['is_custom']),
      archived: RowReader.bool_(r['archived']),
      sortOrder: RowReader.int_(r['sort_order']),
      createdAt: meta.createdAt,
      updatedAt: meta.updatedAt,
      deletedAt: meta.deletedAt,
      syncStatus: meta.syncStatus,
    );
  }

  final String id;
  final String? userId;
  final String name;
  final TransactionType type;
  final String icon;
  final int color;
  final bool isCustom;
  final bool archived;
  final int sortOrder;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;

  Map<String, Object?> toRow() => {
        'id': id,
        'user_id': userId,
        'name': name,
        'type': type.name,
        'icon': icon,
        'color': color,
        'is_custom': isCustom ? 1 : 0,
        'archived': archived ? 1 : 0,
        'sort_order': sortOrder,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'deleted_at': deletedAt?.millisecondsSinceEpoch,
      };

  CategoryEntity copyWith({
    String? name,
    TransactionType? type,
    String? icon,
    int? color,
    bool? archived,
    int? sortOrder,
  }) =>
      CategoryEntity(
        id: id,
        userId: userId,
        name: name ?? this.name,
        type: type ?? this.type,
        icon: icon ?? this.icon,
        color: color ?? this.color,
        isCustom: isCustom,
        archived: archived ?? this.archived,
        sortOrder: sortOrder ?? this.sortOrder,
        createdAt: createdAt,
        updatedAt: updatedAt,
        deletedAt: deletedAt,
        syncStatus: syncStatus,
      );
}
