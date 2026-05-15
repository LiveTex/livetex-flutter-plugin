# livetex-flutter-plugin

Dart `>=3.4`. Flutter `>=3.16` для UI и push.

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
```

```dart
import "package:firebase_core/firebase_core.dart";
import "package:flutter/foundation.dart";
import "package:flutter/material.dart";
import "package:livetex_chat/livetex_chat.dart";
import "package:livetex_chat_push/livetex_chat_push.dart";
import "package:livetex_chat_ui/livetex_chat_ui.dart";

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  // Инициализация Firebase до runApp: требуется для FCM и LivetexPushBootstrap.
  // Настройка проекта: документация FlutterFire, команда `flutterfire configure`.
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp();
    }
  } catch (e) {
    // Если Firebase ещё не настроен, приложение может работать без пушей.
    if (kDebugMode) {
      debugPrint("Firebase.initializeApp: $e");
    }
  }
  runApp(const ExampleApp());
}

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(home: ExampleHome());
  }
}

class ExampleHome extends StatelessWidget {
  const ExampleHome({super.key});

  void _openChat(BuildContext context) {
    // Для обращения в поддержку приложите этот журнал и текст chat.collectSupportReport().
    final traceLines = <String>[];

    final cfg = LivetexChatConfig(
      touchPoint: "<touchPoint>",
      authEndpoint: Uri.parse("https://visitor-api.livetex.ru/v1/auth"),
      visitorToken: null, // опционально: сохранённый токен — тот же посетитель/диалог
      trace: traceLines.add, // Опционально: Дебаг журнал
    );

    Navigator.of(context).push<void>(
      MaterialPageRoute<void>(
        builder: (_) => LivetexChatScreen(
          config: cfg,
          title: "Чат",
          afterConnected: (LivetexChat chat) async {
            if (kIsWeb) {
              // На веб-платформе в этом примере push не инициализируем.
              return;
            }
            try {
              // Подключение push: получение FCM-токена, привязка к сессии, локальные уведомления.
              await LivetexPushBootstrap.init(chat: chat);
            } catch (e) {
              if (kDebugMode) {
                debugPrint("LivetexPushBootstrap.init: $e");
              }
            }
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: FilledButton(
          onPressed: () => _openChat(context),
          child: const Text("Открыть чат"),
        ),
      ),
    );
  }
}
```
