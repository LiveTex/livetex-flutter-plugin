import "dart:convert";

/// Builders for outbound Visitor-API v1 JSON WebSocket payloads.
///
/// Each method returns a JSON string intended for [LivetexVisitorSession.sendRawJson].
abstract final class VisitorOutgoing {
  static String text({
    required String correlationId,
    required String content,
  }) {
    return jsonEncode({
      "type": "text",
      "correlationId": correlationId,
      "content": content,
    });
  }

  static String typing({
    required String correlationId,
    String content = "",
  }) {
    return jsonEncode({
      "type": "typing",
      "correlationId": correlationId,
      "content": content,
    });
  }

  static String department({
    required String correlationId,
    required String id,
  }) {
    return jsonEncode({
      "type": "department",
      "correlationId": correlationId,
      "id": id,
    });
  }

  static String attributes({
    required String correlationId,
    String? name,
    String? phone,
    String? email,
    required Map<String, String> attributes,
  }) {
    final map = <String, dynamic>{
      "type": "attributes",
      "correlationId": correlationId,
      "attributes": attributes,
    };
    if (name != null) map["name"] = name;
    if (phone != null) map["phone"] = phone;
    if (email != null) map["email"] = email;
    return jsonEncode(map);
  }

  static String file({
    required String correlationId,
    required String name,
    required String url,
  }) {
    return jsonEncode({
      "type": "file",
      "correlationId": correlationId,
      "name": name,
      "url": url,
    });
  }

  static String getHistory({
    required String correlationId,
    required String messageId,
    required int offset,
  }) {
    return jsonEncode({
      "type": "getHistory",
      "correlationId": correlationId,
      "messageId": messageId,
      "offset": offset,
    });
  }

  static String rating({
    required String correlationId,
    required String rateType,
    required String value,
    String? comment,
  }) {
    final map = <String, dynamic>{
      "type": "rating",
      "correlationId": correlationId,
      "rate": {"type": rateType, "value": value},
    };
    if (comment != null) map["comment"] = comment;
    return jsonEncode(map);
  }

  static String buttonPressed({
    required String correlationId,
    required String payload,
  }) {
    return jsonEncode({
      "type": "buttonPressed",
      "correlationId": correlationId,
      "payload": payload,
    });
  }
}
