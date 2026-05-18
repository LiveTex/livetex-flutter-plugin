import "package:flutter/material.dart";

/// Visual tokens for the LiveTex chat UI. Default factory mirrors the native
/// Android `demo-lib` look — values extracted from the real `colors.xml`,
/// `dimens.xml`, drawables and color selectors. The host app's `ThemeData`
/// is intentionally NOT consulted, so a Material 3 default purple seed in
/// the host cannot leak into the chat screen.
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
    required this.botKeyboardButtonDisabled,
    required this.botKeyboardButtonText,
    required this.departmentButton,
    required this.departmentButtonText,
    required this.attributesAccent,
    required this.attributesAccentText,
    required this.composerBackground,
    required this.composerField,
    required this.composerFieldStroke,
    required this.composerHint,
    required this.composerAction,
    required this.composerActionDisabled,
    required this.composerAddAction,
    required this.composerAddActionDisabled,
    required this.composerText,
    required this.ratingPanelBackground,
    required this.ratingFormBackground,
    required this.ratingStarActive,
    required this.ratingStarInactive,
    required this.ratingThumbUp,
    required this.ratingThumbDown,
    required this.ratingThumbInactive,
    required this.ratingButton,
    required this.ratingButtonText,
    required this.ratingButtonDisabledBg,
    required this.ratingButtonDisabledText,
    required this.ratingButtonStroke,
    required this.ratingButtonStrokeDisabled,
    required this.quoteAccent,
    required this.bubbleRadius,
    required this.controlRadius,
    required this.cardRadius,
    required this.composerFieldRadius,
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
  final Color botKeyboardButtonDisabled;
  final Color botKeyboardButtonText;
  final Color departmentButton;
  final Color departmentButtonText;
  final Color attributesAccent;
  final Color attributesAccentText;
  final Color composerBackground;
  final Color composerField;
  final Color composerFieldStroke;
  final Color composerHint;
  final Color composerAction;
  final Color composerActionDisabled;
  final Color composerAddAction;
  final Color composerAddActionDisabled;
  final Color composerText;
  final Color ratingPanelBackground;
  final Color ratingFormBackground;
  final Color ratingStarActive;
  final Color ratingStarInactive;
  final Color ratingThumbUp;
  final Color ratingThumbDown;
  final Color ratingThumbInactive;
  final Color ratingButton;
  final Color ratingButtonText;
  final Color ratingButtonDisabledBg;
  final Color ratingButtonDisabledText;
  final Color ratingButtonStroke;
  final Color ratingButtonStrokeDisabled;
  final Color quoteAccent;
  final double bubbleRadius;
  final double controlRadius;
  final double cardRadius;
  final double composerFieldRadius;

  /// Native-matching preset (Android `demo-lib`). Values from:
  ///   - drawable/rounded_rectangle_blue.xml (outgoing #3E7AD7, radius 30dp)
  ///   - drawable/bg_gray_rounded.xml (incoming #F5F5F5, radius 30dp)
  ///   - drawable/bg_input_field.xml (white + stroke #E5E5E5, radius 20dp)
  ///   - drawable/bg_rating_message.xml (#F3F4F6, radius 10dp)
  ///   - color/message_button_enabled_disabled.xml (#3E7AD7 / #aa3E7AD7)
  ///   - color/control_enabled_disabled.xml (#3E7AD7 / #E5E5E5) send btn
  ///   - color/add_enabled_disabled.xml (#000000 / #E5E5E5) + btn
  ///   - color/bg_rate_button.xml (#167AFA / #0A000000) Оценить btn
  ///   - color/text_color_rate_button.xml (#ffffff / 25% black) Оценить text
  ///   - color/bg_stroke_rate_button.xml (#167AFA / #D9D9D9) Оценить stroke
  ///   - layout/i_chat_message_system.xml (#7E7979 12sp) system + date
  ///   - drawable/bg_darkgray_rounded.xml (#757B85, radius 10dp) image-time
  ///   - layout/l_department_button.xml (#F9F9F9 bg, black text)
  ///   - layout/a_chat.xml (#F3F4F6 rating panel, #24973E attributes Отправить)
  factory LivetexChatTheme.livetex() {
    return const LivetexChatTheme(
      background: Color(0xFFFFFFFF),
      outgoingBubble: Color(0xFF3E7AD7),
      outgoingText: Color(0xFFFFFFFF),
      outgoingTime: Color(0xFF7E7979),
      incomingBubble: Color(0xFFF5F5F5),
      incomingText: Color(0xFF000000),
      incomingTime: Color(0xFF7E7979),
      operatorName: Color(0xFF000000),
      systemText: Color(0xFF7E7979),
      appBarBackground: Color(0xFFFFFFFF),
      appBarForeground: Color(0xFF000000),
      connectionBanner: Color(0xFFFFF4CE),
      connectionBannerText: Color(0xFF6B5400),
      botKeyboardButton: Color(0xFF3E7AD7),
      botKeyboardButtonDisabled: Color(0xAA3E7AD7),
      botKeyboardButtonText: Color(0xFFFFFFFF),
      departmentButton: Color(0xFFF9F9F9),
      departmentButtonText: Color(0xFF000000),
      attributesAccent: Color(0xFF24973E),
      attributesAccentText: Color(0xFFFFFFFF),
      composerBackground: Color(0xFFFFFFFF),
      composerField: Color(0xFFFFFFFF),
      composerFieldStroke: Color(0xFFE5E5E5),
      composerHint: Color(0xFFC4C4C4),
      composerAction: Color(0xFF3E7AD7),
      composerActionDisabled: Color(0xFFE5E5E5),
      composerAddAction: Color(0xFF000000),
      composerAddActionDisabled: Color(0xFFE5E5E5),
      composerText: Color(0xFF000000),
      ratingPanelBackground: Color(0xFFF3F4F6),
      ratingFormBackground: Color(0xFFF3F4F6),
      ratingStarActive: Color(0xFFFADB14),
      ratingStarInactive: Color(0x140A0A0A),
      ratingThumbUp: Color(0xFF24973E),
      ratingThumbDown: Color(0xFFD23E3E),
      ratingThumbInactive: Color(0xFFB7B9BD),
      ratingButton: Color(0xFF167AFA),
      ratingButtonText: Color(0xFFFFFFFF),
      ratingButtonDisabledBg: Color(0x0A000000),
      ratingButtonDisabledText: Color(0x40000000),
      ratingButtonStroke: Color(0xFF167AFA),
      ratingButtonStrokeDisabled: Color(0xFFD9D9D9),
      quoteAccent: Color(0xFF3E7AD7),
      bubbleRadius: 30,
      controlRadius: 10,
      cardRadius: 15,
      composerFieldRadius: 20,
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
