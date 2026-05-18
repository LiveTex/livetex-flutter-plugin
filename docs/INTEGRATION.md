# Интеграция LiveTex-чата во Flutter-приложение

Документ для разработчиков, которые встраивают LiveTex-чат в своё приложение на Flutter. Если ты разрабатываешь сам SDK — смотри `CORE_TODOS.md`.

## Содержание
1. [Минимальная интеграция за 3 строки](#1-минимальная-интеграция)
2. [Конфигурация: touchPoint, endpoints, on-premise](#2-конфигурация)
3. [Кастомизация внешнего вида (брендирование)](#3-кастомизация-внешнего-вида)
4. [Опциональность формы атрибутов](#4-форма-атрибутов)
5. [Push-уведомления](#5-push-уведомления)
6. [Жизненный цикл и persistence визитёра](#6-жизненный-цикл-и-persistence-визитёра)
7. [Низкоуровневый API (`livetex_chat`) без UI](#7-низкоуровневый-api-без-ui)
8. [FAQ и частые подводные камни](#8-faq-и-частые-подводные-камни)

---

## 1. Минимальная интеграция

В `pubspec.yaml`:
```yaml
dependencies:
  livetex_chat: ^X.Y.Z
  livetex_chat_ui: ^X.Y.Z
```

В коде:
```dart
import 'package:livetex_chat/livetex_chat.dart';
import 'package:livetex_chat_ui/livetex_chat_ui.dart';

Navigator.of(context).push(MaterialPageRoute(
  builder: (_) => LivetexChatScreen(
    config: LivetexChatConfig(
      touchPoint: 'XXX:YYYYY-YYYY-YYYY-YYYY-YYYYYYYYYYYY',
    ),
    title: 'Поддержка',
  ),
));
```

Всё. Подключение к Visitor-API, авторизация, восстановление сокета, отображение сообщений, кнопок бота, формы атрибутов, оценки — всё это уже внутри.

---

## 2. Конфигурация

### touchPoint
Идентификатор «точки контакта» на стороне LiveTex. Получается в личном кабинете LiveTex. Формат: `<id>:<uuid>`, например `168:8417b4fa-35a3-4799-a0d4-809fd0b7a8a8`.

Передаётся в `LivetexChatConfig.touchPoint`. **Это единственное обязательное поле конфига.**

### Где хранить touchPoint в реальном приложении

Не хардкодь — это публичный ключ, но публикация его в открытом коде нежелательна. Варианты:

**А. Compile-time через `--dart-define`** (подходит для production-сборок):
```dart
const _touchPoint = String.fromEnvironment('LT_TOUCHPOINT');
```
И сборка:
```bash
flutter build apk --dart-define=LT_TOUCHPOINT=168:8417b4fa-...
flutter build ipa --dart-define=LT_TOUCHPOINT=168:8417b4fa-...
```

**Б. Из защищённого хранилища приложения**, если значение приходит с сервера после авторизации пользователя в твоём приложении:
```dart
final touchPoint = await yourAppApi.fetchLivetexTouchPoint();
final cfg = LivetexChatConfig(touchPoint: touchPoint, ...);
```

### Кастомные endpoints (on-premise)

Если LiveTex развёрнут не в облаке, а у тебя on-premise:
```dart
LivetexChatConfig(
  touchPoint: '...',
  authEndpoint: Uri.parse('https://livetex.your-company.ru/v1/auth'),
  // baseUrl: ... — для будущих расширений, сейчас не используется
);
```

По умолчанию используется облако: `https://visitor-api.livetex.ru/v1/auth`.

### Trace / диагностические логи

Чтобы видеть исходящие/входящие WebSocket-фреймы (формат: `ws_in {...}`, `ws_out {...}`):
```dart
LivetexChatConfig(
  touchPoint: '...',
  trace: (line) => debugPrint('[livetex] $line'),
  traceRedactTokens: true, // default — токены замаскированы в логе
);
```

В production обычно `trace: null` (по умолчанию) — никакого вывода вообще.

---

## 3. Кастомизация внешнего вида

Чат полностью брендируется через `LivetexChatTheme` — иммутабельная палитра из 40+ цветовых и геометрических токенов. По умолчанию используется готовый пресет под бренд LiveTex (`LivetexChatTheme.livetex()`), но можно подменить любые токены или собрать тему с нуля.

### Пример: подменить только основные цвета

```dart
final myTheme = LivetexChatTheme.livetex().copyWith(
  outgoingBubble: const Color(0xFF1E88E5),     // цвет сообщений пользователя
  composerAction: const Color(0xFF1E88E5),     // иконка отправки
  attributesAccent: const Color(0xFF1E88E5),   // кнопка "Отправить" в форме
  ratingButton: const Color(0xFF1E88E5),       // кнопка "ОЦЕНИТЬ"
);

LivetexChatScreen(
  config: cfg,
  theme: myTheme,
);
```

> `copyWith` будет добавлен — пока используй полный конструктор `LivetexChatTheme(...)`.

### Полный список токенов

Группы (имена соответствуют полям класса):

**Общие:**
- `background` — фон скаффолда
- `appBarBackground`, `appBarForeground` — фон и текст шапки
- `systemText` — текст системных сообщений и разделителей дат

**Бабл сообщения:**
- `outgoingBubble`, `outgoingText`, `outgoingTime` — пользователь
- `incomingBubble`, `incomingText`, `incomingTime` — оператор/бот
- `operatorName` — имя оператора над баблом
- `bubbleRadius` — радиус скругления

**Композер (нижняя панель ввода):**
- `composerBackground`, `composerField`, `composerFieldStroke`, `composerFieldRadius`
- `composerText`, `composerHint`
- `composerAction`, `composerActionDisabled` — кнопка отправить
- `composerAddAction`, `composerAddActionDisabled` — кнопка вложений

**Форма атрибутов:**
- `attributesAccent`, `attributesAccentText` — зелёная кнопка «Отправить»
- `attributesHint` — цвет подсказок в полях (на белом фоне карточки)
- `cardRadius` — радиус карточки

**Кнопки бота и групп:**
- `botKeyboardButton`, `botKeyboardButtonDisabled`, `botKeyboardButtonText`
- `departmentButton`, `departmentButtonText`

**Оценка:**
- `ratingPanelBackground` — фон верхней липкой плашки
- `ratingFormBackground` — фон карточки финальной оценки
- `ratingStarActive`, `ratingStarInactive` — звёзды
- `ratingThumbUp`, `ratingThumbDown`, `ratingThumbInactive` — пальцы (2pt)
- `ratingButton`, `ratingButtonText`, `ratingButtonStroke` — активная кнопка «ОЦЕНИТЬ»
- `ratingButtonDisabledBg`, `ratingButtonDisabledText`, `ratingButtonStrokeDisabled`

**Прочее:**
- `connectionBanner`, `connectionBannerText` — баннер «Соединение потеряно»
- `quoteAccent` — вертикальная полоса цитирования
- `controlRadius` — общий радиус контролов (кнопки, поля)

### Подменить отдельные виджеты

Если кастомизация цветов не покрывает — можно собрать экран из кирпичей. Все виджеты экспортируются: `Composer`, `MessageTile`, `TopRatingPanel`, `BottomRatingForm`, `AttributesForm`, `DepartmentPicker`, `BotKeyboard`, `ConnectionBanner`. Берёшь `LivetexChat` напрямую, подписываешься на его потоки и рендеришь по своему.

---

## 4. Форма атрибутов

Бэкенд может попросить сообщить атрибуты визитёра (имя/телефон/email) — приходит событие `attributesRequest`. По умолчанию `LivetexChatScreen` показывает встроенную форму в нижней панели вместо композера.

Если ты собираешь эти данные сам (твой собственный onboarding, CRM-поиск, авторизация в твоём приложении), форму можно отключить:

```dart
LivetexChatScreen(
  config: cfg,
  showAttributesForm: false,                  // не показывать форму
  onAttributesRequested: () {
    // сервер хочет атрибуты — реагируй как удобно
    // (показать свой диалог, подтянуть из CRM, …)
    analytics.log('lt_attributes_requested');
  },
);
```

И отправь атрибуты сам в любой удобный момент:

```dart
final chat = LivetexChat(cfg);
// ...
await chat.sendAttributes(
  correlationId: 'attr-${DateTime.now().millisecondsSinceEpoch}',
  name: 'Иван',
  phone: '+7…',
  email: 'ivan@example.com',
  attributes: const {},
);
```

Если ты передал `chat` в `LivetexChatScreen(chat: chat, config: cfg)` — пользуйся им. Если нет — создай свой инстанс и shared'ишь между экранами.

---

## 5. Push-уведомления

Это пакет `livetex_chat_push`. Подробности — в его собственном README. Кратко:

1. В своём приложении настроить FCM (Android) / APNS (iOS) — это вне зоны LiveTex.
2. Получить device-token (FCM token / APNS token).
3. Передать его в `LivetexChatConfig.deviceToken` и/или вызвать `chat.updateDeviceToken(token)` при refresh.
4. LiveTex-серверы будут адресовать push'и тому же визитёру.

`livetex_chat_push` поверх `firebase_messaging` + `flutter_local_notifications` — оркестрация показа push при receive в foreground.

---

## 6. Жизненный цикл и persistence визитёра

### Визитёрский токен

Сервер при первом auth выдаёт `visitorToken` — это идентификатор визитёра, к которому он привязывает все его диалоги, переписку, оценки. Если приложение перезапустится с пустым токеном — сервер создаст **нового** визитёра, и переписки прошлой сессии уже не будет видно (хотя на сервере она хранится).

**На момент написания этого документа cross-session persistence ещё не реализован** на стороне ядра. Когда будет — конфиг получит callbacks:

```dart
// БУДУЩИЙ API (см. CORE_TODOS.md #2.2)
LivetexChatConfig(
  touchPoint: '...',
  loadPersistedVisitorToken: () async => prefs.getString('lt_visitor_token'),
  savePersistedVisitorToken: (token) async => prefs.setString('lt_visitor_token', token),
);
```

С этими callbacks переписка будет переживать перезапуск приложения.

### Auto-reconnect

Уже реализован. При возвращении приложения из background (`AppLifecycleState.resumed`) экран автоматически переподключается, если соединение было потеряно. Кнопка «Повторить» в баннере «Соединение потеряно» — fallback на случай, если auto-reconnect не сработал (например, нет интернета).

WebSocket держится живым через ping/pong каждые 10 сек (как в native sdk-android).

---

## 7. Низкоуровневый API без UI

Если тебе не подходит `LivetexChatScreen` и хочется свой UI:

```dart
final chat = LivetexChat(LivetexChatConfig(
  touchPoint: '...',
  trace: (line) => debugPrint('[lt] $line'),
));

await chat.connect();

// Подписки:
chat.connectionState.listen((state) {/* connected/connecting/disconnected */});
chat.messages.listen((list) {/* List<ChatMessage> */});
chat.dialogState.listen((state) {/* VisitorDialogState? */});
chat.attributesRequest.listen((_) {/* сервер просит атрибуты */});
chat.departmentRequest.listen((deps) {/* List<DepartmentItem> */});
chat.employeeTyping.listen((event) {/* оператор печатает */});
chat.errors.listen((error) {/* LivetexChatError */});

// Команды:
chat.sendText('Привет');
chat.sendTyping();
await chat.sendFile(File('/path/to/file.png'));
chat.sendRating(rateType: 'fivePoint', value: '5', comment: 'Спасибо');
chat.sendAttributes(correlationId: '...', name: '...', phone: '...', email: '...', attributes: {});
chat.selectDepartment(correlationId: '...', id: 'department-id');
chat.pressButton(payload: '...');
chat.loadHistory(messageId: oldestId, offset: 20);

await chat.disconnect();
chat.dispose();
```

Полная типизация — в `livetex_chat/lib/livetex_chat.dart` и `domain/`.

---

## 8. FAQ и частые подводные камни

### Q: Я закрыл/перезапустил приложение и потерял всю переписку
Cross-session persistence визитёра ещё не реализован. См. п. 6 и `CORE_TODOS.md` #2.2.

### Q: Файл не отправляется на Android 13+
Проверь, что `file_picker` корректно работает в твоём приложении. Permissions на runtime не требуются — `file_picker` использует Storage Access Framework. Если падает — включи trace, в логе должны быть события `sendFile start` и далее `upload BEGIN`/`upload OK`/`upload FAILED`.

### Q: Фиолетовый цвет где-то проскакивает в UI
Material 3 в Flutter по умолчанию подмешивает seed-цвет (фиолетовый) ко всему, что не явно стилизовано — focus border, primary action, surface tint. Если что-то фиолетовое — это место не покрыто `LivetexChatTheme`. Сообщи разработчикам LiveTex, добавим токен.

### Q: Хочу поменять язык
Подписи сейчас захардкожены на русском (тексты «Введите сообщение», «Прикрепить», «Соединение потеряно», «Повторить», «ОЦЕНИТЬ», «Не удалось подтвердить оценку» и т.п.). Локализация — отдельная задача. Если нужен другой язык — можно временно собрать собственный экран из кирпичей с своими строками.

### Q: WebView, web target
SDK работает на mobile (Android + iOS) и desktop (Windows/macOS/Linux). На **web** не работает: использует `dart:io` (`File`, `IOWebSocketChannel.pingInterval`). Web — отдельная задача.

### Q: Кнопки бота с эмодзи `⁤` (U+2064) выглядят странно
Это invisible separator из протокола Visitor-API. **Не трогай** ни label, ни payload — сервер их так и ждёт обратно при `pressButton`.

### Q: На iOS приложение в background теряет соединение — это нормально?
Да. iOS приостанавливает WebSocket в background. SDK переподключается автоматически на `resumed`. См. `_LivetexChatScreenState.didChangeAppLifecycleState`.

### Q: Размер вложений?
Текстовое сообщение — до 2000 символов (серверный лимит). Файлы — серверный лимит на стороне LiveTex (~25 МБ обычно), уточняй у вашего менеджера. SDK сам ограничения не накладывает.

### Q: Где спросить, если непонятно?
- Issues в GitHub-репозитории `LiveTex/livetex-flutter-plugin`.
- Сапорт LiveTex через личный кабинет.
