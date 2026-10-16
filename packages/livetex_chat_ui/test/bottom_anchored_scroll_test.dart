import "package:flutter/material.dart";
import "package:flutter_test/flutter_test.dart";
import "package:livetex_chat_ui/src/bottom_anchored_scroll_controller.dart";

void main() {
  Future<void> pumpList(
    WidgetTester tester,
    ScrollController controller,
    double height,
  ) {
    return tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topCenter,
          child: SizedBox(
            height: height,
            child: ListView.builder(
              controller: controller,
              itemCount: 100,
              itemExtent: 50,
              itemBuilder: (_, i) => Text("item $i"),
            ),
          ),
        ),
      ),
    );
  }

  testWidgets("shrinking viewport keeps bottom edge content in place",
      (tester) async {
    final c = BottomAnchoredScrollController();
    await pumpList(tester, c, 600);
    c.jumpTo(1000);
    await tester.pump();

    await pumpList(tester, c, 300);
    expect(c.offset, 1300);

    await pumpList(tester, c, 600);
    expect(c.offset, 1000);
  });

  testWidgets("at bottom stays at bottom when viewport shrinks",
      (tester) async {
    final c = BottomAnchoredScrollController();
    await pumpList(tester, c, 600);
    c.jumpTo(c.position.maxScrollExtent);
    await tester.pump();

    await pumpList(tester, c, 300);
    expect(c.offset, c.position.maxScrollExtent);
  });

  testWidgets("near top clamps to zero when viewport grows", (tester) async {
    final c = BottomAnchoredScrollController();
    await pumpList(tester, c, 300);
    c.jumpTo(100);
    await tester.pump();

    await pumpList(tester, c, 600);
    expect(c.offset, 0);
  });
}
