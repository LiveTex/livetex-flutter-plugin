/// Recoverable or informational error from the chat core.
final class LivetexChatError {
  const LivetexChatError({required this.message, this.code, this.cause});

  final String message;
  final String? code;
  final Object? cause;

  @override
  String toString() => "LivetexChatError($code): $message";
}
