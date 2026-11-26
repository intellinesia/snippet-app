import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/motion_routes.dart';
import 'package:snippet/screens/mobile_shell.dart';
import 'package:snippet/screens/shell_models.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/page_stack.dart';



void main() {
  group('AppPageRoute on Android', () {
    Future<void> pushSecond(WidgetTester t, {bool disableAnimations = false}) async {
      await t.pumpWidget(MediaQuery(
        data: MediaQueryData(disableAnimations: disableAnimations),
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Builder(
            builder: (ctx) => Scaffold(
              key: const Key('page1'),
              body: Center(
                child: TextButton(
                  key: const Key('push'),
                  onPressed: () => pushApp<void>(
                    ctx,
                    (_) => Scaffold(
                      key: const Key('page2'),
                      body: const Center(child: Text('Second')),
                    ),
                  ),
                  child: const Text('Push'),
                ),
              ),
            ),
          ),
        ),
      ));
      await t.tap(find.byKey(const Key('push')));
    }

    testWidgets('pops on an edge drag past half the width', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      // Release projects velocity and pops past half the width, as on a phone.
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(390, 844);
      addTearDown(t.view.reset);
      try {
        await pushSecond(t);
        await t.pumpAndSettle();

        final g = await t.startGesture(const Offset(8, 300));
        await g.moveBy(const Offset(160, 0));
        await g.moveBy(const Offset(160, 0));
        await t.pump();
        expect(t.getTopLeft(find.byKey(const Key('page2'))).dx, closeTo(320, 2));
        expect(t.getTopLeft(find.byKey(const Key('page1'))).dx, lessThan(0));
        await g.up();
        await t.pumpAndSettle();

        expect(find.byKey(const Key('page2')), findsNothing);
        expect(find.byKey(const Key('page1')), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('cancels edge drag below 1/3 threshold', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await pushSecond(t);
        await t.pumpAndSettle();

        await t.timedDragFrom(
          const Offset(8, 300),
          const Offset(200, 0),
          const Duration(seconds: 1),
        );
        await t.pumpAndSettle();

        expect(find.byKey(const Key('page2')), findsOneWidget);
        expect(t.getTopLeft(find.byKey(const Key('page2'))).dx, closeTo(0, 0.5));
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

    testWidgets('pops on fast fling from left edge', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      // Release projects velocity and pops past half the width, as on a phone.
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(390, 844);
      addTearDown(t.view.reset);
      try {
        await pushSecond(t);
        await t.pumpAndSettle();

        await t.flingFrom(const Offset(8, 300), const Offset(100, 0), 1200);
        await t.pumpAndSettle();

        expect(find.byKey(const Key('page2')), findsNothing);
        expect(find.byKey(const Key('page1')), findsOneWidget);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

  });

  testWidgets('AppPageRoute on desktop does not enable edge pop swipe',
      (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await t.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
          builder: (ctx) => Scaffold(
            body: TextButton(
              key: const Key('push'),
              onPressed: () => pushApp<void>(
                ctx,
                (_) => const Scaffold(key: Key('page2'), body: Text('Second')),
              ),
              child: const Text('Push'),
            ),
          ),
        ),
      ));
      await t.tap(find.byKey(const Key('push')));
      await t.pumpAndSettle();

      await t.timedDragFrom(
        const Offset(8, 300),
        const Offset(350, 0),
        const Duration(milliseconds: 300),
      );
      await t.pumpAndSettle();
      expect(find.byKey(const Key('page2')), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  group('MobileShell session slide & Android edge swipe', () {
    testWidgets('slides session in from right and swipes back past half',
        (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        var chatsOpen = true;
        late StateSetter hostSetState;

        Widget buildShell() => MaterialApp(
              theme: buildAppTheme(),
              home: StatefulBuilder(
                builder: (ctx, setState) {
                  hostSetState = setState;
                  return MobileShell(
                    activeTabBody: const SizedBox.expand(
                      child: ColoredBox(key: Key('tab'), color: Colors.blue),
                    ),
                    sidebar: const SizedBox.expand(
                      child: ColoredBox(key: Key('side'), color: Colors.red),
                    ),
                    hasActiveTab: true,
                    chatsOpen: chatsOpen,
                    drilledDown: false,
                    mobileHome: MobileHome.chats,
                    onClearDrillDown: () {},
                    onMobileHome: (_) {},
                    onCloseChats: () {},
                    onOpenChats: () => setState(() => chatsOpen = true),
                  );
                },
              ),
            );

        await t.pumpWidget(buildShell());
        await t.pumpAndSettle();

        hostSetState(() => chatsOpen = false);
        await t.pump();
        await t.pump(const Duration(milliseconds: 170));
        expect(t.getTopLeft(find.byKey(const Key('tab'))).dx, greaterThan(0));
        expect(t.getTopLeft(find.byKey(const Key('side'))).dx, lessThan(0));

        await t.pumpAndSettle();
        expect(t.getTopLeft(find.byKey(const Key('tab'))).dx, closeTo(0, 0.5));

        // A slow drag short of half springs back.
        await t.timedDragFrom(
          const Offset(8, 300),
          const Offset(200, 0),
          const Duration(seconds: 1),
        );
        await t.pumpAndSettle();
        expect(chatsOpen, isFalse);

        // Past half commits, and the swipe may start mid-page.
        final g = await t.startGesture(const Offset(200, 300));
        await g.moveBy(const Offset(20, 0));
        await g.moveBy(const Offset(220, 0));
        await g.moveBy(const Offset(220, 0));
        await t.pump();
        expect(t.getTopLeft(find.byKey(const Key('tab'))).dx,
            closeTo(460 - 8, 10));
        await g.up();
        await t.pumpAndSettle();
        expect(chatsOpen, isTrue);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  });

  setUp(() {});

  Future<StateSetter> host(WidgetTester t, {required ValueChanged<bool> got,
      Widget? pageChild}) async {
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    var open = false;
    late StateSetter set;
    await t.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: StatefulBuilder(builder: (context, s) {
        set = s;
        return PhonePageStack(
          onBack: () => s(() {
            open = false;
            got(false);
          }),
          base: const ColoredBox(key: Key('base'), color: Colors.red),
          page: open
              ? (pageChild ??
                  const ColoredBox(key: Key('page'), color: Colors.blue))
              : null,
        );
      }),
    ));
    // Opening goes through the same setter the owner would use.
    return (fn) => set(() {
          open = true;
          fn();
        });
  }

  double pageX(WidgetTester t) => t.getTopLeft(find.byKey(const Key('page'))).dx;
  double baseX(WidgetTester t) => t.getTopLeft(find.byKey(const Key('base'))).dx;

  testWidgets('a swipe from mid-page past half goes back', (t) async {
    bool? back;
    final open = await host(t, got: (v) => back = v);
    open(() {});
    await t.pumpAndSettle();
    final g = await t.startGesture(const Offset(150, 400));
    await g.moveBy(const Offset(20, 0));
    await g.moveBy(const Offset(200, 0));
    await t.pump();
    expect(pageX(t), greaterThan(150));
    await g.up();
    await t.pumpAndSettle();
    expect(back, isFalse);
    expect(find.byKey(const Key('page')), findsNothing);
    expect(baseX(t), closeTo(0, .5));
  });

  testWidgets('a slow short swipe springs back', (t) async {
    bool? back;
    final open = await host(t, got: (v) => back = v);
    open(() {});
    await t.pumpAndSettle();
    await t.timedDragFrom(const Offset(150, 400), const Offset(90, 0),
        const Duration(seconds: 1));
    await t.pumpAndSettle();
    expect(back, isNull);
    expect(pageX(t), closeTo(0, .5));
  });

  testWidgets('a quick flick goes back even when short', (t) async {
    bool? back;
    final open = await host(t, got: (v) => back = v);
    open(() {});
    await t.pumpAndSettle();
    await t.flingFrom(const Offset(150, 400), const Offset(60, 0), 1200);
    await t.pumpAndSettle();
    expect(back, isFalse);
  });

  testWidgets('a horizontal scroller under the finger keeps its drag',
      (t) async {
    bool? back;
    final open = await host(t,
        got: (v) => back = v,
        pageChild: ColoredBox(
          key: const Key('page'),
          color: Colors.blue,
          child: Align(
            alignment: Alignment.topCenter,
            child: SizedBox(
              height: 100,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < 20; i++)
                    SizedBox(width: 120, child: Text('chip $i')),
                ],
              ),
            ),
          ),
        ));
    open(() {});
    await t.pumpAndSettle();
    await t.dragFrom(const Offset(200, 50), const Offset(-200, 0));
    await t.pumpAndSettle();
    await t.dragFrom(const Offset(150, 50), const Offset(300, 0));
    await t.pumpAndSettle();
    expect(back, isNull);
    expect(pageX(t), closeTo(0, .5));
  });
}

