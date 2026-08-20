import "package:flutter/gestures.dart";
import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:livetex_chat_ui/src/widgets/message_html.dart";

const style = TextStyle(fontSize: 16, color: Colors.black);
const linkColor = Color(0xFF3E7AD7);

/// Flattens the span tree into (text, style, hasRecognizer) leaves.
List<(String, TextStyle?, bool)> leaves(TextSpan root) {
  final out = <(String, TextStyle?, bool)>[];
  void walk(InlineSpan s) {
    if (s is TextSpan) {
      if (s.text != null && s.text!.isNotEmpty) {
        out.add((s.text!, s.style, s.recognizer != null));
      }
      s.children?.forEach(walk);
    }
  }

  walk(root);
  return out;
}

void main() {
  group("containsHtml", () {
    test("true for a real tag", () {
      expect(containsHtml("<b>bold</b>"), isTrue);
    });

    test("false for a lone angle bracket comparison", () {
      expect(containsHtml("a < b"), isFalse);
    });

    test("false for plain text", () {
      expect(containsHtml("без тегов"), isFalse);
    });
  });

  group("tag mapping", () {
    test("bold tag maps to FontWeight.bold", () {
      final span = buildMessageSpan(
        "<b>жирный</b> текст",
        style: style,
        linkColor: linkColor,
      );
      final l = leaves(span);
      expect(l[0].$1, "жирный");
      expect(l[0].$2?.fontWeight, FontWeight.bold);
      expect(l[1].$1, " текст");
      expect(span.toPlainText(), "жирный текст");
    });

    test("strong tag maps to FontWeight.bold", () {
      final span = buildMessageSpan(
        "<strong>важно</strong>",
        style: style,
        linkColor: linkColor,
      );
      expect(leaves(span)[0].$2?.fontWeight, FontWeight.bold);
    });

    test("i and em tags map to FontStyle.italic", () {
      final spanI = buildMessageSpan(
        "<i>курсив</i>",
        style: style,
        linkColor: linkColor,
      );
      final spanEm = buildMessageSpan(
        "<em>курсив</em>",
        style: style,
        linkColor: linkColor,
      );
      expect(leaves(spanI)[0].$2?.fontStyle, FontStyle.italic);
      expect(leaves(spanEm)[0].$2?.fontStyle, FontStyle.italic);
    });

    test("u tag maps to TextDecoration.underline", () {
      final span = buildMessageSpan(
        "<u>подчёркнуто</u>",
        style: style,
        linkColor: linkColor,
      );
      expect(leaves(span)[0].$2?.decoration, TextDecoration.underline);
    });

    test("s, strike, del map to TextDecoration.lineThrough", () {
      for (final tag in ["s", "strike", "del"]) {
        final span = buildMessageSpan(
          "<$tag>зачёркнуто</$tag>",
          style: style,
          linkColor: linkColor,
        );
        expect(
          leaves(span)[0].$2?.decoration,
          TextDecoration.lineThrough,
          reason: "tag <$tag>",
        );
      }
    });

    test("nested tags combine decorations", () {
      final span = buildMessageSpan(
        "<b><i>жирный курсив</i></b>",
        style: style,
        linkColor: linkColor,
      );
      final l = leaves(span)[0];
      expect(l.$1, "жирный курсив");
      expect(l.$2?.fontWeight, FontWeight.bold);
      expect(l.$2?.fontStyle, FontStyle.italic);
    });

    test("underline and strikethrough combine via TextDecoration.combine", () {
      final span = buildMessageSpan(
        "<u><s>текст</s></u>",
        style: style,
        linkColor: linkColor,
      );
      final decoration = leaves(span)[0].$2?.decoration;
      expect(decoration?.contains(TextDecoration.underline), isTrue);
      expect(decoration?.contains(TextDecoration.lineThrough), isTrue);
    });

    test("br and br/ become newlines", () {
      final span1 = buildMessageSpan(
        "первая<br>вторая",
        style: style,
        linkColor: linkColor,
      );
      final span2 = buildMessageSpan(
        "первая<br/>вторая",
        style: style,
        linkColor: linkColor,
      );
      expect(span1.toPlainText(), "первая\nвторая");
      expect(span2.toPlainText(), "первая\nвторая");
    });

    test("p separates paragraphs with a blank line, no leading/trailing", () {
      final span = buildMessageSpan(
        "<p>Первый</p><p>Второй</p>",
        style: style,
        linkColor: linkColor,
      );
      expect(span.toPlainText(), "Первый\n\nВторой");
    });

    test("p before/after plain text also breaks paragraphs", () {
      final span = buildMessageSpan(
        "intro<p>para</p>",
        style: style,
        linkColor: linkColor,
      );
      expect(span.toPlainText(), "intro\n\npara");
    });

    test("ul/li render each item on its own line prefixed with a bullet", () {
      final span = buildMessageSpan(
        "<ul><li>Один</li><li>Два</li></ul>",
        style: style,
        linkColor: linkColor,
      );
      expect(span.toPlainText(), "• Один\n• Два");
    });

    test("ol/li render each item on its own line prefixed with a bullet", () {
      final span = buildMessageSpan(
        "<ol><li>Раз</li><li>Два</li></ol>",
        style: style,
        linkColor: linkColor,
      );
      expect(span.toPlainText(), "• Раз\n• Два");
    });

    test("valid link gets recognizer that reports the url", () {
      String? opened;
      final recs = <GestureRecognizer>[];
      final span = buildMessageSpan(
        '<a href="https://livetex.ru">сайт</a>',
        style: style,
        linkColor: linkColor,
        onOpenLink: (u) => opened = u,
        recognizers: recs,
      );
      final link = leaves(span).singleWhere((l) => l.$3);
      expect(link.$1, "сайт");
      expect(link.$2?.decoration, TextDecoration.underline);
      expect(link.$2?.color, linkColor);
      expect(recs, hasLength(1));
      (recs.single as TapGestureRecognizer).onTap!();
      expect(opened, "https://livetex.ru");
    });

    test("tel: link is allowed", () {
      final span = buildMessageSpan(
        '<a href="tel:+79991234567">Позвонить</a>',
        style: style,
        linkColor: linkColor,
        onOpenLink: (_) {},
        recognizers: <GestureRecognizer>[],
      );
      expect(leaves(span).any((l) => l.$3), isTrue);
    });

    test("mailto: link is allowed", () {
      final span = buildMessageSpan(
        '<a href="mailto:test@example.com">Написать</a>',
        style: style,
        linkColor: linkColor,
        onOpenLink: (_) {},
        recognizers: <GestureRecognizer>[],
      );
      expect(leaves(span).any((l) => l.$3), isTrue);
    });

    test("javascript href renders as plain text without recognizer", () {
      String? opened;
      final span = buildMessageSpan(
        '<a href="javascript:alert(1)">кликни</a>',
        style: style,
        linkColor: linkColor,
        onOpenLink: (u) => opened = u,
      );
      expect(span.toPlainText(), "кликни");
      expect(leaves(span).any((l) => l.$3), isFalse);
      expect(opened, isNull);
    });

    test("anchor without href renders as plain text", () {
      final span = buildMessageSpan(
        "<a>просто текст</a>",
        style: style,
        linkColor: linkColor,
        onOpenLink: (_) {},
      );
      expect(span.toPlainText(), "просто текст");
      expect(leaves(span).any((l) => l.$3), isFalse);
    });

    test("onOpenLink null keeps link styling but no recognizer", () {
      final span = buildMessageSpan(
        '<a href="https://livetex.ru">сайт</a>',
        style: style,
        linkColor: linkColor,
      );
      final l = leaves(span)[0];
      expect(l.$2?.decoration, TextDecoration.underline);
      expect(l.$2?.color, linkColor);
      expect(l.$3, isFalse);
    });

    test("unknown tags are dropped, inner text kept", () {
      final span = buildMessageSpan(
        '<div><span><font color="red">текст</font></span></div>',
        style: style,
        linkColor: linkColor,
      );
      expect(span.toPlainText(), "текст");
      final l = leaves(span)[0];
      expect(l.$2?.fontWeight, isNot(FontWeight.bold));
    });

    test("img with no inner text renders nothing", () {
      final span = buildMessageSpan(
        '<img src="x.png"/>',
        style: style,
        linkColor: linkColor,
      );
      expect(span.toPlainText(), "");
    });

    test("script tag and its content are dropped entirely", () {
      final span = buildMessageSpan(
        'до<script>alert("x")</script>после',
        style: style,
        linkColor: linkColor,
      );
      expect(span.toPlainText(), "допосле");
    });

    test("style tag and its content are dropped entirely", () {
      final span = buildMessageSpan(
        "до<style>b{color:red}</style>после",
        style: style,
        linkColor: linkColor,
      );
      expect(span.toPlainText(), "допосле");
    });

    test("named entities decoded in text nodes", () {
      final span = buildMessageSpan(
        "<b>&lt;tag&gt; &amp; &quot;quote&quot; &#39;apos&apos;&nbsp;end</b>",
        style: style,
        linkColor: linkColor,
      );
      expect(span.toPlainText(), "<tag> & \"quote\" 'apos' end");
    });

    test("numeric entities decoded, decimal and hex", () {
      final span = buildMessageSpan(
        "<b>&#169; &#x41;</b>",
        style: style,
        linkColor: linkColor,
      );
      expect(span.toPlainText(), "© A");
    });

    test("bare ampersand stays literal", () {
      final span = buildMessageSpan(
        "<b>AT&T</b>",
        style: style,
        linkColor: linkColor,
      );
      expect(span.toPlainText(), "AT&T");
    });

    test("real href wins over a data-href decoy attribute", () {
      String? opened;
      final recs = <GestureRecognizer>[];
      final span = buildMessageSpan(
        '<a data-href="https://evil.ru" href="https://good.ru">ссылка</a>',
        style: style,
        linkColor: linkColor,
        onOpenLink: (u) => opened = u,
        recognizers: recs,
      );
      final link = leaves(span).singleWhere((l) => l.$3);
      expect(link.$1, "ссылка");
      (recs.single as TapGestureRecognizer).onTap!();
      expect(opened, "https://good.ru");
    });

    test("href not preceded by whitespace is not picked up (e.g. xhref)", () {
      final span = buildMessageSpan(
        '<a xhref="https://evil.ru">ссылка</a>',
        style: style,
        linkColor: linkColor,
        onOpenLink: (_) {},
        recognizers: <GestureRecognizer>[],
      );
      expect(leaves(span).any((l) => l.$3), isFalse);
    });

    test("out-of-range numeric entity does not throw, stays literal", () {
      expect(
        () => buildMessageSpan(
          "<b>&#1114112; &#x110000;</b>",
          style: style,
          linkColor: linkColor,
        ),
        returnsNormally,
      );
      final span = buildMessageSpan(
        "<b>&#1114112; &#x110000;</b>",
        style: style,
        linkColor: linkColor,
      );
      expect(span.toPlainText(), "&#1114112; &#x110000;");
    });

    test("entities decoded inside href attribute value", () {
      String? opened;
      final recs = <GestureRecognizer>[];
      final span = buildMessageSpan(
        '<a href="https://x.ru/?a=1&amp;b=2">ссылка</a>',
        style: style,
        linkColor: linkColor,
        onOpenLink: (u) => opened = u,
        recognizers: recs,
      );
      expect(span.toPlainText(), "ссылка");
      (recs.single as TapGestureRecognizer).onTap!();
      expect(opened, "https://x.ru/?a=1&b=2");
    });
  });

  group("robustness", () {
    test("unclosed tag styles to end of input without crashing", () {
      final span = buildMessageSpan(
        "<b>bold to the end",
        style: style,
        linkColor: linkColor,
      );
      expect(span.toPlainText(), "bold to the end");
      expect(leaves(span)[0].$2?.fontWeight, FontWeight.bold);
    });

    test("stray closing tag is ignored", () {
      final span = buildMessageSpan(
        "text</b>more",
        style: style,
        linkColor: linkColor,
      );
      expect(span.toPlainText(), "textmore");
    });

    test("nesting deeper than 32 ignores deeper styles but keeps text", () {
      // 32 <b> reach the cap; the 33rd style tag (<i>) must NOT apply — if
      // the cap were deleted, the innermost leaf would also be italic.
      final open = "<b>" * 32;
      final close = "</b>" * 32;
      final span = buildMessageSpan(
        "$open<i>глубоко</i>$close",
        style: style,
        linkColor: linkColor,
      );
      final innermost = leaves(span).singleWhere((l) => l.$1 == "глубоко");
      expect(innermost.$2?.fontWeight, FontWeight.bold);
      expect(innermost.$2?.fontStyle, isNot(FontStyle.italic));
    });

    test("oversized input returned as single plain span", () {
      final big = "<b>${"а" * 40000}</b>";
      final span = buildMessageSpan(big, style: style, linkColor: linkColor);
      expect(span.toPlainText(), big);
      expect(leaves(span).any((l) => l.$3), isFalse);
    });

    test("containsHtml false skips tag parsing, linkify still runs", () {
      String? opened;
      final span = buildMessageSpan(
        "a < b смотри www.livetex.ru",
        style: style,
        linkColor: linkColor,
        onOpenLink: (u) => opened = u,
        recognizers: <GestureRecognizer>[],
      );
      expect(span.toPlainText(), "a < b смотри www.livetex.ru");
      final link = leaves(span).singleWhere((l) => l.$3);
      expect(link.$1, "www.livetex.ru");
      (span.children!
              .whereType<TextSpan>()
              .firstWhere((s) => s.recognizer != null)
              .recognizer!
          as TapGestureRecognizer)
          .onTap!();
      expect(opened, "https://www.livetex.ru");
    });

    test("many unmatched '<' bails to a single plain span, fast", () {
      final input = "<" * 32760;
      final stopwatch = Stopwatch()..start();
      final span = buildMessageSpan(input, style: style, linkColor: linkColor);
      stopwatch.stop();
      expect(span.toPlainText(), input);
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
    });

    test("many unmatched '<' in plainTextOfMessage bails fast too", () {
      final input = "<" * 32760;
      final stopwatch = Stopwatch()..start();
      final result = plainTextOfMessage(input);
      stopwatch.stop();
      expect(result, input);
      expect(stopwatch.elapsedMilliseconds, lessThan(1000));
    });

    test("recognizer is not created when recognizers list is omitted", () {
      final span = buildMessageSpan(
        '<a href="https://livetex.ru">сайт</a>',
        style: style,
        linkColor: linkColor,
        onOpenLink: (_) {},
      );
      final l = leaves(span)[0];
      expect(l.$2?.decoration, TextDecoration.underline);
      expect(l.$3, isFalse);
    });
  });

  group("linkify", () {
    test("bare https url becomes a link", () {
      String? opened;
      final span = buildMessageSpan(
        "смотри https://livetex.ru тут",
        style: style,
        linkColor: linkColor,
        onOpenLink: (u) => opened = u,
        recognizers: <GestureRecognizer>[],
      );
      final link = leaves(span).singleWhere((l) => l.$3);
      expect(link.$1, "https://livetex.ru");
      final rec = span.children!
          .whereType<TextSpan>()
          .firstWhere((s) => s.recognizer != null)
          .recognizer! as TapGestureRecognizer;
      rec.onTap!();
      expect(opened, "https://livetex.ru");
    });

    test("linkify bare www url", () {
      final span = buildMessageSpan(
        "смотри www.livetex.ru тут",
        style: style,
        linkColor: linkColor,
        onOpenLink: (_) {},
        recognizers: <GestureRecognizer>[],
      );
      final link = leaves(span).singleWhere((l) => l.$3);
      expect(link.$1, "www.livetex.ru");
    });

    test("bare email becomes mailto link", () {
      String? opened;
      final span = buildMessageSpan(
        "пишите test@example.com пожалуйста",
        style: style,
        linkColor: linkColor,
        onOpenLink: (u) => opened = u,
        recognizers: <GestureRecognizer>[],
      );
      final link = leaves(span).singleWhere((l) => l.$3);
      expect(link.$1, "test@example.com");
      final rec = span.children!
          .whereType<TextSpan>()
          .firstWhere((s) => s.recognizer != null)
          .recognizer! as TapGestureRecognizer;
      rec.onTap!();
      expect(opened, "mailto:test@example.com");
    });

    test("trailing punctuation is not part of the linkified url", () {
      final span = buildMessageSpan(
        "смотри https://livetex.ru, у нас скидки",
        style: style,
        linkColor: linkColor,
        onOpenLink: (_) {},
        recognizers: <GestureRecognizer>[],
      );
      final link = leaves(span).singleWhere((l) => l.$3);
      expect(link.$1, "https://livetex.ru");
      expect(span.toPlainText(), "смотри https://livetex.ru, у нас скидки");
    });

    test("linkify runs inside HTML plain text segments too", () {
      final span = buildMessageSpan(
        "<b>жирный</b> смотри https://livetex.ru",
        style: style,
        linkColor: linkColor,
        onOpenLink: (_) {},
        recognizers: <GestureRecognizer>[],
      );
      final link = leaves(span).singleWhere((l) => l.$3);
      expect(link.$1, "https://livetex.ru");
    });
  });

  group("scheme allowlist", () {
    test("http, https, mailto, tel are allowed case-insensitively", () {
      for (final href in [
        "HTTP://livetex.ru",
        "HTTPS://livetex.ru",
        "MAILTO:test@example.com",
        "TEL:+79991234567",
      ]) {
        final span = buildMessageSpan(
          '<a href="$href">ссылка</a>',
          style: style,
          linkColor: linkColor,
          onOpenLink: (_) {},
          recognizers: <GestureRecognizer>[],
        );
        expect(
          leaves(span).any((l) => l.$3),
          isTrue,
          reason: "scheme in $href",
        );
      }
    });

    test("disallowed schemes render as plain text", () {
      for (final href in [
        "ftp://livetex.ru",
        "file:///etc/passwd",
        "data:text/html,x",
        "intent://x",
      ]) {
        final span = buildMessageSpan(
          '<a href="$href">ссылка</a>',
          style: style,
          linkColor: linkColor,
          onOpenLink: (_) {},
        );
        expect(
          leaves(span).any((l) => l.$3),
          isFalse,
          reason: "scheme in $href",
        );
      }
    });
  });

  group("plainTextOfMessage", () {
    test("strips tags and decodes entities, br becomes newline", () {
      expect(plainTextOfMessage("<b>а</b> &amp; б<br>в"), "а & б\nв");
    });

    test("non-HTML input returned unchanged", () {
      expect(plainTextOfMessage("без тегов"), "без тегов");
      expect(plainTextOfMessage("a < b"), "a < b");
    });

    test("p becomes a paragraph break", () {
      expect(plainTextOfMessage("<p>Первый</p><p>Второй</p>"),
          "Первый\n\nВторой");
    });

    test("li becomes a bulleted line", () {
      expect(plainTextOfMessage("<ul><li>Один</li><li>Два</li></ul>"),
          "• Один\n• Два");
    });
  });
}
