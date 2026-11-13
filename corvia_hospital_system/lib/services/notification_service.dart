import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:logging/logging.dart';
import 'package:timezone/data/latest_all.dart' as tz_data;
import 'package:timezone/timezone.dart' as tz;

final Logger _logger = Logger('NotificationService');

/// Local notifications for medication reminders.
///
/// Reminders are scheduled on the device, not pushed from the server, so they
/// keep working offline. Every method is a no-op rather than a throw when the
/// platform refuses: a reminder failing to schedule must never take down the
/// screen the user is on.
class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  static const String _channelId = 'medication_reminders';
  static const String _channelName = 'Medication reminders';
  static const String _channelDescription =
      'Reminders to take your medication at the times you set.';

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _ready = false;

  /// Safe to call more than once. Sets the local timezone from the device so a
  /// reminder set for 08:00 fires at 08:00 wherever the user actually is.
  Future<void> init() async {
    if (_ready) return;

    try {
      tz_data.initializeTimeZones();
      final localZone = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(localZone.identifier));

      const android = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwin = DarwinInitializationSettings(
        // Asked for explicitly in requestPermissions() instead, so the prompt
        // lands when the user first sets a reminder rather than at cold start.
        requestAlertPermission: false,
        requestBadgePermission: false,
        requestSoundPermission: false,
      );

      await _plugin.initialize(
        settings: const InitializationSettings(
          android: android,
          iOS: darwin,
          macOS: darwin,
        ),
      );

      _ready = true;
    } catch (_) {
      _logger.warning('Notification init unavailable');
    }
  }

  /// Asks for notification permission. Call this when the user does something
  /// that implies they want reminders, not on startup.
  ///
  /// Returns false if permission was refused or unavailable, so callers can
  /// tell the user their reminder was saved but will not alert them.
  Future<bool> requestPermissions() async {
    await init();

    try {
      final android = _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

      if (android != null) {
        final granted = await android.requestNotificationsPermission() ?? false;
        if (!granted) return false;

        // Not fatal if refused: without it Android may batch the alarm and
        // deliver the reminder late, but it will still arrive.
        await android.requestExactAlarmsPermission();
        return true;
      }

      final darwin = _plugin.resolvePlatformSpecificImplementation<
          IOSFlutterLocalNotificationsPlugin>();

      if (darwin != null) {
        return await darwin.requestPermissions(
              alert: true,
              badge: true,
              sound: true,
            ) ??
            false;
      }

      return false;
    } catch (e) {
      _logger.warning('Notification permission request failed: $e');
      return false;
    }
  }

  /// Schedules [medicationName] to repeat every day at [hour]:[minute].
  ///
  /// [reminderId] is the row's uuid; it is folded into a stable 31-bit int
  /// because the platform keys notifications by int, and the same uuid must
  /// always map to the same int or we could never cancel the right one.
  Future<void> scheduleDailyMedicationReminder({
    required String reminderId,
    required String medicationName,
    required int hour,
    required int minute,
  }) async {
    await init();
    if (!_ready) return;

    try {
      await _plugin.zonedSchedule(
        id: notificationIdFor(reminderId),
        title: 'Time for your medication',
        body: 'Take your $medicationName.',
        scheduledDate: _nextInstanceOf(hour, minute),
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        // Repeats daily by matching only the time component.
        matchDateTimeComponents: DateTimeComponents.time,
        payload: reminderId,
        notificationDetails: const NotificationDetails(
          android: AndroidNotificationDetails(
            _channelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
            category: AndroidNotificationCategory.reminder,
          ),
          iOS: DarwinNotificationDetails(
            interruptionLevel: InterruptionLevel.timeSensitive,
          ),
        ),
      );
    } catch (e) {
      _logger.warning('Could not schedule reminder $reminderId: $e');
    }
  }

  Future<void> cancelMedicationReminder(String reminderId) async {
    await init();
    if (!_ready) return;

    try {
      await _plugin.cancel(id: notificationIdFor(reminderId));
    } catch (e) {
      _logger.warning('Could not cancel reminder $reminderId: $e');
    }
  }

  Future<void> cancelAll() async {
    await init();
    if (!_ready) return;

    try {
      await _plugin.cancelAll();
    } catch (e) {
      _logger.warning('Could not cancel reminders: $e');
    }
  }

  /// The next occurrence of [hour]:[minute] in the device's timezone, rolling
  /// to tomorrow when that time has already passed today.
  tz.TZDateTime _nextInstanceOf(int hour, int minute) {
    final now = tz.TZDateTime.now(tz.local);

    var next = tz.TZDateTime(
      tz.local,
      now.year,
      now.month,
      now.day,
      hour,
      minute,
    );

    if (!next.isAfter(now)) {
      next = next.add(const Duration(days: 1));
    }

    return next;
  }

  /// Stable uuid -> int. Masked to 31 bits because Android notification ids are
  /// signed 32-bit and a negative id is rejected.
  static int notificationIdFor(String reminderId) =>
      reminderId.hashCode & 0x7fffffff;

  /// Parses the 'HH:mm' string stored in medication_reminders.reminder_time.
  /// Returns null when the value is missing or malformed, so callers can skip
  /// scheduling rather than guess at a time.
  static ({int hour, int minute})? parseReminderTime(String? value) {
    if (value == null) return null;

    final parts = value.split(':');
    if (parts.length < 2) return null;

    final hour = int.tryParse(parts[0]);
    final minute = int.tryParse(parts[1]);

    if (hour == null || minute == null) return null;
    if (hour < 0 || hour > 23 || minute < 0 || minute > 59) return null;

    return (hour: hour, minute: minute);
  }
}
