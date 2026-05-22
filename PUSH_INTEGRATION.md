# Push — дополнение к [README.md](README.md)

---

## Поведение LiveTex

- Пока приложение на экране и сокет жив — сообщения по WebSocket, push не используется.
- `LivetexChatPush` при сворачивании вызывает `chat.disconnect()` → LiveTex шлёт push, только если у визитёра **нет активного WebSocket**.
- Экран чата закрыт, приложение на переднем плане — **не push**; слушайте `chat.messages`, свой in-app индикатор.

Push на устройство доставляет **LiveTex** (FCM / APNS). Ключи передаёте на **[support@livetex.ru](mailto:support@livetex.ru)** — см. таблицы ниже.

---

## Как открыть экран чата

В README у `LivetexChatPush` указано `onNotificationTap: openChat`. Эта функция должна показать `LivetexChatScreen` — **тот же экран**, что и при обычном входе в чат из вашего UI.

Два входа — два способа навигации:

| Откуда | Почему |
| --- | --- |
| Кнопка / пункт меню в приложении | Есть `context` виджета → обычный `Navigator` |
| Тап по push-уведомлению | `context` часто нет (фон, cold start) → `GlobalKey<NavigatorState>` на `MaterialApp` |

**Из UI приложения:**

```dart
Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => LivetexChatScreen(config: chat.config, chat: chat, title: "Чат"),
  ),
);
```

**Из `onNotificationTap` (передайте ту же логику в `openChat`):**

```dart
final navigatorKey = GlobalKey<NavigatorState>();

void openChat() {
  navigatorKey.currentState?.push(
    MaterialPageRoute(
      builder: (_) => LivetexChatScreen(config: chat.config, chat: chat, title: "Чат"),
    ),
  );
}

// в MaterialApp:
MaterialApp(navigatorKey: navigatorKey, home: /* ... */);
```

Один и тот же `openChat` можно повесить и на кнопку «Чат», если удобнее — тогда достаточно `navigatorKey`.

---

## Нативная настройка — куда что класть

Нужен Firebase в проекте приложения (`flutterfire configure` или вручную).  
`firebase_core` / `firebase_messaging` подтягиваются из `livetex_chat_push`; если в app уже свой Firebase — выровняйте версии в `pubspec`.

### Android


| Что                         | Откуда                                                                | Куда                                                                                              |
| --------------------------- | --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------- |
| `google-services.json`      | Firebase Console → приложение Android                                 | `android/app/google-services.json`                                                                |
| FCM service-account `.json` | Firebase Console → Project settings → Service accounts → Generate key | **[support@livetex.ru](mailto:support@livetex.ru)** (указать ключ разработчика / аккаунт LiveTex) |


### iOS


| Что                        | Откуда                                                                 | Куда                                                        |
| -------------------------- | ---------------------------------------------------------------------- | ----------------------------------------------------------- |
| `GoogleService-Info.plist` | Firebase Console → приложение iOS                                      | `ios/Runner/` (через Xcode)                                 |
| APNS `.p12` + пароль       | Apple Developer → APNS cert (подробнее — KB LiveTex, «SDK iOS → Push») | **[support@livetex.ru](mailto:support@livetex.ru)**         |
| Capabilities               | Xcode → Runner                                                         | Push Notifications, Background Modes → Remote notifications |

