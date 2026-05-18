import "dart:async";
import "dart:convert";
import "dart:io";

import "package:http/http.dart" as http;
import "package:web_socket_channel/io.dart";
import "package:web_socket_channel/web_socket_channel.dart";

import "auth_result.dart";
import "parser.dart";
import "server_messages.dart";
import "../livetex_trace.dart";

Uri _visitorUploadUri(Uri uploadRoot, String? filenameSuffixPath) {
  if (filenameSuffixPath == null || filenameSuffixPath.isEmpty) {
    return uploadRoot;
  }
  final path = "${uploadRoot.path}/${Uri.encodeComponent(filenameSuffixPath)}"
      .replaceAll("//", "/");
  return uploadRoot.replace(path: path);
}

bool _isPlainAscii(String s) => !s.codeUnits.any((c) => c > 127);

/// Typical account settings list `jpg` but not always `jpeg`. Normalizes final path suffix.
String? _normalizedUploadSuffix(String? suffix) {
  if (suffix == null || suffix.isEmpty) return suffix;
  return suffix.replaceAll(RegExp(r'\.jpe?g$', caseSensitive: false), '.jpg');
}

String _asciiMultipartExtensionCandidate(String filename) {
  final dot = filename.lastIndexOf(".");
  if (dot <= 0 || dot >= filename.length - 1) return "";
  final raw = filename.substring(dot + 1).toLowerCase();
  if (raw.length > 16 || !RegExp(r"^[a-z0-9]+$").hasMatch(raw)) {
    return "";
  }
  return ".$raw";
}

/// Builds a multipart `filename=` that stays ASCII-safe.
///
/// Some multipart stacks (http4s, etc.) fail to parse Content-Disposition when
/// `filename` holds non‑ASCII unless RFC 5987 encoding is applied; Dart's default
/// [http.MultipartRequest] does not add that encoding. Prefer ASCII here; callers
/// can still encode the logical name via [filenameSuffixPath] (URL suffix) or the
/// WebSocket `file` message.
String _multipartBodyFilenameHint(String diskPath, String? filenameSuffixPath) {
  final base = diskPath.replaceAll(RegExp(r'[/\\]'), '/').split('/').last;

  var ext = _asciiMultipartExtensionCandidate(base);
  if (ext.isEmpty &&
      filenameSuffixPath != null &&
      filenameSuffixPath.isNotEmpty) {
    ext = _asciiMultipartExtensionCandidate(filenameSuffixPath);
  }

  // Normalize toward `jpg` for common allow‑lists keyed on three letters.
  if (ext == ".jpeg") {
    ext = ".jpg";
  }

  if (filenameSuffixPath != null &&
      filenameSuffixPath.isNotEmpty &&
      _isPlainAscii(filenameSuffixPath)) {
    final s = filenameSuffixPath;
    final cand = _asciiMultipartExtensionCandidate(s);
    if (cand.isNotEmpty) {
      final dot = s.lastIndexOf(".");
      return "${s.substring(0, dot)}$cand";
    }
    final stem = s.contains(".") ? s.substring(0, s.lastIndexOf(".")) : s;
    if (ext.isNotEmpty) {
      return "${stem.isEmpty ? "upload" : stem}$ext";
    }
    return stem.isEmpty ? "upload" : stem;
  }

  final stamp = DateTime.now().millisecondsSinceEpoch;
  return "upload_$stamp${ext.isNotEmpty ? ext : ".bin"}";
}

/// Thrown when `GET /v1/auth` is not HTTP 200.
final class LivetexVisitorAuthException implements Exception {
  LivetexVisitorAuthException(this.statusCode, this.body);
  final int statusCode;
  final String body;

  @override
  String toString() => "LivetexVisitorAuthException($statusCode): $body";
}

/// Thrown when multipart upload does not return HTTP 200.
final class LivetexVisitorUploadException implements Exception {
  LivetexVisitorUploadException(this.statusCode, this.body);
  final int statusCode;
  final String body;

  @override
  String toString() => "LivetexVisitorUploadException($statusCode): $body";
}

/// HTTP authentication against Visitor-Auth (`GET …/v1/auth`).
Future<AuthResult> livetexVisitorAuthenticate({
  required Uri authEndpoint,
  required String touchPoint,
  http.Client? httpClient,
  String? visitorToken,
  String? customVisitorToken,
  String? deviceToken,

  /// e.g. `android`, `ios`
  String? deviceType,
  Map<String, String> headers = const {},
  void Function(String line)? trace,
  bool traceRedactTokens = true,
}) async {
  final ownClient = httpClient == null;
  final client = httpClient ?? http.Client();
  try {
    final qp = <String, String>{
      "touchPoint": touchPoint,
      if (visitorToken != null) "visitorToken": visitorToken,
      if (customVisitorToken != null) "customVisitorToken": customVisitorToken,
      if (deviceToken != null) "deviceToken": deviceToken,
      if (deviceType != null) "deviceType": deviceType,
    };
    final uri = authEndpoint.replace(queryParameters: qp);
    livetexTraceMaybeEmit(trace, traceRedactTokens, "auth GET $uri");
    final response = await client.get(uri, headers: headers);
    if (response.statusCode != 200) {
      throw LivetexVisitorAuthException(response.statusCode, response.body);
    }
    final map = jsonDecode(response.body) as Map<String, dynamic>;
    return AuthResult.fromJson(map);
  } finally {
    if (ownClient) client.close();
  }
}

/// WebSocket session to Visitor-API (`wss://…/v1/ws/{visitorToken}` from [AuthResult]).
final class LivetexVisitorSession {
  LivetexVisitorSession._(this.auth, this._channel);

  final AuthResult auth;
  final WebSocketChannel _channel;

  /// Called when the WebSocket stream ends (network drop, server close). Used for reconnect.
  void Function()? onDisconnected;
  final StreamController<VisitorServerMessage> _controller =
      StreamController<VisitorServerMessage>.broadcast();

  StreamSubscription<dynamic>? _socketSub;

  /// Opens auth, then connects the socket.
  static Future<LivetexVisitorSession> connect({
    required Uri authEndpoint,
    required String touchPoint,
    http.Client? httpClient,
    String? visitorToken,
    String? customVisitorToken,
    String? deviceToken,
    String? deviceType,
    Map<String, String> headers = const {},
    void Function(String line)? trace,
    bool traceRedactTokens = true,
    void Function(String inboundJson)? onInboundText,
  }) async {
    final auth = await livetexVisitorAuthenticate(
      authEndpoint: authEndpoint,
      touchPoint: touchPoint,
      httpClient: httpClient,
      visitorToken: visitorToken,
      customVisitorToken: customVisitorToken,
      deviceToken: deviceToken,
      deviceType: deviceType,
      headers: headers,
      trace: trace,
      traceRedactTokens: traceRedactTokens,
    );
    return LivetexVisitorSession.open(auth, onInboundText: onInboundText);
  }

  /// Connect using an existing [AuthResult] from a prior `livetexVisitorAuthenticate` call.
  factory LivetexVisitorSession.open(
    AuthResult auth, {
    void Function(String inboundJson)? onInboundText,
  }) {
    final uri = Uri.parse(auth.endpoints.ws);
    // pingInterval enables protocol-level WebSocket ping/pong every 30s.
    // Without it the socket can be silently torn down by an idle-timeout on
    // any intermediate proxy (Cloudflare / corporate NAT / mobile carrier
    // typically close idle WS in 60-120s) and our `sink.add()` would
    // happily push frames into a drained connection. With pingInterval
    // set, dart:io WebSocket aborts the connection when no pong arrives,
    // `onDone` fires, and the existing `_scheduleReconnect` kicks in.
    final channel = IOWebSocketChannel.connect(
      uri,
      pingInterval: const Duration(seconds: 30),
    );
    final session = LivetexVisitorSession._(auth, channel);
    session._socketSub = channel.stream.listen(
      (event) {
        if (event is String) {
          onInboundText?.call(event);
          session._controller.add(parseServerMessage(event));
        }
      },
      onError: session._controller.addError,
      onDone: () {
        session.onDisconnected?.call();
      },
    );
    return session;
  }

  /// Parsed server payloads (`state`, `update`, `result`, …).
  Stream<VisitorServerMessage> get messages => _controller.stream;

  /// Raw UTF-8 text frames only (ignored if binary).
  Stream<String> get rawMessages =>
      _channel.stream.where((e) => e is String).cast<String>();

  void sendRawJson(String json) {
    _channel.sink.add(json);
  }

  Future<void> close() async {
    await _socketSub?.cancel();
    await _controller.close();
    await _channel.sink.close();
  }

  /// Multipart field name defaults to `fileUpload` (LiveTex file‑service).
  ///
  /// Send `Authorization: Bearer {visitorToken}`. Optionally override
  /// [fileFieldName] if your environment expects another part name (e.g. `file`).
  ///
  /// [filenameSuffixPath], when set, becomes the trailing URL segment behind
  /// [AuthEndpoints.upload] (RFC 3986 percent‑encoding applied per component).
  Future<String> uploadMultipartFile({
    required File file,
    http.Client? httpClient,
    String? filenameSuffixPath,
    String fileFieldName = "fileUpload",
    Uri? uploadBaseOverride,
  }) async {
    final uploadRoot = uploadBaseOverride ?? Uri.parse(auth.endpoints.upload);
    final suffix = _normalizedUploadSuffix(filenameSuffixPath);
    final uri = _visitorUploadUri(uploadRoot, suffix);

    final ownClient = httpClient == null;
    final client = httpClient ?? http.Client();
    try {
      final request = http.MultipartRequest("POST", uri);
      request.headers["Authorization"] = "Bearer ${auth.visitorToken}";
      request.files.add(
        await http.MultipartFile.fromPath(
          fileFieldName,
          file.path,
          filename: _multipartBodyFilenameHint(
            file.path,
            suffix,
          ),
        ),
      );
      final streamed = await client.send(request);
      final body = await streamed.stream.bytesToString();
      if (streamed.statusCode != 200) {
        throw LivetexVisitorUploadException(streamed.statusCode, body);
      }
      return body;
    } finally {
      if (ownClient) client.close();
    }
  }
}
