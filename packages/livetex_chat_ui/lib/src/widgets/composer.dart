import "package:flutter/material.dart";

import "../livetex_chat_theme.dart";

/// Bottom composer. Three operational states, mirroring native
/// `ChatInputState` (NORMAL / DISABLED / HIDDEN):
/// - HIDDEN — when `showInput=false` from the dialog state; the screen
///   should NOT render this widget at all (return null upstream).
/// - DISABLED — when not connected; the field stays visible, send icon
///   greyed out so the user keeps their typed text in view.
/// - NORMAL — connected and ready.
class Composer extends StatefulWidget {
  const Composer({
    super.key,
    required this.controller,
    required this.onSend,
    required this.onChanged,
    required this.onAttach,
    required this.enabled,
    this.quoteText,
    this.onClearQuote,
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final ValueChanged<String> onChanged;
  final Future<void> Function() onAttach;
  final bool enabled;

  /// When non-null, a one-line preview of the quoted message is rendered
  /// above the input. Mirrors native `quoteContainerView` (see
  /// `ChatActivity:701-703`).
  final String? quoteText;

  /// Called when the user taps the `×` on the quote preview to discard it.
  final VoidCallback? onClearQuote;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> with WidgetsBindingObserver {
  bool _hasText = false;
  final FocusNode _focusNode = FocusNode();

  /// Tracks last-known keyboard visibility from `viewInsets.bottom`. We need
  /// the previous value to detect the *transition* from visible-to-hidden
  /// (a system gesture / IME hide button) — that's the case where Flutter
  /// keeps focus on the field but the OS dropped the keyboard, leaving a
  /// re-tap as a no-op.
  bool _keyboardVisible = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    widget.controller.addListener(_onCtrl);
    _hasText = widget.controller.text.trim().isNotEmpty;
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.controller.removeListener(_onCtrl);
    _focusNode.dispose();
    super.dispose();
  }

  void _onCtrl() {
    final has = widget.controller.text.trim().isNotEmpty;
    if (has != _hasText && mounted) setState(() => _hasText = has);
  }

  @override
  void didChangeMetrics() {
    // `viewInsets.bottom` is the soft-keyboard height; it goes to 0 when
    // the IME hides for ANY reason (system swipe-down, "↓" navigation
    // button, programmatic dismiss). We need a post-frame read so the new
    // metrics are visible from MediaQuery.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final nowVisible = MediaQuery.of(context).viewInsets.bottom > 0;
      if (_keyboardVisible && !nowVisible && _focusNode.hasFocus) {
        // Workaround for Flutter issue where a system-gesture dismiss
        // closes the IME without dropping focus. Without this unfocus, the
        // next tap on the field is a no-op (Flutter thinks the field is
        // already focused, so it doesn't re-ask the IME to show), and the
        // user can't type until they tap *another* field first.
        _focusNode.unfocus();
      }
      _keyboardVisible = nowVisible;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = LivetexChatTheme.of(context);
    final canSend = widget.enabled && _hasText;
    final addColor = widget.enabled
        ? theme.composerAddAction
        : theme.composerAddActionDisabled;
    final sendColor =
        canSend ? theme.composerAction : theme.composerActionDisabled;
    final quote = widget.quoteText;
    return Material(
      color: theme.composerBackground,
      elevation: 0,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(18, 8, 18, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (quote != null && quote.isNotEmpty)
                _QuotePreview(
                  text: quote,
                  onClear: widget.onClearQuote ?? () {},
                ),
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
              IconButton(
                tooltip: "Прикрепить",
                onPressed: widget.enabled ? widget.onAttach : null,
                icon: Icon(Icons.add, size: 28, color: addColor),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 42,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: theme.composerField,
                    borderRadius:
                        BorderRadius.circular(theme.composerFieldRadius),
                    border: Border.all(color: theme.composerFieldStroke),
                  ),
                  child: TextField(
                    controller: widget.controller,
                    focusNode: _focusNode,
                    // Field stays editable even when disconnected so the user
                    // can keep / correct their typed text; only the send icon
                    // is greyed out (mirrors native ChatActivity DISABLED).
                    minLines: 1,
                    maxLines: 4,
                    maxLength: 2000,
                    style:
                        TextStyle(fontSize: 18, color: theme.composerText),
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
                    onSubmitted:
                        canSend ? (_) => widget.onSend() : null,
                  ),
                ),
              ),
              const SizedBox(width: 8),
              IconButton(
                tooltip: "Отправить",
                onPressed: canSend ? widget.onSend : null,
                icon: Icon(Icons.send, size: 26, color: sendColor),
                padding: EdgeInsets.zero,
                constraints: const BoxConstraints(
                  minWidth: 32,
                  minHeight: 42,
                ),
              ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// One-line preview of a quoted message shown above the composer input,
/// mirroring native `quoteContainerView` in `a_chat.xml`. Close button
/// discards the quote without affecting any typed text.
class _QuotePreview extends StatelessWidget {
  const _QuotePreview({required this.text, required this.onClear});

  final String text;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final theme = LivetexChatTheme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(width: 2, color: theme.quoteAccent),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      "Ответ на сообщение",
                      style: TextStyle(
                        fontSize: 11,
                        color: theme.quoteAccent,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.composerText,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: "Убрать цитату",
              onPressed: onClear,
              icon: Icon(Icons.close, size: 18, color: theme.composerHint),
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
      ),
    );
  }
}
