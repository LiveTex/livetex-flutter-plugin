/// Response body of `GET .../v1/auth` (Visitor-Auth service).
class AuthResult {
  const AuthResult({
    required this.visitorToken,
    required this.endpoints,
    required this.settings,
  });

  final String visitorToken;
  final AuthEndpoints endpoints;
  final AuthSettings settings;

  factory AuthResult.fromJson(Map<String, dynamic> json) {
    return AuthResult(
      visitorToken: json["visitorToken"] as String,
      endpoints: AuthEndpoints.fromJson(
        json["endpoints"] as Map<String, dynamic>,
      ),
      settings: AuthSettings.fromJson(json["settings"] as Map<String, dynamic>),
    );
  }
}

class AuthEndpoints {
  const AuthEndpoints({required this.ws, required this.upload});

  final String ws;
  final String upload;

  factory AuthEndpoints.fromJson(Map<String, dynamic> json) {
    return AuthEndpoints(
      ws: json["ws"] as String,
      upload: json["upload"] as String,
    );
  }
}

class AuthSettings {
  const AuthSettings({required this.fileTransferring});

  final bool fileTransferring;

  factory AuthSettings.fromJson(Map<String, dynamic> json) {
    return AuthSettings(
      fileTransferring: json["fileTransferring"] as bool,
    );
  }
}
