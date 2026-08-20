import "package:flutter/material.dart";
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
}
