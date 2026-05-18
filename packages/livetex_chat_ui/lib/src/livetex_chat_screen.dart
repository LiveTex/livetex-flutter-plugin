import "dart:async";
import "dart:developer" as developer;
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

/// Detected once per screen lifetime — see `_ratingMode` doc.
enum _RatingMode { topSticky, bottomCard }

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

  /// Auto-follow tail only when the user is already at (or near) the bottom.
  /// Mirrors common chat UX — don't yank the user away from history they're
  /// reading just because a new message arrived.
  bool _userAtBottom = true;

  List<ChatMessage> _messages = const [];
  VisitorDialogState? _dialog;
  LivetexConnectionState _conn = LivetexConnectionState.disconnected;

  /// Mode picked once, on the first `rate` payload of the session, and kept
  /// for the rest of the screen lifetime:
  /// - `topSticky`  — first rate arrived while the dialog was assigned
  ///   (admin configured "сквозная"). Show top panel forever; never bottom.
  /// - `bottomCard` — first rate arrived while the dialog was already
  ///   unassigned (admin configured "финальная"). Show bottom card per
  ///   current state; never top. Bottom is not sticky — if the state stops
  ///   carrying a rate, the card disappears, mirroring native
  ///   `ChatViewModel.onDialogStateUpdate:559-562`.
  /// Locked once chosen so a routine operator action (e.g. reopening the
  /// closed dialog) cannot accidentally flip a "финальная" configuration
  /// into a top panel.
  _RatingMode? _ratingMode;

  /// Latest rate payload — refreshed on every state that carries one. Used
  /// only when `_ratingMode == _RatingMode.topSticky` to drive the top
  /// panel. Mirrors native `pendingRatingPanelState` + `ChatActivity`
  /// fallback at `updateDialogState:795-803`: even after operator closes
  /// the dialog or a WebSocket reconnect strips `rate` from the next
  /// `dialogState`, the top panel keeps showing this cached payload until
  /// the screen is destroyed (force-quit).
  DialogRateState? _stickyTopRate;

  /// Top panel expand/collapse — lifted to the screen so a tap anywhere in
  /// the message list collapses an open panel, matching native
  /// `ChatActivity:339-349` (`messagesView.setOnTouchListener` →
  /// `feedbackContainerView.callOnClick()`).
  bool _topRatingExpanded = false;

  bool _typingVisible = false;
  Timer? _typingTimer;
  DateTime? _lastTypingSent;

  bool _afterConnectDone = false;

  final List<_PendingBottom> _bottomQueue = [];
  List<DepartmentItem> _pendingDepartments = const [];

  @override
  void initState() {
    super.initState();
    _chat = widget.chat ?? LivetexChat(widget.config);
    _ownChat = widget.chat == null;
    _scroll.addListener(_onScroll);
    _wire();
    if (widget.autoconnect) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_chat.connect());
      });
    }
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    // 80px tolerance: treat "just above the bottom" as still-at-bottom, so a
    // momentary overscroll or a small lift while reading new messages keeps
    // auto-follow on.
    final atBottom = pos.pixels >= pos.maxScrollExtent - 80;
    if (atBottom != _userAtBottom) _userAtBottom = atBottom;
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
          // Lock the rating mode on the very first rate payload. After that
          // routine status transitions (operator closing/reopening the
          // dialog) cannot flip a "финальная" config into a top panel or
          // vice versa. The top panel keeps a cached `_stickyTopRate` so it
          // survives a reconnect that omits `rate`; bottom is rebuilt from
          // the current state each time.
          final r = d?.rate;
          if (r != null && (r.enabledType?.isNotEmpty ?? false)) {
            _ratingMode ??= d!.status == DialogStatus.unassigned
                ? _RatingMode.bottomCard
                : _RatingMode.topSticky;
            if (_ratingMode == _RatingMode.topSticky) {
              _stickyTopRate = r;
            }
          }
          // Drop the department picker only when an operator is actually
          // attached (`assigned`) — that's the case the server routed for
          // us. `aiBot` is still a valid moment to show the picker (the
          // bot is asking which queue to hand over to), so don't yank it
          // away just because the status moved off `unassigned`.
          if (d?.status == DialogStatus.assigned &&
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
        // Only ignore if an operator is already attached to the dialog
        // (`assigned`) — that covers the post-reconnect dup-request case
        // where the dialog was routed via the admin panel while we were
        // offline. Other states (`aiBot`, `inQueue`, `unassigned`) are
        // legitimate moments for the picker: a bot offering to hand the
        // chat over to a human is the most common one, and gating that
        // out hides the picker entirely.
        if (_dialog?.status == DialogStatus.assigned) {
          return;
        }
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
    if (!_userAtBottom) return;
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
    _scroll.removeListener(_onScroll);
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

  void _onPressBotButton(ButtonPayload b) {
    _chat.pressButton(payload: b.payload);
    final url = b.url;
    if (url == null || url.isEmpty) return;
    // Native delays by 300ms so the visual press effect is visible.
    Future<void>.delayed(const Duration(milliseconds: 300), () async {
      if (!mounted) return;
      final ok = await _tryLaunchUrl(url);
      if (!ok && mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text("Не удалось открыть ссылку: $url")),
        );
      }
    });
  }

  Future<bool> _tryLaunchUrl(String url) async {
    try {
      return await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
    } catch (_) {
      return false;
    }
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
    // `_ratingMode` is locked on the first rate payload — see its doc.
    //   topSticky  → top panel for the rest of the session (sticky cache).
    //   bottomCard → bottom card driven by current state; not sticky, so
    //                disappears if the operator reopens the dialog or the
    //                server stops sending rate (mirrors native).
    final stateRate = d?.rate;
    final hasStateRate =
        stateRate != null && (stateRate.enabledType?.isNotEmpty ?? false);
    final isUnassigned = d?.status == DialogStatus.unassigned;
    final topRate = _stickyTopRate;
    final showTopRating =
        _ratingMode == _RatingMode.topSticky && topRate != null;
    final showBottomRating = _ratingMode == _RatingMode.bottomCard &&
        hasStateRate &&
        isUnassigned;
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
              key: ValueKey("top-${topRate.enabledType}"),
              rate: topRate,
              expanded: _topRatingExpanded,
              onExpandedChanged: (v) =>
                  setState(() => _topRatingExpanded = v),
              onSubmit: (value) {
                developer.log(
                  "[ui] TOP onSubmit value=$value "
                  "conn=$_conn "
                  "stickyType=${_stickyTopRate?.enabledType} "
                  "stateStatus=${_dialog?.status} "
                  "stateRate.enabledType=${_dialog?.rate?.enabledType} "
                  "stateRate.isSet=${_dialog?.rate?.isSet?.value}",
                  name: "livetex_ui",
                );
                _chat.sendRating(
                  rateType: topRate.enabledType!,
                  value: value,
                );
              },
            ),
          Expanded(
            child: GestureDetector(
              // Tap on the message list collapses an open top rating panel,
              // mirroring native ChatActivity:339-349. `translucent` so
              // taps on actual children (messages, bot keyboard) still
              // reach them.
              behavior: HitTestBehavior.translucent,
              onTap: _topRatingExpanded
                  ? () => setState(() => _topRatingExpanded = false)
                  : null,
              child: _MessageList(
                messages: _messages,
                scroll: _scroll,
                typingVisible: _typingVisible,
                operatorName: d?.employee?.name,
                onPressBotButton: _onPressBotButton,
                bottomRating: showBottomRating
                    ? _BottomRatingDescriptor(
                        rate: stateRate,
                        onSubmit: (value, comment) => _chat.sendRating(
                          rateType: stateRate.enabledType!,
                          value: value,
                          comment: comment,
                        ),
                      )
                    : null,
              ),
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
    required this.onPressBotButton,
    required this.bottomRating,
  });

  final List<ChatMessage> messages;
  final ScrollController scroll;
  final bool typingVisible;
  final String? operatorName;
  final void Function(ButtonPayload) onPressBotButton;
  final _BottomRatingDescriptor? bottomRating;

  @override
  Widget build(BuildContext context) {
    final items = _buildItems(
      messages,
      typingVisible,
      operatorName,
      onPressBotButton,
    );
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
  void Function(ButtonPayload) onPressBotButton,
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
      out.add(BotKeyboard(keyboard: kb, onPress: onPressBotButton));
    }
  }
  if (typingVisible) {
    out.add(TypingTile(operatorName: operatorName));
  }
  return out;
}
