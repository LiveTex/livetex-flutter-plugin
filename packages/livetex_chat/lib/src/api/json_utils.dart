/// Best-effort parse of server JSON timestamps (Joda-style offset without colon).
DateTime? tryParseServerDate(Object? value) {
  if (value is! String || value.isEmpty) return null;
  final s = value;
  final normalized =
      s.contains("T") && !s.endsWith("Z") && RegExp(r"[+-]\d{4}$").hasMatch(s)
          ? "${s.substring(0, s.length - 2)}:${s.substring(s.length - 2)}"
          : s;
  return DateTime.tryParse(normalized);
}
