import '../app/dependencies.dart';
import '../core/services/data_change_bus.dart';
import '../data/models/goal.dart';
import 'bus_aware_notifier.dart';

class GoalsProvider extends BusAwareNotifier {
  GoalsProvider(this._deps) : super(_deps.bus, {Tables.goals, Tables.settings});

  final AppDependencies _deps;

  List<GoalEntity> goals = const [];
  String baseCurrency = 'USD';

  int get totalSavedMinor => goals.fold(0, (s, g) => s + g.savedMinor);
  int get totalTargetMinor => goals.fold(0, (s, g) => s + g.targetMinor);

  @override
  Future<void> reload() async {
    baseCurrency = await _deps.currency.baseCurrency();
    goals = await _deps.goals.all();
  }

  Future<void> create({
    required String name,
    required int targetMinor,
    int savedMinor = 0,
    DateTime? targetDate,
    required String icon,
    required int color,
  }) =>
      _deps.goals.create(
        name: name,
        targetMinor: targetMinor,
        savedMinor: savedMinor,
        targetDate: targetDate,
        icon: icon,
        color: color,
      );

  Future<void> update(
    String id, {
    required String name,
    required int targetMinor,
    required int savedMinor,
    DateTime? targetDate,
    required String icon,
    required int color,
  }) =>
      _deps.goals.update(
        id,
        name: name,
        targetMinor: targetMinor,
        savedMinor: savedMinor,
        targetDate: targetDate,
        icon: icon,
        color: color,
      );

  Future<void> contribute(String id, int deltaMinor) => _deps.goals.contribute(id, deltaMinor);

  Future<void> delete(String id) => _deps.goals.delete(id);
}
