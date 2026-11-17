import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/page_stack.dart';
import 'package:snippet/theme.dart';

void main() {
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

  testWidgets('push springs in with parallax and settles', (t) async {
    final open = await host(t, got: (_) {});
    open(() {});
    await t.pump();
    await t.pump(const Duration(milliseconds: 80));
    expect(pageX(t), inExclusiveRange(1, 390));
    expect(baseX(t), lessThan(0));
    await t.pumpAndSettle();
    expect(pageX(t), closeTo(0, .5));
    expect(find.byKey(const Key('base')), findsNothing,
        reason: 'a fully covered base is offstage');
  });

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
