import "dart:async";
import "dart:io";

import "package:file_picker/file_picker.dart";
import "package:flutter/material.dart";
import "package:livetex_chat/livetex_chat.dart";
import "package:url_launcher/url_launcher.dart";

import "livetex_chat_theme.dart";
import "widgets/attributes_form.dart";
import "widgets/bot_keyboard.dart";
import "widgets/composer.dart";
import "widgets/connection_banner.dart";
import "widgets/department_picker.dart";
import "widgets/message_tile.dart";
import "widgets/rating_widget.dart";

/// Pending bottom-area state, mirrors native `ChatViewState` FIFO queue
/// (attributes / departments forms replace the composer one at a time).
enum _PendingBottom { attributes, departments }

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

  List<ChatMessage> _messages = const [];
  VisitorDialogState? _dialog;
  DialogRateState? _lastRate; // Sticky per rate-requirements.md §2.3
  LivetexConnectionState _conn = LivetexConnectionState.disconnected;

  bool _typingVisible = false;
  Timer? _typingTimer;
  DateTime? _lastTypingSent;

  bool _afterConnectDone = false;
  bool _topRatingShownOnce = false;

  final List<_PendingBottom> _bottomQueue = [];
  List<DepartmentItem> _pendingDepartments = const [];

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
        if (!mounted) return;
        setState(() => _conn = s);
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
        if (!mounted) return;
        setState(() {
          _dialog = d;
          if (d?.rate?.enabledType?.isNotEmpty ?? false) {
            _lastRate = d!.rate;
            if (d.status != DialogStatus.unassigned) {
              _topRatingShownOnce = true;
            }
          }
          // Drop department picker if the dialog moved to an assigned state
          // before the user picked — server routed it for us.
          if (d != null &&
              d.status != DialogStatus.unassigned &&
              _bottomQueue.contains(_PendingBottom.departments)) {
            _bottomQueue.remove(_PendingBottom.departments);
          }
        });
      }),
      _chat.messages.listen((m) {
        if (!mounted) return;
        setState(() => _messages = List.from(m));
        _scrollToEnd();
      }),
      _chat.errors.listen((e) {
        if (!mounted) return;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(e.message)),
        );
      }),
      _chat.attributesRequest.listen((_) {
        if (!mounted) return;
        setState(() {
          if (!_bottomQueue.contains(_PendingBottom.attributes)) {
            _bottomQueue.add(_PendingBottom.attributes);
          }
        });
      }),
      _chat.departmentRequest.listen((deps) {
        if (!mounted) return;
        if (deps.isEmpty) return;
        if (deps.length == 1) {
          final corr = "dep-${DateTime.now().millisecondsSinceEpoch}";
          _chat.selectDepartment(correlationId: corr, id: deps.first.id);
          return;
        }
        setState(() {
          _pendingDepartments = deps;
          if (!_bottomQueue.contains(_PendingBottom.departments)) {
            _bottomQueue.add(_PendingBottom.departments);
          }
        });
      }),
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

  void _submitAttributes({String? name, String? phone, String? email}) {
    final corr = "attr-${DateTime.now().millisecondsSinceEpoch}";
    _chat.sendAttributes(
      correlationId: corr,
      name: name,
      phone: phone,
      email: email,
      attributes: const {},
    );
    if (!mounted) return;
    setState(() {
      _bottomQueue.remove(_PendingBottom.attributes);
    });
  }

  void _selectDepartment(DepartmentItem d) {
    final corr = "dep-${DateTime.now().millisecondsSinceEpoch}";
    _chat.selectDepartment(correlationId: corr, id: d.id);
    if (!mounted) return;
    setState(() {
      _bottomQueue.remove(_PendingBottom.departments);
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = widget.theme ?? LivetexChatTheme.livetex();
    return LivetexChatThemeScope(
      theme: theme,
      child: _buildScaffold(theme),
    );
  }

  Widget _buildScaffold(LivetexChatTheme theme) {
    final d = _dialog;
    final displayRate = _lastRate ?? d?.rate;
    final hasRate =
        displayRate != null && (displayRate.enabledType?.isNotEmpty ?? false);
    final isUnassigned = d?.status == DialogStatus.unassigned;
    final showTopRating =
        hasRate && (!isUnassigned || _topRatingShownOnce);
    final showBottomRating = hasRate && isUnassigned;
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
            ConnectionBanner(state: _conn, onRetry: () => _chat.connect()),
          if (showTopRating)
            TopRatingPanel(
              key: ValueKey("top-${displayRate.enabledType}"),
              rate: displayRate,
              onSubmit: (value) => _chat.sendRating(
                rateType: displayRate.enabledType!,
                value: value,
              ),
            ),
          Expanded(
            child: _MessageList(
              messages: _messages,
              scroll: _scroll,
              typingVisible: _typingVisible,
              operatorName: d?.employee?.name,
              bottomRating: showBottomRating
                  ? _BottomRatingDescriptor(
                      rate: displayRate,
                      onSubmit: (value, comment) => _chat.sendRating(
                        rateType: displayRate.enabledType!,
                        value: value,
                        comment: comment,
                      ),
                    )
                  : null,
            ),
          ),
          _buildBottomArea(theme, d),
        ],
      ),
    );
  }

  Widget _buildBottomArea(LivetexChatTheme theme, VisitorDialogState? d) {
    // Pending forms (attributes / departments) take priority — they replace
    // the composer, mirroring native `ChatActivity` FIFO logic.
    final pending = _bottomQueue.isEmpty ? null : _bottomQueue.first;
    if (pending == _PendingBottom.attributes) {
      return AttributesForm(
        onSubmit: ({String? name, String? phone, String? email}) =>
            _submitAttributes(name: name, phone: phone, email: email),
      );
    }
    if (pending == _PendingBottom.departments &&
        _pendingDepartments.isNotEmpty) {
      return DepartmentPicker(
        departments: _pendingDepartments,
        onSelect: _selectDepartment,
      );
    }
    // showInput=false ⇒ HIDDEN: hide composer entirely (bot is working).
    if (d != null && !d.showInput) return const SizedBox.shrink();
    // Otherwise show the composer. Disabled (greyed send) when not connected.
    return Composer(
      controller: _textCtrl,
      onSend: _sendText,
      onChanged: _onComposerChanged,
      onAttach: _pickAndSendFile,
      enabled: _conn == LivetexConnectionState.connected,
    );
  }
}

class _BottomRatingDescriptor {
  const _BottomRatingDescriptor({required this.rate, required this.onSubmit});

  final DialogRateState rate;
  final void Function(String value, String? comment) onSubmit;
}

class _MessageList extends StatelessWidget {
  const _MessageList({
    required this.messages,
    required this.scroll,
    required this.typingVisible,
    required this.operatorName,
    required this.bottomRating,
  });

  final List<ChatMessage> messages;
  final ScrollController scroll;
  final bool typingVisible;
  final String? operatorName;
  final _BottomRatingDescriptor? bottomRating;

  @override
  Widget build(BuildContext context) {
    final items = _buildItems(messages, typingVisible, operatorName, context);
    if (bottomRating != null) {
      items.add(
        BottomRatingForm(
          key: ValueKey("bottom-${bottomRating!.rate.enabledType}"),
          rate: bottomRating!.rate,
          onSubmit: bottomRating!.onSubmit,
        ),
      );
    }
    return ListView.builder(
      controller: scroll,
      padding: const EdgeInsets.fromLTRB(8, 12, 8, 12),
      itemCount: items.length,
      itemBuilder: (_, i) => items[i],
    );
  }
}

List<Widget> _buildItems(
  List<ChatMessage> messages,
  bool typingVisible,
  String? operatorName,
  BuildContext context,
) {
  final out = <Widget>[];
  DateTime? prevDay;
  for (var i = 0; i < messages.length; i++) {
    final m = messages[i];
    final local = m.createdAt.toLocal();
    final day = DateTime(local.year, local.month, local.day);
    if (prevDay == null || day != prevDay) {
      out.add(DateSeparator(date: local));
      prevDay = day;
    }
    out.add(MessageTile(message: m));
    // Bot keyboard rendered as a separate, full-width component below the
    // message bubble (mirrors native `buttonsContainerView` in
    // `i_chat_message_in.xml`).
    final kb = m.keyboard;
    if (!m.isVisitor && kb != null && kb.buttons.isNotEmpty) {
      out.add(BotKeyboard(
        keyboard: kb,
        onPress: (b) {
          final st = context
              .findAncestorStateOfType<_LivetexChatScreenState>();
          st?._chat.pressButton(payload: b.payload);
          if (b.url != null && b.url!.isNotEmpty) {
            Future<void>.delayed(
              const Duration(milliseconds: 300),
              () {
                // Best-effort: open URL in external app (kept lightweight here;
                // a button can be both `payload` and `url`, and native delays
                // by 300ms for the visual press effect).
                // ignore: discarded_futures
                _launchUrl(b.url!);
              },
            );
          }
        },
      ));
    }
  }
  if (typingVisible) {
    out.add(TypingTile(operatorName: operatorName));
  }
  return out;
}

Future<void> _launchUrl(String url) async {
  try {
    await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
  } catch (_) {
    // Silently ignore — the bot payload has already been sent.
  }
}
