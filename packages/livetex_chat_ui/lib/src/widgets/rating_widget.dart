import "package:flutter/material.dart";
import "package:livetex_chat/livetex_chat.dart";

import "../livetex_chat_theme.dart";

/// One parameterized widget covering all rating placements/states/types.
///
/// State machine:
///   - If [rate.isSet] is non-null OR the user just submitted a value, render
///     the **result** view (read-only, shows the chosen value and `textAfter`).
///   - Else if [initiallyExpanded] is true OR the user tapped to expand,
///     render the **interactive** view (large stars/thumbs, optional comment,
///     submit button disabled until a value is picked).
///   - Else render the **collapsed** view (label + small indicator).
///
/// Type is driven by [rate.enabledType] ∈ {`fivePoint`, `doublePoint`}.
class RatingWidget extends StatefulWidget {
  const RatingWidget({
    super.key,
    required this.rate,
    required this.onSubmit,
    required this.background,
    this.initiallyExpanded = false,
    this.padding = const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
  });

  final DialogRateState rate;
  final void Function(String value, String? comment) onSubmit;
  final Color background;
  final bool initiallyExpanded;
  final EdgeInsets padding;

  @override
  State<RatingWidget> createState() => _RatingWidgetState();
}

class _RatingWidgetState extends State<RatingWidget> {
  /// Sentinel `-1` = not picked yet. Otherwise:
  /// - `fivePoint`: 1..5
  /// - `doublePoint`: 0 (negative) | 1 (positive)
  int _picked = -1;
  bool _expanded = false;
  String? _localComment;
  bool _localSubmitted = false;
  late final TextEditingController _commentCtrl;

  @override
  void initState() {
    super.initState();
    _expanded = widget.initiallyExpanded;
    _commentCtrl = TextEditingController();
  }

  @override
  void dispose() {
    _commentCtrl.dispose();
    super.dispose();
  }

  bool get _isFivePoint => widget.rate.enabledType == "fivePoint";
  bool get _isDoublePoint => widget.rate.enabledType == "doublePoint";

  bool get _canSubmit {
    if (_isFivePoint) return _picked >= 1;
    if (_isDoublePoint) return _picked == 0 || _picked == 1;
    return false;
  }

  int _intOrZero(String? raw) {
    if (raw == null) return 0;
    return int.tryParse(raw) ?? 0;
  }

  void _submit() {
    if (!_canSubmit) return;
    final value = _picked.toString();
    final comment = _commentCtrl.text.trim().isEmpty
        ? null
        : _commentCtrl.text.trim();
    setState(() {
      _localSubmitted = true;
      _localComment = comment;
    });
    widget.onSubmit(value, comment);
  }

  @override
  Widget build(BuildContext context) {
    final theme = LivetexChatTheme.of(context);
    final isSet = widget.rate.isSet;
    final showResult = isSet != null || _localSubmitted;
    final Widget body;
    if (showResult) {
      body = _buildResult(theme, isSet);
    } else if (_expanded) {
      body = _buildInteractive(theme);
    } else {
      body = _buildCollapsed(theme);
    }
    return Material(
      color: widget.background,
      child: Padding(
        padding: widget.padding,
        child: body,
      ),
    );
  }

  Widget _buildCollapsed(LivetexChatTheme theme) {
    final label = (widget.rate.textBefore?.trim().isNotEmpty ?? false)
        ? widget.rate.textBefore!.trim()
        : "Оцените качество обслуживания";
    return InkWell(
      onTap: () => setState(() => _expanded = true),
      child: Row(
        children: [
          Expanded(
            child: Text(
              label,
              style: TextStyle(fontSize: 12, color: theme.systemText),
            ),
          ),
          if (_isFivePoint)
            _SmallStars(value: 0, theme: theme)
          else if (_isDoublePoint)
            _SmallThumbs(value: -1, theme: theme),
        ],
      ),
    );
  }

  Widget _buildInteractive(LivetexChatTheme theme) {
    final textBefore = widget.rate.textBefore?.trim() ?? "";
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
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
        Center(
          child: _isFivePoint
              ? _LargeStars(
                  value: _picked,
                  theme: theme,
                  onPick: (v) => setState(() => _picked = v),
                )
              : _LargeThumbs(
                  value: _picked,
                  theme: theme,
                  onPick: (positive) =>
                      setState(() => _picked = positive ? 1 : 0),
                ),
        ),
        if (widget.rate.commentEnabled ?? false)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: TextField(
              controller: _commentCtrl,
              maxLength: 1000,
              maxLines: 4,
              minLines: 2,
              style: TextStyle(fontSize: 14, color: theme.composerText),
              decoration: InputDecoration(
                hintText: "Комментарий (не обязательно)",
                hintStyle: TextStyle(color: theme.composerHint),
                counterText: "",
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 8,
                ),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(theme.controlRadius),
                  borderSide: BorderSide(color: theme.composerHint),
                ),
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.only(top: 16),
          child: Center(
            child: SizedBox(
              height: 36,
              child: FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: theme.ratingButton,
                  foregroundColor: theme.ratingButtonText,
                  disabledBackgroundColor:
                      theme.ratingButton.withValues(alpha: 0.08),
                  disabledForegroundColor:
                      theme.composerText.withValues(alpha: 0.25),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(theme.controlRadius),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 24),
                ),
                onPressed: _canSubmit ? _submit : null,
                child: const Text("Оценить", style: TextStyle(fontSize: 14)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildResult(LivetexChatTheme theme, SetRatePayload? isSet) {
    final serverValue = _intOrZero(isSet?.value);
    final value = isSet != null
        ? serverValue
        : (_isFivePoint ? _picked : (_picked >= 0 ? _picked : 0));
    final comment = isSet?.comment ?? _localComment;
    final textAfter = widget.rate.textAfter?.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Center(
          child: _isFivePoint
              ? _SmallStars(value: value, theme: theme)
              : _SmallThumbs(value: value, theme: theme),
        ),
        if (comment != null && comment.trim().isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              comment.trim(),
              style: TextStyle(fontSize: 14, color: theme.incomingText),
              textAlign: TextAlign.center,
            ),
          ),
        if (textAfter != null && textAfter.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 16),
            child: Text(
              textAfter,
              style: TextStyle(fontSize: 12, color: theme.systemText),
              textAlign: TextAlign.center,
            ),
          ),
      ],
    );
  }
}

class _SmallStars extends StatelessWidget {
  const _SmallStars({required this.value, required this.theme});

  final int value;
  final LivetexChatTheme theme;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++)
          Padding(
            padding: const EdgeInsets.only(left: 4),
            child: Icon(
              i < value ? Icons.star_rounded : Icons.star_outline_rounded,
              size: 22,
              color: i < value
                  ? theme.ratingStarActive
                  : theme.systemText.withValues(alpha: 0.6),
            ),
          ),
      ],
    );
  }
}

class _LargeStars extends StatelessWidget {
  const _LargeStars({
    required this.value,
    required this.theme,
    required this.onPick,
  });

  final int value;
  final LivetexChatTheme theme;
  final ValueChanged<int> onPick;

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < 5; i++)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
              onTap: () => onPick(i + 1),
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: Icon(
                  i < value ? Icons.star_rounded : Icons.star_outline_rounded,
                  size: 44,
                  color: i < value
                      ? theme.ratingStarActive
                      : theme.systemText.withValues(alpha: 0.6),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _SmallThumbs extends StatelessWidget {
  const _SmallThumbs({required this.value, required this.theme});

  /// 1 = positive, 0 = negative, -1 = nothing picked.
  final int value;
  final LivetexChatTheme theme;

  @override
  Widget build(BuildContext context) {
    final upActive = value == 1;
    final downActive = value == 0;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          upActive ? Icons.thumb_up_alt : Icons.thumb_up_alt_outlined,
          size: 22,
          color: upActive
              ? Colors.green
              : theme.systemText.withValues(alpha: 0.5),
        ),
        const SizedBox(width: 16),
        Icon(
          downActive ? Icons.thumb_down_alt : Icons.thumb_down_alt_outlined,
          size: 22,
          color: downActive
              ? Colors.red
              : theme.systemText.withValues(alpha: 0.5),
        ),
      ],
    );
  }
}

class _LargeThumbs extends StatelessWidget {
  const _LargeThumbs({
    required this.value,
    required this.theme,
    required this.onPick,
  });

  /// 1 = positive picked, 0 = negative picked, -1 = nothing picked.
  final int value;
  final LivetexChatTheme theme;
  final ValueChanged<bool> onPick;

  @override
  Widget build(BuildContext context) {
    final upActive = value == 1;
    final downActive = value == 0;
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onPick(true),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Icon(
              upActive ? Icons.thumb_up_alt : Icons.thumb_up_alt_outlined,
              size: 45,
              color: upActive
                  ? Colors.green
                  : theme.systemText.withValues(alpha: 0.5),
            ),
          ),
        ),
        const SizedBox(width: 52),
        InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => onPick(false),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Icon(
              downActive ? Icons.thumb_down_alt : Icons.thumb_down_alt_outlined,
              size: 45,
              color: downActive
                  ? Colors.red
                  : theme.systemText.withValues(alpha: 0.5),
            ),
          ),
        ),
      ],
    );
  }
}
