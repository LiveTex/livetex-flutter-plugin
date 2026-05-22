# Push — дополнение к README

Базовый код (`livetexSetupPush`, `LivetexChat`, `LivetexChatPush`, конфиг) — в [README.md](README.md).

---

## Поведение LiveTex

- Пока приложение на экране и сокет жив — сообщения по WebSocket, push не используется.
- `LivetexChatPush` при сворачивании вызывает `chat.disconnect()` → LiveTex шлёт push, только если у визитёра **нет активного WebSocket**.
- Экран чата закрыт, приложение на переднем плане — **не push**; слушайте `chat.messages`, свой in-app индикатор.

**Кто доставляет push оператору (настраивается у LiveTex):**


|                      | A. Свой сервер | B. LiveTex                                 |
| -------------------- | -------------- | ------------------------------------------ |
| Кто шлёт             | Ваш бэкенд     | LiveTex (FCM / APNS)                       |
| Что передать LiveTex | URL вебхука    | FCM service-account JSON и/или APNS `.p12` |


Код в приложении одинаковый — device-token уходит в LiveTex через SDK.

**Вебхук LiveTex → ваш сервер (вариант A):**


| Поле       | Описание                       |
| ---------- | ------------------------------ |
| `version`  | `"1"`                          |
| `platform` | `ios` / `android`              |
| `to`       | FCM- или APNS-токен устройства |
| `text`     | текст сообщения (опц.)         |
| `url`      | ссылка на файл (опц.)          |


---

## Навигация

**Кнопка «Открыть чат»** — есть `BuildContext`:

```dart
Navigator.of(context).push(
  MaterialPageRoute(
    builder: (_) => LivetexChatScreen(config: chat.config, chat: chat, title: "Чат"),
  ),
);
```

**Тап по push** (`onNotificationTap`) — `context` часто нет → `GlobalKey` на `MaterialApp`:

```dart
final navigatorKey = GlobalKey<NavigatorState>();

void openChat() {
  navigatorKey.currentState?.push(
    MaterialPageRoute(
      builder: (_) => LivetexChatScreen(config: chat.config, chat: chat, title: "Чат"),
    ),
  );
}

MaterialApp(navigatorKey: navigatorKey, home: /* ... */);
```

---

## Нативная настройка — куда что класть

Нужен Firebase в проекте приложения (`flutterfire configure` или вручную).  
`firebase_core` / `firebase_messaging` подтягиваются из `livetex_chat_push`; если в app уже свой Firebase — выровняйте версии в `pubspec`.

### Android


| Что                         | Откуда                                                                | Куда                                                                                                         |
| --------------------------- | --------------------------------------------------------------------- | ------------------------------------------------------------------------------------------------------------ |
| `google-services.json`      | Firebase Console → приложение Android                                 | `android/app/google-services.json`                                                                           |
| FCM service-account `.json` | Firebase Console → Project settings → Service accounts → Generate key | **[support@livetex.ru](mailto:support@livetex.ru)** (вариант B; указать ключ разработчика / аккаунт LiveTex) |


### iOS


| Что                        | Откуда                                                                 | Куда                                                            |
| -------------------------- | ---------------------------------------------------------------------- | --------------------------------------------------------------- |
| `GoogleService-Info.plist` | Firebase Console → приложение iOS                                      | `ios/Runner/` (через Xcode)                                     |
| APNS `.p12` + пароль       | Apple Developer → APNS cert (подробнее — KB LiveTex, «SDK iOS → Push») | **[support@livetex.ru](mailto:support@livetex.ru)** (вариант B) |
| Capabilities               | Xcode → Runner                                                         | Push Notifications, Background Modes → Remote notifications     |


---

