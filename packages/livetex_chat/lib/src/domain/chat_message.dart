import "../api/server_messages.dart";

/// Normalized row for the message list (visitor + optimistic local).
enum ChatMessageSendState { none, sending, sent, failed }

final class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.createdAt,
    required this.isVisitor,
    this.text,
    this.fileName,
    this.fileUrl,
    this.creatorLabel,
    this.creatorType,
    this.avatarUrl,
    this.keyboard,
    this.sendState = ChatMessageSendState.none,
    this.correlationId,
  });

  final String id;
  final DateTime createdAt;
  final bool isVisitor;
  final String? text;
  final String? fileName;
  final String? fileUrl;
  final String? creatorLabel;

  /// Raw `creator.type` from Visitor-API: "visitor" | "employee" | "bot" |
  /// "system". Use this for behavior decisions (e.g. system messages render
  /// without a bubble) instead of matching the localized [creatorLabel].
  final String? creatorType;

  /// Operator avatar URL from `creator.employee.avatarUrl`. Empty for bot
  /// and visitor messages; UI falls back to a generic icon when null.
  final String? avatarUrl;

  final KeyboardPayload? keyboard;
  final ChatMessageSendState sendState;
  final String? correlationId;

  ChatMessage copyWith({
    String? id,
    DateTime? createdAt,
    bool? isVisitor,
    String? text,
    String? fileName,
    String? fileUrl,
    String? creatorLabel,
    String? creatorType,
    String? avatarUrl,
    KeyboardPayload? keyboard,
    ChatMessageSendState? sendState,
    String? correlationId,
  }) {
    return ChatMessage(
      id: id ?? this.id,
      createdAt: createdAt ?? this.createdAt,
      isVisitor: isVisitor ?? this.isVisitor,
      text: text ?? this.text,
      fileName: fileName ?? this.fileName,
      fileUrl: fileUrl ?? this.fileUrl,
      creatorLabel: creatorLabel ?? this.creatorLabel,
      creatorType: creatorType ?? this.creatorType,
      avatarUrl: avatarUrl ?? this.avatarUrl,
      keyboard: keyboard ?? this.keyboard,
      sendState: sendState ?? this.sendState,
      correlationId: correlationId ?? this.correlationId,
    );
  }
}
