import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

enum NotificationChannel { budget, reminders }

abstract class NotificationService {
  Future<void> init();
  Future<void> requestPermission();
  Future<void> show({
    required int id,
    required String title,
    required String body,
    NotificationChannel channel = NotificationChannel.budget,
  });
}

class LocalNotificationService implements NotificationService {
  final FlutterLocalNotificationsPlugin _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;

  @override
  Future<void> init() async {
    try {
      const settings = InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      );
      await _plugin.initialize(settings);
      _ready = true;
    } catch (e) {
      debugPrint('Notifications unavailable: $e');
    }
  }

  @override
  Future<void> requestPermission() async {
    if (!_ready) return;
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, badge: true, sound: true);
    } catch (e) {
      debugPrint('Notification permission request failed: $e');
    }
  }

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    NotificationChannel channel = NotificationChannel.budget,
  }) async {
    if (!_ready) return;
    final android = channel == NotificationChannel.budget
        ? const AndroidNotificationDetails(
            'budget_alerts',
            'Budget alerts',
            channelDescription: 'Warnings when you approach or exceed a budget',
            importance: Importance.high,
            priority: Priority.high,
          )
        : const AndroidNotificationDetails(
            'bill_reminders',
            'Bill reminders',
            channelDescription: 'Reminders for upcoming recurring payments',
            importance: Importance.defaultImportance,
            priority: Priority.defaultPriority,
          );
    try {
      await _plugin.show(
        id,
        title,
        body,
        NotificationDetails(android: android, iOS: const DarwinNotificationDetails()),
      );
    } catch (e) {
      debugPrint('Failed to show notification: $e');
    }
  }
}

/// Records notifications instead of showing them (tests / unsupported platforms).
class RecordingNotificationService implements NotificationService {
  final List<({int id, String title, String body})> shown = [];

  @override
  Future<void> init() async {}

  @override
  Future<void> requestPermission() async {}

  @override
  Future<void> show({
    required int id,
    required String title,
    required String body,
    NotificationChannel channel = NotificationChannel.budget,
  }) async {
    shown.add((id: id, title: title, body: body));
  }
}
