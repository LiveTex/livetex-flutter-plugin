# livetex-flutter-plugin

Dart `>=3.11`. Flutter `>=3.41.6`. iOS `>=14`.

## Документация

- [PUSH_INTEGRATION.md](PUSH_INTEGRATION.md) — нативная настройка Firebase/APNS, навигация по push, доставка у LiveTex.

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

Фрагменты, не один файл: `chat`/`push` — в `State` приложения; экран — через `Navigator.push`; `dispose` — в `State.dispose`.

```dart
import "package:livetex_chat/livetex_chat.dart";
import "package:livetex_chat_push/livetex_chat_push.dart";
import "package:livetex_chat_ui/livetex_chat_ui.dart";

Future<void> main() async {
  await livetexSetupPush();
  runApp(/* ваше приложение */);
}

final traceLines = <String>[];

final chat = LivetexChat(
  LivetexChatConfig(
    // touchPoint — обязательный. Ключ точки контакта LiveTex (например `168:uuid`).
    touchPoint: "<touchPoint>",
    // authEndpoint — опционально. URL Visitor-Auth; если не задан — `{baseUrl}/v1/auth`
    // (по умолчанию `https://visitor-api.livetex.ru/v1/auth`).
    authEndpoint: Uri.parse("https://visitor-api.livetex.ru/v1/auth"),
    // visitorToken — опционально. Сохранённый токен визитёра: тот же посетитель и диалог
    // после перезапуска (обычно через loadVisitorToken / saveVisitorToken).
    visitorToken: null,
    // trace — опционально. Колбэк строк журнала SDK (auth, ws, lifecycle); для отладки
    // и обращений в поддержку вместе с chat.collectSupportReport().
    trace: traceLines.add,
  ),
);

final push = LivetexChatPush(
  chat: chat,
  onNotificationTap: openChat,
);
await push.initialize();

LivetexChatScreen(
  config: chat.config,
  chat: chat,
  title: "Чат",
);

await push.dispose();
chat.dispose();
```

Подробнее про push: [PUSH_INTEGRATION.md](PUSH_INTEGRATION.md).

