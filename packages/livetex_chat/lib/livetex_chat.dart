/// LiveTex Flutter/Dart SDK: Visitor-Auth, WebSocket, multipart upload, high-level [LivetexChat].
///
/// Low-level entry points: [livetexVisitorAuthenticate], [LivetexVisitorSession],
/// [VisitorOutgoing], [parseServerMessage].
library livetex_chat;

export "src/api/auth_result.dart";
export "src/api/json_utils.dart" show tryParseServerDate;
export "src/api/protocol_outgoing.dart";
export "src/api/server_messages.dart";
export "src/api/parser.dart" show parseServerMessage;
export "src/api/visitor_client.dart";

export "src/domain/chat_message.dart";
export "src/livetex_trace.dart"
    show
        livetexChatPackageVersion,
        livetexSupportMaskTouchPoint,
        livetexTraceFormatLine,
        livetexTraceMaybeEmit,
        livetexTraceRedact;
export "src/livetex_chat_config.dart";
export "src/livetex_chat_errors.dart";
export "src/livetex_connection_state.dart";
export "src/livetex_chat.dart";
