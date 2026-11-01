import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest_10y.dart' as tzdata;
import 'package:timezone/timezone.dart' as tz;

/// Notifications systeme (rappels d'emissions, fin d'enregistrement).
/// Toutes les erreurs sont ignorees : les notifications sont un bonus,
/// l'application affiche aussi ses propres alertes.
class Notifier {
  Notifier._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _ready = false;

  /// Plateformes ou les notifications programmees fonctionnent app fermee.
  static bool get canSchedule =>
      Platform.isAndroid || Platform.isIOS || Platform.isMacOS;

  static Future<void> init() async {
    if (_ready) return;
    // Linux sans bus D-Bus de session (serveur, conteneur) : pas de notifications.
    if (Platform.isLinux &&
        (Platform.environment['DBUS_SESSION_BUS_ADDRESS'] ?? '').isEmpty) {
      return;
    }
    try {
      tzdata.initializeTimeZones();
      await _plugin.initialize(
        settings: const InitializationSettings(
          android: AndroidInitializationSettings('@mipmap/ic_launcher'),
          iOS: DarwinInitializationSettings(
            requestAlertPermission: false,
            requestBadgePermission: false,
            requestSoundPermission: false,
          ),
          macOS: DarwinInitializationSettings(),
          linux: LinuxInitializationSettings(defaultActionName: 'Ouvrir'),
          windows: WindowsInitializationSettings(
            appName: 'StreamFlow',
            appUserModelId: 'StreamFlow.StreamFlow.Player',
            guid: '7c1f3a52-5d1e-4b8e-9a6e-3f0c2d9b8e41',
          ),
        ),
      );
      _ready = true;
    } catch (_) {
      _ready = false;
    }
  }

  /// Demande l'autorisation d'afficher des notifications (Android 13+, iOS).
  static Future<void> requestPermission() async {
    if (!_ready) return;
    try {
      await _plugin
          .resolvePlatformSpecificImplementation<
              AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      await _plugin
          .resolvePlatformSpecificImplementation<
              IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(alert: true, sound: true);
    } catch (_) {}
  }

  static const _details = NotificationDetails(
    android: AndroidNotificationDetails(
      'reminders',
      'Rappels',
      channelDescription: 'Rappels des émissions et enregistrements',
      importance: Importance.high,
      priority: Priority.high,
    ),
    iOS: DarwinNotificationDetails(),
    macOS: DarwinNotificationDetails(),
  );

  static Future<void> show(int id, String title, String body) async {
    if (!_ready) return;
    try {
      await _plugin.show(
          id: id, title: title, body: body, notificationDetails: _details);
    } catch (_) {}
  }

  static Future<void> schedule(
      int id, DateTime when, String title, String body) async {
    if (!_ready || !canSchedule) return;
    if (when.isBefore(DateTime.now())) return;
    try {
      await _plugin.zonedSchedule(
        id: id,
        scheduledDate: tz.TZDateTime.from(when.toUtc(), tz.UTC),
        notificationDetails: _details,
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
        title: title,
        body: body,
      );
    } catch (_) {}
  }

  static Future<void> cancel(int id) async {
    if (!_ready) return;
    try {
      await _plugin.cancel(id: id);
    } catch (_) {}
  }
}
