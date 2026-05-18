import "package:cached_network_image/cached_network_image.dart";
import "package:flutter/material.dart";
import "package:flutter_cache_manager/flutter_cache_manager.dart";
import "package:intl/intl.dart";
import "package:livetex_chat/livetex_chat.dart";
import "package:photo_view/photo_view.dart";
import "package:share_plus/share_plus.dart";
import "package:url_launcher/url_launcher.dart";

import "../livetex_chat_theme.dart";

/// Detects an image based on URL extension. Used both for `file` messages
/// with image URLs and for `text` messages whose content is a bare image URL.
const _imageExts = <String>{
  ".png", ".jpg", ".jpeg", ".gif", ".webp", ".bmp", ".heic", ".heif",
};

/// Quote-reply format from Visitor-API: `"> <quoted line>\n<reply text>"`.
/// Same as native sdk-android `ChatItem.findQuotedText`.
class _QuoteParts {
  const _QuoteParts(this.quote, this.body);
  final String quote;
  final String body;
}

_QuoteParts? _splitQuote(String? content) {
  if (content == null || !content.startsWith("> ")) return null;
  final nl = content.indexOf("\n");
  if (nl <= 2) return null;
  return _QuoteParts(content.substring(2, nl), content.substring(nl + 1));
}

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

  bool get _isSystem => message.creatorType == "system";

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
              message.creatorLabel!.isNotEmpty)
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
                _OperatorAvatar(avatarUrl: message.avatarUrl),
                const SizedBox(width: 6),
              ],
              // Time + delivery icons go beside the bubble (visitor: to its
              // left, operator: to its right) — matches native sdk-ui where
              // short messages don't get squashed into a circle by an
              // inside-bubble timestamp.
              if (isVisitor)
                _BubbleMeta(
                  createdAt: message.createdAt,
                  sendState: message.sendState,
                  isVisitor: true,
                ),
              if (isVisitor) const SizedBox(width: 4),
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
                  ),
                ),
              ),
              if (!isVisitor) const SizedBox(width: 4),
              if (!isVisitor)
                _BubbleMeta(
                  createdAt: message.createdAt,
                  sendState: message.sendState,
                  isVisitor: false,
                ),
            ],
          ),
        ],
      ),
    );
  }
}

/// Renders message text; if it starts with a "> quoted line\n" prefix,
/// renders the quoted line as an inline quote block (vertical accent bar
/// + dimmed text) above the actual message body. Same content shape as
/// native sdk-android `ChatItem.findQuotedText`.
class _TextWithOptionalQuote extends StatelessWidget {
  const _TextWithOptionalQuote({required this.text, required this.fg});

  final String text;
  final Color fg;

  @override
  Widget build(BuildContext context) {
    final theme = LivetexChatTheme.of(context);
    final parts = _splitQuote(text);
    if (parts == null) {
      return SelectableText(text, style: TextStyle(fontSize: 16, color: fg));
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        IntrinsicHeight(
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 2, color: theme.quoteAccent),
              const SizedBox(width: 8),
              Flexible(
                child: Text(
                  parts.quote,
                  style: TextStyle(
                    fontSize: 14,
                    color: fg.withValues(alpha: 0.75),
                  ),
                  maxLines: 3,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ),
        if (parts.body.isNotEmpty) ...[
          const SizedBox(height: 6),
          SelectableText(
            parts.body,
            style: TextStyle(fontSize: 16, color: fg),
          ),
        ],
      ],
    );
  }
}

/// Time + delivery icon rendered OUTSIDE the bubble (mirrors native sdk-ui).
/// Keeping these out of the bubble lets short messages render at their
/// natural width — a one-character reply doesn't get inflated into a circle
/// by an inside-bubble timestamp.
class _BubbleMeta extends StatelessWidget {
  const _BubbleMeta({
    required this.createdAt,
    required this.sendState,
    required this.isVisitor,
  });

  final DateTime createdAt;
  final ChatMessageSendState sendState;
  final bool isVisitor;

  @override
  Widget build(BuildContext context) {
    final theme = LivetexChatTheme.of(context);
    final timeColor = theme.incomingTime;
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (sendState == ChatMessageSendState.sending) ...[
            SizedBox(
              width: 12,
              height: 12,
              child: CircularProgressIndicator(
                strokeWidth: 1.5,
                color: timeColor,
              ),
            ),
            const SizedBox(width: 4),
          ],
          if (sendState == ChatMessageSendState.failed) ...[
            const Icon(Icons.error_outline, size: 14, color: Colors.red),
            const SizedBox(width: 4),
          ],
          if (sendState == ChatMessageSendState.sent && isVisitor) ...[
            Icon(Icons.done_all, size: 14, color: timeColor),
            const SizedBox(width: 4),
          ],
          Text(
            DateFormat.Hm().format(createdAt.toLocal()),
            style: TextStyle(fontSize: 11, color: timeColor),
          ),
        ],
      ),
    );
  }
}

class _OperatorAvatar extends StatelessWidget {
  const _OperatorAvatar({this.avatarUrl});

  final String? avatarUrl;

  @override
  Widget build(BuildContext context) {
    final theme = LivetexChatTheme.of(context);
    final hasUrl = avatarUrl != null && avatarUrl!.isNotEmpty;
    return ClipOval(
      child: Container(
        width: 32,
        height: 32,
        color: theme.incomingBubble,
        child: hasUrl
            ? CachedNetworkImage(
                imageUrl: avatarUrl!,
                fit: BoxFit.cover,
                errorWidget: (_, __, ___) => Icon(
                  Icons.support_agent,
                  size: 18,
                  color: theme.systemText,
                ),
              )
            : Icon(Icons.support_agent, size: 18, color: theme.systemText),
      ),
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
  });

  final bool isVisitor;
  final String? text;
  final String? fileName;
  final String? fileUrl;
  final bool isImage;
  final bool isFile;

  @override
  Widget build(BuildContext context) {
    final theme = LivetexChatTheme.of(context);
    final bg = isVisitor ? theme.outgoingBubble : theme.incomingBubble;
    final fg = isVisitor ? theme.outgoingText : theme.incomingText;
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
                onTap: () => _openFileUrl(context, fileUrl),
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
              _TextWithOptionalQuote(text: text!, fg: fg),
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
        child: Stack(
          fit: StackFit.expand,
          children: [
            PhotoView(
              imageProvider: CachedNetworkImageProvider(url),
              backgroundDecoration: const BoxDecoration(color: Colors.black),
              minScale: PhotoViewComputedScale.contained,
              maxScale: PhotoViewComputedScale.covered * 3,
              onTapUp: (c, details, ctrl) => Navigator.pop(ctx),
            ),
            Positioned(
              top: 32,
              right: 8,
              child: Row(
                children: [
                  // Save / share via system sheet. Mirrors native sdk-ui —
                  // Android `ImageActivity.downloadImage()` uses
                  // DownloadManager, iOS uses UIActivityViewController; on
                  // Flutter the share sheet covers both with one UI.
                  IconButton(
                    icon: const Icon(Icons.save_alt, color: Colors.white),
                    tooltip: "Сохранить",
                    onPressed: () => _saveImage(ctx, url),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    tooltip: "Закрыть",
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Open a server-supplied file URL externally. Scheme-allowlisted to
  /// http/https — a `file://`/`javascript:`/custom-scheme URL coming from
  /// the operator must NOT trigger an OS handler, that's a deep-link /
  /// intent-hijack vector when the SDK ships into third-party host apps.
  Future<void> _openFileUrl(BuildContext context, String? raw) async {
    if (raw == null || raw.isEmpty) return;
    final uri = Uri.tryParse(raw);
    final ok = uri != null && (uri.scheme == "http" || uri.scheme == "https");
    if (!ok) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        const SnackBar(content: Text("Не удалось открыть файл")),
      );
      return;
    }
    try {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      if (context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          const SnackBar(content: Text("Не удалось открыть файл")),
        );
      }
    }
  }

  Future<void> _saveImage(BuildContext context, String url) async {
    final messenger = ScaffoldMessenger.maybeOf(context);
    try {
      // Image is already in the CachedNetworkImage cache from rendering,
      // so this hits disk without an extra HTTP request in the common case.
      final file = await DefaultCacheManager().getSingleFile(url);
      await Share.shareXFiles([XFile(file.path)]);
    } catch (e) {
      messenger?.showSnackBar(
        SnackBar(content: Text("Не удалось сохранить изображение: $e")),
      );
    }
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
