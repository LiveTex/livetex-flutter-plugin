import "dart:async";

import "package:firebase_core/firebase_core.dart";
import "package:firebase_messaging/firebase_messaging.dart";
import "package:flutter/foundation.dart";
import "package:flutter/widgets.dart";
import "package:flutter_local_notifications/flutter_local_notifications.dart";
import "package:livetex_chat/livetex_chat.dart";

const String _channelId = "livetex_chat";
const String _channelName = "LiveTex";
const String _notificationPayload = "livetex";

const InitializationSettings _localInitSettings = InitializationSettings(
  android: AndroidInitializationSettings("@mipmap/ic_launcher"),
  iOS: DarwinInitializationSettings(),
);

const NotificationDetails _notificationDetails = NotificationDetails(
  android: AndroidNotificationDetails(
    _channelId,
    _channelName,
    importance: Importance.max,
    priority: Priority.high,
  ),
  iOS: DarwinNotificationDetails(),
);

/// Фоновый обработчик FCM. Бэкенд LiveTex шлёт на Android data-сообщение
/// (`data: {text: ...}`) без notification-блока — OS сама уведомление не
/// покажет, поэтому строим локальное уведомление здесь.
///
/// Хост-приложение обязано зарегистрировать его в `main()` ДО `runApp`:
/// `FirebaseMessaging.onBackgroundMessage(livetexFirebaseBackgroundHandler);`
@pragma("vm:entry-point")
Future<void> livetexFirebaseBackgroundHandler(RemoteMessage message) async {
  if (Firebase.apps.isEmpty) {
    await Firebase.initializeApp();
  }
  final text = message.data["text"];
  if (text == null || text.isEmpty) return;
  final plugin = FlutterLocalNotificationsPlugin();
  await plugin.initialize(_localInitSettings);
  await plugin.show(
    message.hashCode,
    _channelName,
    text,
    _notificationDetails,
    payload: _notificationPayload,
  );
}

/// Оркестрация push-уведомлений для [LivetexChat].
///
/// Жизненный цикл: `final push = LivetexChatPush(chat: chat, onNotificationTap:
/// ...); await push.initialize();` — и `await push.dispose()` при завершении.
///
/// Помимо push, [LivetexChatPush] рвёт WebSocket при сворачивании приложения
/// и реконнектит при возврате — это условие, по которому бэкенд решает слать
/// push (нет сокета → есть push).
class LivetexChatPush with WidgetsBindingObserver {
  LivetexChatPush({required this.chat, this.onNotificationTap});

  final LivetexChat chat;

  /// Вызывается при тапе по уведомлению (foreground-локалка,
  /// `onMessageOpenedApp` или запуск из killed-состояния).
  final VoidCallback? onNotificationTap;

  final FlutterLocalNotificationsPlugin _localPlugin =
      FlutterLocalNotificationsPlugin();
  final List<StreamSubscription<dynamic>> _subs = [];
  bool _initialized = false;

  Future<void> initialize() async {
    if (_initialized) return;
    _initialized = true;

    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }

    await _localPlugin.initialize(
      _localInitSettings,
      onDidReceiveNotificationResponse: (_) => onNotificationTap?.call(),
    );

    final messaging = FirebaseMessaging.instance;
    await messaging.requestPermission();

    await _refreshDeviceToken();
    _subs.add(
      messaging.onTokenRefresh.listen((_) => _refreshDeviceToken()),
    );

    _subs.add(FirebaseMessaging.onMessage.listen(_showForegroundNotification));
    _subs.add(
      FirebaseMessaging.onMessageOpenedApp.listen(
        (_) => onNotificationTap?.call(),
      ),
    );

    final initial = await messaging.getInitialMessage();
    if (initial != null) onNotificationTap?.call();

    WidgetsBinding.instance.addObserver(this);
  }

  /// Android — FCM-токен; iOS — APNS-токен (бэкенд LiveTex пушит на iOS через
  /// APNS напрямую). APNS-токен бывает `null` до завершения регистрации —
  /// тогда повтор произойдёт на ближайшем `resumed` (см. lifecycle).
  Future<void> _refreshDeviceToken() async {
    final messaging = FirebaseMessaging.instance;
    final String? token;
    if (defaultTargetPlatform == TargetPlatform.iOS) {
      token = await messaging.getAPNSToken();
    } else {
      token = await messaging.getToken();
    }
    if (token != null && token.isNotEmpty) {
      chat.updateDeviceToken(token);
    }
  }

  Future<void> _showForegroundNotification(RemoteMessage message) async {
    // Android — data-сообщение (`data.text`); iOS notification-fallback.
    final text = message.data["text"] ?? message.notification?.body;
    if (text == null || text.isEmpty) return;
    await _localPlugin.show(
      message.hashCode,
      _channelName,
      text,
      _notificationDetails,
      payload: _notificationPayload,
    );
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
        // Рвём сокет → бэкенд видит «визитёр оффлайн» → шлёт push.
        unawaited(chat.disconnect());
      case AppLifecycleState.resumed:
        unawaited(chat.connect());
        // Повторная попытка достать APNS-токен, если он не был готов на старте.
        unawaited(_refreshDeviceToken());
      case AppLifecycleState.inactive:
      case AppLifecycleState.detached:
        break;
    }
  }

  Future<void> dispose() async {
    WidgetsBinding.instance.removeObserver(this);
    for (final sub in _subs) {
      await sub.cancel();
    }
    _subs.clear();
  }
}
