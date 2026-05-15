import "dart:async";
import "dart:io";

import "package:cached_network_image/cached_network_image.dart";
import "package:file_picker/file_picker.dart";
import "package:flutter/material.dart";
import "package:intl/intl.dart";
import "package:livetex_chat/livetex_chat.dart";
import "package:photo_view/photo_view.dart";
import "package:url_launcher/url_launcher.dart";

import "livetex_chat_theme.dart";

/// Drop-in full-screen chat. Defaults to [LivetexChatTheme.livetex] (native
/// Android `demo-lib` look). Pass [theme] to override.
class LivetexChatScreen extends StatefulWidget {
  const LivetexChatScreen({
    super.key,
    required this.config,
    this.chat,
    this.title = "LiveTex",
    this.autoconnect = true,
    this.afterConnected,
    this.theme,
  });

  final LivetexChatConfig config;
  final LivetexChat? chat;
  final String title;
  final bool autoconnect;
  final Future<void> Function(LivetexChat chat)? afterConnected;
  final LivetexChatTheme? theme;

  @override
  State<LivetexChatScreen> createState() => _LivetexChatScreenState();
}

class _LivetexChatScreenState extends State<LivetexChatScreen> {
  late LivetexChat _chat;
  bool _ownChat = false;
  final _textCtrl = TextEditingController();
  final _scroll = ScrollController();
  final _subs = <StreamSubscription<dynamic>>[];

  List<ChatMessage> _messages = [];
  VisitorDialogState? _dialog;
  LivetexConnectionState _conn = LivetexConnectionState.disconnected;
  bool _typingVisible = false;
  Timer? _typingTimer;
  DateTime? _lastTypingSent;

  bool _afterConnectDone = false;

  @override
  void initState() {
    super.initState();
    _chat = widget.chat ?? LivetexChat(widget.config);
    _ownChat = widget.chat == null;
    _wire();
    if (widget.autoconnect) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_chat.connect());
      });
    }
  }

  void _wire() {
    _subs.addAll([
      _chat.connectionState.listen((s) async {
        if (mounted) setState(() => _conn = s);
        if (s == LivetexConnectionState.connected &&
            !_afterConnectDone &&
            widget.afterConnected != null) {
          _afterConnectDone = true;
          try {
            await widget.afterConnected!(_chat);
          } catch (_) {}
        }
      }),
      _chat.dialogState.listen((d) {
        if (mounted) setState(() => _dialog = d);
      }),
      _chat.messages.listen((m) {
        if (mounted) {
          setState(() => _messages = List.from(m));
          _scrollToEnd();
        }
      }),
      _chat.errors.listen((e) {
        if (!mounted) return;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }),
      _chat.attributesRequest.listen((_) => _openAttributesSheet()),
      _chat.departmentRequest.listen(_openDepartmentSheet),
      _chat.employeeTyping.listen((_) {
        if (!mounted) return;
        setState(() => _typingVisible = true);
        _typingTimer?.cancel();
        _typingTimer = Timer(const Duration(seconds: 3), () {
          if (mounted) setState(() => _typingVisible = false);
        });
      }),
    ]);
  }

  void _scrollToEnd() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        _scroll.jumpTo(_scroll.position.maxScrollExtent);
      }
    });
  }

  @override
  void dispose() {
    for (final s in _subs) {
      unawaited(s.cancel());
    }
    _typingTimer?.cancel();
    _textCtrl.dispose();
    _scroll.dispose();
    if (_ownChat) {
      unawaited(_chat.dispose());
    }
    super.dispose();
  }

  Future<void> _openAttributesSheet() async {
    final name = TextEditingController();
    final phone = TextEditingController();
    final email = TextEditingController();
    final theme = LivetexChatTheme.of(context);
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      backgroundColor: theme.background,
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            bottom: MediaQuery.viewInsetsOf(ctx).bottom + 16,
            left: 16,
            right: 16,
            top: 8,
          ),
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    "Представьтесь",
                    textAlign: TextAlign.center,
                    style: TextStyle(fontWeight: FontWeight.w600, fontSize: 16),
                  ),
                ),
                TextField(
                  controller: name,
                  decoration: const InputDecoration(labelText: "Имя"),
                ),
                TextField(
                  controller: phone,
                  decoration: const InputDecoration(labelText: "Телефон"),
                  keyboardType: TextInputType.phone,
                ),
                TextField(
                  controller: email,
                  decoration: const InputDecoration(labelText: "E-mail"),
                  keyboardType: TextInputType.emailAddress,
                ),
                const SizedBox(height: 16),
                SizedBox(
                  height: 48,
                  child: FilledButton(
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.attributesAccent,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius:
                            BorderRadius.circular(theme.cardRadius),
                      ),
                    ),
                    onPressed: () {
                      final corr =
                          "attr-${DateTime.now().millisecondsSinceEpoch}";
                      _chat.sendAttributes(
                        correlationId: corr,
                        name: _trimToNull(name.text),
                        phone: _trimToNull(phone.text),
                        email: _trimToNull(email.text),
                        attributes: const {},
                      );
                      Navigator.pop(ctx);
                    },
                    child: const Text(
                      "Отправить",
                      style: TextStyle(fontSize: 18),
                    ),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String? _trimToNull(String s) {
    final t = s.trim();
    return t.isEmpty ? null : t;
  }

  Future<void> _openDepartmentSheet(List<DepartmentItem> deps) async {
    if (!mounted) return;
    final theme = LivetexChatTheme.of(context);
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      backgroundColor: theme.background,
      builder: (ctx) {
        return SafeArea(
          top: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.only(bottom: 12),
                  child: Text(
                    "Выберите куда направить ваше обращение",
                    style: TextStyle(fontSize: 12, color: theme.systemText),
                    textAlign: TextAlign.center,
                  ),
                ),
                for (final d in deps)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: SizedBox(
                      height: 48,
                      child: FilledButton(
                        style: FilledButton.styleFrom(
                          backgroundColor: theme.departmentButton,
                          foregroundColor: theme.departmentButtonText,
                          shape: RoundedRectangleBorder(
                            borderRadius:
                                BorderRadius.circular(theme.controlRadius),
                          ),
                          elevation: 0,
                        ),
                        onPressed: () {
                          final corr =
                              "dep-${DateTime.now().millisecondsSinceEpoch}";
                          _chat.selectDepartment(
                            correlationId: corr,
                            id: d.id,
                          );
                          Navigator.pop(ctx);
                        },
                        child: Text(d.name, style: const TextStyle(fontSize: 16)),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _pickAndSendFile() async {
    final r = await FilePicker.platform.pickFiles(
      withData: true,
      allowMultiple: false,
    );
    if (r == null || r.files.isEmpty) return;
    final pf = r.files.single;
    if (pf.path != null && pf.path!.isNotEmpty) {
      await _chat.sendFile(File(pf.path!));
      return;
    }
    final bytes = pf.bytes;
    if (bytes == null) return;
    final name = pf.name.isEmpty
        ? "upload.bin"
        : pf.name.replaceAll(RegExp(r"[/\\]"), "_");
    final tmp = File(
      "${Directory.systemTemp.path}/lt_ui_${DateTime.now().millisecondsSinceEpoch}_$name",
    );
    await tmp.writeAsBytes(bytes, flush: true);
    try {
      await _chat.sendFile(tmp, logicalName: name);
    } finally {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
    }
  }

  void _sendText() {
    final t = _textCtrl.text.trim();
    if (t.isEmpty) return;
    _textCtrl.clear();
    _chat.sendText(t);
  }

  void _onComposerChanged(String s) {
    if (s.trim().isEmpty) return;
    final now = DateTime.now();
    if (_lastTypingSent == null ||
        now.difference(_lastTypingSent!) > const Duration(seconds: 2)) {
      _lastTypingSent = now;
      _chat.sendTyping();
    }
  }

  void _maybeLoadHistory() {
    if (_messages.isEmpty) return;
    final oldest =
        _messages.reduce((a, b) => a.createdAt.isBefore(b.createdAt) ? a : b);
    _chat.loadHistory(messageId: oldest.id, offset: 20);
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme ?? LivetexChatTheme.livetex();
    return LivetexChatThemeScope(
      theme: theme,
      child: Builder(
        builder: (innerCtx) {
          final d = _dialog;
          final rate = d?.rate;
          final showTopRating = rate != null &&
              rate.enabledType != null &&
              rate.enabledType!.isNotEmpty &&
              d != null &&
              d.status != DialogStatus.unassigned &&
              rate.isSet == null;
          return Scaffold(
            backgroundColor: theme.background,
            appBar: AppBar(
              backgroundColor: theme.appBarBackground,
              foregroundColor: theme.appBarForeground,
              elevation: 0,
              centerTitle: true,
              title: Text(widget.title),
              actions: [
                IconButton(
                  tooltip: "История",
                  onPressed: _conn == LivetexConnectionState.connected
                      ? _maybeLoadHistory
                      : null,
                  icon: const Icon(Icons.history),
                ),
              ],
            ),
            body: Column(
              children: [
                if (_conn != LivetexConnectionState.connected)
                  _ConnectionBanner(
                    state: _conn,
                    onRetry: () => _chat.connect(),
                  ),
                if (showTopRating) _RatingStrip(chat: _chat, rate: rate),
                Expanded(
                  child: _MessageList(
                    messages: _messages,
                    scroll: _scroll,
                    typingVisible: _typingVisible,
                    operatorName: d?.employee?.name,
                  ),
                ),
                if (d != null &&
                    d.showInput &&
                    _conn == LivetexConnectionState.connected)
                  _Composer(
                    controller: _textCtrl,
                    onSend: _sendText,
                    onChanged: _onComposerChanged,
                    onFile: _pickAndSendFile,
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _ConnectionBanner extends StatelessWidget {
  const _ConnectionBanner({required this.state, required this.onRetry});

  final LivetexConnectionState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = LivetexChatTheme.of(context);
    return Material(
      color: theme.connectionBanner,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 18,
              color: theme.connectionBannerText,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _connLabel(state),
                style: TextStyle(
                  fontSize: 13,
                  color: theme.connectionBannerText,
                ),
              ),
            ),
            TextButton(
              onPressed: state == LivetexConnectionState.connecting ||
                      state == LivetexConnectionState.reconnecting
                  ? null
                  : onRetry,
              style: TextButton.styleFrom(
                foregroundColor: theme.connectionBannerText,
              ),
              child: const Text("Повторить"),
            ),
          ],
        ),
      ),
    );
  }
}

String _connLabel(LivetexConnectionState c) {
  return switch (c) {
    LivetexConnectionState.disconnected => "Соединение потеряно",
    LivetexConnectionState.connecting => "Подключение…",
    LivetexConnectionState.reconnecting => "Переподключение…",
    LivetexConnectionState.connected => "Соединение восстановлено",
  };
}

class _RatingStrip extends StatelessWidget {
  const _RatingStrip({required this.chat, required this.rate});

  final LivetexChat chat;
  final DialogRateState rate;

  @override
  Widget build(BuildContext context) {
    // Stage 2 will redesign this to match native (stars + comment + submit).
    // Stage 1 keeps a temporary panel using LivetexChatTheme tokens so it
    // doesn't pull purple from the host's Material 3 default.
    final theme = LivetexChatTheme.of(context);
    final t = rate.enabledType ?? "";
    return Material(
      color: theme.ratingPanelBackground,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (rate.textBefore != null && rate.textBefore!.trim().isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(
                  rate.textBefore!.trim(),
                  style: TextStyle(fontSize: 12, color: theme.systemText),
                ),
              ),
            if (t == "doublePoint")
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: () => _send("0"),
                      child: const Text("Плохо"),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: FilledButton(
                      style: FilledButton.styleFrom(
                        backgroundColor: theme.ratingButton,
                        foregroundColor: theme.ratingButtonText,
                      ),
                      onPressed: () => _send("1"),
                      child: const Text("Хорошо"),
                    ),
                  ),
                ],
              )
            else if (t == "fivePoint")
              Wrap(
                spacing: 6,
                children: [
                  for (final v in const ["1", "2", "3", "4", "5"])
                    FilledButton.tonal(
                      onPressed: () => _send(v),
                      child: Text(v),
                    ),
                ],
              )
            else
              Text(
                "Оценка ($t) — отправьте вручную через API",
                style: TextStyle(fontSize: 12, color: theme.systemText),
              ),
          ],
        ),
      ),
    );
  }

  void _send(String value) {
    final rt = rate.enabledType;
    if (rt == null) return;
    chat.sendRating(rateType: rt, value: value);
  }
}

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.messages,
    required this.scroll,
    required this.typingVisible,
    required this.operatorName,
  });

  final List<ChatMessage> messages;
  final ScrollController scroll;
  final bool typingVisible;
  final String? operatorName;

  @override
  Widget build(BuildContext context) {
    final items = _buildListItems(messages, typingVisible, operatorName);
    return ListView.builder(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
      itemCount: items.length,
      itemBuilder: (_, i) => items[i],
    );
  }
}

List<Widget> _buildListItems(
  List<ChatMessage> messages,
  bool typingVisible,
  String? operatorName,
) {
  final out = <Widget>[];
  DateTime? prevDay;
  for (final m in messages) {
    final local = m.createdAt.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    if (prevDay == null || day != prevDay) {
      out.add(_DateSeparator(date: local));
      prevDay = day;
    }
    out.add(_MessageTile(message: m));
  }
  if (typingVisible) {
    out.add(_TypingTile(operatorName: operatorName));
  }
  return out;
}

class _DateSeparator extends StatelessWidget {
  const _DateSeparator({required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final theme = LivetexChatTheme.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(date.year, date.month, date.day);
    final delta = today.difference(that).inDays;
    final label = switch (delta) {
      0 => "Сегодня",
      1 => "Вчера",
      _ => "${date.day} ${_ruMonth(date.month)}",
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Text(
          label,
          style: TextStyle(fontSize: 12, color: theme.systemText),
        ),
      ),
    );
  }
}

const _ruMonths = <String>[
  "",
  "января",
  "февраля",
  "марта",
  "апреля",
  "мая",
  "июня",
  "июля",
  "августа",
  "сентября",
  "октября",
  "ноября",
  "декабря",
];

String _ruMonth(int month) {
  if (month < 1 || month > 12) return "";
  return _ruMonths[month];
}

class _TypingTile extends StatelessWidget {
  const _TypingTile({required this.operatorName});

  final String? operatorName;

  @override
  Widget build(BuildContext context) {
    final theme = LivetexChatTheme.of(context);
    final text = operatorName != null && operatorName!.isNotEmpty
        ? "$operatorName печатает…"
        : "Печатает…";
    return Padding(
      padding: const EdgeInsets.only(left: 56, top: 4, bottom: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: TextStyle(fontSize: 12, color: theme.systemText),
        ),
      ),
    );
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({required this.message});

  final ChatMessage message;

  static const _imageExts = {
    ".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".heic", ".heif",
  };

  static bool _isImageUrl(String? u) {
    if (u == null || u.isEmpty) return false;
    final low = u.toLowerCase();
    for (final ext in _imageExts) {
      if (low.endsWith(ext)) return true;
    }
    return false;
  }

  bool get _isSystem => message.creatorLabel == "Система";

  @override
  Widget build(BuildContext context) {
    if (_isSystem) return _SystemMessageTile(text: message.text ?? "");
    final theme = LivetexChatTheme.of(context);
    final isVisitor = message.isVisitor;
    final isImageMessage =
        _isImageUrl(message.fileUrl) || _isImageUrl(message.text);
    final isFileMessage =
        message.fileUrl != null && !isImageMessage;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment:
            isVisitor ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isVisitor &&
              message.creatorLabel != null &&
              message.creatorLabel!.isNotEmpty &&
              message.creatorLabel != "Вы")
            Padding(
              padding: const EdgeInsets.only(left: 48, bottom: 2),
              child: Text(
                message.creatorLabel!,
                style: TextStyle(fontSize: 11, color: theme.operatorName),
              ),
            ),
          Row(
            mainAxisAlignment:
                isVisitor ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isVisitor) ...[
                const _OperatorAvatar(),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * 0.78,
                  ),
                  child: _MessageBubble(
                    isVisitor: isVisitor,
                    text: message.text,
                    fileName: message.fileName,
                    fileUrl: message.fileUrl,
                    isImageMessage: isImageMessage,
                    isFileMessage: isFileMessage,
                    createdAt: message.createdAt,
                    sendState: message.sendState,
                  ),
                ),
              ),
            ],
          ),
          if (message.keyboard != null &&
              message.keyboard!.buttons.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(left: 48, top: 8, right: 8),
              child: _BotKeyboard(
                keyboard: message.keyboard!,
                onPress: (b) {
                  final st =
                      context.findAncestorStateOfType<_LivetexChatScreenState>();
                  st?._chat.pressButton(payload: b.payload);
                  if (b.url != null && b.url!.isNotEmpty) {
                    Future<void>.delayed(
                      const Duration(milliseconds: 300),
                      () {
                        launchUrl(
                          Uri.parse(b.url!),
                          mode: LaunchMode.externalApplication,
                        );
                      },
                    );
                  }
                },
              ),
            ),
        ],
      ),
    );
  }
}

class _OperatorAvatar extends StatelessWidget {
  const _OperatorAvatar();

  @override
  Widget build(BuildContext context) {
    final theme = LivetexChatTheme.of(context);
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: theme.incomingBubble,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.support_agent,
        size: 18,
        color: theme.systemText,
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.isVisitor,
    required this.text,
    required this.fileName,
    required this.fileUrl,
    required this.isImageMessage,
    required this.isFileMessage,
    required this.createdAt,
    required this.sendState,
  });

  final bool isVisitor;
  final String? text;
  final String? fileName;
  final String? fileUrl;
  final bool isImageMessage;
  final bool isFileMessage;
  final DateTime createdAt;
  final ChatMessageSendState sendState;

  @override
  Widget build(BuildContext context) {
    final theme = LivetexChatTheme.of(context);
    final bg = isVisitor ? theme.outgoingBubble : theme.incomingBubble;
    final fg = isVisitor ? theme.outgoingText : theme.incomingText;
    final timeFg = isVisitor ? Colors.white70 : theme.incomingTime;
    final imageUrl = isImageMessage
        ? (fileUrl ?? (text != null && _MessageTile._isImageUrl(text) ? text : null))
        : null;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(theme.bubbleRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imageUrl != null)
              GestureDetector(
                onTap: () => _openImage(context, imageUrl),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    width: 200,
                    height: 200,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => SizedBox(
                      width: 200,
                      height: 200,
                      child: Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.composerAction,
                          ),
                        ),
                      ),
                    ),
                    errorWidget: (_, __, ___) => SizedBox(
                      width: 200,
                      height: 200,
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: theme.systemText,
                      ),
                    ),
                  ),
                ),
              )
            else if (isFileMessage && fileName != null)
              InkWell(
                onTap: () {
                  if (fileUrl != null && fileUrl!.isNotEmpty) {
                    launchUrl(
                      Uri.parse(fileUrl!),
                      mode: LaunchMode.externalApplication,
                    );
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.insert_drive_file_outlined,
                        color: fg,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          fileName!,
                          style: TextStyle(fontSize: 15, color: fg),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (text != null && text!.isNotEmpty)
              SelectableText(
                text!,
                style: TextStyle(fontSize: 16, color: fg),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (sendState == ChatMessageSendState.sending) ...[
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: timeFg,
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  if (sendState == ChatMessageSendState.failed) ...[
                    const Icon(
                      Icons.error_outline,
                      size: 14,
                      color: Colors.red,
                    ),
                    const SizedBox(width: 4),
                  ],
                  if (sendState == ChatMessageSendState.sent && isVisitor) ...[
                    Icon(Icons.done_all, size: 14, color: timeFg),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    DateFormat.Hm().format(createdAt.toLocal()),
                    style: TextStyle(fontSize: 11, color: timeFg),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openImage(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        insetPadding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
        child: PhotoView(
          imageProvider: CachedNetworkImageProvider(url),
          backgroundDecoration: const BoxDecoration(color: Colors.black),
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 3,
          onTapUp: (c, details, ctrl) => Navigator.pop(ctx),
        ),
      ),
    );
  }
}

class _SystemMessageTile extends StatelessWidget {
  const _SystemMessageTile({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = LivetexChatTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: theme.systemText),
        ),
      ),
    );
  }
}

class _BotKeyboard extends StatelessWidget {
  const _BotKeyboard({required this.keyboard, required this.onPress});

  final KeyboardPayload keyboard;
  final void Function(ButtonPayload button) onPress;

  @override
  Widget build(BuildContext context) {
    final theme = LivetexChatTheme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final b in keyboard.buttons)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: SizedBox(
              height: 44,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: theme.botKeyboardButton,
                  foregroundColor: theme.botKeyboardButtonText,
                  disabledBackgroundColor:
                      theme.botKeyboardButton.withValues(alpha: 0.5),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(theme.controlRadius),
                  ),
                ),
                onPressed: keyboard.pressed ? null : () => onPress(b),
                child: Text(
                  b.label,
                  style: const TextStyle(fontSize: 16),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Composer extends StatefulWidget {
  const _Composer({
    required this.controller,
    required this.onSend,
    required this.onChanged,
    required this.onFile,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final ValueChanged<String> onChanged;
  final Future<void> Function() onFile;

  @override
  State<_Composer> createState() => _ComposerState();
}

class _ComposerState extends State<_Composer> {
  bool _hasText = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onCtrl);
    _hasText = widget.controller.text.trim().isNotEmpty;
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onCtrl);
    super.dispose();
  }

  void _onCtrl() {
    final has = widget.controller.text.trim().isNotEmpty;
    if (has != _hasText && mounted) setState(() => _hasText = has);
  }

  @override
  Widget build(BuildContext context) {
    final theme = LivetexChatTheme.of(context);
    return Material(
      color: theme.composerBackground,
      elevation: 0,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              IconButton(
                tooltip: "Прикрепить",
                onPressed: widget.onFile,
                icon: Icon(
                  Icons.add,
                  size: 28,
                  color: theme.composerAction,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 42),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.composerField,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: TextField(
                    controller: widget.controller,
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 2000,
                    style: TextStyle(fontSize: 18, color: theme.composerText),
                    decoration: InputDecoration(
                      hintText: "Введите сообщение",
                      hintStyle: TextStyle(color: theme.composerHint),
                      border: InputBorder.none,
                      counterText: "",
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 10,
                      ),
                    ),
                    onChanged: widget.onChanged,
                    onSubmitted: (_) => widget.onSend(),
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: "Отправить",
                onPressed: _hasText ? widget.onSend : null,
                icon: Icon(
                  Icons.send,
                  size: 26,
                  color: _hasText
                      ? theme.composerAction
                      : theme.composerActionDisabled,
                ),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(minWidth: 32, minHeight: 42),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
