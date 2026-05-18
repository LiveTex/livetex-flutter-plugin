import "package:flutter/material.dart";
import "package:livetex_chat/livetex_chat.dart";

import "../livetex_chat_theme.dart";
import "full_width_chat_button.dart";

/// Full-width column of bot keyboard buttons rendered as its own component
/// under the bot message bubble (mirrors native Android `buttonsContainerView`
/// in `i_chat_message_in.xml`). When [KeyboardPayload.pressed] is true, all
/// buttons render disabled (translucent blue).
class BotKeyboard extends StatelessWidget {
  const BotKeyboard({
    super.key,
    required this.keyboard,
    required this.onPress,
  });

  final KeyboardPayload keyboard;
  final void Function(ButtonPayload button) onPress;

  @override
  Widget build(BuildContext context) {
    final theme = LivetexChatTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final b in keyboard.buttons)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: FullWidthChatButton(
                label: b.label,
                background: theme.botKeyboardButton,
                foreground: theme.botKeyboardButtonText,
                disabledBackground: theme.botKeyboardButtonDisabled,
                disabledForeground: theme.botKeyboardButtonText,
                onPressed: keyboard.pressed ? null : () => onPress(b),
              ),
            ),
        ],
      ),
    );
  }
}
