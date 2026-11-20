import '../app/dependencies.dart';
import '../core/services/data_change_bus.dart';
import '../data/models/category.dart';
import '../data/models/enums.dart';
import 'bus_aware_notifier.dart';

class CategoriesProvider extends BusAwareNotifier {
  CategoriesProvider(this._deps) : super(_deps.bus, {Tables.categories});

  final AppDependencies _deps;

  /// Includes archived categories so historical transactions still resolve.
  List<CategoryEntity> all = const [];
  Map<String, CategoryEntity> byId = const {};

  List<CategoryEntity> active(TransactionType type) =>
      all.where((c) => c.type == type && !c.archived).toList();

  List<CategoryEntity> get archived => all.where((c) => c.archived).toList();

  String nameOf(String id) => byId[id]?.name ?? 'Uncategorized';

  Map<String, String> get names => {for (final c in all) c.id: c.name};

  @override
  Future<void> reload() async {
    all = await _deps.categories.all(includeArchived: true);
    byId = {for (final c in all) c.id: c};
  }

  Future<void> create({
    required String name,
    required TransactionType type,
    required String icon,
    required int color,
  }) =>
      _deps.categories.create(name: name, type: type, icon: icon, color: color);

  Future<void> update(CategoryEntity category) => _deps.categories.update(category);

  Future<void> setArchived(String id, bool archived) => _deps.categories.setArchived(id, archived);
}
