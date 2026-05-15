const String livetexChatPackageVersion = "0.1.0";

String livetexTraceFormatLine(String message) =>
    "${DateTime.now().toUtc().toIso8601String()} $message";

void livetexTraceMaybeEmit(
  void Function(String line)? sink,
  bool redactTokens,
  String message,
) {
  if (sink == null) return;
  final body = livetexTraceRedact(message, redact: redactTokens);
  sink(livetexTraceFormatLine(body));
}

String livetexTraceRedact(String input, {required bool redact}) {
  if (!redact) return input;
  var s = input;
  s = s.replaceAllMapped(
    RegExp(r"touchPoint=([^&\s]+)"),
    (m) => "touchPoint=…(${m[1]!.length}ch)",
  );
  s = s.replaceAllMapped(
    RegExp(r"visitorToken=([^&\s]+)"),
    (m) => "visitorToken=…(${m[1]!.length}ch)",
  );
  s = s.replaceAllMapped(
    RegExp(r"customVisitorToken=([^&\s]+)"),
    (m) => "customVisitorToken=…(${m[1]!.length}ch)",
  );
  s = s.replaceAllMapped(
    RegExp(r"deviceToken=([^&\s]+)"),
    (m) => "deviceToken=…(${m[1]!.length}ch)",
  );
  s = s.replaceAllMapped(
    RegExp(r"Bearer\s+\S+"),
    (_) => "Bearer …",
  );
  s = s.replaceAllMapped(
    RegExp(r"(wss?://[^/]+(?::\d+)?/v\d+/ws/)([^/\?\s]+)"),
    (m) => "${m[1]}…",
  );
  return s;
}

String livetexSupportMaskTouchPoint(String touchPoint) {
  final i = touchPoint.indexOf(":");
  if (i <= 0) return "(len ${touchPoint.length})";
  return "${touchPoint.substring(0, i)}:(len ${touchPoint.length - i - 1})";
}
