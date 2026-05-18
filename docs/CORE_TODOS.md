# Что нужно поправить в `livetex_chat` (core-пакет)

Список изменений, которые **не могу сделать сам** в ветке `fix/ui-and-protocol-alignment`,
т.к. трогать core я не должен. Прошу разработчика проектного ядра внести их в свою ветку
и согласовать API; UI-пакет (`livetex_chat_ui`) подтянется без дополнительных правок.

Каждый пункт — отдельный, независимый. Можно делать в любом порядке.

---

## 1. UI не понимает, доставлен ли отправленный запрос на сервер

**Где:** `LivetexChat.sendRating`, `LivetexChat.sendAttributes`, `LivetexChat.selectDepartment`.

**Симптом:**
- В UI у нас локальный флаг `_submitting` в форме оценки, который сбрасывается, когда
  с сервера прилетает обновлённый `dialogState` (`isSet != null`).
- Если сеть лежит / отвал WebSocket / payload улетел в /dev/null — мы зависаем в
  состоянии «отправляю» бесконечно.
- Временное решение в UI — 10-секундный таймаут с показом snackbar «попробуйте ещё раз».
  Это плохо: пользователь не отличает «не отправилось» от «отправилось, но сервер тормозит».

**Что нужно:**
Сделать методы возвращающими `Future<...>`, который завершается:
- успешно — когда сокет подтвердил приём (или прилетел ответ с server-side id);
- с ошибкой — когда сокет в `disconnected`, либо вернулся error frame, либо timeout по слою.

Сигнатуры примерно так (имена результата на ваше усмотрение):

```dart
Future<SendResult> sendRating({
  required String rateType,
  required String value,
  String? comment,
});

Future<SendResult> sendAttributes({
  required String correlationId,
  String? name, String? phone, String? email,
  required Map<String, String> attributes,
});

Future<SendResult> selectDepartment({
  required String correlationId,
  required String id,
});
```

UI тогда уберёт «слепой» таймаут и будет ждать ответ от ядра, показывая прогресс /
ошибку строго по фактическому состоянию.

---

## 2. Нет надёжного способа определить системное сообщение

**Где:** `ChatMessage` (core), `MessageTile` (UI, `packages/livetex_chat_ui/lib/src/widgets/message_tile.dart`).

**Симптом:** в UI сейчас системность ловится сравнением строки лейбла автора:
```dart
bool get _isSystem => message.creatorLabel == "Система";
```
Это сломается при:
- любой смене текста (локализация, другой бренд);
- сообщении настоящего оператора, которого случайно назвали «Система»;
- системных сообщениях без `creatorLabel` (например, "Диалог закрыт").

**Что нужно:**
Добавить в `ChatMessage` поле `creatorType` (строка или enum), маппить его из
visitor-api поля `creator.type` (`system` / `employee` / `bot` / `visitor`).

```dart
class ChatMessage {
  ...
  /// Из visitor-api: "system" | "employee" | "bot" | "visitor".
  final String? creatorType;
  ...
}
```

UI заменит fragile-проверку на `message.creatorType == "system"` и сразу получит
корректное отображение системных уведомлений независимо от языка.

---

## 3. Зависимость `livetex_chat` через git, а не через path внутри монорепо

**Где:** `packages/livetex_chat_ui/pubspec.yaml`.

**Симптом:** `livetex_chat` подключён как:
```yaml
dependencies:
  livetex_chat:
    git:
      url: https://github.com/LiveTex/livetex-flutter-plugin.git
      path: packages/livetex_chat
      ref: master
```

Из-за этого:
- любая правка в `packages/livetex_chat` локально **не подхватывается** UI-пакетом — UI
  тянет master из удалённого репо;
- разработчику в этой же монорепе невозможно дебажить core+ui одновременно без ручного
  `pub override`;
- `melos bootstrap` не «склеивает» пакеты автоматически.

**Что нужно:**
Поменять на path-зависимость с melos-managed dependency overrides:

```yaml
dependencies:
  livetex_chat:
    path: ../livetex_chat
```

И добавить в `melos.yaml` секцию (если ещё нет) для авто-овeррайдов, чтобы публикация
наружу не ломалась:

```yaml
command:
  bootstrap:
    usePubspecOverrides: true
```

При публикации в pub.dev (если планируется) melos сам подменит path на version.

---

## 4. После reconnect бот молчит и оценка не отправляется (sticky-routing)

**Где:** `LivetexChat._openSession()` в `packages/livetex_chat/lib/src/livetex_chat.dart`.

**Симптом (воспроизведён на устройстве):**
1. Открыли чат, бот написал приветствие, нажимаем кнопки — бот отвечает, всё ок.
2. Wi-Fi off → on (или диалог идёт долго и сокет переподнялся сам).
3. После reconnect: `buttonPressed` фрейм уходит, сервер даже отвечает
   `{"type":"result", "correlationId":"btn-…", "error":[]}` — но **бот не присылает
   следующее сообщение**. `sendRating` уходит, но сервер вообще не отвечает на
   `rate-*` correlation id, и через 10 сек срабатывает наш safety-net snackbar
   «Не удалось подтвердить оценку».
4. Полный перезапуск приложения → всё снова работает корректно.

**Корневая причина:** Visitor-API использует sticky-routing — визитёрская сессия
живёт на конкретной ноде (`visitor-api-i1-04…`), и сервер привязывает её к
**persistent visitor token**, который выдаётся в первом `auth`-ответе. При
последующих подключениях этот же `visitorToken` должен передаваться в auth, чтобы
сервер вернул тот же `ws-endpoint` той же ноды.

Native sdk-ui это делает явно — `ChatViewModel:472-495` достаёт `visitorToken`
из `SharedPreferences` и при первом успешном auth сохраняет туда же выданный
сервером токен:

```java
String visitorToken = sp.getString(Const.KEY_VISITOR_TOKEN, null);
authData = AuthData.withVisitorToken(visitorToken);
...
.subscribe(visitorTokenReceived -> {
    sp.edit().putString(Const.KEY_VISITOR_TOKEN, visitorTokenReceived).apply();
});
```

В нашем `_openSession()` мы при **каждом** подключении передаём
`config.visitorToken` (то, что лежит в конфиге с момента создания `LivetexChat`).
Если в первом auth-ответе сервер выдал новый/обновлённый `visitorToken` — мы его
не сохраняем. На reconnect auth-сервер видит исходный токен (или null) и может
выдать новый ws-endpoint на другой ноде. На той ноде нашей dialog-сессии нет:
- бот не знает контекста → молчит на нажатия кнопок (хотя `result` шлёт);
- rating падает в пустоту, потому что rate-state живёт на старой ноде.

**Что нужно:**

1. В `LivetexChat` хранить `String? _lastVisitorToken` (in-memory достаточно).
   После каждого успешного auth обновлять его из `auth.visitorToken`.
2. В `_openSession()` передавать `visitorToken: _lastVisitorToken ?? config.visitorToken`,
   а не голый `config.visitorToken`.
3. (Опционально, но желательно) добавить callback в `LivetexChatConfig`:
   ```dart
   Future<String?> Function()? loadPersistedVisitorToken;
   Future<void> Function(String token)? savePersistedVisitorToken;
   ```
   Тогда host-app сможет сохранить токен между запусками приложения (через
   `shared_preferences`/`flutter_secure_storage`). Аналог native
   `Const.KEY_VISITOR_TOKEN` в SharedPreferences.

После #1-2 будет починен reconnect внутри сессии приложения. После #3 — и
переход между запусками приложения (бот будет помнить визитёра).

---

## Сводка

| # | Файл/символ | Что сделать |
|---|---|---|
| 1 | `LivetexChat.send{Rating,Attributes,…}` | Возвращать `Future<SendResult>` с success / error |
| 2 | `ChatMessage.creatorType` | Добавить поле, маппить из `creator.type` visitor-api |
| 3 | `packages/livetex_chat_ui/pubspec.yaml` | Поменять `git:` на `path: ../livetex_chat` |
| 4 | `LivetexChat._openSession()` | Сохранять выданный сервером `visitorToken` и переиспользовать его на reconnect (sticky-routing) |

После этих правок я уберу из UI:
- 10-секундный safety-net в `rating_widget.dart` (станет ненужным после #1 — Future вернёт ошибку быстрее, и причина "no reply from server after reconnect" из #4 исчезнет);
- fragile-проверку `creatorLabel == "Система"` в `message_tile.dart` (после #2).

И добавлю в README инструкцию по локальной разработке `melos bootstrap` (после #3).
