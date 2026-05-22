# LiveTex Flutter SDK — настройка push-уведомлений

Документ для интегратора, встраивающего LiveTex Flutter SDK в своё приложение.
Описывает, как подключить push-уведомления, чтобы пользователь получал ответ
оператора, когда приложение свёрнуто.

---

## 1. Как это работает

Пока приложение открыто, чат работает через WebSocket — сообщения приходят
мгновенно, push не нужен. Когда пользователь **сворачивает приложение**,
`LivetexChatPush` разрывает WebSocket. Сервер LiveTex отправляет push-уведомление
при новом сообщении от оператора **только если у визитёра нет активного
WebSocket-соединения**.

Каждое сообщение оператора, отправленное пока приложение свёрнуто, формирует
своё push-уведомление. При возврате на экран чата всё равно стоит подгрузить
историю — доставка push (FCM/APNS) не даёт 100% гарантии, отдельные
уведомления могут не дойти.

> **Оповещение, когда экран чата закрыт, но приложение открыто** — это НЕ задача
> push. Сокет на переднем плане жив; подпишитесь на `chat.messages` и покажите
> свой in-app индикатор. См. `INTEGRATION.md`.

Доставка push возможна двумя способами (на стороне LiveTex):

| Способ | Кто шлёт push | Что передать в LiveTex |
|---|---|---|
| **A. Свой сервер** (рекомендует LiveTex) | Ваш бэкенд по вебхуку от LiveTex | URL вашего сервера |
| **B. LiveTex напрямую** | Серверы LiveTex (FCM / APNS) | FCM service-account ключ и/или APNS-сертификат |

В обоих случаях **код в приложении одинаковый** (раздел 2) — приложение всегда
получает device-token и передаёт его в LiveTex. Различается только настройка
доставки (раздел 3).

---

## 2. Код приложения (одинаково для обоих способов)

### 2.1. Зависимости

В `pubspec.yaml` приложения:

```yaml
dependencies:
  livetex_chat:
    git: { url: https://github.com/LiveTex/livetex-flutter-plugin.git, path: packages/livetex_chat }
  livetex_chat_ui:
    git: { url: https://github.com/LiveTex/livetex-flutter-plugin.git, path: packages/livetex_chat_ui }
  livetex_chat_push:
    git: { url: https://github.com/LiveTex/livetex-flutter-plugin.git, path: packages/livetex_chat_push }
  firebase_core: ^4.9.0
  firebase_messaging: ^16.2.2
```

### 2.2. Инициализация в `main()`

Фоновый обработчик push **обязан** регистрироваться до `runApp`:

```dart
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:livetex_chat_push/livetex_chat_push.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  FirebaseMessaging.onBackgroundMessage(livetexFirebaseBackgroundHandler);
  runApp(const MyApp());
}
```

### 2.3. Создание `LivetexChatPush`

`LivetexChat` держите на уровне приложения (он должен переживать открытие/закрытие
экрана чата). Рядом создайте `LivetexChatPush`:

```dart
final chat = LivetexChat(LivetexChatConfig(touchPoint: '<ваш ключ>'));

final push = LivetexChatPush(
  chat: chat,
  onNotificationTap: () {
    // Открыть экран чата. Используйте GlobalKey<NavigatorState>,
    // т.к. тап может прийти когда виджет-дерево ещё не построено.
  },
);
await push.initialize();
```

`initialize()` сам: запросит разрешение на уведомления (системный диалог),
получит device-token и передаст его в LiveTex, подпишется на входящие push и
на жизненный цикл приложения (разрыв сокета при сворачивании).

При завершении — `await push.dispose()`.

---

## 3. Настройка доставки push

### Вариант A — свой сервер (рекомендуется LiveTex)

Вы присылаете в LiveTex URL вашего сервера. LiveTex шлёт на него вебхук с JSON
при новом сообщении оператора, когда соединение с приложением прервано:

| Поле | Тип | Обяз. | Описание |
|---|---|---|---|
| `version` | string | + | Версия протокола (сейчас `1`) |
| `platform` | string | + | `ios` или `android` |
| `to` | string | + | device-token устройства (FCM-токен / APNS-токен) |
| `text` | string | − | Текст сообщения |
| `url` | string | − | Ссылка на файл |

Ваш сервер на основе этих данных сам отправляет push в FCM/APNS.

**Плюс:** вы не передаёте третьей стороне ключи; полный контроль над содержимым.

### Вариант B — LiveTex шлёт push напрямую

#### Android (FCM)

1. Создайте проект в [Firebase Console](https://console.firebase.google.com/)
   (или используйте существующий).
2. Добавьте Android-приложение с вашим `applicationId`, скачайте
   `google-services.json` → положите в `android/app/google-services.json`.
3. В `android/settings.gradle(.kts)` в блок `plugins`:
   `id "com.google.gms.google-services" version "4.4.2" apply false`
4. В `android/app/build.gradle(.kts)` в блок `plugins`:
   `id "com.google.gms.google-services"`
5. В Firebase Console → Настройки проекта → **Сервисные аккаунты** → создайте
   закрытый ключ (скачается `.json`). Отправьте этот `.json` на
   **support@livetex.ru**, указав ваш ключ разработчика / идентификатор аккаунта
   LiveTex.

#### iOS (APNS)

LiveTex отправляет push на iOS через APNS напрямую. При этом Flutter-SDK
использует `firebase_messaging` для получения APNS-токена устройства, поэтому
iOS-приложению нужен и Firebase, и APNS-сертификат у LiveTex:

1. В Firebase Console добавьте iOS-приложение, скачайте `GoogleService-Info.plist`
   → добавьте в `ios/Runner/` через Xcode.
2. В Xcode для таргета Runner включите capability **Push Notifications** и
   **Background Modes → Remote notifications**.
3. Создайте APNS-сертификат (CSR в Keychain Access → App ID с capability
   Push Notifications в Apple Developer → APNS SSL Certificate → экспорт `.p12`
   с паролем). Подробная пошаговая инструкция — в KB LiveTex, раздел
   «SDK для iOS → Push нотификации».
4. Отправьте `.p12` + пароль на **support@livetex.ru**, указав ваш ключ
   разработчика / идентификатор аккаунта и профиль (development/Sandbox или
   production).

> Передача FCM-ключа / APNS-сертификата в LiveTex — это шаг настройки на стороне
> LiveTex; полные инструкции и скриншоты — в базе знаний LiveTex (разделы
> «SDK для Android» и «SDK для iOS», подраздел «Push нотификации»).

---

## 4. Проверка

1. Соберите приложение на физическом устройстве (push не работает на эмуляторе
   без Google Play / на iOS-симуляторе).
2. Откройте экран чата — в трейсе (`LivetexChatConfig.trace`) убедитесь, что в
   auth уходит `deviceToken=…`.
3. Сверните приложение — в трейсе появится `ws_done` (сокет разорван).
4. Пусть оператор ответит из консоли LiveTex.
5. На устройстве появится push с текстом ответа; тап по нему открывает чат.

> На iOS APNS-токен обычно не готов в момент старта приложения — первый `auth`
> может уйти без `deviceToken`, а когда токен появится, SDK сделает повторный
> `auth` уже с `deviceToken=…`. Два запроса `auth` подряд в трейсе — это
> нормально.
