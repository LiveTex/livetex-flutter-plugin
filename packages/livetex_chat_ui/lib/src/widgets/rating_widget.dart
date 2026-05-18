import "dart:async";
import "dart:developer" as developer;

import "package:flutter/material.dart";
import "package:livetex_chat/livetex_chat.dart";

import "../livetex_chat_theme.dart";

/// Hardcoded title for the top rating panel per `rate-requirements.md` §4.1
/// (`textBefore` from the server is intentionally ignored for the top panel).
const _kTopPanelTitle = "Оцените качество обслуживания";
const _kCommentHint = "Комментарий (не обязательно)";
const _kSubmitLabel = "ОЦЕНИТЬ";
const _kCommentMaxLength = 1000;

/// Top rating panel (sticky at the top of the chat).
///
/// Per `rate-requirements.md` §4:
/// - Hardcoded title "Оцените качество обслуживания". `textBefore` is ignored.
/// - No comment field. `commentEnabled` is ignored.
/// - No `textAfter` shown.
/// - Submitted state auto-collapses with highlighted icons.
/// - Re-rating is allowed: tap a collapsed panel to re-expand and re-pick.
class TopRatingPanel extends StatefulWidget {
  const TopRatingPanel({
    super.key,
    required this.rate,
    required this.expanded,
    required this.onExpandedChanged,
    required this.onSubmit,
  });

  final DialogRateState rate;

  /// Expand/collapse is controlled from the host so an outside tap (on the
  /// message list) can collapse the panel — mirrors native
  /// `ChatActivity:339-349` (`messagesView.setOnTouchListener` →
  /// `feedbackContainerView.callOnClick()`).
  final bool expanded;
  final ValueChanged<bool> onExpandedChanged;

  final void Function(String value) onSubmit;

  @override
  State<TopRatingPanel> createState() => _TopRatingPanelState();
}

class _TopRatingPanelState extends State<TopRatingPanel> {
  /// -1 = no pick (Initial); 1..5 (fivePoint) / 0|1 (doublePoint) otherwise.
  int _picked = -1;
  bool _submitting = false;

  bool get _isFivePoint => widget.rate.enabledType == "fivePoint";
  bool get _isDoublePoint => widget.rate.enabledType == "doublePoint";

  Timer? _submitTimeout;

  @override
  void didUpdateWidget(covariant TopRatingPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Server confirmed submission — fire only on the actual transition, not
    // on any unrelated parent rebuild while `_submitting` is still true.
    final wasSet = oldWidget.rate.isSet?.value;
    final nowSet = widget.rate.isSet?.value;
    if (wasSet != nowSet && nowSet != null && _submitting) {
      _submitTimeout?.cancel();
      _submitting = false;
      _picked = -1;
      widget.onExpandedChanged(false);
    }
    // Reset selection on outside-tap collapse so the next expand starts
    // clean (matches §4.3 — re-expand resets the picked value).
    if (oldWidget.expanded && !widget.expanded && !_submitting) {
      _picked = -1;
    }
    // enabledType changed — reset selection per §4.4.
    if (oldWidget.rate.enabledType != widget.rate.enabledType) {
      _submitTimeout?.cancel();
      _picked = -1;
      _submitting = false;
    }
  }

  @override
  void dispose() {
    _submitTimeout?.cancel();
    super.dispose();
  }

  bool get _canSubmit {
    if (_isFivePoint) return _picked >= 1;
    if (_isDoublePoint) return _picked == 0 || _picked == 1;
    return false;
  }

  void _submit() {
    developer.log(
      "[top] _submit canSubmit=$_canSubmit submitting=$_submitting picked=$_picked",
      name: "livetex_ui",
    );
    if (!_canSubmit) return;
    setState(() => _submitting = true);
    widget.onSubmit(_picked.toString());
    _submitTimeout?.cancel();
    // Safety net: if the server never confirms, unblock the UI so the user
    // can retry. The actual submission may still have succeeded on the wire.
    _submitTimeout = Timer(const Duration(seconds: 10), () {
      if (!mounted || !_submitting) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text("Не удалось подтвердить оценку. Попробуйте ещё раз."),
        ),
      );
    });
  }

  int _isSetValue() {
    final raw = widget.rate.isSet?.value;
    if (raw == null) return -1;
    return int.tryParse(raw) ?? -1;
  }

  @override
  Widget build(BuildContext context) {
    final theme = LivetexChatTheme.of(context);
    // SizedBox + double.infinity makes the Material span the full screen
    // width inside the parent Column — otherwise the panel shrinks to its
    // intrinsic content size and leaves bare white strips on either side.
    return SizedBox(
      width: double.infinity,
      child: Material(
        color: theme.ratingPanelBackground,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          child: widget.expanded
              ? _buildExpanded(theme)
              : _buildCollapsed(theme),
        ),
      ),
    );
  }

  Widget _buildCollapsed(LivetexChatTheme theme) {
    final shown = _isSetValue();
    return InkWell(
      onTap: () {
        setState(() => _picked = -1); // reset selection on re-expand per §4.3
        widget.onExpandedChanged(true);
      },
      child: Row(
        children: [
          const Expanded(
            child: Text(
              _kTopPanelTitle,
              style: TextStyle(fontSize: 12, color: Color(0xFF7E7979)),
            ),
          ),
          if (_isFivePoint)
            _Stars(value: shown < 0 ? 0 : shown, size: 22, theme: theme)
          else if (_isDoublePoint)
            _Thumbs(value: shown < 0 ? -1 : shown, size: 22, theme: theme),
        ],
      ),
    );
  }

  Widget _buildExpanded(LivetexChatTheme theme) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        const Padding(
          padding: EdgeInsets.only(bottom: 16),
          child: Text(
            _kTopPanelTitle,
            style: TextStyle(fontSize: 12, color: Color(0xFF7E7979)),
          ),
        ),
        if (_isFivePoint)
          _Stars(
            value: _picked,
            size: 44,
            theme: theme,
            onPick: _submitting ? null : (v) => setState(() => _picked = v),
          )
        else if (_isDoublePoint)
          _Thumbs(
            value: _picked,
            size: 45,
            theme: theme,
            onPick: _submitting
                ? null
                : (positive) => setState(() => _picked = positive ? 1 : 0),
          ),
        const SizedBox(height: 16),
        _SubmitButton(
          enabled: _canSubmit && !_submitting,
          submitting: _submitting,
          onPressed: _submit,
        ),
      ],
    );
  }
}

/// Bottom rating form rendered as an in-list item after the last message
/// when the dialog status is `unassigned` (operator closed the dialog).
///
/// Per `rate-requirements.md` §3:
/// - Uses `textBefore` (above), `textAfter` (below the card after Submitted).
/// - Comment field rendered when `commentEnabled=true`, max 1000 chars.
/// - Submit button disabled until a value is picked; comment doesn't affect.
/// - Once Submitted (`isSet` present) the form is locked — no re-rating.
class BottomRatingForm extends StatefulWidget {
  const BottomRatingForm({
    super.key,
    required this.rate,
    required this.onSubmit,
  });

  final DialogRateState rate;
  final void Function(String value, String? comment) onSubmit;

  @override
  State<BottomRatingForm> createState() => _BottomRatingFormState();
}

class _BottomRatingFormState extends State<BottomRatingForm> {
  int _picked = -1;
  bool _submitting = false;
  Timer? _submitTimeout;
  final TextEditingController _comment = TextEditingController();

  bool get _isFivePoint => widget.rate.enabledType == "fivePoint";
  bool get _isDoublePoint => widget.rate.enabledType == "doublePoint";

  bool get _canSubmit {
    if (_isFivePoint) return _picked >= 1;
    if (_isDoublePoint) return _picked == 0 || _picked == 1;
    return false;
  }

  @override
  void didUpdateWidget(covariant BottomRatingForm oldWidget) {
    super.didUpdateWidget(oldWidget);
    // enabledType changed in-place — reset per §3.6.
    if (oldWidget.rate.enabledType != widget.rate.enabledType) {
      _submitTimeout?.cancel();
      _picked = -1;
      _submitting = false;
    }
    // Server confirmed — fire only on the actual transition.
    final wasSet = oldWidget.rate.isSet?.value;
    final nowSet = widget.rate.isSet?.value;
    if (wasSet != nowSet && nowSet != null && _submitting) {
      _submitTimeout?.cancel();
      _submitting = false;
    }
  }

  @override
  void dispose() {
    _submitTimeout?.cancel();
    _comment.dispose();
    super.dispose();
  }

  void _submit() {
    if (!_canSubmit) return;
    final c = _comment.text.trim();
    setState(() => _submitting = true);
    widget.onSubmit(_picked.toString(), c.isEmpty ? null : c);
    _submitTimeout?.cancel();
    _submitTimeout = Timer(const Duration(seconds: 10), () {
      if (!mounted || !_submitting) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(
          content: Text("Не удалось подтвердить оценку. Попробуйте ещё раз."),
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = LivetexChatTheme.of(context);
    final isSet = widget.rate.isSet;
    final isSubmitted = isSet != null;
    final textBefore = widget.rate.textBefore?.trim() ?? "";
    final textAfter = widget.rate.textAfter?.trim() ?? "";
    final commentEnabled = widget.rate.commentEnabled ?? false;
    return Padding(
      padding: const EdgeInsets.fromLTRB(18, 12, 18, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            decoration: BoxDecoration(
              color: theme.ratingFormBackground,
              borderRadius: BorderRadius.circular(theme.controlRadius),
            ),
            padding: const EdgeInsets.all(16),
            child: isSubmitted
                ? _buildSubmitted(theme, isSet)
                : _buildEditable(theme, textBefore, commentEnabled),
          ),
          if (isSubmitted && textAfter.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 16),
              child: Center(
                child: Text(
                  textAfter,
                  style: TextStyle(fontSize: 12, color: theme.systemText),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildEditable(
    LivetexChatTheme theme,
    String textBefore,
    bool commentEnabled,
  ) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (textBefore.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text(
              textBefore,
              style: TextStyle(fontSize: 14, color: theme.incomingText),
              textAlign: TextAlign.center,
            ),
          ),
        if (_isFivePoint)
          _Stars(
            value: _picked,
            size: 44,
            theme: theme,
            onPick: _submitting ? null : (v) => setState(() => _picked = v),
          )
        else if (_isDoublePoint)
          _Thumbs(
            value: _picked,
            size: 45,
            theme: theme,
            onPick: _submitting
                ? null
                : (positive) => setState(() => _picked = positive ? 1 : 0),
          ),
        if (commentEnabled) ...[
          const SizedBox(height: 16),
          TextField(
            controller: _comment,
            enabled: !_submitting,
            maxLength: _kCommentMaxLength,
            maxLines: 5,
            minLines: 2,
            style: TextStyle(fontSize: 14, color: theme.composerText),
            decoration: InputDecoration(
              hintText: _kCommentHint,
              hintStyle: TextStyle(color: theme.composerHint),
              counterText: "",
              filled: true,
              fillColor: Colors.white,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(theme.controlRadius),
                borderSide: BorderSide(color: theme.composerFieldStroke),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(theme.controlRadius),
                borderSide: BorderSide(color: theme.composerFieldStroke),
              ),
            ),
          ),
        ],
        const SizedBox(height: 16),
        _SubmitButton(
          enabled: _canSubmit && !_submitting,
          submitting: _submitting,
          onPressed: _submit,
        ),
      ],
    );
  }

  Widget _buildSubmitted(LivetexChatTheme theme, SetRatePayload isSet) {
    final value = int.tryParse(isSet.value) ?? 0;
    final comment = isSet.comment?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        if (_isFivePoint)
          _Stars(value: value, size: 22, theme: theme)
        else if (_isDoublePoint)
          _Thumbs(value: value, size: 22, theme: theme),
        if (comment != null && comment.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              comment,
              style: TextStyle(fontSize: 14, color: theme.incomingText),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

class _SubmitButton extends StatelessWidget {
  const _SubmitButton({
    required this.enabled,
    required this.submitting,
    required this.onPressed,
  });

  final bool enabled;
  final bool submitting;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final theme = LivetexChatTheme.of(context);
    return SizedBox(
      height: 36,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          backgroundColor:
              enabled ? theme.ratingButton : theme.ratingButtonDisabledBg,
          foregroundColor:
              enabled ? theme.ratingButtonText : theme.ratingButtonDisabledText,
          disabledForegroundColor: theme.ratingButtonDisabledText,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(theme.controlRadius),
          ),
          side: BorderSide(
            color: enabled
                ? theme.ratingButtonStroke
                : theme.ratingButtonStrokeDisabled,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 24),
        ),
        onPressed: enabled ? onPressed : null,
        child: submitting
            ? const SizedBox(
                width: 14,
                height: 14,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: Colors.white,
                ),
              )
            : const Text(_kSubmitLabel, style: TextStyle(fontSize: 14)),
      ),
    );
  }
}

class _Stars extends StatelessWidget {
  const _Stars({
    required this.value,
    required this.size,
    required this.theme,
    this.onPick,
  });

  /// 0..5 — number of filled stars.
  final int value;
  final double size;
  final LivetexChatTheme theme;
  final ValueChanged<int>? onPick;

  @override
  Widget build(BuildContext context) {
    final inactive = theme.systemText.withValues(alpha: 0.6);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: size > 28 ? 4 : 2),
            child: _Tappable(
              onTap: onPick == null ? null : () => onPick!(i + 1),
              child: Icon(
                i < value ? Icons.star_rounded : Icons.star_outline_rounded,
                size: size,
                color: i < value ? theme.ratingStarActive : inactive,
              ),
            ),
          ),
      ],
    );
  }
}

class _Thumbs extends StatelessWidget {
  const _Thumbs({
    required this.value,
    required this.size,
    required this.theme,
    this.onPick,
  });

  /// 1 = up, 0 = down, -1 = nothing.
  final int value;
  final double size;
  final LivetexChatTheme theme;
  final ValueChanged<bool>? onPick;

  @override
  Widget build(BuildContext context) {
    final up = value == 1;
    final down = value == 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        _Tappable(
          onTap: onPick == null ? null : () => onPick!(true),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: size > 28 ? 26 : 8),
            child: Icon(
              up ? Icons.thumb_up_alt : Icons.thumb_up_alt_outlined,
              size: size,
              color: up ? theme.ratingThumbUp : theme.ratingThumbInactive,
            ),
          ),
        ),
        _Tappable(
          onTap: onPick == null ? null : () => onPick!(false),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: size > 28 ? 26 : 8),
            child: Icon(
              down ? Icons.thumb_down_alt : Icons.thumb_down_alt_outlined,
              size: size,
              color: down ? theme.ratingThumbDown : theme.ratingThumbInactive,
            ),
          ),
        ),
      ],
    );
  }
}

class _Tappable extends StatelessWidget {
  const _Tappable({required this.child, required this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (onTap == null) return child;
    return InkResponse(
      onTap: onTap,
      radius: 28,
      child: child,
    );
  }
}
