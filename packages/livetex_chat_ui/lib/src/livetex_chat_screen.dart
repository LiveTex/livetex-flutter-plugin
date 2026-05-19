import "dart:async";
import "dart:developer" as developer;
import "dart:io";

import "package:file_picker/file_picker.dart";
import "package:flutter/foundation.dart" show kDebugMode;
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
    this.showAttributesForm = true,
    this.onAttributesRequested,
  });

  final LivetexChatConfig config;
  final LivetexChat? chat;
  final String title;
  final bool autoconnect;
  final Future<void> Function(LivetexChat chat)? afterConnected;
  final LivetexChatTheme? theme;

  /// When `true` (default) the built-in `AttributesForm` is added to the
  /// bottom-area FIFO queue on every `attributesRequest` from the server.
  /// Set to `false` if the host app collects visitor info elsewhere (own
  /// onboarding, CRM lookup, etc.) and does not want the inline form. The
  /// server still expects the data eventually — the host can respond via
  /// `chat.sendAttributes(...)` directly, or hook into
  /// [onAttributesRequested] to be notified.
  final bool showAttributesForm;

  /// Called every time the server sends `attributesRequest`. Fires
  /// regardless of [showAttributesForm] — host apps that want to react
  /// (analytics, custom UI, autofill from CRM) can do so here.
  final VoidCallback? onAttributesRequested;

  @override
  State<LivetexChatScreen> createState() => _LivetexChatScreenState();
}

class _LivetexChatScreenState extends State<LivetexChatScreen>
    with WidgetsBindingObserver {
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

  /// Quoted message text the user picked via long-press → "Цитировать".
  /// When non-null, the next outgoing text is prefixed with `"> $_quoteText\n"`
  /// before being sent — matches native
  /// `ChatState.createNewTextMessage(text, quoteText)`.
  String? _quoteText;

  @override
  void initState() {
    super.initState();
    _chat = widget.chat ?? LivetexChat(widget.config);
    _ownChat = widget.chat == null;
    _scroll.addListener(_onScroll);
    WidgetsBinding.instance.addObserver(this);
    _wire();
    if (widget.autoconnect) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        unawaited(_chat.connect());
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Auto-reconnect on app resume only when we're actually idle. If we
    // are already `connecting` or `reconnecting`, firing connect() again
    // races with a backoff timer that may fire seconds later, and we'd
    // end up with two live sessions and overlapping subscriptions.
    if (state == AppLifecycleState.resumed &&
        _conn == LivetexConnectionState.disconnected) {
      unawaited(_chat.connect());
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
          // Merge incoming rate with the cached one. The server can send
          // partial state-updates — verified on device: after a successful
          // sendRating in a closed dialog the next state has rate that only
          // carries `isSet` and drops `enabledType`/`textBefore`/etc.
          final r = d?.rate;
          if (r != null) {
            final cached = _stickyTopRate;
            final merged = DialogRateState(
              enabledType: (r.enabledType?.isNotEmpty ?? false)
                  ? r.enabledType
                  : cached?.enabledType,
              commentEnabled: r.commentEnabled ?? cached?.commentEnabled,
              textBefore: r.textBefore ?? cached?.textBefore,
              textAfter: r.textAfter ?? cached?.textAfter,
              isSet: r.isSet ?? cached?.isSet,
            );
            // Mode is locked once, on the first rate payload that arrives.
            // Decision: if the dialog is unassigned at this point, the
            // backend is in "финальная" mode (rating only at end of chat);
            // otherwise "сквозная". Locking is independent of whether
            // `enabledType` is present — a state with only `isSet` (e.g.
            // when the user re-enters a dialog that was already rated)
            // still locks the mode, so the top panel actually shows.
            _ratingMode ??= d!.status == DialogStatus.unassigned
                ? _RatingMode.bottomCard
                : _RatingMode.topSticky;
            if (_ratingMode == _RatingMode.topSticky) {
              _stickyTopRate = merged;
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
        widget.onAttributesRequested?.call();
        if (!widget.showAttributesForm) return;
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
    WidgetsBinding.instance.removeObserver(this);
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

  void _diag(String msg) {
    // Guarded so we never leak file names, sizes, or paths to logcat in
    // release builds shipped inside third-party host apps.
    if (kDebugMode) developer.log(msg, name: "livetex_ui");
  }

  Future<void> _pickAndSendFile() async {
    _diag("file pick start");
    final FilePickerResult? r;
    try {
      r = await FilePicker.platform.pickFiles(
        withData: true,
        allowMultiple: false,
      );
    } catch (e) {
      _diag("file pick FAILED: $e");
      if (mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text("Не удалось открыть выбор файла")),
        );
      }
      return;
    }
    if (r == null || r.files.isEmpty) {
      _diag("file pick cancelled");
      return;
    }
    final pf = r.files.single;
    _diag("file picked size=${pf.size} hasPath=${pf.path != null} "
        "hasBytes=${pf.bytes != null}");
    if (pf.path != null && pf.path!.isNotEmpty) {
      try {
        await _chat.sendFile(File(pf.path!));
      } catch (e) {
        _diag("sendFile by path FAILED: $e");
      }
      return;
    }
    final bytes = pf.bytes;
    if (bytes == null) {
      _diag("file has neither path nor bytes — aborting");
      return;
    }
    final name = pf.name.isEmpty
        ? "upload.bin"
        : pf.name.replaceAll(RegExp(r"[/\\]"), "_");
    final tmp = File(
      "${Directory.systemTemp.path}/lt_ui_${DateTime.now().millisecondsSinceEpoch}_$name",
    );
    await tmp.writeAsBytes(bytes, flush: true);
    try {
      await _chat.sendFile(tmp, logicalName: name);
    } catch (e) {
      _diag("sendFile by bytes FAILED: $e");
    } finally {
      try {
        if (await tmp.exists()) await tmp.delete();
      } catch (_) {}
    }
  }

  void _sendText() {
    final t = _textCtrl.text.trim();
    if (t.isEmpty) return;
    // Belt-and-braces: the composer's send button is already disabled when
    // not connected, but a stray keyboard `onSubmitted` (or a race with
    // disconnect mid-tap) could still get here. Don't clear the text field
    // — the user's typed message stays so they can retry once we reconnect.
    if (_conn != LivetexConnectionState.connected) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text("Нет соединения. Сообщение не отправлено.")),
      );
      return;
    }
    final q = _quoteText;
    final payload = (q == null || q.isEmpty) ? t : "> $q\n$t";
    _textCtrl.clear();
    if (q != null) setState(() => _quoteText = null);
    _chat.sendText(payload);
  }

  void _setQuote(String text) {
    setState(() => _quoteText = text);
  }

  void _clearQuote() {
    if (_quoteText == null) return;
    setState(() => _quoteText = null);
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
        // No URL in the snackbar — server-supplied content shown verbatim
        // is a small phishing surface.
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text("Не удалось открыть ссылку")),
        );
      }
    });
  }

  Future<bool> _tryLaunchUrl(String url) async {
    try {
      final uri = Uri.tryParse(url);
      // Allowlist http/https only. Server-supplied button URLs come from a
      // chat operator/bot; an `intent://…` (Android deep-link hijack), a
      // `javascript:` URL, or a custom scheme registered by another app on
      // the device must NOT be auto-launched.
      if (uri == null || (uri.scheme != "http" && uri.scheme != "https")) {
        return false;
      }
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
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
        // No manual history button — paging is expected to come from a
        // scroll-to-top listener (see UI TODO in docs/CORE_TODOS.md).
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
              onSubmit: (value) => _chat.sendRating(
                rateType: topRate.enabledType!,
                value: value,
              ),
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
                onQuote: _setQuote,
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
      quoteText: _quoteText,
      onClearQuote: _clearQuote,
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
    required this.onQuote,
    required this.bottomRating,
  });

  final List<ChatMessage> messages;
  final ScrollController scroll;
  final bool typingVisible;
  final String? operatorName;
  final void Function(ButtonPayload) onPressBotButton;
  final ValueChanged<String> onQuote;
  final _BottomRatingDescriptor? bottomRating;

  @override
  Widget build(BuildContext context) {
    final items = _buildItems(
      messages,
      typingVisible,
      operatorName,
      onPressBotButton,
      onQuote,
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
  ValueChanged<String> onQuote,
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
    out.add(MessageTile(message: m, onQuote: onQuote));
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
