import "dart:io" show Platform;

String resolveLivetexVisitorDeviceType(String? deviceType) {
  final t = deviceType?.trim();
  if (t != null && t.isNotEmpty) return t;
  if (Platform.isIOS) return "ios";
  if (Platform.isAndroid) return "android";
  return "android";
}

/// Configuration for [LivetexChat] (Visitor-Auth + Visitor-API).
final class LivetexChatConfig {
  const LivetexChatConfig({
    required this.touchPoint,
    this.authEndpoint,
    this.baseUrl,
    this.visitorToken,
    this.customVisitorToken,
    this.deviceToken,
    this.deviceType,
    this.headers = const {},
    this.trace,
    this.traceRedactTokens = true,
  });

  /// Touch point id from LiveTex (e.g. `168:uuid`).
  final String touchPoint;

  /// Full auth URL. If null, derived from [baseUrl] as `{base}/v1/auth`.
  final Uri? authEndpoint;

  /// Cloud default `https://visitor-api.livetex.ru` when [authEndpoint] is null.
  final Uri? baseUrl;

  final String? visitorToken;
  final String? customVisitorToken;
  final String? deviceToken;

  final String? deviceType;

  final Map<String, String> headers;

  final void Function(String line)? trace;

  final bool traceRedactTokens;

  Uri resolveAuthEndpoint() {
    if (authEndpoint != null) return authEndpoint!;
    final root = baseUrl ?? Uri.parse("https://visitor-api.livetex.ru");
    return root.replace(path: "${root.path}/v1/auth".replaceAll("//", "/"));
  }
}
