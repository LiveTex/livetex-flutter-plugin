import "package:flutter/material.dart";

/// Visual tokens for the LiveTex chat UI. Default factory mirrors the native
/// Android `demo-lib` look (white background, blue outgoing / gray incoming
/// bubbles, gold stars, navy toolbar accent). The host app's `ThemeData` is
/// intentionally NOT consulted, so a Material 3 default purple seed in the
/// host cannot leak into the chat screen.
class LivetexChatTheme {
  const LivetexChatTheme({
    required this.background,
    required this.outgoingBubble,
    required this.outgoingText,
    required this.outgoingTime,
    required this.incomingBubble,
    required this.incomingText,
    required this.incomingTime,
    required this.operatorName,
    required this.systemText,
    required this.appBarBackground,
    required this.appBarForeground,
    required this.connectionBanner,
    required this.connectionBannerText,
    required this.botKeyboardButton,
    required this.botKeyboardButtonText,
    required this.departmentButton,
    required this.departmentButtonText,
    required this.attributesAccent,
    required this.composerBackground,
    required this.composerField,
    required this.composerHint,
    required this.composerAction,
    required this.composerActionDisabled,
    required this.composerText,
    required this.ratingPanelBackground,
    required this.ratingStarActive,
    required this.ratingStarInactive,
    required this.ratingButton,
    required this.ratingButtonText,
    required this.quoteAccent,
    required this.bubbleRadius,
    required this.controlRadius,
    required this.cardRadius,
  });

  final Color background;
  final Color outgoingBubble;
  final Color outgoingText;
  final Color outgoingTime;
  final Color incomingBubble;
  final Color incomingText;
  final Color incomingTime;
  final Color operatorName;
  final Color systemText;
  final Color appBarBackground;
  final Color appBarForeground;
  final Color connectionBanner;
  final Color connectionBannerText;
  final Color botKeyboardButton;
  final Color botKeyboardButtonText;
  final Color departmentButton;
  final Color departmentButtonText;
  final Color attributesAccent;
  final Color composerBackground;
  final Color composerField;
  final Color composerHint;
  final Color composerAction;
  final Color composerActionDisabled;
  final Color composerText;
  final Color ratingPanelBackground;
  final Color ratingStarActive;
  final Color ratingStarInactive;
  final Color ratingButton;
  final Color ratingButtonText;
  final Color quoteAccent;
  final double bubbleRadius;
  final double controlRadius;
  final double cardRadius;

  /// Native-matching preset (Android `demo-lib`). Values from
  /// `colors.xml`/`dimens.xml`/`styles.xml`; missing exact pixel values are
  /// derived to visually match the demo screenshots.
  factory LivetexChatTheme.livetex() {
    return const LivetexChatTheme(
      background: Color(0xFFFFFFFF),
      outgoingBubble: Color(0xFF54B0E0),
      outgoingText: Color(0xFFFFFFFF),
      outgoingTime: Color(0xFF7E7979),
      incomingBubble: Color(0xFFECEDF1),
      incomingText: Color(0xFF000000),
      incomingTime: Color(0xFF7E7979),
      operatorName: Color(0xFF000000),
      systemText: Color(0xFF7E7979),
      appBarBackground: Color(0xFFFFFFFF),
      appBarForeground: Color(0xFF000000),
      connectionBanner: Color(0xFFFFF4CE),
      connectionBannerText: Color(0xFF6B5400),
      botKeyboardButton: Color(0xFF54B0E0),
      botKeyboardButtonText: Color(0xFFFFFFFF),
      departmentButton: Color(0xFFF9F9F9),
      departmentButtonText: Color(0xFF000000),
      attributesAccent: Color(0xFF24973E),
      composerBackground: Color(0xFFFFFFFF),
      composerField: Color(0xFFF3F4F6),
      composerHint: Color(0xFFC4C4C4),
      composerAction: Color(0xFF54B0E0),
      composerActionDisabled: Color(0xFFC4C4C4),
      composerText: Color(0xFF000000),
      ratingPanelBackground: Color(0xFFF3F4F6),
      ratingStarActive: Color(0xFFFADB14),
      ratingStarInactive: Color(0x140A0A0A),
      ratingButton: Color(0xFF54B0E0),
      ratingButtonText: Color(0xFFFFFFFF),
      quoteAccent: Color(0xFF3E7AD7),
      bubbleRadius: 16,
      controlRadius: 10,
      cardRadius: 15,
    );
  }

  static LivetexChatTheme of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_LivetexChatThemeScope>();
    return scope?.theme ?? LivetexChatTheme.livetex();
  }
}

class LivetexChatThemeScope extends StatelessWidget {
  const LivetexChatThemeScope({
    super.key,
    required this.theme,
    required this.child,
  });

  final LivetexChatTheme theme;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return _LivetexChatThemeScope(theme: theme, child: child);
  }
}

class _LivetexChatThemeScope extends InheritedWidget {
  const _LivetexChatThemeScope({
    required this.theme,
    required super.child,
  });

  final LivetexChatTheme theme;

  @override
  bool updateShouldNotify(covariant _LivetexChatThemeScope oldWidget) {
    return theme != oldWidget.theme;
  }
}
