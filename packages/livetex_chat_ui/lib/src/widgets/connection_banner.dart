import "package:flutter/material.dart";
import "package:livetex_chat/livetex_chat.dart";

import "../livetex_chat_theme.dart";

class ConnectionBanner extends StatelessWidget {
  const ConnectionBanner({
    super.key,
    required this.state,
    required this.onRetry,
  });

  final LivetexConnectionState state;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final theme = LivetexChatTheme.of(context);
    final canRetry = state == LivetexConnectionState.disconnected;
    return Material(
      color: theme.connectionBanner,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Row(
          children: [
            Icon(
              Icons.cloud_off_outlined,
              size: 18,
              color: theme.connectionBannerText,
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _label(state),
                style: TextStyle(
                  fontSize: 13,
                  color: theme.connectionBannerText,
                ),
              ),
            ),
            TextButton(
              onPressed: canRetry ? onRetry : null,
              style: TextButton.styleFrom(
                foregroundColor: theme.connectionBannerText,
              ),
              child: const Text("Повторить"),
            ),
          ],
        ),
      ),
    );
  }

  static String _label(LivetexConnectionState s) {
    return switch (s) {
      LivetexConnectionState.disconnected => "Соединение потеряно",
      LivetexConnectionState.connecting => "Подключение…",
      LivetexConnectionState.reconnecting => "Переподключение…",
      LivetexConnectionState.connected => "",
    };
  }
}
