import "json_utils.dart";

/// Base type for inbound Visitor-API messages produced by [parseServerMessage].
///
/// Subtypes cover `state`, `update`, `result`, `error`, attribute/department requests,
/// and [VisitorEmployeeTyping]. Everything else surfaces as [VisitorUnknownMessage]
/// or [VisitorRawText].
sealed class VisitorServerMessage {
  const VisitorServerMessage();
}

/// Inbound frame that is not valid JSON.
final class VisitorRawText extends VisitorServerMessage {
  VisitorRawText(this.text);
  final String text;
}

/// Decoded JSON map with an unknown or unsupported `type`.
final class VisitorUnknownMessage extends VisitorServerMessage {
  VisitorUnknownMessage(this.json);
  final Map<String, dynamic> json;
}

enum DialogStatus {
  unassigned,
  inQueue,
  assigned,
  aiBot;

  static DialogStatus? parse(String? value) {
    switch (value) {
      case "unassigned":
        return DialogStatus.unassigned;
      case "inQueue":
        return DialogStatus.inQueue;
      case "assigned":
        return DialogStatus.assigned;
      case "aiBot":
        return DialogStatus.aiBot;
      default:
        return null;
    }
  }
}

enum EmployeeOnlineStatus {
  online,
  offline;

  static EmployeeOnlineStatus? parse(String? value) {
    switch (value) {
      case "online":
        return EmployeeOnlineStatus.online;
      case "offline":
        return EmployeeOnlineStatus.offline;
      default:
        return null;
    }
  }
}

final class AssignedEmployee {
  AssignedEmployee({
    required this.name,
    required this.position,
    required this.avatarUrl,
    this.rating,
  });

  factory AssignedEmployee.fromJson(Map<String, dynamic> j) {
    return AssignedEmployee(
      name: j["name"] as String,
      position: j["position"] as String,
      avatarUrl: j["avatarUrl"] as String,
      rating: j["rating"] as String?,
    );
  }

  final String name;
  final String position;
  final String avatarUrl;
  final String? rating;
}

final class DialogRateState {
  DialogRateState({
    this.enabledType,
    this.commentEnabled,
    this.textBefore,
    this.textAfter,
    this.isSet,
  });

  factory DialogRateState.fromJson(Map<String, dynamic> j) {
    final isSetRaw = j["isSet"];
    return DialogRateState(
      enabledType: j["enabledType"] as String?,
      commentEnabled: j["commentEnabled"] as bool?,
      textBefore: j["textBefore"] as String?,
      textAfter: j["textAfter"] as String?,
      isSet: isSetRaw is Map<String, dynamic>
          ? SetRatePayload.fromJson(isSetRaw)
          : null,
    );
  }

  final String? enabledType;
  final bool? commentEnabled;
  final String? textBefore;
  final String? textAfter;
  final SetRatePayload? isSet;
}

final class SetRatePayload {
  SetRatePayload({required this.type, required this.value, this.comment});

  factory SetRatePayload.fromJson(Map<String, dynamic> j) {
    return SetRatePayload(
      type: j["type"] as String,
      value: j["value"] as String,
      comment: j["comment"] as String?,
    );
  }

  final String type;
  final String value;
  final String? comment;
}

final class VisitorDialogState extends VisitorServerMessage {
  VisitorDialogState({
    required this.status,
    this.employeeStatus,
    this.employee,
    required this.showInput,
    this.rate,
  });

  factory VisitorDialogState.fromJson(Map<String, dynamic> j) {
    final rateRaw = j["rate"];
    return VisitorDialogState(
      status:
          DialogStatus.parse(j["status"] as String?) ?? DialogStatus.unassigned,
      employeeStatus:
          EmployeeOnlineStatus.parse(j["employeeStatus"] as String?),
      employee: (j["employee"] is Map<String, dynamic>)
          ? AssignedEmployee.fromJson(j["employee"] as Map<String, dynamic>)
          : null,
      showInput: j["showInput"] as bool,
      rate: rateRaw is Map<String, dynamic>
          ? DialogRateState.fromJson(rateRaw)
          : null,
    );
  }

  final DialogStatus status;
  final EmployeeOnlineStatus? employeeStatus;
  final AssignedEmployee? employee;
  final bool showInput;
  final DialogRateState? rate;
}

sealed class UpdateMessagePayload {
  const UpdateMessagePayload();
}

final class TextUpdatePayload extends UpdateMessagePayload {
  TextUpdatePayload({
    required this.id,
    required this.createdAt,
    required this.content,
    required this.creator,
    this.keyboard,
    this.attributes,
  });

  factory TextUpdatePayload.fromJson(Map<String, dynamic> j) {
    final kb = j["keyboard"];
    final attrs = j["attributes"];
    return TextUpdatePayload(
      id: j["id"] as String,
      createdAt: tryParseServerDate(j["createdAt"]) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      content: j["content"] as String,
      creator: CreatorModel.fromJson(j["creator"] as Map<String, dynamic>),
      keyboard:
          kb is Map<String, dynamic> ? KeyboardPayload.fromJson(kb) : null,
      attributes: attrs is Map<String, dynamic>
          ? attrs.map<String, String>(
              (String k, dynamic v) => MapEntry(k, v.toString()),
            )
          : null,
    );
  }

  final String id;
  final DateTime createdAt;
  final String content;
  final CreatorModel creator;
  final KeyboardPayload? keyboard;
  final Map<String, String>? attributes;
}

final class FileUpdatePayload extends UpdateMessagePayload {
  FileUpdatePayload({
    required this.id,
    required this.createdAt,
    required this.name,
    required this.url,
    required this.creator,
  });

  factory FileUpdatePayload.fromJson(Map<String, dynamic> j) {
    return FileUpdatePayload(
      id: j["id"] as String,
      createdAt: tryParseServerDate(j["createdAt"]) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      name: j["name"] as String,
      url: j["url"] as String,
      creator: CreatorModel.fromJson(j["creator"] as Map<String, dynamic>),
    );
  }

  final String id;
  final DateTime createdAt;
  final String name;
  final String url;
  final CreatorModel creator;
}

final class EmployeeBrief {
  EmployeeBrief({
    required this.name,
    required this.position,
    required this.avatarUrl,
  });

  factory EmployeeBrief.fromJson(Map<String, dynamic> j) {
    return EmployeeBrief(
      name: j["name"] as String,
      position: j["position"] as String,
      avatarUrl: j["avatarUrl"] as String,
    );
  }

  final String name;
  final String position;
  final String avatarUrl;
}

final class CreatorModel {
  CreatorModel({required this.creatorType, this.employee});

  factory CreatorModel.fromJson(Map<String, dynamic> j) {
    final emp = j["employee"];
    return CreatorModel(
      creatorType: j["type"] as String,
      employee:
          emp is Map<String, dynamic> ? EmployeeBrief.fromJson(emp) : null,
    );
  }

  final String creatorType;
  final EmployeeBrief? employee;
}

final class KeyboardPayload {
  KeyboardPayload({required this.buttons, required this.pressed});

  factory KeyboardPayload.fromJson(Map<String, dynamic> j) {
    final list = j["buttons"] as List<dynamic>? ?? [];
    return KeyboardPayload(
      buttons: list
          .map((e) => ButtonPayload.fromJson(e as Map<String, dynamic>))
          .toList(),
      pressed: j["pressed"] as bool,
    );
  }

  final List<ButtonPayload> buttons;
  final bool pressed;
}

final class ButtonPayload {
  ButtonPayload({
    required this.label,
    required this.payload,
    this.url,
  });

  factory ButtonPayload.fromJson(Map<String, dynamic> j) {
    return ButtonPayload(
      label: j["label"] as String,
      payload: j["payload"] as String,
      url: j["url"] as String?,
    );
  }

  final String label;
  final String payload;
  final String? url;
}

final class VisitorUpdate extends VisitorServerMessage {
  VisitorUpdate({
    required this.createdAt,
    required this.messages,
    this.correlationId,
  });

  factory VisitorUpdate.fromJson(Map<String, dynamic> j) {
    final raw = j["messages"] as List<dynamic>? ?? [];
    final messages =
        raw.map((m) => _decodeUpdatePiece(m as Map<String, dynamic>)).toList();
    return VisitorUpdate(
      correlationId: j["correlationId"] as String?,
      createdAt: tryParseServerDate(j["createdAt"]) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      messages: messages,
    );
  }

  final String? correlationId;
  final DateTime createdAt;
  final List<UpdateMessagePayload> messages;

  static UpdateMessagePayload _decodeUpdatePiece(Map<String, dynamic> m) {
    final t = m["type"] as String?;
    switch (t) {
      case "file":
        return FileUpdatePayload.fromJson(m);
      case "text":
      default:
        return TextUpdatePayload.fromJson(m);
    }
  }
}

final class SentMessageRef {
  SentMessageRef({required this.createdAt, required this.id});

  factory SentMessageRef.fromJson(Map<String, dynamic> j) {
    return SentMessageRef(
      createdAt: tryParseServerDate(j["createdAt"]) ??
          DateTime.fromMillisecondsSinceEpoch(0),
      id: j["id"] as String,
    );
  }

  final DateTime createdAt;
  final String id;
}

final class VisitorResult extends VisitorServerMessage {
  VisitorResult({
    required this.correlationId,
    this.sentMessage,
    required this.errors,
  });

  factory VisitorResult.fromJson(Map<String, dynamic> j) {
    final sm = j["sentMessage"];
    final err = j["error"] as List<dynamic>? ?? [];
    return VisitorResult(
      correlationId: j["correlationId"] as String,
      sentMessage:
          sm is Map<String, dynamic> ? SentMessageRef.fromJson(sm) : null,
      errors: err.map((e) => e as String).toList(),
    );
  }

  final String correlationId;
  final SentMessageRef? sentMessage;
  final List<String> errors;

  bool get isSuccess => errors.isEmpty;
}

final class VisitorApiError extends VisitorServerMessage {
  VisitorApiError({required this.code});

  factory VisitorApiError.fromJson(Map<String, dynamic> j) {
    return VisitorApiError(code: j["code"] as String);
  }

  final String code;
}

final class VisitorAttributesRequest extends VisitorServerMessage {
  const VisitorAttributesRequest();
}

final class DepartmentItem {
  DepartmentItem({
    required this.id,
    required this.name,
    required this.order,
  });

  factory DepartmentItem.fromJson(Map<String, dynamic> j) {
    return DepartmentItem(
      id: j["id"] as String,
      name: j["name"] as String,
      order: (j["order"] as num).toInt(),
    );
  }

  final String id;
  final String name;
  final int order;
}

final class VisitorDepartmentRequest extends VisitorServerMessage {
  VisitorDepartmentRequest({required this.departments});

  factory VisitorDepartmentRequest.fromJson(Map<String, dynamic> j) {
    final list = j["departments"] as List<dynamic>? ?? [];
    return VisitorDepartmentRequest(
      departments: list
          .map((e) => DepartmentItem.fromJson(e as Map<String, dynamic>))
          .toList(),
    );
  }

  final List<DepartmentItem> departments;
}

final class VisitorEmployeeTyping extends VisitorServerMessage {
  VisitorEmployeeTyping({required this.createdAt});

  factory VisitorEmployeeTyping.fromJson(Map<String, dynamic> j) {
    return VisitorEmployeeTyping(
      createdAt: tryParseServerDate(j["createdAt"]) ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }

  final DateTime createdAt;
}
