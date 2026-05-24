import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show Color;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Thin wrapper around flutter_local_notifications used to display a system
/// banner when Supabase Realtime delivers a new `notifications` row while
/// the app is in the foreground (or recently backgrounded). This is the
/// "no Firebase" path — true push when the app is killed is provided by
/// background_poll.dart (15-min Workmanager poll).
class LocalNotifications {
  LocalNotifications._();
  static final LocalNotifications instance = LocalNotifications._();

  final _plugin = FlutterLocalNotificationsPlugin();
  bool _ready = false;
  int _id = 0;

  /// Called when the user taps a system notification banner — receives the
  /// `payload` string passed to `show(...)`. Set from main.dart so the app
  /// can route the user to the POI on the map.
  void Function(String payload)? onTap;

  // Suffix the channel id whenever the bundled sound changes — Android
  // channels are immutable once created, so swapping the sound needs a
  // brand-new channelId or the OS keeps the old "default" sound forever.
  static const _alertsChannelId = 'community_alerts_crow';
  static const _alertsChannelName = 'Community alerts';
  static const _alertsChannelDesc =
      'Notifies when someone reports a stolen bike or a point is approved.';

  Future<void> init() async {
    if (_ready) return;
    const init = InitializationSettings(
      android: AndroidInitializationSettings('@mipmap/ic_launcher'),
    );
    await _plugin.initialize(
      init,
      onDidReceiveNotificationResponse: (resp) {
        final payload = resp.payload;
        if (payload == null || payload.isEmpty) return;
        onTap?.call(payload);
      },
    );

    // Pre-create the channel so the importance level is set correctly.
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    await android?.createNotificationChannel(
      const AndroidNotificationChannel(
        _alertsChannelId,
        _alertsChannelName,
        description: _alertsChannelDesc,
        importance: Importance.high,
        // Crow caw — same clip used by the iOS APNs push payload.
        sound: RawResourceAndroidNotificationSound('crow_caw'),
        playSound: true,
        enableVibration: true,
      ),
    );
    // Android 13+ runtime permission. POST_NOTIFICATIONS is also declared
    // in AndroidManifest. Ask once — silently no-op on older OS versions.
    await android?.requestNotificationsPermission();

    // If the app was launched cold by tapping a notification, that tap was
    // queued before onDidReceiveNotificationResponse was registered. Drain
    // it here so we don't lose the routing intent.
    final launchDetails = await _plugin.getNotificationAppLaunchDetails();
    if (launchDetails?.didNotificationLaunchApp == true) {
      final payload = launchDetails!.notificationResponse?.payload;
      if (payload != null && payload.isNotEmpty) {
        // Defer slightly so AppState + map screen have time to construct.
        Future.delayed(const Duration(milliseconds: 600),
            () => onTap?.call(payload));
      }
    }
    _ready = true;
  }

  Future<void> show({
    required String title,
    required String body,
    bool urgent = false,
    String? payload,
  }) async {
    if (!_ready) await init();
    final id = ++_id;
    debugPrint('LocalNotifications.show: "$title" (urgent=$urgent)');
    try {
      await _plugin.show(
        id,
        title,
        body,
        NotificationDetails(
          android: AndroidNotificationDetails(
            _alertsChannelId,
            _alertsChannelName,
            channelDescription: _alertsChannelDesc,
            importance: Importance.max,
            priority: Priority.max,
            visibility: NotificationVisibility.public,
            category: urgent
                ? AndroidNotificationCategory.alarm
                : AndroidNotificationCategory.message,
            color: urgent ? const Color(0xFFEF4444) : null,
            ticker: urgent ? 'Community alert' : null,
            playSound: true,
            sound: const RawResourceAndroidNotificationSound('crow_caw'),
            enableVibration: true,
          ),
        ),
        payload: payload,
      );
    } catch (e) {
      debugPrint('LocalNotifications.show error: $e');
    }
  }
}
