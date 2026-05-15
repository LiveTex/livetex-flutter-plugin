import "dart:convert";

import "server_messages.dart";

/// Parses a single Visitor-API WebSocket text frame.
///
/// Invalid JSON yields [VisitorRawText]. Missing or unknown `type` yields
/// [VisitorUnknownMessage]. Known `type` values map to [VisitorServerMessage] subtypes.
VisitorServerMessage parseServerMessage(String raw) {
  Object? decoded;
  try {
    decoded = jsonDecode(raw);
  } catch (_) {
    return VisitorRawText(raw);
  }
  if (decoded is! Map<String, dynamic>) {
    return VisitorUnknownMessage({"_raw": raw});
  }
  final type = decoded["type"];
  if (type is! String) {
    return VisitorUnknownMessage(decoded);
  }
  try {
    switch (type) {
      case "state":
        return VisitorDialogState.fromJson(decoded);
      case "update":
        return VisitorUpdate.fromJson(decoded);
      case "result":
        return VisitorResult.fromJson(decoded);
      case "error":
        return VisitorApiError.fromJson(decoded);
      case "attributesRequest":
        return const VisitorAttributesRequest();
      case "departmentRequest":
        return VisitorDepartmentRequest.fromJson(decoded);
      case "employeeTyping":
        return VisitorEmployeeTyping.fromJson(decoded);
      default:
        return VisitorUnknownMessage(decoded);
    }
  } catch (_) {
    return VisitorUnknownMessage(decoded);
  }
}
