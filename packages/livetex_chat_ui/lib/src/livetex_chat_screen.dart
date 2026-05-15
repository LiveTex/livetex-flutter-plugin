import "dart:async";
import "dart:io";

import "package:cached_network_image/cached_network_image.dart";
import "package:file_picker/file_picker.dart";
import "package:flutter/material.dart";
import "package:intl/intl.dart";
import "package:livetex_chat/livetex_chat.dart";
import "package:photo_view/photo_view.dart";
import "package:url_launcher/url_launcher.dart";

/// Drop-in full-screen chat (Material 3). Creates [LivetexChat] unless [chat] is passed.
class LivetexChatScreen extends StatefulWidget {
  const LivetexChatScreen({
    super.key,
    required this.config,
    this.chat,
    this.title = "LiveTex",
    this.autoconnect = true,
    this.afterConnected,
  });

  final LivetexChatConfig config;
  final LivetexChat? chat;
  final String title;
  final bool autoconnect;
  final Future<void> Function(LivetexChat chat)? afterConnected;

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
    final key = TextEditingController(text: "city");
    final val = TextEditingController(text: "Moscow");
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
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
                const Text("Атрибуты", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18)),
                TextField(controller: name, decoration: const InputDecoration(labelText: "Имя")),
                TextField(controller: phone, decoration: const InputDecoration(labelText: "Телефон")),
                TextField(controller: email, decoration: const InputDecoration(labelText: "Email")),
                TextField(controller: key, decoration: const InputDecoration(labelText: "Ключ")),
                TextField(controller: val, decoration: const InputDecoration(labelText: "Значение")),
                FilledButton(
                  child: const Text("Отправить"),
                  onPressed: () {
                    final corr = "attr-${DateTime.now().millisecondsSinceEpoch}";
                    _chat.sendAttributes(
                      correlationId: corr,
                      name: name.text.trim().isEmpty ? null : name.text.trim(),
                      phone: phone.text.trim().isEmpty ? null : phone.text.trim(),
                      email: email.text.trim().isEmpty ? null : email.text.trim(),
                      attributes: {
                        if (key.text.trim().isNotEmpty) key.text.trim(): val.text,
                      },
                    );
                    Navigator.pop(ctx);
                  },
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _openDepartmentSheet(List<DepartmentItem> deps) async {
    if (!mounted) return;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) {
        return ListView.builder(
          shrinkWrap: true,
          itemCount: deps.length,
          itemBuilder: (_, i) {
            final d = deps[i];
            return ListTile(
              title: Text(d.name),
              subtitle: Text("id=${d.id}"),
              onTap: () {
                final corr = "dep-${DateTime.now().millisecondsSinceEpoch}";
                _chat.selectDepartment(correlationId: corr, id: d.id);
                Navigator.pop(ctx);
              },
            );
          },
        );
      },
    );
  }

  Future<void> _pickAndSendFile() async {
    final r = await FilePicker.platform.pickFiles(withData: true, allowMultiple: false);
    if (r == null || r.files.isEmpty) return;
    final pf = r.files.single;
    if (pf.path != null && pf.path!.isNotEmpty) {
      await _chat.sendFile(File(pf.path!));
      return;
    }
    final bytes = pf.bytes;
    if (bytes == null) return;
    final name = pf.name.isEmpty ? "upload.bin" : pf.name.replaceAll(RegExp(r"[/\\]"), "_");
    final tmp = File("${Directory.systemTemp.path}/lt_ui_${DateTime.now().millisecondsSinceEpoch}_$name");
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
    final now = DateTime.now();
    if (_lastTypingSent == null || now.difference(_lastTypingSent!) > const Duration(seconds: 2)) {
      _lastTypingSent = now;
      _chat.sendTyping();
    }
  }

  void _maybeLoadHistory() {
    if (_messages.isEmpty) return;
    final oldest = _messages.reduce((a, b) => a.createdAt.isBefore(b.createdAt) ? a : b);
    _chat.loadHistory(messageId: oldest.id, offset: 0);
  }

  @override
  Widget build(BuildContext context) {
    final d = _dialog;
    final rate = d?.rate;
    final showTopRating = rate != null &&
        rate.enabledType != null &&
        rate.enabledType!.isNotEmpty &&
        d != null &&
        d.status != DialogStatus.unassigned &&
        rate.isSet == null;

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.title),
            Text(
              _conn == LivetexConnectionState.connected ? _statusLine(d) : _connLabel(_conn),
              style: TextStyle(
                fontSize: 12,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            tooltip: "История",
            onPressed: _conn == LivetexConnectionState.connected ? _maybeLoadHistory : null,
            icon: const Icon(Icons.history),
          ),
        ],
      ),
      body: Column(
        children: [
          if (_conn != LivetexConnectionState.connected)
            MaterialBanner(
              content: Text(_connLabel(_conn)),
              actions: [TextButton(onPressed: () => _chat.connect(), child: const Text("Переподключить"))],
            ),
          if (_typingVisible)
            const LinearProgressIndicator(minHeight: 2),
          if (showTopRating) _RatingStrip(chat: _chat, rate: rate),
          Expanded(child: _MessageList(messages: _messages, scroll: _scroll)),
          if (d != null && d.showInput && _conn == LivetexConnectionState.connected)
            _Composer(
              controller: _textCtrl,
              onSend: _sendText,
              onFile: _pickAndSendFile,
              keyboard: _lastKeyboard(),
            ),
        ],
      ),
    );
  }

  KeyboardPayload? _lastKeyboard() {
    for (var i = _messages.length - 1; i >= 0; i--) {
      final k = _messages[i].keyboard;
      if (k != null && k.buttons.isNotEmpty) return k;
    }
    return null;
  }

  String _statusLine(VisitorDialogState? d) {
    if (d == null) return "…";
    return "${d.status.name}${d.employee != null ? " · ${d.employee!.name}" : ""}";
  }
}

class _RatingStrip extends StatelessWidget {
  const _RatingStrip({
    required this.chat,
    required this.rate,
  });

  final LivetexChat chat;
  final DialogRateState rate;

  @override
  Widget build(BuildContext context) {
    final t = rate.enabledType ?? "";
    return Material(
      color: Theme.of(context).colorScheme.secondaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (rate.textBefore != null && rate.textBefore!.trim().isNotEmpty)
              Text(rate.textBefore!.trim()),
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
              Text("Оценка ($t) — отправьте вручную через API"),
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
  const _MessageList({required this.messages, required this.scroll});

  final List<ChatMessage> messages;
  final ScrollController scroll;

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      controller: scroll,
      padding: const EdgeInsets.all(8),
      itemCount: messages.length,
      itemBuilder: (_, i) => _MessageTile(message: messages[i]),
    );
  }
}

class _MessageTile extends StatelessWidget {
  const _MessageTile({required this.message});

  final ChatMessage message;

  static bool _isImageUrl(String? u) {
    if (u == null || u.isEmpty) return false;
    final low = u.toLowerCase();
    return low.endsWith(".png") ||
        low.endsWith(".jpg") ||
        low.endsWith(".jpeg") ||
        low.endsWith(".gif") ||
        low.endsWith(".webp");
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final align = message.isVisitor ? Alignment.centerRight : Alignment.centerLeft;
    final bg = message.isVisitor ? scheme.primaryContainer : scheme.surfaceContainerHighest;
    final url = message.fileUrl ?? (message.text != null && _isImageUrl(message.text) ? message.text : null);
    return Align(
      alignment: align,
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.88),
        child: Card(
          color: bg,
          margin: const EdgeInsets.only(bottom: 8),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message.creatorLabel ?? "",
                  style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                ),
                if (message.text != null && message.text!.isNotEmpty && url == null)
                  SelectableText(message.text!, style: const TextStyle(fontSize: 15)),
                if (message.fileName != null && url != null && !_isImageUrl(url))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(message.fileName!),
                    subtitle: Text(message.fileUrl!, maxLines: 1, overflow: TextOverflow.ellipsis),
                    onTap: () => launchUrl(Uri.parse(message.fileUrl!), mode: LaunchMode.externalApplication),
                  ),
                if (message.fileName != null && url == null)
                if (url != null && _isImageUrl(url))
                  GestureDetector(
                    onTap: () => _openImage(context, url),
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(12),
                      child: CachedNetworkImage(
                        imageUrl: url,
                        height: 180,
                        fit: BoxFit.cover,
                        placeholder: (_, __) => const SizedBox(
                          height: 120,
                          child: Center(child: CircularProgressIndicator()),
                        ),
                      ),
                    ),
                  )
                else if (url != null)
                  InkWell(
                    onTap: () => launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication),
                    child: Text(url, style: const TextStyle(decoration: TextDecoration.underline)),
                  ),
                if (message.keyboard != null && message.keyboard!.buttons.isNotEmpty)
                  Wrap(
                    spacing: 6,
                    runSpacing: 6,
                    children: [
                      for (final b in message.keyboard!.buttons)
                        ActionChip(
                          label: Text(b.label),
                          onPressed: message.keyboard!.pressed
                              ? null
                              : () {
                                  final st = context
                                      .findAncestorStateOfType<_LivetexChatScreenState>();
                                  st?._chat.pressButton(payload: b.payload);
                                  if (b.url != null && b.url!.isNotEmpty) {
                                    Future<void>.delayed(const Duration(milliseconds: 300), () {
                                      launchUrl(Uri.parse(b.url!), mode: LaunchMode.externalApplication);
                                    });
                                  }
                                },
                        ),
                    ],
                  ),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    Text(
                      DateFormat.Hm().format(message.createdAt.toLocal()),
                      style: TextStyle(fontSize: 11, color: scheme.onSurfaceVariant),
                    ),
                    if (message.sendState == ChatMessageSendState.sending) ...[
                      const SizedBox(width: 4),
                      const SizedBox(width: 12, height: 12, child: CircularProgressIndicator(strokeWidth: 2)),
                    ],
                    if (message.sendState == ChatMessageSendState.failed)
                      const Icon(Icons.error_outline, size: 16, color: Colors.red),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  void _openImage(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        insetPadding: EdgeInsets.zero,
        child: PhotoView(
          imageProvider: CachedNetworkImageProvider(url),
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 3,
          onTapUp: (c, details, ctrl) => Navigator.pop(ctx),
        ),
      ),
    );
  }
}

class _Composer extends StatelessWidget {
  const _Composer({
    required this.controller,
    required this.onSend,
    required this.onFile,
    this.keyboard,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final Future<void> Function() onFile;
  final KeyboardPayload? keyboard;

  @override
  Widget build(BuildContext context) {
    final chat = context.findAncestorStateOfType<_LivetexChatScreenState>()!._chat;
    return Material(
      elevation: 8,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (keyboard != null && keyboard!.buttons.isNotEmpty)
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (final b in keyboard!.buttons)
                        Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: ActionChip(
                            label: Text(b.label),
                            onPressed: keyboard!.pressed
                                ? null
                                : () {
                                    chat.pressButton(payload: b.payload);
                                    if (b.url != null && b.url!.isNotEmpty) {
                                      Future<void>.delayed(const Duration(milliseconds: 300), () {
                                        launchUrl(Uri.parse(b.url!), mode: LaunchMode.externalApplication);
                                      });
                                    }
                                  },
                          ),
                        ),
                    ],
                  ),
                ),
              Row(
                children: [
                  IconButton.filledTonal(onPressed: () => onFile(), icon: const Icon(Icons.attach_file)),
                  Expanded(
                    child: TextField(
                      controller: controller,
                      minLines: 1,
                      maxLines: 4,
                      decoration: const InputDecoration(hintText: "Сообщение…", border: OutlineInputBorder()),
                      onSubmitted: (_) => onSend(),
                    ),
                  ),
                  IconButton.filled(onPressed: onSend, icon: const Icon(Icons.send)),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

String _connLabel(LivetexConnectionState c) {
  return switch (c) {
    LivetexConnectionState.disconnected => "Нет соединения",
    LivetexConnectionState.connecting => "Подключение…",
    LivetexConnectionState.reconnecting => "Переподключение…",
    LivetexConnectionState.connected => "Ок",
  };
}