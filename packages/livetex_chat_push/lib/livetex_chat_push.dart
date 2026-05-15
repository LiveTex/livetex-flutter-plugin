import "dart:async";

import "package:firebase_core/firebase_core.dart";
import "package:firebase_messaging/firebase_messaging.dart";
import "package:flutter/foundation.dart";
import "package:flutter_local_notifications/flutter_local_notifications.dart";
import "package:livetex_chat/livetex_chat.dart";

/// Optional bootstrap: Firebase + local notifications + token for [LivetexChat].
///
/// Host must call [Firebase.initializeApp] (e.g. via `flutterfire configure`)
/// before [init].
final class LivetexPushBootstrap {
  LivetexPushBootstrap._();

  static final _plugin = FlutterLocalNotificationsPlugin();
  static bool _inited = false;

  /// Returns FCM token (Android) or APNS token (iOS) when available.
  static Future<String?> init({
    required LivetexChat chat,
    void Function(String payload)? onOpenFromNotification,
  }) async {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
    if (_inited) {
      final existing = await FirebaseMessaging.instance.getToken();
      if (existing != null) {
        chat.updateDeviceToken(existing);
      }
      return existing;
    }
    _inited = true;
    FirebaseMessaging.onBackgroundMessage(_firebaseMessagingBackgroundHandler);
    await _plugin.initialize(
      const InitializationSettings(
        android: AndroidInitializationSettings("@mipmap/ic_launcher"),
        iOS: DarwinInitializationSettings(),
      ),
      onDidReceiveNotificationResponse: (details) {
        final p = details.payload;
        if (p != null) onOpenFromNotification?.call(p);
      },
    );
    await FirebaseMessaging.instance.requestPermission();
    final messaging = FirebaseMessaging.instance;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      await messaging.setAutoInitEnabled(true);
    }
    final token = await messaging.getToken();
    if (token != null) {
      chat.updateDeviceToken(token);
    }
    messaging.onTokenRefresh.listen(chat.updateDeviceToken);
    FirebaseMessaging.onMessage.listen((RemoteMessage m) async {
      final n = m.notification;
      final title = n?.title ?? "LiveTex";
      final body = n?.body ?? "";
      await _plugin.show(
        m.hashCode,
        title,
        body,
        const NotificationDetails(
          android: AndroidNotificationDetails(
            "livetex_chat",
            "LiveTex",
            importance: Importance.max,
            priority: Priority.high,
          ),
          iOS: DarwinNotificationDetails(),
        ),
        payload: m.data["payload"]?.toString(),
      );
    });
    return token;
  }
}

@pragma("vm:entry-point")
Future<void> _firebaseMessagingBackgroundHandler(RemoteMessage message) async {
  await Firebase.initializeApp();
}
