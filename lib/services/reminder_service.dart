import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

/// System notifications for note reminders.
///
/// Native scheduling exists on Android, iOS and macOS. On Windows and the web
/// this plugin version cannot schedule, so [nativeSupported] is false and the
/// controller shows reminders in-app while the notebook is open instead.
class ReminderService {
  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  bool get nativeSupported =>
      !kIsWeb &&
      (defaultTargetPlatform == TargetPlatform.android ||
          defaultTargetPlatform == TargetPlatform.iOS ||
          defaultTargetPlatform == TargetPlatform.macOS);

  Future<void> initialize() async {
    if (_initialized || !nativeSupported) {
      return;
    }

    tz.initializeTimeZones();

    const AndroidInitializationSettings android =
        AndroidInitializationSettings('@mipmap/ic_launcher');
    const DarwinInitializationSettings darwin = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    try {
      await _plugin.initialize(
        const InitializationSettings(
          android: android,
          iOS: darwin,
          macOS: darwin,
        ),
      );
      _initialized = true;
    } catch (_) {
      // Leave reminders disabled rather than blocking app start-up.
    }
  }

  /// Asks for notification permission (Android 13+, iOS). Returns true when
  /// notifications can be shown.
  Future<bool> requestPermission() async {
    if (!nativeSupported || !_initialized) {
      return false;
    }
    try {
      final AndroidFlutterLocalNotificationsPlugin? android =
          _plugin.resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      if (android != null) {
        return await android.requestNotificationsPermission() ?? false;
      }
      final IOSFlutterLocalNotificationsPlugin? ios =
          _plugin.resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      if (ios != null) {
        return await ios.requestPermissions(
                alert: true, badge: true, sound: true) ??
            false;
      }
    } catch (_) {
      return false;
    }
    return true;
  }

  Future<void> scheduleReminder({
    required String noteId,
    required String title,
    required String body,
    required DateTime when,
  }) async {
    if (!nativeSupported || !_initialized || when.isBefore(DateTime.now())) {
      return;
    }

    final tz.TZDateTime at = tz.TZDateTime.from(when.toUtc(), tz.UTC);
    final String safeTitle = title.trim().isEmpty ? 'Note reminder' : title;
    final String preview =
        body.length > 140 ? '${body.substring(0, 140)}...' : body;

    const NotificationDetails details = NotificationDetails(
      android: AndroidNotificationDetails(
        'note_reminders',
        'Note reminders',
        channelDescription: 'Reminders you set on notes',
        importance: Importance.high,
        priority: Priority.high,
      ),
      iOS: DarwinNotificationDetails(),
      macOS: DarwinNotificationDetails(),
    );

    // Exact alarms need a user-granted permission on Android 12+. Use them when
    // allowed, otherwise fall back to an inexact alarm (usually within a few
    // minutes) instead of failing.
    AndroidScheduleMode mode = AndroidScheduleMode.inexactAllowWhileIdle;
    final AndroidFlutterLocalNotificationsPlugin? android =
        _plugin.resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin>();
    if (android != null &&
        (await android.canScheduleExactNotifications() ?? false)) {
      mode = AndroidScheduleMode.exactAllowWhileIdle;
    }

    try {
      await _plugin.zonedSchedule(
        _idFor(noteId),
        safeTitle,
        preview,
        at,
        details,
        androidScheduleMode: mode,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    } catch (_) {
      if (mode == AndroidScheduleMode.exactAllowWhileIdle) {
        await _plugin.zonedSchedule(
          _idFor(noteId),
          safeTitle,
          preview,
          at,
          details,
          androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
          uiLocalNotificationDateInterpretation:
              UILocalNotificationDateInterpretation.absoluteTime,
        );
      }
    }
  }

  Future<void> cancelReminder(String noteId) async {
    if (!nativeSupported || !_initialized) {
      return;
    }
    try {
      await _plugin.cancel(_idFor(noteId));
      // Reminders scheduled by v0.2 used String.hashCode as the id.
      await _plugin.cancel(noteId.hashCode.abs());
    } catch (_) {
      // Nothing scheduled; ignore.
    }
  }

  /// Stable 31-bit id per note (String.hashCode is not stable across runs on
  /// every platform, so use a simple FNV-1a hash instead).
  int _idFor(String noteId) {
    int hash = 0x811c9dc5;
    for (final int unit in noteId.codeUnits) {
      hash ^= unit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash;
  }
}
