# livetex_chat

Dart‑библиотека для клиента **LiveTex Visitor API** (удобно подключать из Flutter и из чистого Dart): авторизация по HTTP (Visitor‑Auth), сессия по **WebSocket** (Visitor‑API), multipart‑загрузка файлов. Реализовано поверх официальных типов сообщений из репозитория Visitor‑API (Scala сервер не входит в пакет — это только клиент).

**Версия пакета:** см. [`pubspec.yaml`](pubspec.yaml).

Документация по использованию библиотеки — **только этот файл**. Папки `example/` в пакете нет.

---

## Содержание

1. [Возможности и ограничения](#возможности-и-ограничения)  
2. [Зависимости](#зависимости)  
3. [Подключение](#подключение)  
4. [Обзор потока: auth → WS → сообщения](#обзор-потока-auth--ws--сообщения)  
5. [Справочник API](#справочник-api)  
6. [Протокол WebSocket: типы `type`](#протокол-websocket-типы-type)  
7. [Загрузка файлов](#загрузка-файлов)  
8. [Модели входящих сообщений](#модели-входящих-сообщений)  
9. [Ошибки и отладка](#ошибки-и-отладка)  
10. [Ссылки и связанные материалы](#ссылки-и-связанные-материалы)

---

## Возможности и ограничения

| Да | Нет / осторожно |
|----|-------------------|
| `GET …/v1/auth` и разбор [`AuthResult`](#authresult) | Не включает нативный Android/iOS SDK LiveTex (только Visitor API по сети) |
| Подключение к `endpoints.ws` из ответа auth | Полноценная **Web**‑сборка приложения может конфликтовать с **`import dart:io`** при использовании `uploadMultipartFile` в том же изоляте — см. [Загрузка файлов](#загрузка-файлов) |
| Отправка всех поддерживаемых типов сообщений клиента через [`VisitorOutgoing`](#visitoroutgoing) | Бинарные кадры WebSocket не поддерживаются (ожидается текстовый JSON) |
| Разбор входящих сообщений через [`parseServerMessage`](#parsemessageraw) | Протокол расширяется на сервере — неизвестные типы приходят как [`VisitorUnknownMessage`](#visitorunknownmessage) |
| Multipart upload с `Authorization: Bearer {visitorToken}`; поле части по умолчанию **`fileUpload`** | Идемпотентность и ретраи на стороне клиента не встроены |

---

## Зависимости

| Пакет | Назначение |
|-------|------------|
| [`http`](https://pub.dev/packages/http) | HTTP `GET` авторизации, `MultipartRequest` для upload |
| [`web_socket_channel`](https://pub.dev/packages/web_socket_channel) | WebSocket-клиент |

Транзитивно тянутся зависимости этих пакетов.

---

## Подключение

### Локально (монорепо Visitor‑API)

```yaml
dependencies:
  livetex_chat:
    path: livetex-flutter-plugin/packages/livetex_chat
```

Путь укажи относительно `pubspec.yaml` твоего приложения.

### После выноса в отдельный репозиторий

- `git:` URL с веткой/тегом, или  
- опубликованная версия на [pub.dev](https://pub.dev) (когда будет).

Далее:

```bash
flutter pub get
# или
dart pub get
```

---

## Обзор потока: auth → WS → сообщения

1. **Авторизация** — `livetexVisitorAuthenticate` или `LivetexVisitorSession.connect` вызывают `GET` на URL вида `…/v1/auth` с query-параметрами (обязателен `touchPoint`).  
2. В ответе JSON: `visitorToken`, `endpoints.ws`, `endpoints.upload`, `settings.fileTransferring`.  
3. **WebSocket** — подключение к `endpoints.ws` (в URL уже зашит путь с токеном).  
4. **Обмен** — клиент шлёт JSON-строки (удобно через [`VisitorOutgoing`](#visitoroutgoing)), сервер шлёт JSON; разбор через [`parseServerMessage`](#parsemessageraw) (уже встроен в [`LivetexVisitorSession.messages`](#livetexvisitorsession)).  
5. **Файл** — сначала `POST` multipart на `endpoints.upload`, затем в сокет сообщение `type: file` с URL из ответа upload.

Подробный пример см. в разделе [Быстрый пример](#быстрый-пример).

---

## Справочник API

### `livetexVisitorAuthenticate`

Асинхронный вызов Visitor‑Auth: один HTTP `GET`, при успехе возвращает [`AuthResult`](#authresult).

**Сигнатура (основное):**

```dart
Future<AuthResult> livetexVisitorAuthenticate({
  required Uri authEndpoint,
  required String touchPoint,
  http.Client? httpClient,
  String? visitorToken,
  String? customVisitorToken,
  String? deviceToken,
  String? deviceType,
  Map<String, String> headers = const {},
});
```

| Параметр | Обязателен | Описание |
|----------|------------|----------|
| `authEndpoint` | да | Полный URI эндпоинта, например `https://visitor-api.livetex.ru/v1/auth`. Query к существующим полям URL будут **заменены** на параметры ниже. |
| `touchPoint` | да | Идентификатор точки входа (строка из настроек LiveTex, часто вид `id:uuid`). |
| `httpClient` | нет | Свой клиент для тестов/прокси; если `null`, создаётся временный и закрывается после запроса. |
| `visitorToken` | нет | Повторная сессия того же посетителя. |
| `customVisitorToken` | нет | Редкий сценарий шардирования на стороне сервера (см. Visitor‑Auth). |
| `deviceToken` | нет | Токен устройства (push и т.п.), если используется. |
| `deviceType` | нет | Например `android`, `ios`. |
| `headers` | нет | Дополнительные HTTP-заголовки. |

**Исключения:** [`LivetexVisitorAuthException`](#исключения) при статусе ≠ 200.

---

### `LivetexVisitorSession`

Сессия WebSocket + доступ к полям [`auth`](#authresult) для upload.

#### Статические / фабрики

| Метод | Описание |
|-------|----------|
| `static Future<LivetexVisitorSession> connect({…})` | Выполняет [`livetexVisitorAuthenticate`](#livetexvisitorauthenticate) с переданными `authEndpoint`, `touchPoint` и прочими параметрами, затем [`open`](#factory-livetexvisitorsessionopenauthresult-auth). |
| `factory LivetexVisitorSession.open(AuthResult auth)` | Подключается к `auth.endpoints.ws` без повторного HTTP auth. |

#### Свойства и методы

| Член | Тип / возврат | Описание |
|------|----------------|----------|
| `auth` | `AuthResult` | Результат последней авторизации (токен, URL, настройки). |
| `messages` | `Stream<VisitorServerMessage>` | Текстовые кадры сокета, пропущенные через [`parseServerMessage`](#parsemessageraw). |
| `rawMessages` | `Stream<String>` | Сырые текстовые кадры (без парсинга). |
| `sendRawJson(String json)` | `void` | Отправка строки по WebSocket (уже готовый JSON). |
| `uploadMultipartFile({…})` | `Future<String>` | См. [Загрузка файлов](#загрузка-файлов). Тело ответа как строка (обычно URL файла). |
| `close()` | `Future<void>` | Закрытие подписки, контроллера и сокета. |

---

### `VisitorOutgoing`

Статические билдеры **исходящих** JSON-строк для WebSocket. Каждый метод возвращает `String` — передай в `session.sendRawJson(…)`.

Все сообщения содержат поле `type` и, кроме особых случаев, `correlationId` (строка-идентификатор операции на стороне клиента; должен быть уникален в рамках логики приложения).

| Метод | `type` в JSON | Параметры |
|-------|----------------|-----------|
| `text` | `text` | `correlationId`, `content` |
| `typing` | `typing` | `correlationId`, `content` (по умолчанию `""`) |
| `department` | `department` | `correlationId`, `id` (id отдела) |
| `attributes` | `attributes` | `correlationId`, опционально `name`, `phone`, `email`, обязательно `attributes` (`Map<String, String>`) |
| `file` | `file` | `correlationId`, `name`, `url` (URL после успешного upload) |
| `getHistory` | `getHistory` | `correlationId`, `messageId`, `offset` |
| `rating` | `rating` | `correlationId`, `rateType`, `value`, опционально `comment`. В JSON вложенный объект `rate: { type, value }`. Типы на сервере: например `doublePoint`, `fivePoint` (см. бэкенд). |
| `buttonPressed` | `buttonPressed` | `correlationId`, `payload` (строка с кнопки клавиатуры) |

Пример:

```dart
session.sendRawJson(
  VisitorOutgoing.text(correlationId: 'c1', content: 'Привет'),
);
```

---

### `parseServerMessage`

```dart
VisitorServerMessage parseServerMessage(String raw);
```

- Пытается `jsonDecode(raw)`.  
- При ошибке декодирования возвращает [`VisitorRawText`](#visitorrawtext).  
- При неизвестном `type` — [`VisitorUnknownMessage`](#visitorunknownmessage) с исходной `Map`.  
- При ошибке разбора известного типа — тоже `VisitorUnknownMessage` с данными (устойчивый режим).

Используется внутри `LivetexVisitorSession`; можно вызывать вручную для тестов или при работе с [`rawMessages`](#livetexvisitorsession).

---

### `tryParseServerDate`

Парсинг дат в полях сервера (формат Joda/ISO с суффиксом смещения без двоеточия). Возвращает `DateTime?`. Используется внутри моделей `Update` / сообщений.

---

### `AuthResult`

Тело ответа `GET /v1/auth`.

| Поле | Тип | Описание |
|------|-----|----------|
| `visitorToken` | `String` | Токен посетителя; используется в Bearer при upload и в пути WS. |
| `endpoints` | `AuthEndpoints` | `ws`, `upload`. |
| `settings` | `AuthSettings` | Например `fileTransferring`. |

#### `AuthEndpoints`

- `ws` — полный URL WebSocket.  
- `upload` — базовый URL POST multipart (без обязательного суффикса имени файла).

#### `AuthSettings`

- `fileTransferring` — разрешена ли передача файлов на точке.

---

## Протокол WebSocket: типы `type`

### От сервера (входящие)

| Значение `type` | Dart-класс (после разбора) |
|-----------------|----------------------------|
| `state` | `VisitorDialogState` |
| `update` | `VisitorUpdate` |
| `result` | `VisitorResult` |
| `error` | `VisitorApiError` |
| `attributesRequest` | `VisitorAttributesRequest` |
| `departmentRequest` | `VisitorDepartmentRequest` |
| `employeeTyping` | `VisitorEmployeeTyping` |

Иные значения попадают в `VisitorUnknownMessage`.

### От клиента (исходящие)

Соответствуют методам [`VisitorOutgoing`](#visitoroutgoing): `text`, `file`, `typing`, `department`, `attributes`, `getHistory`, `rating`, `buttonPressed`.

Полное соответствие полей — в исходниках сервера `visitor-api` (пакеты `incoming` / `outgoing`).

---

## Загрузка файлов

```dart
Future<String> uploadMultipartFile({
  required File file,
  http.Client? httpClient,
  String? filenameSuffixPath,
  String fileFieldName = 'fileUpload',
  Uri? uploadBaseOverride,
})
```

| Параметр | Описание |
|----------|----------|
| `file` | Локальный файл (`dart:io`). |
| `httpClient` | Опционально свой HTTP-клиент. |
| `filenameSuffixPath` | Если не пустой, путь дополняется: `{upload}/{encodedSegment}` для варианта с именем в URL (как на сервере `…/upload/{filename}`). |
| `fileFieldName` | Имя части multipart (по умолчанию **`fileUpload`**, как у file‑service Visitor‑API). Для совместимости со старым моком и т.п. передайте `file`. |
| `uploadBaseOverride` | Подмена базового URL upload. |

Заголовок: **`Authorization: Bearer ${auth.visitorToken}`**.

Метод: **POST**, тело multipart.

**Ответ:** тело успешного ответа как `String` (часто URL); его передают в [`VisitorOutgoing.file`](#visitoroutgoing).

**Поведение имён (важно для прод-сервисов):**

- В заголовке multipart параметр `filename=` подбирается **только из ASCII** (кириллица и прочий Unicode в теле multipart часто ломают разбор на стороне сервиса). Логическое имя с кириллицей по-прежнему можно передать в **`filenameSuffixPath`** (сегмент пути `…/upload/{encoded}`) и в поле **`name`** сообщения WebSocket `type: file`.
- Если задан **`filenameSuffixPath`**, хвост **`.jpeg` / `.jpg`** (любой регистр) перед запросом нормализуется к **`.jpg`** — многие белые списки расширений содержат только `jpg`.
- Проверка **`fileExtensionNotAllowed`** на стороне Visitor‑API делается по **расширению из `url`** входящего сообщения `file`, а не по полю `name` — URL после upload должен давать распознаваемое расширение.

Ограничение: нужен **`dart:io.File`**. Для Web обычно делают отдельный слой загрузки (bytes + `MultipartFile.fromBytes`) в другом таргете через conditional imports — в текущей версии пакета этого нет в публичном API.

---

## Модели входящих сообщений

Базовый тип: **`sealed class VisitorServerMessage`**.

| Класс | Назначение |
|-------|------------|
| `VisitorRawText` | Кадр не JSON. |
| `VisitorUnknownMessage` | JSON без поддержанного `type` или ошибка разбора. |
| `VisitorDialogState` | Статус диалога, сотрудник, `showInput`, рейтинг и т.д. |
| `VisitorUpdate` | Пачка элементов истории (`TextUpdatePayload`, `FileUpdatePayload`). |
| `VisitorResult` | Ack/Nack операции по `correlationId`, опционально `sentMessage`, список строк ошибок. |
| `VisitorApiError` | Ошибка уровня API (`code`). |
| `VisitorAttributesRequest` | Нужно отправить атрибуты. |
| `VisitorDepartmentRequest` | Список отделов `DepartmentItem` для выбора. |
| `VisitorEmployeeTyping` | Индикатор набора текста оператором. |

Вложенные модели (`CreatorModel`, `ButtonPayload`, `KeyboardPayload`, рейтинг и т.д.) см. в [`lib/src/server_messages.dart`](lib/src/server_messages.dart).

---

## Ошибки и отладка

### Исключения

| Класс | Когда |
|-------|-------|
| `LivetexVisitorAuthException` | HTTP auth не `200`; поля `statusCode`, `body`. |
| `LivetexVisitorUploadException` | Upload не `200`; `statusCode`, `body`. |

### Логирование и сеть

Библиотека **не** пишет логи сама — оборачивай `messages` и HTTP в свой логгер. Для тестов передай свой `http.Client` (recording/mock).

---

## Быстрый пример

```dart
import 'package:livetex_chat/livetex_chat.dart';

Future<void> visitorClientSample() async {
  final session = await LivetexVisitorSession.connect(
    authEndpoint: Uri.parse('https://visitor-api.livetex.ru/v1/auth'),
    touchPoint: 'ВАША_СТРОКА_TOUCHPOINT',
    deviceType: 'android',
    deviceToken: '',
  );

  final sub = session.messages.listen((msg) {
    // switch (msg) { ... }
  });

  session.sendRawJson(
    VisitorOutgoing.text(correlationId: 'msg-1', content: 'Привет'),
  );

  await sub.cancel();
  await session.close();
}
```

---

## Отладка

`LivetexChatConfig.trace` / `traceRedactTokens`, `LivetexChat.collectSupportReport()`, экспорт `livetex_trace` из `livetex_chat.dart`.

## Ссылки и связанные материалы

- Документация продукта: [Visitor‑API Websocket](https://support.livetex.ru/hc/ru/articles/360010723098-Visitor-API), [Android](https://support.livetex.ru/hc/ru/articles/360011083338-LiveTex-для-Android), [iOS](https://support.livetex.ru/hc/ru/articles/360010974937-LiveTex-для-iOS).  
- Пример авторизации curl — корневой [`README.md`](../../../README.md) репозитория Visitor‑API.  
- Дополнительно по сигнатурам: в каталоге пакета `dart doc` (выход в `doc/api`); после публикации на pub.dev — автогенерируемая страница API.

---

## Лицензия

См. файл [`LICENSE`](LICENSE) в пакете.
