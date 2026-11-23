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
            onSwipeToSessions: () => swiped++,
          ),
        );
    double sideX(WidgetTester t) =>
        t.getTopLeft(find.byKey(const Key('side'))).dx;

    setUp(() {
      swiped = 0;
      went = null;
    });

    // Mission opens only from the bottom bar, never by swiping Sessions.
    testWidgets('right swipe on Sessions does not open Mission', (t) async {
      await t.pumpWidget(shell());
      await t.pump(const Duration(milliseconds: 400));
      final g = await t.startGesture(const Offset(200, 300));
      await g.moveBy(const Offset(30, 0));
      await g.moveBy(const Offset(20, 0));
      await t.pump();
      expect(sideX(t), closeTo(0, .5));
      await g.up();
      await t.pumpAndSettle();

      await t.fling(find.byKey(const Key('side')), const Offset(200, 0), 1500);
      await t.pumpAndSettle();
      expect(swiped, 0);
      expect(sideX(t), closeTo(0, .5));
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

    // The home's Needs you pager takes horizontal drags on its cards; the
    // shell must not also page or open Mission on these drags.
    testWidgets('left swipe on the home is left to its pager', (t) async {
      await t.pumpWidget(shell());
      await t.pump(const Duration(milliseconds: 400));
      await t.fling(find.byKey(const Key('side')), const Offset(-200, 0), 1500);
      await t.pumpAndSettle();
      expect(sideX(t), closeTo(0, .5));
      expect(swiped, 0);
      expect(went, isNull);
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

    testWidgets('right swipe on Agents is left to the home pager', (t) async {
      await t.pumpWidget(shell(home: MobileHome.agents));
      await t.pump(const Duration(milliseconds: 400));
      await t.fling(find.byKey(const Key('side')), const Offset(80, 0), 1500);
      await t.pumpAndSettle();
      expect(went, isNull);
      expect(swiped, 0);
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

    testWidgets('pinch zooms instead of dragging the image', (t) async {
      await open(t);
      final y0 = t.getTopLeft(find.byType(PageView)).dy;
      final c = t.getCenter(find.byType(PageView));
      final f1 = await t.startGesture(c - const Offset(0, 40), pointer: 1);
      final f2 = await t.startGesture(c + const Offset(0, 40), pointer: 2);
      await t.pump();
      // One finger stays put and the other moves down: a drag recogniser
      // would read this as a downward swipe.
      for (var i = 0; i < 12; i++) {
        await f2.moveBy(const Offset(0, 12));
        await t.pump(const Duration(milliseconds: 16));
      }
      final zoom = t
          .widget<InteractiveViewer>(find.byType(InteractiveViewer))
          .transformationController!
          .value
          .getMaxScaleOnAxis();
      expect(zoom, greaterThan(1.3));
      expect(t.getTopLeft(find.byType(PageView)).dy, closeTo(y0, .5));
      await f1.up();
      await f2.up();
      await t.pumpAndSettle();
      expect(find.byType(PageView), findsOneWidget);
    });

    testWidgets('slow short drag springs back', (t) async {
      await open(t);
      final y0 = t.getTopLeft(find.byType(PageView)).dy;
      await t.timedDrag(find.byType(PageView), const Offset(0, 60),
          const Duration(seconds: 1));
      await t.pumpAndSettle();
      expect(find.byType(PageView), findsOneWidget);
      expect(t.getTopLeft(find.byType(PageView)).dy, closeTo(y0, .5));
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
