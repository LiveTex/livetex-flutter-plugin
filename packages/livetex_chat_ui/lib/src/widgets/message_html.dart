import "package:flutter/gestures.dart";
import "package:flutter/material.dart";

// ponytail: caps guard against pathological/malicious input (huge or deeply
// nested HTML) blowing up parse time or the span tree; 32768 chars and 32
// style levels comfortably cover any real bot/operator message.
const _maxInputLength = 32768;
const _maxStyleDepth = 32;

final _htmlTagPattern = RegExp(r'''<("[^"]*"|'[^']*'|[^'">])*>''');

/// True when [text] contains something that looks like an HTML tag.
/// Same regex as native Android TextUtils.containsHtml:
/// <("[^"]*"|'[^']*'|[^'">])*>
bool containsHtml(String text) => _htmlTagPattern.hasMatch(text);

const _allowedSchemes = {"http", "https", "mailto", "tel"};

bool _isAllowedUrl(String? url) {
  if (url == null || url.isEmpty) return false;
  final uri = Uri.tryParse(url);
  if (uri == null) return false;
  return _allowedSchemes.contains(uri.scheme.toLowerCase());
}

const _namedEntities = {
  "amp": "&",
  "lt": "<",
  "gt": ">",
  "quot": '"',
  "apos": "'",
  "nbsp": " ",
};

final _entityPattern = RegExp(r"&(#x[0-9a-fA-F]+|#[0-9]+|[a-zA-Z]+);");

String _decodeEntities(String text) {
  return text.replaceAllMapped(_entityPattern, (m) {
    final body = m[1]!;
    if (body.startsWith("#x") || body.startsWith("#X")) {
      final code = int.tryParse(body.substring(2), radix: 16);
      return code == null ? m[0]! : String.fromCharCode(code);
    }
    if (body.startsWith("#")) {
      final code = int.tryParse(body.substring(1));
      return code == null ? m[0]! : String.fromCharCode(code);
    }
    return _namedEntities[body] ?? m[0]!;
  });
}

const _boldTags = {"b", "strong"};
const _italicTags = {"i", "em"};
const _underlineTags = {"u"};
const _strikeTags = {"s", "strike", "del"};
const _skipContentTags = {"script", "style"};
const _brTags = {"br"};

typedef _Tag = ({String name, bool closing, String? href});

final _tagNameEnd = RegExp(r"\s");
final _hrefPattern = RegExp(
  '''href\\s*=\\s*("([^"]*)"|'([^']*)'|(\\S+))''',
  caseSensitive: false,
);

/// Parses a single already-isolated tag token (e.g. `<a href="x">`,
/// `</b>`, `<br/>`). The outer `<...>` boundaries were already found via
/// [_htmlTagPattern] (that's the "no regex for structure" part); pulling
/// the `href` value out of that small, pre-bounded slice is a plain
/// attribute lookup, not HTML structure parsing.
_Tag _parseTagToken(String token) {
  var body = token.substring(1, token.length - 1).trim();
  final closing = body.startsWith("/");
  if (closing) body = body.substring(1);
  if (body.endsWith("/")) body = body.substring(0, body.length - 1).trimRight();
  final nameEnd = body.indexOf(_tagNameEnd);
  final name = (nameEnd == -1 ? body : body.substring(0, nameEnd)).toLowerCase();
  final hrefMatch = _hrefPattern.firstMatch(body);
  final href = hrefMatch == null
      ? null
      : _decodeEntities(hrefMatch[2] ?? hrefMatch[3] ?? hrefMatch[4] ?? "");
  return (name: name, closing: closing, href: href);
}

/// Finds the position right after the closing tag matching [tagName],
/// searching from [from]. Used to drop `<script>`/`<style>` and all of
/// their raw content in one jump. Falls back to end-of-input when no
/// closing tag is found (unclosed script — no crash, rest is dropped).
int _findClosingIndex(String source, String tagName, int from) {
  final closeToken = "</$tagName".toLowerCase();
  var i = from;
  while (i < source.length) {
    final lt = source.indexOf("<", i);
    if (lt == -1) return source.length;
    final m = _htmlTagPattern.matchAsPrefix(source, lt);
    if (m != null) {
      if (m[0]!.toLowerCase().startsWith(closeToken)) return m.end;
      i = m.end;
    } else {
      i = lt + 1;
    }
  }
  return source.length;
}

typedef _Frame = ({
  String name,
  bool styled,
  bool bold,
  bool italic,
  bool underline,
  bool strike,
  String? linkUrl,
});

_Frame _plainFrame(String name) => (
      name: name,
      styled: false,
      bold: false,
      italic: false,
      underline: false,
      strike: false,
      linkUrl: null,
    );

/// One text run produced by the tokenizer, with the character styles and
/// (if inside a valid `<a href>`) the resolved link URL active at that
/// point. Breaks (`\n`, `\n\n`) and list bullets (`• `) are plain runs.
typedef _Run = ({
  String text,
  bool bold,
  bool italic,
  bool underline,
  bool strike,
  String? linkUrl,
});

_Run _plainRun(String text) => (
      text: text,
      bold: false,
      italic: false,
      underline: false,
      strike: false,
      linkUrl: null,
    );

/// Single-pass tokenizer: walks [source] once, tracking a stack of open
/// tags. Structure (tag boundaries, nesting) is never parsed with regex —
/// only [_htmlTagPattern] is reused to recognize where a tag token starts,
/// exactly like [containsHtml] does.
List<_Run> _walkNodes(String source) {
  final runs = <_Run>[];
  final stack = <_Frame>[];
  var styleDepth = 0;
  var pendingBreak = "";
  var i = 0;

  void flushPending() {
    if (pendingBreak.isNotEmpty) {
      runs.add(_plainRun(pendingBreak));
      pendingBreak = "";
    }
  }

  void emitText(String raw) {
    if (raw.isEmpty) return;
    flushPending();
    var bold = false, italic = false, underline = false, strike = false;
    String? linkUrl;
    for (final f in stack) {
      if (!f.styled) continue;
      bold = bold || f.bold;
      italic = italic || f.italic;
      underline = underline || f.underline;
      strike = strike || f.strike;
      linkUrl = f.linkUrl ?? linkUrl;
    }
    runs.add((
      text: raw,
      bold: bold,
      italic: italic,
      underline: underline,
      strike: strike,
      linkUrl: linkUrl,
    ));
  }

  while (i < source.length) {
    final start = i;
    while (i < source.length) {
      if (source[i] == "<" && _htmlTagPattern.matchAsPrefix(source, i) != null) {
        break;
      }
      i++;
    }
    if (i > start) emitText(_decodeEntities(source.substring(start, i)));
    if (i >= source.length) break;

    final m = _htmlTagPattern.matchAsPrefix(source, i)!;
    final tag = _parseTagToken(m[0]!);
    i = m.end;

    if (_skipContentTags.contains(tag.name)) {
      if (!tag.closing) i = _findClosingIndex(source, tag.name, i);
      continue;
    }
    if (tag.closing) {
      final idx = stack.lastIndexWhere((f) => f.name == tag.name);
      if (idx != -1) {
        final removed = stack.sublist(idx);
        stack.removeRange(idx, stack.length);
        styleDepth -= removed.where((f) => f.styled).length;
      }
      continue;
    }
    if (_brTags.contains(tag.name)) {
      flushPending();
      runs.add(_plainRun("\n"));
      continue;
    }
    if (tag.name == "p") {
      if (runs.isNotEmpty) pendingBreak = "\n\n";
      stack.add(_plainFrame(tag.name));
      continue;
    }
    if (tag.name == "li") {
      if (runs.isNotEmpty) pendingBreak = "\n";
      flushPending();
      runs.add(_plainRun("• "));
      stack.add(_plainFrame(tag.name));
      continue;
    }

    final canStyle = styleDepth < _maxStyleDepth;
    var bold = false, italic = false, underline = false, strike = false;
    String? linkUrl;
    if (canStyle) {
      if (_boldTags.contains(tag.name)) bold = true;
      if (_italicTags.contains(tag.name)) italic = true;
      if (_underlineTags.contains(tag.name)) underline = true;
      if (_strikeTags.contains(tag.name)) strike = true;
      if (tag.name == "a" && _isAllowedUrl(tag.href)) {
        linkUrl = tag.href;
        underline = true;
      }
    }
    final styled = bold || italic || underline || strike || linkUrl != null;
    if (styled) styleDepth++;
    stack.add((
      name: tag.name,
      styled: styled,
      bold: bold,
      italic: italic,
      underline: underline,
      strike: strike,
      linkUrl: linkUrl,
    ));
  }
  return runs;
}

final _linkPattern = RegExp(
  r'(https?://[^\s<>"]+)|(www\.[^\s<>"]+)|([A-Za-z0-9._%+-]+@[A-Za-z0-9-]+\.[A-Za-z]{2,})',
  caseSensitive: false,
);
const _trailingPunct = {".", ",", ";", ":", "!", "?", ")"};

/// Splits [text] on bare URLs/www-links/emails and appends plain +
/// linked leaves to [leaves]. Runs over plain-text segments only — never
/// over text already inside a matched `<a>`.
void _emitLinkified(
  String text,
  TextStyle style,
  Color linkColor,
  void Function(String url)? onOpenLink,
  List<GestureRecognizer>? recognizers,
  List<TextSpan> leaves,
) {
  var last = 0;
  for (final m in _linkPattern.allMatches(text)) {
    var raw = m[0]!;
    var end = m.end;
    while (raw.isNotEmpty && _trailingPunct.contains(raw[raw.length - 1])) {
      raw = raw.substring(0, raw.length - 1);
      end--;
    }
    if (raw.isEmpty) continue;
    if (m.start > last) {
      leaves.add(TextSpan(text: text.substring(last, m.start), style: style));
    }
    String? url;
    final lower = raw.toLowerCase();
    if (lower.startsWith("http://") || lower.startsWith("https://")) {
      url = raw;
    } else if (lower.startsWith("www.")) {
      url = "https://$raw";
    } else if (raw.contains("@")) {
      url = "mailto:$raw";
    }
    if (url != null && _isAllowedUrl(url)) {
      final linkStyle = style.merge(
        TextStyle(decoration: TextDecoration.underline, color: linkColor),
      );
      GestureRecognizer? rec;
      if (onOpenLink != null) {
        final resolved = url;
        rec = TapGestureRecognizer()..onTap = () => onOpenLink(resolved);
        recognizers?.add(rec);
      }
      leaves.add(TextSpan(text: raw, style: linkStyle, recognizer: rec));
    } else {
      leaves.add(TextSpan(text: raw, style: style));
    }
    last = end;
  }
  if (last < text.length) {
    leaves.add(TextSpan(text: text.substring(last), style: style));
  }
}

TextDecoration? _combineDecoration(bool underline, bool strike) {
  if (underline && strike) {
    return TextDecoration.combine(
      [TextDecoration.underline, TextDecoration.lineThrough],
    );
  }
  if (underline) return TextDecoration.underline;
  if (strike) return TextDecoration.lineThrough;
  return null;
}

/// Parses the Android-parity HTML subset (plus linkify of bare URLs and
/// emails in plain segments) into a TextSpan tree.
/// [onOpenLink] receives the validated absolute URL on tap. When null,
/// links still get link styling but no recognizer (used by tests and
/// contexts without tap handling).
/// Returned span's recognizers must be disposed by the caller —
/// collect them via [recognizers].
TextSpan buildMessageSpan(
  String source, {
  required TextStyle style,
  required Color linkColor,
  void Function(String url)? onOpenLink,
  List<GestureRecognizer>? recognizers,
}) {
  if (source.length > _maxInputLength) {
    return TextSpan(text: source, style: style);
  }
  final leaves = <TextSpan>[];
  if (!containsHtml(source)) {
    _emitLinkified(source, style, linkColor, onOpenLink, recognizers, leaves);
    return TextSpan(children: leaves);
  }
  for (final run in _walkNodes(source)) {
    final runStyle = style.merge(TextStyle(
      fontWeight: run.bold ? FontWeight.bold : null,
      fontStyle: run.italic ? FontStyle.italic : null,
      decoration: _combineDecoration(run.underline, run.strike),
    ));
    if (run.linkUrl != null) {
      final linkStyle = runStyle.merge(
        TextStyle(decoration: TextDecoration.underline, color: linkColor),
      );
      GestureRecognizer? rec;
      if (onOpenLink != null) {
        final url = run.linkUrl!;
        rec = TapGestureRecognizer()..onTap = () => onOpenLink(url);
        recognizers?.add(rec);
      }
      leaves.add(TextSpan(text: run.text, style: linkStyle, recognizer: rec));
    } else {
      _emitLinkified(
        run.text,
        runStyle,
        linkColor,
        onOpenLink,
        recognizers,
        leaves,
      );
    }
  }
  return TextSpan(children: leaves);
}

/// Plain text of a message for copy/quote: tags stripped, entities
/// decoded, <br>/<p>/<li> become newlines. For non-HTML input returns
/// the input unchanged.
String plainTextOfMessage(String source) {
  if (!containsHtml(source)) return source;
  if (source.length > _maxInputLength) return source;
  final buffer = StringBuffer();
  for (final run in _walkNodes(source)) {
    buffer.write(run.text);
  }
  return buffer.toString();
}
