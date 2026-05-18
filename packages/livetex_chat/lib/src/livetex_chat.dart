import "dart:async";
import "dart:io";
import "dart:math";

import "package:http/http.dart" as http;
import "api/protocol_outgoing.dart";
import "api/server_messages.dart";
import "api/visitor_client.dart";

import "domain/chat_message.dart";
import "livetex_chat_config.dart";
import "livetex_chat_errors.dart";
import "livetex_connection_state.dart";
import "livetex_trace.dart";

/// High-level chat session over Visitor API (same package as [LivetexVisitorSession]).
final class LivetexChat {
  LivetexChat(this.config, {http.Client? httpClient}) : _http = httpClient;

  final LivetexChatConfig config;
  final http.Client? _http;
  String? _deviceTokenOverride;
  LivetexVisitorSession? _session;
  StreamSubscription<VisitorServerMessage>? _msgSub;
  int _corrSeq = 0;
  bool _disconnectRequested = false;
  Timer? _reconnectTimer;
  int _backoffSec = 3;
  static const int _backoffMax = 30;

  final _connection = StreamController<LivetexConnectionState>.broadcast();
  final _dialog = StreamController<VisitorDialogState?>.broadcast();
  final _messagesCtrl = StreamController<List<ChatMessage>>.broadcast();
  final _errors = StreamController<LivetexChatError>.broadcast();
  final _attributesRequest = StreamController<Null>.broadcast();
  final _departmentRequest =
      StreamController<List<DepartmentItem>>.broadcast();
  final _employeeTyping = StreamController<DateTime>.broadcast();

  final Map<String, ChatMessage> _byId = {};
  final List<String> _order = [];
  VisitorDialogState? _lastDialog;
  DateTime? _lastTypingEmit;
  Stream<LivetexConnectionState> get connectionState => _connection.stream;
  Stream<VisitorDialogState?> get dialogState => _dialog.stream;
  Stream<List<ChatMessage>> get messages => _messagesCtrl.stream;
  Stream<LivetexChatError> get errors => _errors.stream;
  Stream<Null> get attributesRequest => _attributesRequest.stream;
  Stream<List<DepartmentItem>> get departmentRequest =>
      _departmentRequest.stream;
  Stream<DateTime> get employeeTyping => _employeeTyping.stream;

  VisitorDialogState? get currentDialog => _lastDialog;
  List<ChatMessage> get currentMessages => _snapshotMessages();
  LivetexConnectionState get connectionNow => _connNow;
  LivetexConnectionState _connNow = LivetexConnectionState.disconnected;

  String? _lastErrorLine;

  bool get isConnected =>
      _connNow == LivetexConnectionState.connected && _session != null;

  void _emitTrace(String message) {
    livetexTraceMaybeEmit(config.trace, config.traceRedactTokens, message);
  }

  void _traceInboundFrame(String raw) {
    final capped = raw.length > 4096
        ? "${raw.substring(0, 4096)}…(+${raw.length - 4096}b)"
        : raw;
    _emitTrace("ws_in $capped");
  }

  void _registerError(LivetexChatError e) {
    _lastErrorLine = e.toString();
    if (!_errors.isClosed) {
      _errors.add(e);
    }
    _emitTrace("err ${e.code ?? ""} ${e.message}");
  }

  String collectSupportReport() {
    final buf = StringBuffer()
      ..writeln("livetex_chat $livetexChatPackageVersion")
      ..writeln("connection: $_connNow")
      ..writeln("auth_host: ${config.resolveAuthEndpoint().host}")
      ..writeln("touchPoint: ${livetexSupportMaskTouchPoint(config.touchPoint)}")
      ..writeln("last_error: ${_lastErrorLine ?? "none"}")
      ..writeln("os: ${Platform.operatingSystem} ${Platform.operatingSystemVersion}");
    return livetexTraceRedact(buf.toString(), redact: config.traceRedactTokens);
  }

  String _nextCorrelation(String prefix) {
    _corrSeq++;
    return "$prefix-$_corrSeq-${DateTime.now().millisecondsSinceEpoch}";
  }

  void _setConn(LivetexConnectionState s) {
    _connNow = s;
    if (!_connection.isClosed) _connection.add(s);
  }

  Future<void> connect() async {
    _disconnectRequested = false;
    await _openSession();
  }

  Future<void> _openSession() async {
    if (_disconnectRequested) return;
    await _msgSub?.cancel();
    _msgSub = null;
    try {
      await _session?.close();
    } catch (_) {}
    _session = null;
    _setConn(
      _session == null
          ? LivetexConnectionState.connecting
          : LivetexConnectionState.reconnecting,
    );
    _emitTrace("connect");
    try {
      _session = await LivetexVisitorSession.connect(
        authEndpoint: config.resolveAuthEndpoint(),
        touchPoint: config.touchPoint,
        httpClient: _http,
        visitorToken: config.visitorToken,
        customVisitorToken: config.customVisitorToken,
        deviceToken: _deviceTokenOverride ?? config.deviceToken,
        deviceType: resolveLivetexVisitorDeviceType(config.deviceType),
        headers: config.headers,
        trace: config.trace,
        traceRedactTokens: config.traceRedactTokens,
        onInboundText: config.trace != null ? _traceInboundFrame : null,
      );
      _session!.onDisconnected = _onSocketDone;
      _msgSub = _session!.messages.listen(
        _onServerMessage,
        onError: (Object e, StackTrace st) {
          _registerError(LivetexChatError(message: "$e", cause: e));
        },
      );
      _backoffSec = 3;
      _setConn(LivetexConnectionState.connected);
      _emitTrace("connected");
    } on LivetexVisitorAuthException catch (e) {
      _setConn(LivetexConnectionState.disconnected);
      _registerError(
        LivetexChatError(
          message: e.body,
          code: "auth_http_${e.statusCode}",
          cause: e,
        ),
      );
    } catch (e) {
      _setConn(LivetexConnectionState.disconnected);
      _registerError(LivetexChatError(message: "$e", cause: e));
    }
  }

  void _onSocketDone() {
    if (_disconnectRequested) return;
    _emitTrace("ws_done");
    _setConn(LivetexConnectionState.disconnected);
    _scheduleReconnect();
  }

  void _scheduleReconnect() {
    _reconnectTimer?.cancel();
    final wait = min(_backoffSec, _backoffMax);
    _emitTrace("reconnect_in ${wait}s");
    _reconnectTimer = Timer(Duration(seconds: wait), () async {
      if (_disconnectRequested) return;
      _backoffSec = min(_backoffSec * 2, _backoffMax);
      await _msgSub?.cancel();
      _msgSub = null;
      try {
        await _session?.close();
      } catch (_) {}
      _session = null;
      await _openSession();
    });
  }

  Future<void> disconnect() async {
    _disconnectRequested = true;
    _reconnectTimer?.cancel();
    _reconnectTimer = null;
    await _msgSub?.cancel();
    _msgSub = null;
    try {
      await _session?.close();
    } catch (_) {}
    _session = null;
    _setConn(LivetexConnectionState.disconnected);
  }

  /// Updates push token for the next auth / reconnect cycle.
  void updateDeviceToken(String? token) {
    _deviceTokenOverride = token;
  }

  void _onServerMessage(VisitorServerMessage m) {
    switch (m) {
      case VisitorDialogState():
        _lastDialog = m;
        if (!_dialog.isClosed) _dialog.add(m);
        _emitMessages();
      case VisitorUpdate(:final messages):
        for (final piece in messages) {
          _ingestUpdatePiece(piece);
        }
        _emitMessages();
      case final VisitorResult r:
        _applyResult(r.correlationId, r.sentMessage, r.errors);
        _emitMessages();
      case VisitorApiError(:final code):
        _registerError(LivetexChatError(message: "ApiError: $code", code: code));
      case VisitorAttributesRequest():
        if (!_attributesRequest.isClosed) _attributesRequest.add(null);
      case VisitorDepartmentRequest(:final departments):
        if (!_departmentRequest.isClosed) {
          _departmentRequest.add(departments);
        }
      case VisitorEmployeeTyping(:final createdAt):
        final now = DateTime.now();
        if (_lastTypingEmit == null ||
            now.difference(_lastTypingEmit!) > const Duration(milliseconds: 400)) {
          _lastTypingEmit = now;
          if (!_employeeTyping.isClosed) _employeeTyping.add(createdAt);
        }
      case VisitorRawText():
      case VisitorUnknownMessage():
        break;
    }
  }

  void _applyResult(
    String correlationId,
    SentMessageRef? sent,
    List<String> errors,
  ) {
    final pendingId = "pending:$correlationId";
    final existing = _byId[pendingId];
    if (existing == null) return;
    if (errors.isNotEmpty) {
      _byId[pendingId] = existing.copyWith(sendState: ChatMessageSendState.failed);
      return;
    }
    if (sent != null) {
      _byId.remove(pendingId);
      _order.remove(pendingId);
      final merged = existing.copyWith(
        id: sent.id,
        createdAt: sent.createdAt,
        sendState: ChatMessageSendState.sent,
        correlationId: null,
      );
      _byId[sent.id] = merged;
      if (!_order.contains(sent.id)) {
        _insertSortedId(sent.id);
      }
    }
  }

  void _insertSortedId(String id) {
    final t = _byId[id]!.createdAt;
    var i = 0;
    while (i < _order.length && _byId[_order[i]]!.createdAt.isBefore(t)) {
      i++;
    }
    _order.insert(i, id);
  }

  void _ingestUpdatePiece(UpdateMessagePayload piece) {
    switch (piece) {
      case TextUpdatePayload(
          :final id,
          :final createdAt,
          :final content,
          :final creator,
          :final keyboard,
        ):
        final row = ChatMessage(
          id: id,
          createdAt: createdAt,
          isVisitor: creator.creatorType == "visitor",
          text: content,
          creatorLabel: _creatorLabel(creator),
          keyboard: keyboard,
          sendState: ChatMessageSendState.none,
        );
        _upsert(row);
      case FileUpdatePayload(
          :final id,
          :final createdAt,
          :final name,
          :final url,
          :final creator,
        ):
        final row = ChatMessage(
          id: id,
          createdAt: createdAt,
          isVisitor: creator.creatorType == "visitor",
          fileName: name,
          fileUrl: url,
          creatorLabel: _creatorLabel(creator),
          sendState: ChatMessageSendState.none,
        );
        _upsert(row);
    }
  }

  String _creatorLabel(CreatorModel c) {
    return switch (c.creatorType) {
      "visitor" => "Вы",
      "bot" => "Бот",
      "system" => "Система",
      _ => c.employee?.name ?? c.creatorType,
    };
  }

  void _upsert(ChatMessage row) {
    final existed = _byId[row.id];
    _byId[row.id] = row;
    if (existed == null && !_order.contains(row.id)) {
      _insertSortedId(row.id);
    }
  }

  List<ChatMessage> _snapshotMessages() {
    return _order.map((id) => _byId[id]!).toList(growable: false);
  }

  void _emitMessages() {
    if (!_messagesCtrl.isClosed) _messagesCtrl.add(_snapshotMessages());
  }

  void sendRawJson(String json) => _session?.sendRawJson(json);

  void sendText(String text) {
    final s = _session;
    if (s == null) return;
    final corr = _nextCorrelation("txt");
    final pending = ChatMessage(
      id: "pending:$corr",
      createdAt: DateTime.now(),
      isVisitor: true,
      text: text,
      sendState: ChatMessageSendState.sending,
      correlationId: corr,
    );
    _byId[pending.id] = pending;
    _insertSortedId(pending.id);
    _emitMessages();
    s.sendRawJson(VisitorOutgoing.text(correlationId: corr, content: text));
  }

  void sendTyping() {
    final s = _session;
    if (s == null) return;
    final corr = _nextCorrelation("typ");
    s.sendRawJson(VisitorOutgoing.typing(correlationId: corr));
  }

  Future<void> sendFile(File file, {String? logicalName}) async {
    final s = _session;
    if (s == null) return;
    if (!s.auth.settings.fileTransferring) {
      _registerError(
        const LivetexChatError(
          message: "File transfer disabled for this touch point",
          code: "file_disabled",
        ),
      );
      return;
    }
    final corr = _nextCorrelation("file");
    final name = logicalName ?? file.path.split(Platform.pathSeparator).last;
    final pending = ChatMessage(
      id: "pending:$corr",
      createdAt: DateTime.now(),
      isVisitor: true,
      fileName: name,
      sendState: ChatMessageSendState.sending,
      correlationId: corr,
    );
    _byId[pending.id] = pending;
    _insertSortedId(pending.id);
    _emitMessages();
    try {
      final url = await s.uploadMultipartFile(
        file: file,
        filenameSuffixPath: name,
      );
      s.sendRawJson(
        VisitorOutgoing.file(
          correlationId: corr,
          name: name,
          url: url.trim(),
        ),
      );
    } on LivetexVisitorUploadException catch (e) {
      _byId.remove("pending:$corr");
      _order.remove("pending:$corr");
      _emitMessages();
      _registerError(
        LivetexChatError(
          message: e.body,
          code: "upload_${e.statusCode}",
          cause: e,
        ),
      );
    }
  }

  void sendRating({
    required String rateType,
    required String value,
    String? comment,
  }) {
    final s = _session;
    if (s == null) {
      // DIAG: surfaces session loss as a trace event so the on-device log
      // shows it next to the UI's TOP onSubmit log. Remove once the
      // closed-dialog rating issue is confirmed/fixed.
      _emitTrace("sendRating SKIPPED (no session) type=$rateType value=$value");
      return;
    }
    final corr = _nextCorrelation("rate");
    final json = VisitorOutgoing.rating(
      correlationId: corr,
      rateType: rateType,
      value: value,
      comment: comment,
    );
    _emitTrace("ws_out $json");
    s.sendRawJson(json);
  }

  void sendAttributes({
    required String correlationId,
    String? name,
    String? phone,
    String? email,
    required Map<String, String> attributes,
  }) {
    _session?.sendRawJson(
      VisitorOutgoing.attributes(
        correlationId: correlationId,
        name: name,
        phone: phone,
        email: email,
        attributes: attributes,
      ),
    );
  }

  void selectDepartment({required String correlationId, required String id}) {
    _session?.sendRawJson(
      VisitorOutgoing.department(correlationId: correlationId, id: id),
    );
  }

  void loadHistory({required String messageId, int offset = 0}) {
    final corr = _nextCorrelation("hist");
    _session?.sendRawJson(
      VisitorOutgoing.getHistory(
        correlationId: corr,
        messageId: messageId,
        offset: offset,
      ),
    );
  }

  void pressButton({required String payload}) {
    final corr = _nextCorrelation("btn");
    _session?.sendRawJson(
      VisitorOutgoing.buttonPressed(correlationId: corr, payload: payload),
    );
  }

  Future<void> dispose() async {
    await disconnect();
    await _connection.close();
    await _dialog.close();
    await _messagesCtrl.close();
    await _errors.close();
    await _attributesRequest.close();
    await _departmentRequest.close();
    await _employeeTyping.close();
  }
}
