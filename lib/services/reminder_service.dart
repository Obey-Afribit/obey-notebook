import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

class ReminderService {
  final FlutterLocalNotificationsPlugin _notificationsPlugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) {
      return;
    }

    tz.initializeTimeZones();

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings();

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
      macOS: iosSettings,
    );

    await _notificationsPlugin.initialize(settings);
    _initialized = true;
  }

  Future<void> scheduleReminder({
    required String noteId,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    final int id = noteId.hashCode.abs();
    final tz.TZDateTime scheduleAt = tz.TZDateTime.from(when, tz.local);

    await _notificationsPlugin.zonedSchedule(
      id,
      title,
      body,
      scheduleAt,
      const NotificationDetails(
        android: AndroidNotificationDetails(
          'note_reminders',
          'Note reminders',
          importance: Importance.max,
          priority: Priority.high,
        ),
        iOS: DarwinNotificationDetails(),
      ),
      uiLocalNotificationDateInterpretation:
          UILocalNotificationDateInterpretation.absoluteTime,
      androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
    );
  }

  Future<void> cancelReminder(String noteId) {
    return _notificationsPlugin.cancel(noteId.hashCode.abs());
  }
}
