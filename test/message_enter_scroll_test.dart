import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/chat/anchored_scroll.dart';
import 'package:snippet/chat/message_enter.dart';

void main() {
  testWidgets('MessageEnter expands smoothly over 180ms and settles cleanly',
      (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: MessageEnter(
            animate: true,
            child: SizedBox(width: 200, height: 60),
          ),
        ),
      ),
    );
    final startH = tester.getSize(find.byType(MessageEnter)).height;
    expect(startH, lessThan(10));

    await tester.pump(const Duration(milliseconds: 90));
    final midH = tester.getSize(find.byType(MessageEnter)).height;
    expect(midH, greaterThan(startH));
    expect(midH, lessThan(60));

    await tester.pump(const Duration(milliseconds: 120));
    expect(tester.getSize(find.byType(MessageEnter)).height, closeTo(60, 0.5));
  });

  testWidgets('MessageEnter respects reduced motion immediately',
      (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);

    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Align(
          alignment: Alignment.topLeft,
          child: MessageEnter(
            animate: true,
            child: SizedBox(width: 200, height: 60),
          ),
        ),
      ),
    );
    expect(tester.getSize(find.byType(MessageEnter)).height, closeTo(60, 0.5));
  });

  testWidgets(
      'ChatBottomTracker unpins on desktop mouse wheel up and animates back smoothly',
      (tester) async {
    final scroll = AnchoredScrollController();
    final tracker = ChatBottomTracker();
    addTearDown(scroll.dispose);

    late BuildContext ctx;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: SizedBox(
            height: 300,
            child: Builder(builder: (c) {
              ctx = c;
              return NotificationListener<ScrollNotification>(
                onNotification: (n) {
                  tracker.handleScroll(n, scroll);
                  return false;
                },
                child: ListView.builder(
                  controller: scroll,
                  reverse: true,
                  itemCount: 30,
                  itemBuilder: (_, i) => SizedBox(
                    height: 50,
                    child: Text('Row $i'),
                  ),
                ),
              );
            }),
          ),
        ),
      ),
    );

    expect(tracker.stickToBottom, isTrue);

    // Mouse wheel scroll up (in a reversed list, scrolling up increases offset).
    final center = tester.getCenter(find.byType(ListView));
    final pointer = TestPointer(1, PointerDeviceKind.mouse);
    await tester.sendEventToBinding(pointer.hover(center));
    await tester.sendEventToBinding(pointer.scroll(const Offset(0, -180)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(scroll.offset, greaterThan(80));
    expect(tracker.stickToBottom, isFalse);

    // Smooth scroll back to bottom animates over ~200ms rather than jumping in 1 frame.
    tracker.stickToBottom = true;
    tracker.scrollToBottom(scroll, ctx, animated: true);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    expect(scroll.offset, greaterThan(0));
    expect(scroll.offset, lessThan(180));
    await tester.pump(const Duration(milliseconds: 200));
    expect(scroll.offset, closeTo(0, 0.5));
  });
}
