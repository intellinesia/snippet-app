import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/motion_routes.dart';
import 'package:snippet/screens/mobile_shell.dart';
import 'package:snippet/widgets.dart';

Future<GlobalKey<NavigatorState>> _pump(WidgetTester t, Widget top) async {
  final key = GlobalKey<NavigatorState>();
  await t.pumpWidget(MaterialApp(
    navigatorKey: key,
    home: const Scaffold(body: Text('home')),
  ));
  key.currentState!.push(AppPageRoute<void>(builder: (_) => top));
  await t.pumpAndSettle();
  return key;
}

void phoneTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await body(t);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  phoneTest('back swipe works from the middle of the page', (t) async {
    final key = await _pump(t, const Scaffold(body: Center(child: Text('top'))));
    expect(find.text('top'), findsOneWidget);
    await t.dragFrom(const Offset(400, 300), const Offset(500, 0));
    await t.pumpAndSettle();
    expect(key.currentState!.canPop(), isFalse);
  });

  phoneTest('a small drag springs back and stays', (t) async {
    final key = await _pump(t, const Scaffold(body: Center(child: Text('top'))));
    await t.dragFrom(const Offset(200, 300), const Offset(60, 0));
    await t.pumpAndSettle();
    expect(key.currentState!.canPop(), isTrue);
  });

  phoneTest('BackSwipeYield keeps the swipe away from its child',
      (t) async {
    final key = await _pump(
        t,
        const Scaffold(
            body: Column(children: [
          SizedBox(
              height: 200,
              child: BackSwipeYield(child: SizedBox.expand(key: Key('y')))),
        ])));
    await t.dragFrom(const Offset(200, 100), const Offset(500, 0));
    await t.pumpAndSettle();
    expect(key.currentState!.canPop(), isTrue);
    await t.dragFrom(const Offset(200, 400), const Offset(500, 0));
    await t.pumpAndSettle();
    expect(key.currentState!.canPop(), isFalse);
  });

  phoneTest('HomePager drags 1:1 and commits past half', (t) async {
    var page = 0;
    await t.pumpWidget(MaterialApp(
      home: StatefulBuilder(
        builder: (context, set) => HomePagerScope(
          page: page,
          onPage: (p) => set(() => page = p),
          child: const Scaffold(
            body: HomePager(
              sessions: ColoredBox(color: Colors.red, child: Text('s')),
              agents: ColoredBox(color: Colors.blue, child: Text('a')),
            ),
          ),
        ),
      ),
    ));
    final g = await t.startGesture(const Offset(600, 300));
    await g.moveBy(const Offset(-100, 0));
    await g.moveBy(const Offset(-200, 0));
    await t.pump();
    expect(find.text('a'), findsOneWidget);
    final ctl = HomePagerScope.maybeOf(t.element(find.byType(HomePager)))!;
    expect(ctl.position, greaterThan(0.2));
    expect(ctl.position, lessThan(0.6));
    await g.moveBy(const Offset(-300, 0));
    await g.up();
    await t.pumpAndSettle();
    expect(page, 1);
    expect(ctl.position, closeTo(1, 0.001));
  });

  phoneTest('HomePager springs back from a short drag', (t) async {
    var page = 0;
    await t.pumpWidget(MaterialApp(
      home: HomePagerScope(
        page: page,
        onPage: (p) => page = p,
        child: const Scaffold(
          body: HomePager(sessions: Text('s'), agents: Text('a')),
        ),
      ),
    ));
    await t.dragFrom(const Offset(400, 300), const Offset(-60, 0));
    await t.pumpAndSettle();
    expect(page, 0);
  });

  phoneTest('SpringExpand grows on open', (t) async {
    var open = false;
    await t.pumpWidget(MaterialApp(
      home: StatefulBuilder(
        builder: (context, set) => Scaffold(
          body: Column(children: [
            TextButton(onPressed: () => set(() => open = !open), child: const Text('t')),
            SpringExpand(
                open: open, child: const SizedBox(height: 100, width: 100)),
          ]),
        ),
      ),
    ));
    await t.tap(find.text('t'));
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    final mid = t.getSize(find.byType(SpringExpand)).height;
    await t.pumpAndSettle();
    final end = t.getSize(find.byType(SpringExpand)).height;
    expect(mid, greaterThan(0));
    expect(end, closeTo(100, 0.5));
  });
}
