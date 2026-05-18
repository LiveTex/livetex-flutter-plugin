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
  });

  final TextEditingController controller;
  final VoidCallback onSend;
  final ValueChanged<String> onChanged;
  final Future<void> Function() onAttach;
  final bool enabled;

  @override
  State<Composer> createState() => _ComposerState();
}

class _ComposerState extends State<Composer> {
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
    final canSend = widget.enabled && _hasText;
    final addColor = widget.enabled
        ? theme.composerAddAction
        : theme.composerAddActionDisabled;
    final sendColor =
        canSend ? theme.composerAction : theme.composerActionDisabled;
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
                    enabled: widget.enabled,
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
        ),
      ),
    );
  }
}
