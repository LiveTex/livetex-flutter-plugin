# livetex-flutter-plugin

Dart `>=3.6`. Flutter `>=3.27` для UI и push (стек Firebase Messaging 16.x).

## Документация

- [Настройка push-уведомлений](PUSH_INTEGRATION.md)

```yaml
dependencies:
  livetex_chat:
    git:
      url: https://github.com/LiveTex/livetex-flutter-plugin.git
      path: packages/livetex_chat
  livetex_chat_ui:
    git:
      url: https://github.com/LiveTex/livetex-flutter-plugin.git
      path: packages/livetex_chat_ui
  livetex_chat_push:
    git:
      url: https://github.com/LiveTex/livetex-flutter-plugin.git
      path: packages/livetex_chat_push
  firebase_core: ^4.9.0
  firebase_messaging: ^16.2.2
```

```dart
import "package:firebase_core/firebase_core.dart";
import "package:firebase_messaging/firebase_messaging.dart";
import "package:flutter/material.dart";
import "package:livetex_chat/livetex_chat.dart";
import "package:livetex_chat_push/livetex_chat_push.dart";
import "package:livetex_chat_ui/livetex_chat_ui.dart";

// Нужен, чтобы открыть экран чата по тапу на push, когда дерево
// виджетов ещё/уже не построено.
final navigatorKey = GlobalKey<NavigatorState>();

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Firebase должен быть настроен в проекте — см. PUSH_INTEGRATION.md.
  await Firebase.initializeApp();
  // Фоновый обработчик push регистрируется ДО runApp.
  FirebaseMessaging.onBackgroundMessage(livetexFirebaseBackgroundHandler);
  runApp(const ExampleApp());
}

class ExampleApp extends StatefulWidget {
  const ExampleApp({super.key});

  @override
  State<ExampleApp> createState() => _ExampleAppState();
}

class _ExampleAppState extends State<ExampleApp> {
  // LivetexChat и LivetexChatPush живут на уровне приложения — они должны
  // переживать открытие/закрытие экрана чата (этого требует push).
  late final LivetexChat _chat;
  late final LivetexChatPush _push;

  // Журнал для отладки: при обращении в поддержку приложите его содержимое.
  final _trace = <String>[];

  @override
  void initState() {
    super.initState();
    _chat = LivetexChat(
      LivetexChatConfig(touchPoint: "<touchPoint>", trace: _trace.add),
    );
    _push = LivetexChatPush(chat: _chat, onNotificationTap: _openChat);
    _push.initialize();
  }

  @override
  void dispose() {
    _push.dispose();
    _chat.dispose();
    super.dispose();
  }

  void _openChat() {
    navigatorKey.currentState?.push<void>(
      MaterialPageRoute<void>(
        builder: (_) => LivetexChatScreen(
          config: _chat.config,
          chat: _chat,
          title: "Чат",
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      navigatorKey: navigatorKey,
      home: Scaffold(
        body: Center(
          child: FilledButton(
            onPressed: _openChat,
            child: const Text("Открыть чат"),
          ),
        ),
      ),
    );
  }
}
```
