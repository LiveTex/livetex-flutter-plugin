# `livetex_chat` (core) — задачи для разработчиков LiveTex

Этот документ — **внутренний**, для разработчиков, которые пилят сам SDK. Здесь:
- что я (Flutter-UI-инициатива) уже трогал в core в ветке `fix/ui-and-protocol-alignment` и почему,
- что осталось доделать на стороне core, нормальным языком с обоснованием.

Документ для внешних разработчиков (тех, кто встраивает SDK в своё приложение) — отдельный, см. `docs/INTEGRATION.md`.

---

## Часть 1. Что я уже изменил в core (и почему вышел за UI)

Изначальная договорённость была — править только `packages/livetex_chat_ui`. По ходу полевых тестов выяснилось, что несколько багов невозможно вылечить из UI: нужны фиксы в `packages/livetex_chat`. Их я сделал в той же ветке. Описаны ниже, чтобы при ревью было понятно зачем.

### 1.1. `pingInterval: 10s` на WebSocket
**Файл:** `packages/livetex_chat/lib/src/api/visitor_client.dart` (коммит `ab74875`).

**Было:** `WebSocketChannel.connect(uri)` — кроссплатформенный сокет без keep-alive.

**Стало:** `IOWebSocketChannel.connect(uri, pingInterval: Duration(seconds: 10))`.

**Зачем:** на устройстве воспроизводился сценарий — спустя ~1.5 минуты тишины на стороне клиента сервер (или прокси/NAT/Cloudflare) тихо закрывал WebSocket. Наш `sink.add(...)` продолжал «успешно» класть фреймы в drained-соединение, сервер не отвечал, `onDone` не срабатывал, реконнект не запускался. С `pingInterval` каждые 10 сек шлётся протокольный ping; если pong не возвращается — `dart:io WebSocket` явно abort'ит сокет, наш `onDone` срабатывает, существующий `_scheduleReconnect()` подхватывает.

**Совпадает с native** `sdk-android/OkHttpManager.java:19`: `WEBSOCKET_PING_INTERVAL = 10_000L`. На iOS сокет на `URLSessionWebSocketTask` имеет аналогичный keep-alive поверх системного протокола.

### 1.2. `ChatMessage.avatarUrl` и `ChatMessage.creatorType`
**Файл:** `packages/livetex_chat/lib/src/domain/chat_message.dart` + маппинг в `livetex_chat.dart` (коммит `2dab0dc`).

**Было:** `ChatMessage` имел только `creatorLabel: String?` ("Бот" / "Система" / имя оператора). UI был вынужден определять системные сообщения через сравнение строки (`creatorLabel == "Система"`), а аватары оператора рендерил иконкой-заглушкой.

**Стало:** Добавлены два поля:
- `creatorType: String?` — сырой `creator.type` из Visitor-API: `"visitor"` / `"employee"` / `"bot"` / `"system"`. Используется для поведенческих решений (рендер system-message без бабла).
- `avatarUrl: String?` — `creator.employee.avatarUrl`. Используется для отрисовки реального аватара оператора.

**Зачем:** старая проверка по локализованной строке ломалась при любой смене текста (другой бренд / другой язык). Аватары оператора — базовая фича native sdk-ui, она невозможна без передачи URL до слоя UI.

### 1.3. Outbound trace для отладки
**Файл:** `packages/livetex_chat/lib/src/livetex_chat.dart` (коммит `4d00f66`).

**Было:** `livetexTrace` логировал только входящие фреймы (`ws_in {...}`). Невозможно было понять «фрейм ушёл и сервер молчит» vs «фрейм даже не отправлен».

**Стало:** в `sendRating`, `sendText`, `sendFile`, `selectDepartment` перед `sink.add(...)` логируем `ws_out {json}`. Также печатается `sendXxx SKIPPED (no session)`, если `_session == null` (silent no-op случай).

**Зачем:** ровно эти трейсы позволили поймать корневую причину бага «оценка после закрытия диалога не доходит» (оказался UI-баг с merge partial state-update — см. коммит `c8068c4`).

Можно оставить как постоянную диагностику — оверхед нулевой (печать включается только при `config.trace != null`), польза при следующих проблемах — мгновенная.

### 1.4. `dependency_overrides: path: ../livetex_chat` в UI pubspec
**Файл:** `packages/livetex_chat_ui/pubspec.yaml` (коммит `4d00f66`).

**Было:** UI тянул core через `git: ref master`. Локальные правки core не подхватывались до merge ветки в master.

**Стало:** `dependency_overrides` указывает на локальный path. Это **временный** костыль для тестирования.

**Зачем убрать после merge ветки:** см. п. 2.1 ниже — целевое решение это поменять основную `dependencies.livetex_chat` на `path:` (с melos-managed overrides для publish).

---

## Часть 2. Что осталось доделать на стороне core

### 2.1. Persist visitorToken между подключениями
**Связано с:** «после reconnect / возврата из background бот молчит и rating не уходит».

**Что сейчас:** при каждом `connect()` (включая reconnect внутри `_scheduleReconnect`) в `_openSession()` передаётся `config.visitorToken` — то, что лежит в исходном конфиге (обычно `null` или сохранённый снаружи user-token). Сервер выдаёт в auth-ответе новый/обновлённый `visitorToken`, мы его **выкидываем**.

**Что происходит на бэке:** Visitor-API использует sticky-routing — визитёрская сессия привязана к конкретной ноде (`visitor-api-i1-04.livetex.ru`). Привязка идёт по persistent `visitorToken`, который выдаётся серверной стороной. Если мы передаём другой/пустой токен, auth-сервер может выдать **другой** ws-endpoint на другой ноде, на которой нашей dialog-сессии нет — бот не знает контекста, rating падает в пустоту.

**Что нужно сделать:**

```dart
class LivetexChat {
  String? _lastVisitorToken;

  Future<void> _openSession() async {
    // ...
    final auth = await livetexVisitorAuthenticate(
      // ...
      visitorToken: _lastVisitorToken ?? config.visitorToken,
    );
    _lastVisitorToken = auth.visitorToken;  // <— главное
    // ...
  }
}
```

Этого in-memory варианта достаточно для решения «reconnect внутри сессии приложения». Между запусками приложения помогает только cross-session persistence (см. 2.2).

**Как именно проверено в native:** `sdk-ui-android/ChatViewModel.java:472-495` достаёт `visitorToken` из `SharedPreferences` и при первом успешном auth сохраняет туда же выданный сервером токен:

```java
String visitorToken = sp.getString(Const.KEY_VISITOR_TOKEN, null);
authData = AuthData.withVisitorToken(visitorToken);
// ...
.subscribe(visitorTokenReceived -> {
    sp.edit().putString(Const.KEY_VISITOR_TOKEN, visitorTokenReceived).apply();
});
```

### 2.2. Cross-session persistence visitorToken (callbacks в `LivetexChatConfig`)
**Связано с:** «после force-quit и нового запуска приложения визитёр стартует с нуля, переписка пропадает (хотя на сервере она есть)».

**Что нужно:** дать клиентскому приложению возможность сохранить `visitorToken` между запусками. Не делать это в самом core (он не должен зависеть от `shared_preferences`/`flutter_secure_storage`), а через callbacks:

```dart
class LivetexChatConfig {
  // ...
  /// Called once on first `connect()` to load a previously persisted
  /// visitor token. Return null for a brand-new visitor.
  final Future<String?> Function()? loadPersistedVisitorToken;

  /// Called after every successful auth response. The host app is
  /// expected to write `token` to whatever persistent storage it uses
  /// (shared_preferences, flutter_secure_storage, ...). Optional —
  /// without it the token survives only the current app process.
  final Future<void> Function(String token)? savePersistedVisitorToken;
}
```

Клиентское приложение тогда делает:

```dart
final cfg = LivetexChatConfig(
  touchPoint: '...',
  loadPersistedVisitorToken: () => prefs.getString('lt_visitor_token'),
  savePersistedVisitorToken: (t) => prefs.setString('lt_visitor_token', t),
);
```

**Совпадает с native sdk-ui** (`ChatViewModel.java:472-495` — там это `SharedPreferences`-round-trip).

### 2.3. `Future<SendResult>` из `send*` методов
**Связано с:** UI-таймер 10 секунд в `rating_widget.dart` как «safety net» — потому что send-методы void и не возвращают результат отправки.

**Что сейчас:**
```dart
void sendRating({required String rateType, required String value, String? comment});
void sendAttributes(...);
void selectDepartment(...);
```

Все three — fire-and-forget. UI отправляет фрейм и слепо ждёт когда сервер обновит `dialogState` с `rate.isSet`. Если сервер не ответит — крутится прелоадер. Мы прикрутили 10s таймер в UI как костыль.

**Что нужно сделать:** изменить возвращаемый тип:

```dart
sealed class SendResult {
  const SendResult();
}
class SendSuccess extends SendResult { /* server result frame */ }
class SendError extends SendResult { final String code; final String message; ... }
class SendTimeout extends SendResult { ... }

Future<SendResult> sendRating({...});
Future<SendResult> sendAttributes({...});
Future<SendResult> selectDepartment({...});
```

Реализация — повесить future на `correlationId` и резолвить из `_onServerMessage` когда придёт `result` с тем же correlationId. С таймаутом ~15 сек на стороне core.

**После этого** UI уберёт 10s safety-net в `rating_widget.dart` и снэкбары станут точнее («сервер вернул ошибку X» вместо общего «попробуйте ещё раз»).

### 2.4. Зависимость `livetex_chat` через `path:` вместо `git:`
**Файл:** `packages/livetex_chat_ui/pubspec.yaml`.

**Что сейчас:**
```yaml
dependencies:
  livetex_chat:
    git:
      url: https://github.com/LiveTex/livetex-flutter-plugin.git
      path: packages/livetex_chat
```

И мой временный `dependency_overrides: path:` рядом.

**Что нужно:**
```yaml
dependencies:
  livetex_chat:
    path: ../livetex_chat
```

И в `melos.yaml` (если ещё нет):
```yaml
command:
  bootstrap:
    usePubspecOverrides: true
```

**Зачем:** локальные правки в `packages/livetex_chat` тогда сразу подхватываются UI без manual override. При публикации в pub.dev melos сам подменит `path:` на `version:`.

После этого мой `dependency_overrides` из 1.4 надо удалить.

### 2.5. Дедуп / флаг «вся история загружена» в `loadHistory`
**Связано с:** P5 из design-doc — пагинация чанками по 20.

**Что сейчас:** UI вызывает `_chat.loadHistory(messageId: oldest.id, offset: 20)` каждый раз когда пользователь долистывает до верха. Нет флага «больше нет», нет дедупа.

**Что нужно:** в `LivetexChat`:
- хранить флаг `bool _historyExhausted = false` (выставляется когда сервер возвращает меньше 20 сообщений в ответ на `loadHistory`),
- exposить как `chat.canLoadMoreHistory: bool`,
- дедуп по `id` уже есть на уровне `_byId.upsert`, но стоит убедиться что повторный загруженный чанк не сбивает `_order`.

UI после этого скрывает индикатор «загрузка истории» когда `canLoadMoreHistory == false`.

### 2.6. Reconnect race: `connect()` не отменяет активный `_reconnectTimer`
**Связано с:** обнаружено логическим аудитом ветки. UI частично закрыл (auto-reconnect теперь срабатывает только при `_conn == disconnected`), но core всё равно остаётся уязвим, если кто-то вызовет `connect()` снаружи в неудачный момент.

**Что происходит сейчас:** `connect()` (`livetex_chat.dart:103-106`) выставляет `_disconnectRequested = false` и сразу же зовёт `_openSession()`. Активный `_reconnectTimer` НЕ отменяется. Если приложение свернули посередине 30-секундного backoff, а потом разверyнули, `connect()` запускает новую сессию мгновенно — а потом ещё и timer фaerит через секунды и запускает **вторую** сессию. Старая и новая работают параллельно, `_session` перезаписывается посередине жизни первой, её `onDisconnected` срабатывает позже и шедулит ещё один reconnect. Каскад дублей сообщений и зомби-сессий.

**Что нужно:** в `connect()` (и в `_scheduleReconnect`) первой строкой отменять активный таймер:
```dart
Future<void> connect() async {
  _disconnectRequested = false;
  _reconnectTimer?.cancel();
  _reconnectTimer = null;
  await _openSession();
}
```

И ещё хорошо бы guard внутри `_openSession()` — если `_connNow == connecting`, no-op. Это защитит от двух concurrent connect() даже если внешний код их вызывает.

### 2.7. Pending-сообщения «зависают» в `sending` после reconnect навсегда
**Связано с:** обнаружено логическим аудитом ветки.

**Что происходит сейчас:** `sendText` / `sendFile` вставляют оптимистическую строку `ChatMessage(id: "pending:$corr", sendState: sending)` в `_byId` / `_order`. Реальный `id` приходит от сервера в `VisitorResult` через подписку `_msgSub`. При reconnect `_openSession()` отменяет `_msgSub` и заменяет `_session` — старая подписка мертва. Если `result` для отправленного фрейма приходит **после** этой точки (или не приходит вовсе из-за того что отправлялось в drained socket), pending-строка уже не получит свой id и навечно зависнет с спиннером.

**Что нужно:** в `_openSession()` (или в `_onSocketDone()`) перед очисткой `_msgSub` пройти `_byId` и пометить все строки с ключом `pending:*` как `failed`:

```dart
void _markPendingAsFailed() {
  var changed = false;
  for (final entry in _byId.entries) {
    if (entry.key.startsWith("pending:") &&
        entry.value.sendState == ChatMessageSendState.sending) {
      _byId[entry.key] = entry.value.copyWith(
        sendState: ChatMessageSendState.failed,
      );
      changed = true;
    }
  }
  if (changed) _emitMessages();
}
```

Зовётся первой строкой в `_openSession()` и в `_onSocketDone()`. UI после этого корректно покажет «failed» иконку (она у нас уже рендерится), а в будущем — кнопку tap-to-resend.

### 2.8. Состояние `reconnecting` — мёртвый код
**Связано с:** обнаружено и логическим, и quality-аудитами.

**Что происходит сейчас:** в `_openSession()` идёт `_session = null` строкой 115, а на следующей же строке тернарник `_session == null ? connecting : reconnecting` — условие всегда true. `_setConn(reconnecting)` никогда не вызывается, и состояние `LivetexConnectionState.reconnecting` фактически невозможно увидеть из стрима.

**Что нужно:**
```dart
final wasConnected = _session != null;
await _session?.close();
_session = null;
_setConn(wasConnected
    ? LivetexConnectionState.reconnecting
    : LivetexConnectionState.connecting);
```

После этого UI сможет отличать первичное подключение от переподключения (например, разные тексты в баннере).

### 2.9. Backoff при `tooManyRequests`
**Связано с:** P9 из design-doc.

**Что сейчас:** если сервер ответил `ApiError.code = "tooManyRequests"`, мы это просто эмитим как ошибку. Следующая отправка может пойти моментально.

**Что нужно:** в `LivetexChat` ввести небольшую очередь исходящих с pacing, и при получении `tooManyRequests` — увеличить интервал между отправками экспоненциально (3 → 6 → 12 сек) с автосбросом после успешной серии.

Не блокер, но при write-heavy сценариях защитит от штормов.

---

## Часть 3. Сводная таблица

| # | Что | Где | Приоритет | Что разблокирует |
|---|---|---|---|---|
| 2.1 | In-memory `_lastVisitorToken` + использовать на reconnect | `LivetexChat._openSession` | **Высокий** | Перестанет «бот молчит после background» |
| 2.2 | Callbacks `load/savePersistedVisitorToken` в `LivetexChatConfig` | `LivetexChatConfig` | Средний | Переписка переживает рестарт приложения |
| 2.3 | `Future<SendResult>` из `send{Rating,Attributes,Department}` | `LivetexChat` | Средний | Снимет 10s safety-net таймер в UI |
| 2.4 | `git:` → `path:` в UI pubspec | `livetex_chat_ui/pubspec.yaml` | Низкий (после merge ветки) | Уберёт мой `dependency_overrides` |
| 2.5 | `canLoadMoreHistory` + флаг исчерпания | `LivetexChat.loadHistory` | Низкий | Корректное поведение при долгой истории |
| 2.6 | `connect()` отменяет `_reconnectTimer`; guard на parallel-connect | `LivetexChat.connect` / `_openSession` | **Высокий** | Гонка двух сессий при background → resume в момент backoff |
| 2.7 | Помечать `pending:*` сообщения как `failed` перед сменой `_msgSub` | `LivetexChat._openSession` / `_onSocketDone` | **Высокий** | Сообщения в `sending` после reconnect не зависают навсегда |
| 2.8 | Корректно эмитить `reconnecting` (сейчас всегда `connecting`) | `LivetexChat._openSession:115-119` | Низкий | UI сможет отличать первичное подключение от reconnect |
| 2.9 | Backoff на `tooManyRequests` | `LivetexChat` | Низкий | Устойчивость к rate limit |

После 2.1, 2.3, 2.7 я (UI-сторона) сделаю последний cleanup-PR: уберу outbound trace из 1.3 (если будет принято решение что он избыточен), safety-net таймер из `rating_widget.dart`, и подключу tap-to-resend для `failed`-сообщений (нужен метод `LivetexChat.resendMessage(correlationId)`).

---

## Приложение А. Что обнаружил аудит ветки (как routed)

Полный отчёт security + logic + quality audits лежит в истории чата на разработке. Здесь только что куда пошло.

### Закрыто в этой же ветке (UI-сторона):
- SEC: scheme allowlist (`http`/`https` only) на `launchUrl` для button.url и file.url — закрывает intent-hijack / deep-link trigger через server-supplied URL.
- SEC: snackbar при провале `launchUrl` больше не показывает raw URL (минор phishing surface).
- SEC: `developer.log` в `_pickAndSendFile` теперь под `kDebugMode` — file names / sizes / paths не утекают в logcat в release-сборках.
- LOGIC: `_ratingMode` теперь lock'ается на первом же non-null rate (раньше — только если был `enabledType`, что ломало кейс «зашёл в уже оценённый диалог»).
- LOGIC: `_sendText` не очищает текстовое поле, если соединения нет (раньше — теряли сообщение).
- LOGIC: auto-reconnect на `AppLifecycleState.resumed` срабатывает только при `_conn == disconnected` (раньше — гонка с backoff timer).
- QUALITY: `LivetexChatTheme.copyWith` добавлен — host app может брендировать без копирования 43 аргументов.
- QUALITY: `attributes_form.dart` использует `theme.composerFieldStroke` вместо хардкода `#E5E5E5`.
- QUALITY: library-doc-комментарий на `livetex_chat_ui.dart`.

### Передано сюда (core / разработчики SDK):
- 2.6 — `connect()` не отменяет `_reconnectTimer`.
- 2.7 — pending-сообщения зависают после reconnect.
- 2.8 — `reconnecting` state мёртвый.
