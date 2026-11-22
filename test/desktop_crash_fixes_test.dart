import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/chat/anchored_scroll.dart';
import 'package:snippet/chat/ledger_line.dart';
import 'package:snippet/chat/message_enter.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/tool_activity.dart';
import 'package:snippet/widgets.dart';

void main() {
  testWidgets(
      'Pressable ignores pointer release after disposal without animateBack crash',
      (tester) async {
    var mounted = true;
    late StateSetter setOuter;

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: StatefulBuilder(
          builder: (_, setState) {
            setOuter = setState;
            if (!mounted) return const SizedBox.shrink();
            return Listener(
              onPointerDown: (_) => setState(() => mounted = false),
              child: Pressable(
                kind: PressKind.row,
                child: const SizedBox(width: 120, height: 48, child: Text('Go')),
              ),
            );
          },
        ),
      ),
    ));

    final g = await tester.startGesture(tester.getCenter(find.text('Go')));
    await tester.pump();
    expect(find.text('Go'), findsNothing);
    // Delivering up/cancel after disposal must never call animateBack on a disposed controller.
    await g.up();
    await tester.pump();
    expect(tester.takeException(), isNull);

    // Also verify disposing mid-press via external state change.
    setOuter(() => mounted = true);
    await tester.pump();
    final g2 = await tester.startGesture(tester.getCenter(find.text('Go')));
    await tester.pump();
    await g2.cancel();
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'LedgerStrip preserves OverlayPortalController when steps, clock, and fail banner appear or disappear',
      (tester) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    List<ToolStep> steps = const [];

    Widget build(List<ToolStep> current) => MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: LedgerLiveScope(
              agentId: 'snippet',
              onStop: () {},
              child: LedgerStrip(rows: const [], steps: current),
            ),
          ),
        );

    // 1. Mount empty (steps.isEmpty, elapsed == null, fail == null).
    await tester.pumpWidget(build(steps));
    await tester.pump();
    expect(tester.takeException(), isNull);

    // 2. First running step arrives: inserts _bar() and _clock() BEFORE the OverlayPortal in Row.
    steps = [
      ToolStep(
        tool: 'bash',
        args: const {'command': 'flutter test'},
        startMs: now - 2500,
      ),
    ];
    await tester.pumpWidget(build(steps));
    await tester.pump();
    expect(tester.takeException(), isNull);

    // 3. Open the peek OverlayPortal while running.
    await tester.tap(find.text('Peek'));
    await tester.pump();
    expect(tester.takeException(), isNull);

    // 4. A failed step arrives: inserts the failure banner BEFORE strip in Column.
    steps = [
      ToolStep(
        tool: 'bash',
        args: const {'command': 'false'},
        result: const {'exit_code': 1, 'stderr': 'boom'},
        startMs: now - 3000,
        endMs: now - 1500,
      ),
      ToolStep(
        tool: 'read',
        args: const {'path': 'lib/main.dart'},
        startMs: now - 1000,
      ),
    ];
    await tester.pumpWidget(build(steps));
    await tester.pump();
    expect(tester.takeException(), isNull);

    // 5. Dismissing the failure banner removes widgets BEFORE strip in Column.
    await tester.tap(find.byTooltip('Dismiss'));
    await tester.pump();
    expect(tester.takeException(), isNull);

    // 6. Returning to empty steps removes _bar() and _clock() BEFORE OverlayPortal in Row.
    await tester.pumpWidget(build(const []));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets(
      'ChatBottomTracker and AnchoredScrollController tolerate multi-position attach and ignore nested scrollables',
      (tester) async {
    final scroll = AnchoredScrollController();
    addTearDown(scroll.dispose);
    final tracker = ChatBottomTracker();

    // Attach the same controller to two scroll views to verify no multi-attach crash.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Row(children: [
          Expanded(
            child: NotificationListener<ScrollNotification>(
              onNotification: (n) {
                tracker.handleScroll(n, scroll);
                return false;
              },
              child: ListView(
                controller: scroll,
                reverse: true,
                children: const [SizedBox(height: 800)],
              ),
            ),
          ),
          Expanded(
            child: ListView(
              controller: scroll,
              reverse: true,
              children: const [SizedBox(height: 800)],
            ),
          ),
        ]),
      ),
    ));
    await tester.pump();

    expect(scroll.positions.length, 2);
    expect(tracker.atBottom(scroll), isTrue);
    final ctx = tester.element(find.byType(Scaffold));
    tracker.scrollToBottom(scroll, ctx);
    tracker.rowResized(scroll, 40, 200);
    scroll.correctBy(40);
    expect(tester.takeException(), isNull);

    // Detach back to a single scroll view containing a nested horizontal scrollable.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: NotificationListener<ScrollNotification>(
          onNotification: (n) {
            tracker.handleScroll(n, scroll);
            return false;
          },
          child: ListView(
            controller: scroll,
            reverse: true,
            children: const [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: SizedBox(width: 1200, height: 80, child: Text('code')),
              ),
              SizedBox(height: 1200),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();

    expect(tracker.stickToBottom, isTrue);
    await tester.drag(find.text('code'), const Offset(-200, 0));
    await tester.pump();
    // Scrolling the nested horizontal code block must not unpin the transcript.
    expect(tracker.stickToBottom, isTrue);
    expect(tester.takeException(), isNull);
  });
}
