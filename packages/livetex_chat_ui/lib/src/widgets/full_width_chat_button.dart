import "package:flutter/material.dart";

import "../livetex_chat_theme.dart";

/// Full-width chat button used both for bot keyboard buttons and department
/// picker buttons. Color is parameterized via [background]/[foreground] so
/// the same widget can render the blue bot keyboard and the gray department
/// picker, matching the native Android `l_message_keyboard_button.xml` and
/// `l_department_button.xml` while sharing layout.
class FullWidthChatButton extends StatelessWidget {
  const FullWidthChatButton({
    super.key,
    required this.label,
    required this.background,
    required this.foreground,
    this.disabledBackground,
    this.disabledForeground,
    this.onPressed,
    this.height = 44,
  });

  final String label;
  final Color background;
  final Color foreground;
  final Color? disabledBackground;
  final Color? disabledForeground;
  final VoidCallback? onPressed;
  final double height;

  @override
  Widget build(BuildContext context) {
    final theme = LivetexChatTheme.of(context);
    return SizedBox(
      height: height,
      child: FilledButton(
        style: FilledButton.styleFrom(
          backgroundColor: background,
          foregroundColor: foreground,
          disabledBackgroundColor: disabledBackground ?? background,
          disabledForegroundColor: disabledForeground ?? foreground,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(theme.controlRadius),
          ),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        onPressed: onPressed,
        child: Text(
          label,
          style: const TextStyle(fontSize: 16),
          textAlign: TextAlign.center,
          overflow: TextOverflow.ellipsis,
          maxLines: 2,
        ),
      ),
    );
  }
}
