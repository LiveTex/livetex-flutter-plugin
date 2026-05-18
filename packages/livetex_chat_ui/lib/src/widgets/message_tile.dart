import "package:cached_network_image/cached_network_image.dart";
import "package:flutter/material.dart";
import "package:intl/intl.dart";
import "package:livetex_chat/livetex_chat.dart";
import "package:photo_view/photo_view.dart";
import "package:url_launcher/url_launcher.dart";

import "../livetex_chat_theme.dart";

/// Detects an image based on URL extension. Used both for `file` messages
/// with image URLs and for `text` messages whose content is a bare image URL.
const _imageExts = <String>{
  ".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".heic", ".heif",
};

bool _isImageUrl(String? u) {
  if (u == null || u.isEmpty) return false;
  final low = u.toLowerCase();
  for (final ext in _imageExts) {
    if (low.endsWith(ext)) return true;
  }
  return false;
}

/// One chat message — visitor / employee / bot / system. System messages
/// render as a centered gray line without a bubble.
class MessageTile extends StatelessWidget {
  const MessageTile({super.key, required this.message});

  final ChatMessage message;

  bool get _isSystem => message.creatorLabel == "Система";

  @override
  Widget build(BuildContext context) {
    if (_isSystem) return _SystemMessageTile(text: message.text ?? "");
    final theme = LivetexChatTheme.of(context);
    final isVisitor = message.isVisitor;
    final isImage =
        _isImageUrl(message.fileUrl) || _isImageUrl(message.text);
    final isFile = message.fileUrl != null && !isImage;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Column(
        crossAxisAlignment:
            isVisitor ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!isVisitor &&
              message.creatorLabel != null &&
              message.creatorLabel!.isNotEmpty &&
              message.creatorLabel != "Вы")
            Padding(
              padding: const EdgeInsets.only(left: 48, bottom: 2),
              child: Text(
                message.creatorLabel!,
                style: TextStyle(fontSize: 11, color: theme.operatorName),
              ),
            ),
          Row(
            mainAxisAlignment:
                isVisitor ? MainAxisAlignment.end : MainAxisAlignment.start,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              if (!isVisitor) ...[
                const _OperatorAvatar(),
                const SizedBox(width: 6),
              ],
              Flexible(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: MediaQuery.sizeOf(context).width * 0.78,
                  ),
                  child: _MessageBubble(
                    isVisitor: isVisitor,
                    text: message.text,
                    fileName: message.fileName,
                    fileUrl: message.fileUrl,
                    isImage: isImage,
                    isFile: isFile,
                    createdAt: message.createdAt,
                    sendState: message.sendState,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _OperatorAvatar extends StatelessWidget {
  const _OperatorAvatar();

  @override
  Widget build(BuildContext context) {
    final theme = LivetexChatTheme.of(context);
    return Container(
      width: 32,
      height: 32,
      decoration: BoxDecoration(
        color: theme.incomingBubble,
        shape: BoxShape.circle,
      ),
      child: Icon(Icons.support_agent, size: 18, color: theme.systemText),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({
    required this.isVisitor,
    required this.text,
    required this.fileName,
    required this.fileUrl,
    required this.isImage,
    required this.isFile,
    required this.createdAt,
    required this.sendState,
  });

  final bool isVisitor;
  final String? text;
  final String? fileName;
  final String? fileUrl;
  final bool isImage;
  final bool isFile;
  final DateTime createdAt;
  final ChatMessageSendState sendState;

  @override
  Widget build(BuildContext context) {
    final theme = LivetexChatTheme.of(context);
    final bg = isVisitor ? theme.outgoingBubble : theme.incomingBubble;
    final fg = isVisitor ? theme.outgoingText : theme.incomingText;
    final timeFg = isVisitor ? Colors.white70 : theme.incomingTime;
    final imageUrl = isImage
        ? (fileUrl ?? (_isImageUrl(text) ? text : null))
        : null;
    return Material(
      color: bg,
      borderRadius: BorderRadius.circular(theme.bubbleRadius),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (imageUrl != null)
              GestureDetector(
                onTap: () => _openImage(context, imageUrl),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: CachedNetworkImage(
                    imageUrl: imageUrl,
                    width: 200,
                    height: 200,
                    fit: BoxFit.cover,
                    placeholder: (_, __) => SizedBox(
                      width: 200,
                      height: 200,
                      child: Center(
                        child: SizedBox(
                          width: 28,
                          height: 28,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: theme.composerAction,
                          ),
                        ),
                      ),
                    ),
                    errorWidget: (_, __, ___) => SizedBox(
                      width: 200,
                      height: 200,
                      child: Icon(
                        Icons.broken_image_outlined,
                        color: theme.systemText,
                      ),
                    ),
                  ),
                ),
              )
            else if (isFile && fileName != null)
              InkWell(
                onTap: () {
                  if (fileUrl != null && fileUrl!.isNotEmpty) {
                    launchUrl(
                      Uri.parse(fileUrl!),
                      mode: LaunchMode.externalApplication,
                    );
                  }
                },
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.insert_drive_file_outlined,
                        color: fg,
                        size: 24,
                      ),
                      const SizedBox(width: 8),
                      Flexible(
                        child: Text(
                          fileName!,
                          style: TextStyle(fontSize: 15, color: fg),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),
              )
            else if (text != null && text!.isNotEmpty)
              SelectableText(
                text!,
                style: TextStyle(fontSize: 16, color: fg),
              ),
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (sendState == ChatMessageSendState.sending) ...[
                    SizedBox(
                      width: 12,
                      height: 12,
                      child: CircularProgressIndicator(
                        strokeWidth: 1.5,
                        color: timeFg,
                      ),
                    ),
                    const SizedBox(width: 4),
                  ],
                  if (sendState == ChatMessageSendState.failed) ...[
                    const Icon(
                      Icons.error_outline,
                      size: 14,
                      color: Colors.red,
                    ),
                    const SizedBox(width: 4),
                  ],
                  if (sendState == ChatMessageSendState.sent && isVisitor) ...[
                    Icon(Icons.done_all, size: 14, color: timeFg),
                    const SizedBox(width: 4),
                  ],
                  Text(
                    DateFormat.Hm().format(createdAt.toLocal()),
                    style: TextStyle(fontSize: 11, color: timeFg),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _openImage(BuildContext context, String url) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black87,
      builder: (ctx) => Dialog(
        insetPadding: EdgeInsets.zero,
        backgroundColor: Colors.transparent,
        child: PhotoView(
          imageProvider: CachedNetworkImageProvider(url),
          backgroundDecoration: const BoxDecoration(color: Colors.black),
          minScale: PhotoViewComputedScale.contained,
          maxScale: PhotoViewComputedScale.covered * 3,
          onTapUp: (c, details, ctrl) => Navigator.pop(ctx),
        ),
      ),
    );
  }
}

class _SystemMessageTile extends StatelessWidget {
  const _SystemMessageTile({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = LivetexChatTheme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Center(
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: TextStyle(fontSize: 12, color: theme.systemText),
        ),
      ),
    );
  }
}

class DateSeparator extends StatelessWidget {
  const DateSeparator({super.key, required this.date});

  final DateTime date;

  @override
  Widget build(BuildContext context) {
    final theme = LivetexChatTheme.of(context);
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(date.year, date.month, date.day);
    final delta = today.difference(that).inDays;
    final label = switch (delta) {
      0 => "Сегодня",
      1 => "Вчера",
      _ => "${date.day} ${_ruMonth(date.month)}",
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 12),
      child: Center(
        child: Text(
          label,
          style: TextStyle(fontSize: 12, color: theme.systemText),
        ),
      ),
    );
  }
}

class TypingTile extends StatelessWidget {
  const TypingTile({super.key, required this.operatorName});

  final String? operatorName;

  @override
  Widget build(BuildContext context) {
    final theme = LivetexChatTheme.of(context);
    final text = operatorName != null && operatorName!.isNotEmpty
        ? "$operatorName печатает…"
        : "Печатает…";
    return Padding(
      padding: const EdgeInsets.only(left: 56, top: 4, bottom: 4),
      child: Align(
        alignment: Alignment.centerLeft,
        child: Text(
          text,
          style: TextStyle(fontSize: 12, color: theme.systemText),
        ),
      ),
    );
  }
}

const _ruMonths = <String>[
  "",
  "января",
  "февраля",
  "марта",
  "апреля",
  "мая",
  "июня",
  "июля",
  "августа",
  "сентября",
  "октября",
  "ноября",
  "декабря",
];

String _ruMonth(int m) {
  if (m < 1 || m > 12) return "";
  return _ruMonths[m];
}
