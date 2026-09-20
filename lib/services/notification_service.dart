import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import 'package:luci_mobile/models/router_event.dart';
import 'package:luci_mobile/utils/logger.dart';

/// Shows the event feed's findings as system notifications.
///
/// The feed itself is derived locally from polling the router
/// ([EventDeriver]); nothing is sent anywhere. That matters: the privacy
/// policy promises all communication stays between the device and the
/// router, which rules out any push service.
class NotificationService {
  NotificationService([FlutterLocalNotificationsPlugin? plugin])
    : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  static const channelId = 'router_events';
  static const channelName = 'Router events';

  bool _ready = false;

  Future<void> init() async {
    if (_ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
        iOS: DarwinInitializationSettings(
          requestAlertPermission: false,
          requestBadgePermission: false,
          requestSoundPermission: false,
        ),
      ),
    );
    _ready = true;
  }

  /// Asks for permission, returning whether it was granted.
  ///
  /// Android 13+ needs a runtime grant; older versions answer null, which
  /// means "already allowed" rather than "refused".
  Future<bool> requestPermission() async {
    await init();
    try {
      final android = _plugin
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >();
      if (android != null) {
        return await android.requestNotificationsPermission() ?? true;
      }
      final ios = _plugin
          .resolvePlatformSpecificImplementation<
            IOSFlutterLocalNotificationsPlugin
          >();
      if (ios != null) {
        return await ios.requestPermissions(alert: true, sound: true) ?? false;
      }
    } catch (e, stack) {
      Logger.exception('Requesting notification permission failed', e, stack);
    }
    return false;
  }

  /// Posts one notification per event.
  ///
  /// Each uses the event's own id so the same event arriving twice — a
  /// re-run of the same poll window — replaces rather than stacks.
  Future<void> show(List<({RouterEvent event, String text})> items) async {
    if (items.isEmpty) return;
    await init();
    for (final item in items) {
      try {
        await _plugin.show(
          id: notificationId(item.event),
          title: item.text,
          notificationDetails: NotificationDetails(
            android: AndroidNotificationDetails(
              channelId,
              channelName,
              importance: _importance(item.event.severity),
              priority: _priority(item.event.severity),
              // A router event is information, not an alarm; waking the
              // screen for "a laptop joined" would be indefensible.
              category: AndroidNotificationCategory.status,
            ),
            iOS: const DarwinNotificationDetails(),
          ),
        );
      } catch (e, stack) {
        Logger.exception('Showing a notification failed', e, stack);
      }
    }
  }

  /// A stable id per event, so repeats replace instead of piling up.
  @visibleForTesting
  static int notificationId(RouterEvent event) =>
      event.dedupeKey.hashCode & 0x7fffffff;

  static Importance _importance(EventSeverity severity) => switch (severity) {
    EventSeverity.problem => Importance.high,
    EventSeverity.warning => Importance.defaultImportance,
    EventSeverity.info => Importance.low,
  };

  static Priority _priority(EventSeverity severity) => switch (severity) {
    EventSeverity.problem => Priority.high,
    EventSeverity.warning => Priority.defaultPriority,
    EventSeverity.info => Priority.low,
  };
}
