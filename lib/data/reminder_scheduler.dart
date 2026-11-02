import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

import '../domain/reminder_plan.dart';

/// Device boundary for local notifications. The app hands it the whole
/// [ReminderPlan] each time it changes.
abstract interface class ReminderScheduler {
  /// Asks the OS for permission to notify. Returns whether it was granted.
  Future<bool> requestPermission();

  /// Cancels everything pending and schedules [plan] instead.
  Future<void> replaceAll(ReminderPlan plan);
}

/// Does nothing: platforms without scheduled notifications (web, desktop
/// besides macOS).
class NoopReminderScheduler implements ReminderScheduler {
  const NoopReminderScheduler();

  @override
  Future<bool> requestPermission() async => false;

  @override
  Future<void> replaceAll(ReminderPlan plan) async {}
}

/// Schedules through `flutter_local_notifications` (Android, iOS, macOS).
class LocalNotificationScheduler implements ReminderScheduler {
  LocalNotificationScheduler([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  /// Whether this platform can schedule notifications.
  static bool get isSupported =>
      !kIsWeb &&
      const {
        TargetPlatform.android,
        TargetPlatform.iOS,
        TargetPlatform.macOS,
      }.contains(defaultTargetPlatform);

  final FlutterLocalNotificationsPlugin _plugin;
  Future<void>? _ready;

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'reminders',
      'Reminders',
      channelDescription:
          'Daily keystone check-ins, the Mid-Month Campfire and season ends',
    ),
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
  );

  Future<void> _init() => _ready ??= () async {
    tz_data.initializeTimeZones();
    try {
      final zone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(zone.identifier));
    } catch (_) {
      // Unknown zone name: fall back to UTC offsets of the device clock.
      tz.setLocalLocation(tz.UTC);
    }
    // Permission is asked for separately, when reminders are on.
    const darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: darwin,
        macOS: darwin,
      ),
    );
  }();

  @override
  Future<bool> requestPermission() async {
    await _init();
    final granted = switch (defaultTargetPlatform) {
      TargetPlatform.android =>
        await _plugin
            .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin
            >()
            ?.requestNotificationsPermission(),
      TargetPlatform.iOS =>
        await _plugin
            .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true),
      TargetPlatform.macOS =>
        await _plugin
            .resolvePlatformSpecificImplementation<
              MacOSFlutterLocalNotificationsPlugin
            >()
            ?.requestPermissions(alert: true, badge: true, sound: true),
      _ => false,
    };
    return granted ?? false;
  }

  @override
  Future<void> replaceAll(ReminderPlan plan) async {
    await _init();
    await _plugin.cancelAll();
    for (final reminder in plan.reminders) {
      await _plugin.zonedSchedule(
        id: reminder.id,
        // From the instant, so a zone fallback still fires at device time.
        scheduledDate: tz.TZDateTime.from(reminder.at, tz.local),
        notificationDetails: _details,
        // Inexact needs no exact-alarm permission; a few minutes late is fine.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: reminder.title,
        body: reminder.body,
      );
    }
  }
}
