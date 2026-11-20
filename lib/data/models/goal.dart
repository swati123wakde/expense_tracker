import 'enums.dart';
import 'row_utils.dart';

class GoalEntity {
  const GoalEntity({
    required this.id,
    required this.name,
    required this.targetMinor,
    required this.savedMinor,
    required this.icon,
    required this.color,
    required this.createdAt,
    required this.updatedAt,
    this.targetDate,
    this.userId,
    this.deletedAt,
    this.syncStatus = SyncStatus.pendingCreate,
  });

  factory GoalEntity.fromRow(Map<String, Object?> r) {
    final meta = SyncMeta.fromRow(r);
    return GoalEntity(
      id: meta.id,
      userId: meta.userId,
      name: RowReader.str(r['name']),
      targetMinor: RowReader.int_(r['target_minor']),
      savedMinor: RowReader.int_(r['saved_minor']),
      targetDate: RowReader.dateOrNull(r['target_date']),
      icon: RowReader.str(r['icon'], 'savings'),
      color: RowReader.int_(r['color'], 0xFF43A047),
      createdAt: meta.createdAt,
      updatedAt: meta.updatedAt,
      deletedAt: meta.deletedAt,
      syncStatus: meta.syncStatus,
    );
  }

  final String id;
  final String? userId;
  final String name;
  final int targetMinor;
  final int savedMinor;
  final DateTime? targetDate;
  final String icon;
  final int color;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;

  double get progress => targetMinor <= 0 ? 0 : (savedMinor / targetMinor).clamp(0.0, 1.0).toDouble();
  int get remainingMinor => (targetMinor - savedMinor) < 0 ? 0 : targetMinor - savedMinor;
  bool get isComplete => savedMinor >= targetMinor && targetMinor > 0;

  /// Amount that must be saved per month to hit the target date.
  int? monthlyNeeded(DateTime now) {
    final date = targetDate;
    if (date == null || isComplete) return null;
    final months = (date.year - now.year) * 12 + (date.month - now.month);
    if (months <= 0) return remainingMinor;
    return (remainingMinor / months).ceil();
  }

  Map<String, Object?> toRow() => {
        'id': id,
        'user_id': userId,
        'name': name,
        'target_minor': targetMinor,
        'saved_minor': savedMinor,
        'target_date': targetDate?.millisecondsSinceEpoch,
        'icon': icon,
        'color': color,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'deleted_at': deletedAt?.millisecondsSinceEpoch,
      };
}
