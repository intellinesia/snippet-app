import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/menu_widgets.dart';
import 'package:snippet/toast.dart' show resetToastsForTest;
import 'package:snippet/theme.dart';
import 'package:snippet/toast_avoid.dart';

late BuildContext _ctx;

Future<void> _host(WidgetTester t, double w, double scale,
    {bool bar = true}) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = Size(w, 852);
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  await t.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    builder: (c, ch) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: ch!),
    home: Scaffold(body: Builder(builder: (c) {
      _ctx = c;
      return Column(children: [
        if (bar)
          ToastAvoid(
              child: Container(
                  key: const Key('bar'), height: 96, color: Colors.grey)),
        const Expanded(child: SizedBox()),
      ]);
    })),
  ));
  await t.pump(const Duration(milliseconds: 50));
}

void _spec(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (t) async {
    addTearDown(t.view.reset);
    try {
      await body(t);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      resetToastsForTest();
    }
  });
}

void main() {
  for (final w in [360.0, 393.0, 430.0]) {
    for (final s in [1.0, 1.35, 2.0]) {
      _spec('toast top band $w x $s', (t) async {
        await _host(t, w, s);
        final barBottom = t.getRect(find.byKey(const Key('bar'))).bottom;
        toast(_ctx, 'Archived the session',
            actionLabel: 'Undo', onAction: () {});
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));
        final card =
            t.getRect(find.byKey(const Key('toastCard-Archived the session')));
        expect(card.top, closeTo(barBottom + 8, 0.5));
        expect(card.left, 16);
        expect(card.width, w - 32);
        expect(card.height, greaterThanOrEqualTo(48));
        final act = t.getRect(find.byKey(const Key('toastAction')));
        expect(act.width, greaterThanOrEqualTo(48));
        expect(act.height, greaterThanOrEqualTo(48));
        expect(act.right, closeTo(w - 16, 0.5));
        expect(t.takeException(), isNull);
        // Undo toast is gone after 6 s.
        await t.pump(const Duration(seconds: 5));
        expect(find.text('Archived the session'), findsOneWidget);
        await t.pump(const Duration(seconds: 2));
        await t.pump();
        await t.pump(const Duration(milliseconds: 300));
        expect(find.text('Archived the session'), findsNothing);
      });
    }
  }

  _spec('toast sits at safe top plus 8 with no bar; stacks two with 8 gap',
      (t) async {
    await _host(t, 393, 1, bar: false);
    toast(_ctx, 'One');
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    toast(_ctx, 'Two', danger: true);
    toast(_ctx, 'Two', danger: true); // identical within 2 s collapses
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    Rect r(String m) => t.getRect(find.byKey(Key('toastCard-$m')));
    expect(r('Two').top, 8);
    expect(r('One').top, closeTo(r('Two').bottom + 8, 0.5));
    expect(find.text('Two'), findsOneWidget);
    toast(_ctx, 'Three');
    await t.pump(const Duration(milliseconds: 500));
    expect(find.text('One'), findsNothing);
    expect(find.text('Three'), findsOneWidget);
    await t.pump(const Duration(seconds: 9));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
  });
}
