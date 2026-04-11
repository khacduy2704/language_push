import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:timezone/data/latest_all.dart' as tz;
import 'package:timezone/timezone.dart' as tz;

import 'app_database.dart';

class NotificationService {
  NotificationService._();

  static final NotificationService instance = NotificationService._();

  final FlutterLocalNotificationsPlugin _plugin =
      FlutterLocalNotificationsPlugin();

  bool _initialized = false;

  static bool get _isSupported =>
      !kIsWeb && (Platform.isAndroid || Platform.isIOS);

  Future<void> initialize() async {
    if (_initialized || !_isSupported) {
      return;
    }

    tz.initializeTimeZones();

    try {
      final String timezoneName = await FlutterTimezone.getLocalTimezone();
      tz.setLocalLocation(tz.getLocation(timezoneName));
    } catch (_) {
      tz.setLocalLocation(tz.UTC);
    }

    const AndroidInitializationSettings androidSettings =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    const DarwinInitializationSettings iosSettings =
        DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const InitializationSettings settings = InitializationSettings(
      android: androidSettings,
      iOS: iosSettings,
    );

    try {
      await _plugin.initialize(settings);
      _initialized = true;
    } catch (_) {
      // Plugin not available on this platform — notifications disabled.
    }
  }

  Future<void> requestPermissions() async {
    if (!_isSupported || !_initialized) {
      return;
    }

    if (Platform.isAndroid) {
      final AndroidFlutterLocalNotificationsPlugin? androidPlugin = _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>();
      await androidPlugin?.requestNotificationsPermission();
      await androidPlugin?.requestExactAlarmsPermission();
    } else if (Platform.isIOS) {
      final IOSFlutterLocalNotificationsPlugin? iosPlugin = _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>();
      await iosPlugin?.requestPermissions(
        alert: true,
        badge: true,
        sound: true,
      );
    }
  }

  /// Cancels all pending notifications and schedules 50 future ones, each
  /// [intervalMinutes] apart, showing all [words] in the notification body.
  Future<void> schedule({
    required List<Word> words,
    required int intervalMinutes,
  }) async {
    if (!_isSupported || !_initialized) {
      return;
    }

    await _plugin.cancelAll();

    if (words.isEmpty) {
      return;
    }

    final String body = words.map((Word w) {
      return w.meaning.isEmpty
          ? '${w.word} (${w.partOfSpeech})'
          : '${w.word} (${w.partOfSpeech}) ${w.meaning}';
    }).join('\n');

    final AndroidNotificationDetails androidDetails =
        AndroidNotificationDetails(
      'word_push_channel',
      'Word Push',
      channelDescription: 'Periodic word push notifications',
      importance: Importance.high,
      priority: Priority.high,
      styleInformation: BigTextStyleInformation(body),
    );

    final NotificationDetails details = NotificationDetails(
      android: androidDetails,
      iOS: const DarwinNotificationDetails(),
    );

    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);

    for (int i = 1; i <= 50; i++) {
      final tz.TZDateTime scheduledTime =
          now.add(Duration(minutes: intervalMinutes * i));

      await _plugin.zonedSchedule(
        i,
        'Words to push',
        body,
        scheduledTime,
        details,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
      );
    }
  }

  Future<void> cancelAll() async {
    if (!_isSupported || !_initialized) {
      return;
    }
    await _plugin.cancelAll();
  }
}
