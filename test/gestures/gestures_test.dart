import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide testWidgets;
import 'package:flutter_test/flutter_test.dart' as flutter_test
    show testWidgets;
import 'package:snippet/api.dart';
import 'package:snippet/gesture_physics.dart';
import 'package:snippet/media_views.dart';
import 'package:snippet/screens/artifact_viewer.dart';
import 'package:snippet/screens/mobile_shell.dart';
import 'package:snippet/screens/shell_models.dart';
import 'package:snippet/theme.dart';

class _Client extends DaemonClient {
  _Client() : super('https://daemon.invalid', 'test');
}

void main() {
  void testWidgets(String name, Future<void> Function(WidgetTester) body) =>
      flutter_test.testWidgets(name, (t) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          await body(t);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });

  group('physics', () {
    test('rubber band resists and saturates', () {
      expect(rubberBand(0, 100), 0);
      expect(rubberBand(50, 100), lessThan(50));
      expect(rubberBand(10000, 100), lessThan(100));
      expect(rubberBand(-50, 100), -rubberBand(50, 100));
    });
    test('dismiss on distance or velocity', () {
      bool d(double dist, double v) => dragDismisses(
          distance: dist,
          velocity: v,
          distanceThreshold: 100,
          velocityThreshold: 700);
      expect(d(120, 0), isTrue);
      expect(d(10, 900), isTrue);
      expect(d(10, 100), isFalse);
    });
  });

  group('mobile shell swipe', () {
    var swiped = 0;
    MobileHome? went;
    Widget shell({MobileHome home = MobileHome.chats}) => MaterialApp(
          theme: buildAppTheme(),
          home: MobileShell(
            activeTabBody: const ColoredBox(color: Colors.blue),
            sidebar: const SizedBox.expand(
                child: ColoredBox(key: Key('side'), color: Colors.red)),
            hasActiveTab: true,
            chatsOpen: true,
            drilledDown: false,
            mobileHome: home,
            onClearDrillDown: () {},
            onMobileHome: (h) => went = h,
            onCloseChats: () {},
            missionPair: home == MobileHome.chats,
            onSwipeToMission: () => swiped++,
            onSwipeToSessions: () {},
          ),
        );
    double sideX(WidgetTester t) =>
        t.getTopLeft(find.byKey(const Key('side'))).dx;

    setUp(() {
      swiped = 0;
      went = null;
    });

    testWidgets('sidebar tracks the finger 1:1 and fast short fling commits',
        (t) async {
      await t.pumpWidget(shell());
      await t.pump(const Duration(milliseconds: 400));
      final g = await t.startGesture(const Offset(200, 300));
      await g.moveBy(const Offset(30, 0));
      await g.moveBy(const Offset(20, 0));
      await t.pump();
      expect(sideX(t), closeTo(50, 1.5));
      await g.up();
      await t.pumpAndSettle();

      await t.fling(find.byKey(const Key('side')), const Offset(50, 0), 1500);
      await t.pumpAndSettle();
      expect(swiped, 1);
    });

    testWidgets('slow short drag springs back without committing', (t) async {
      await t.pumpWidget(shell());
      await t.pump(const Duration(milliseconds: 400));
      await t.timedDrag(find.byKey(const Key('side')), const Offset(40, 0),
          const Duration(seconds: 1));
      await t.pumpAndSettle();
      expect(swiped, 0);
      expect(sideX(t), closeTo(0, .5));
    });

    testWidgets('left swipe on Sessions pulls and opens Agents', (t) async {
      await t.pumpWidget(shell());
      await t.pump(const Duration(milliseconds: 400));
      final g = await t.startGesture(const Offset(300, 300));
      await g.moveBy(const Offset(-30, 0));
      await g.moveBy(const Offset(-170, 0));
      await t.pump();
      expect(sideX(t), lessThan(0));
      expect(sideX(t), greaterThan(-80));
      await g.up();
      await t.pumpAndSettle();
      expect(sideX(t), closeTo(0, .5));
      expect(swiped, 0);
      expect(went, MobileHome.agents);
    });

    testWidgets('short slow left drag stays on Sessions', (t) async {
      await t.pumpWidget(shell());
      await t.pump(const Duration(milliseconds: 400));
      await t.timedDrag(find.byKey(const Key('side')), const Offset(-30, 0),
          const Duration(seconds: 1));
      await t.pumpAndSettle();
      expect(went, isNull);
      expect(sideX(t), closeTo(0, .5));
    });

    testWidgets('right swipe on Agents returns to Sessions', (t) async {
      await t.pumpWidget(shell(home: MobileHome.agents));
      await t.pump(const Duration(milliseconds: 400));
      await t.fling(find.byKey(const Key('side')), const Offset(80, 0), 1500);
      await t.pumpAndSettle();
      expect(went, MobileHome.chats);
      expect(swiped, 0);

      went = null;
      await t.fling(find.byKey(const Key('side')), const Offset(-80, 0), 1500);
      await t.pumpAndSettle();
      expect(went, isNull);
    });
  });

  group('image viewer', () {
    Future<void> open(WidgetTester t) async {
      await t.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
            builder: (ctx) => TextButton(
                key: const Key('o'),
                onPressed: () =>
                    showImageViewer(ctx, client: _Client(), path: '/a.png'),
                child: const Text('open'))),
      ));
      await t.tap(find.byKey(const Key('o')));
      await t.pump();
      await t.pump(const Duration(milliseconds: 400));
    }

    testWidgets('fast short fling dismisses', (t) async {
      await open(t);
      await t.fling(find.byType(PageView), const Offset(0, 60), 2000);
      await t.pumpAndSettle();
      expect(find.byType(PageView), findsNothing);
    });

    testWidgets('slow short drag springs back', (t) async {
      await open(t);
      await t.timedDrag(find.byType(PageView), const Offset(0, 60),
          const Duration(seconds: 1));
      await t.pumpAndSettle();
      expect(find.byType(PageView), findsOneWidget);
      expect(t.getTopLeft(find.byType(PageView)).dy, closeTo(0, .5));
    });
  });

  group('artifact sheet', () {
    Future<void> open(WidgetTester t) async {
      await t.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Builder(
            builder: (ctx) => TextButton(
                key: const Key('o'),
                onPressed: () => showArtifactSheet(
                    ctx, (close) => const SizedBox.expand(key: Key('body'))),
                child: const Text('open'))),
      ));
      await t.tap(find.byKey(const Key('o')));
      await t.pumpAndSettle();
    }

    testWidgets('header fling dismisses, slow short drag springs back',
        (t) async {
      await open(t);
      final top = t.getTopLeft(find.byKey(const Key('body'))).dy;
      await t.timedDragFrom(Offset(200, top + 20), const Offset(0, 40),
          const Duration(seconds: 1));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('body')), findsOneWidget);
      expect(t.getTopLeft(find.byKey(const Key('body'))).dy, closeTo(top, .5));

      final p = Offset(200, top + 20);
      await t.flingFrom(p, const Offset(0, 60), 2000);
      await t.pumpAndSettle();
      expect(find.byKey(const Key('body')), findsNothing);
    });
  });
}
