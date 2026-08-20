import "package:flutter/material.dart";
import "package:flutter/services.dart";
import "package:flutter_test/flutter_test.dart";
import "package:livetex_chat/livetex_chat.dart";
import "package:livetex_chat_ui/livetex_chat_ui.dart";
// url_launcher_platform_interface is a transitive dependency of url_launcher
// (already resolved in pubspec.lock), used here only to mock the real launch
// seam for one widget test. Kept out of pubspec.yaml per the task's "no new
// dependencies" constraint — a plain `await launchUrl(...)` never resolves
// against an unregistered platform channel in the widget-test harness (it
// hangs indefinitely, confirmed empirically), so mocking the platform is the
// only reliable way to assert the real tap-to-launch path end to end.
// ignore: depend_on_referenced_packages
import "package:url_launcher_platform_interface/link.dart";
// ignore: depend_on_referenced_packages
import "package:url_launcher_platform_interface/url_launcher_platform_interface.dart";

ChatMessage msg(String text, {bool isVisitor = false, String? creatorType}) =>
    ChatMessage(
      id: "1",
      createdAt: DateTime(2026),
      isVisitor: isVisitor,
      text: text,
      creatorType: creatorType,
      sendState: ChatMessageSendState.sent,
    );

Widget host(Widget child) => MaterialApp(
      home: Scaffold(
        body: LivetexChatThemeScope(
          theme: LivetexChatTheme.livetex(),
          child: child,
        ),
      ),
    );

/// Records the last url handed to the platform, standing in for a spy on
/// the private launcher — `UrlLauncherPlatform.instance` is the real seam
/// `MessageTile` calls through (`launchUrl` from `package:url_launcher`),
/// so this exercises the production tap path instead of a test-only hook.
class _FakeUrlLauncher extends UrlLauncherPlatform {
  String? launchedUrl;

  @override
  LinkDelegate? get linkDelegate => null;

  @override
  Future<bool> launchUrl(String url, LaunchOptions options) async {
    launchedUrl = url;
    return true;
  }
}

/// Taps "Скопировать" in the already-open actions menu and returns what was
/// handed to `Clipboard.setData` — the copy path has no public getter, so
/// this intercepts the platform channel `Clipboard.setData` actually calls.
Future<String?> _tapCopyAndCaptureClipboard(WidgetTester tester) async {
  String? copied;
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    (call) async {
      if (call.method == "Clipboard.setData") {
        copied = (call.arguments as Map)["text"] as String?;
      }
      return null;
    },
  );
  await tester.tap(find.text("Скопировать"));
  await tester.pumpAndSettle();
  tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
    SystemChannels.platform,
    null,
  );
  return copied;
}

void main() {
  testWidgets("incoming html message renders without raw tags",
      (tester) async {
    await tester.pumpWidget(host(MessageTile(message: msg("<b>привет</b>"))));
    expect(find.textContaining("<b>"), findsNothing);
    expect(find.textContaining("привет"), findsOneWidget);
  });

  testWidgets("visitor message keeps raw text", (tester) async {
    await tester.pumpWidget(
        host(MessageTile(message: msg("<b>привет</b>", isVisitor: true))));
    expect(find.textContaining("<b>привет</b>"), findsOneWidget);
  });

  testWidgets("system html message renders without raw tags", (tester) async {
    await tester.pumpWidget(host(MessageTile(
        message:
            msg("<i>диалог завершён</i>", creatorType: "system"))));
    expect(find.textContaining("<i>"), findsNothing);
  });

  testWidgets("tap on link span reports url", (tester) async {
    final fake = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = fake;

    await tester.pumpWidget(host(MessageTile(
        message: msg('<a href="https://livetex.ru">ссылка</a>'))));
    await tester.tap(find.textContaining("ссылка"));
    await tester.pumpAndSettle();

    expect(fake.launchedUrl, "https://livetex.ru");
    // The recognizer handled the tap, not `SelectableText.onTap` — no
    // actions menu popped up alongside the link launch.
    expect(find.byType(BottomSheet), findsNothing);
  });

  testWidgets("tap on plain (non-link) incoming text opens the actions menu",
      (tester) async {
    await tester.pumpWidget(host(MessageTile(message: msg("привет"))));
    await tester.tap(find.text("привет"));
    await tester.pumpAndSettle();

    expect(find.byType(BottomSheet), findsOneWidget);
  });

  testWidgets("copy strips html tags for an incoming message", (tester) async {
    await tester
        .pumpWidget(host(MessageTile(message: msg("<b>жирный</b> текст"))));
    await tester.tap(find.textContaining("жирный"));
    await tester.pumpAndSettle();

    expect(await _tapCopyAndCaptureClipboard(tester), "жирный текст");
  });

  testWidgets(
      "copy keeps a visitor message verbatim even when it looks like html",
      (tester) async {
    // "5 < 6 > 3" trips the loose Android-parity containsHtml regex (it
    // matches any "<...>" span, not just real tags) — for a visitor's own
    // message this must NOT be run through plainTextOfMessage, or copy
    // would silently strip the "< 6 >" the visitor actually typed.
    await tester.pumpWidget(
        host(MessageTile(message: msg("5 < 6 > 3", isVisitor: true))));
    await tester.tap(find.text("5 < 6 > 3"));
    await tester.pumpAndSettle();

    expect(await _tapCopyAndCaptureClipboard(tester), "5 < 6 > 3");
  });

  testWidgets("system tile link tap still fires (Text.rich, non-selectable)",
      (tester) async {
    final fake = _FakeUrlLauncher();
    UrlLauncherPlatform.instance = fake;

    await tester.pumpWidget(host(MessageTile(
        message: msg('<a href="https://livetex.ru">ссылка</a>',
            creatorType: "system"))));
    await tester.tap(find.textContaining("ссылка"));
    await tester.pumpAndSettle();

    expect(fake.launchedUrl, "https://livetex.ru");
  });

  testWidgets(
      "quote-reply message: body renders parsed html, quote line renders plain",
      (tester) async {
    await tester.pumpWidget(host(MessageTile(
        message:
            msg("> quoted <b>tag</b> line\nbody with <b>html</b>"))));

    expect(find.textContaining("<b>"), findsNothing);
    expect(find.textContaining("quoted tag line"), findsOneWidget);
    expect(find.textContaining("body with html"), findsOneWidget);
  });
}
