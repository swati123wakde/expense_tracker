import 'enums.dart';
import 'row_utils.dart';

class AccountEntity {
  const AccountEntity({
    required this.id,
    required this.name,
    required this.type,
    required this.currency,
    required this.icon,
    required this.color,
    required this.createdAt,
    required this.updatedAt,
    this.userId,
    this.archived = false,
    this.deletedAt,
    this.syncStatus = SyncStatus.pendingCreate,
  });

  factory AccountEntity.fromRow(Map<String, Object?> r) {
    final meta = SyncMeta.fromRow(r);
    return AccountEntity(
      id: meta.id,
      userId: meta.userId,
      name: RowReader.str(r['name']),
      type: AccountType.parse(r['type']),
      currency: RowReader.str(r['currency'], 'USD'),
      icon: RowReader.str(r['icon'], 'wallet'),
      color: RowReader.int_(r['color'], 0xFF1E88E5),
      archived: RowReader.bool_(r['archived']),
      createdAt: meta.createdAt,
      updatedAt: meta.updatedAt,
      deletedAt: meta.deletedAt,
      syncStatus: meta.syncStatus,
    );
  }

  final String id;
  final String? userId;
  final String name;
  final AccountType type;
  final String currency;
  final String icon;
  final int color;
  final bool archived;
  final DateTime createdAt;
  final DateTime updatedAt;
  final DateTime? deletedAt;
  final SyncStatus syncStatus;

  Map<String, Object?> toRow() => {
        'id': id,
        'user_id': userId,
        'name': name,
        'type': type.name,
        'currency': currency,
        'icon': icon,
        'color': color,
        'archived': archived ? 1 : 0,
        'created_at': createdAt.millisecondsSinceEpoch,
        'updated_at': updatedAt.millisecondsSinceEpoch,
        'deleted_at': deletedAt?.millisecondsSinceEpoch,
      };

  AccountEntity copyWith({
    String? name,
    AccountType? type,
    String? currency,
    String? icon,
    int? color,
    bool? archived,
  }) =>
      AccountEntity(
        id: id,
        userId: userId,
        name: name ?? this.name,
        type: type ?? this.type,
        currency: currency ?? this.currency,
        icon: icon ?? this.icon,
        color: color ?? this.color,
        archived: archived ?? this.archived,
        createdAt: createdAt,
        updatedAt: updatedAt,
        deletedAt: deletedAt,
        syncStatus: syncStatus,
      );
}

/// Account with its computed balance (in the account's own currency).
class AccountBalance {
  const AccountBalance({
    required this.account,
    required this.incomeMinor,
    required this.expenseMinor,
  });

  final AccountEntity account;
  final int incomeMinor;
  final int expenseMinor;

  int get balanceMinor => incomeMinor - expenseMinor;
}
