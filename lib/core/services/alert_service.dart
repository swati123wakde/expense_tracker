import '../../data/models/app_settings.dart';
import '../../data/models/recurring_rule.dart';
import '../../data/repositories/settings_repository.dart';
import '../finance/budget_calculator.dart';
import '../utils/date_utils.dart';
import 'notification_service.dart';

/// Decides *when* a local notification is worth sending, so users get one
/// alert per threshold per month instead of a notification on every edit.
class AlertService {
  AlertService(this._settings, this._notifications);

  final SettingsRepository _settings;
  final NotificationService _notifications;

  Future<bool> _enabled() => _settings.getBool(SettingsKeys.notificationsEnabled, fallback: true);

  /// Notifies when a budget crosses a higher threshold (50/75/90/100) than
  /// the last one notified this month. Returns the messages sent.
  Future<List<String>> checkBudgets({
    required DateTime now,
    required List<({BudgetStatus status, String? categoryName})> budgets,
    required String Function(int minor) format,
  }) async {
    if (!await _enabled()) return const [];
    final monthKey = '${now.year}-${now.month}';
    final monthName = DateUtilsX.monthName(now.month);
    final sent = <String>[];
    for (final b in budgets) {
      final s = b.status;
      final reached = s.isExceeded ? 101 : s.reachedThreshold;
      // Only 75%+ triggers a push; 50% is shown in-app only to avoid noise.
      if (reached == null || reached < 75) continue;
      final key = SettingsKeys.budgetAlert(s.budgetId, monthKey);
      final last = await _settings.getInt(key) ?? 0;
      if (reached <= last) continue;
      final message = BudgetCalculator.warningMessage(
        s,
        monthName: monthName,
        format: format,
        categoryName: b.categoryName,
      );
      if (message == null) continue;
      await _notifications.show(
        id: s.budgetId.hashCode & 0x7fffffff,
        title: s.isExceeded ? 'Budget exceeded' : 'Budget alert',
        body: message,
      );
      await _settings.setInt(key, reached);
      sent.add(message);
    }
    return sent;
  }

  /// "Your rent is due tomorrow." for recurring expenses due within a day.
  Future<List<String>> checkUpcoming({
    required DateTime now,
    required List<RecurringRule> upcoming,
    required Map<String, String> categoryNames,
    required String Function(RecurringRule rule) formatAmount,
  }) async {
    if (!await _enabled()) return const [];
    final sent = <String>[];
    final tomorrow = DateUtilsX.startOfDay(now).add(const Duration(days: 1));
    for (final rule in upcoming) {
      if (rule.type.name != 'expense') continue;
      final dueDay = DateUtilsX.startOfDay(rule.nextDueAt);
      if (dueDay != tomorrow) continue;
      final key = SettingsKeys.recurringReminder(rule.id, rule.occurrencesGenerated);
      if (await _settings.getInt(key) != null) continue;
      final label = rule.note.isNotEmpty ? rule.note : (categoryNames[rule.categoryId] ?? 'payment');
      final message = 'Your $label (${formatAmount(rule)}) is due tomorrow.';
      await _notifications.show(
        id: rule.id.hashCode & 0x7fffffff,
        title: 'Upcoming payment',
        body: message,
        channel: NotificationChannel.reminders,
      );
      await _settings.setInt(key, 1);
      sent.add(message);
    }
    return sent;
  }
}
