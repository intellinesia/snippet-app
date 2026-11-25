import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide testWidgets;
import 'package:flutter_test/flutter_test.dart' as ft show testWidgets;
import 'package:snippet/attention_state.dart';
import 'package:snippet/menu_widgets.dart';
import 'package:snippet/notification_popovers.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/toast.dart' show resetToastsForTest;
import 'package:snippet/top_zone.dart';
import 'package:snippet/widgets.dart' show AppIcon;

void testWidgets(String name, Future<void> Function(WidgetTester) body) =>
    ft.testWidgets(name, (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await body(t);
      } finally {
        debugDefaultTargetPlatformOverride = null;
        phoneNeedsYou.value = 0;
        resetToastsForTest();
        TopZone.reset();
      }
    });

late BuildContext _ctx;

Future<void> _pump(WidgetTester t, double w, double scale, int count) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = Size(w, 852);
  addTearDown(t.view.reset);
  TopZone.reset();
  TopZone.register('page', 96);
  phoneNeedsYou.value = count;
  await t.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(
            textScaler: TextScaler.linear(scale),
            padding: const EdgeInsets.only(top: 44)),
        child: child!),
    home: NotificationPopovers(
        child: Scaffold(body: Builder(builder: (c) {
      _ctx = c;
      return const SizedBox.expand();
    }))),
  ));
  await t.pumpAndSettle();
}

void main() {
  for (final w in [360.0, 393.0, 430.0]) {
    for (final scale in [1.0, 1.35, 2.0]) {
      testWidgets('NT-03 bar ${w.toInt()} x$scale', (t) async {
        await _pump(t, w, scale, 2);
        final bar = find.byKey(const ValueKey('bar'));
        expect(bar, findsOneWidget);
        final r = t.getRect(bar);
        expect(r.left, 0);
        expect(r.width, w);
        expect(r.top, 96);
        if (scale == 1) expect(r.height, 48);
        expect(r.height, greaterThanOrEqualTo(48));
        expect(find.text('2 need you'), findsOneWidget);
        final review = t.getRect(find
            .ancestor(of: find.text('Review'), matching: find.byType(ConstrainedBox))
            .first);
        expect(review.width, greaterThanOrEqualTo(48));
        expect(review.height, greaterThanOrEqualTo(48));
        expect(review.right, w - 4);
        expect(
            t.widget<Text>(find.text('2 need you')).style?.color, AppColors.run);
        expect(
            t.widget<AppIcon>(find.byType(AppIcon).first).color, AppColors.run);

        // A toast sits 8 below the bar, the lowest registered top bar.
        toast(_ctx, 'Approved');
        await t.pump(const Duration(milliseconds: 300));
        expect(TopZone.floatTop(_ctx), r.bottom + 8);
        final toastTop = t.getTopLeft(find.text('Approved')).dy;
        expect(toastTop, greaterThanOrEqualTo(r.bottom + 8));
        expect(t.takeException(), isNull);
      });
    }
  }

  testWidgets('NT-03 counts: 1 needs you, 0 collapses', (t) async {
    await _pump(t, 393, 1, 1);
    expect(find.text('1 needs you'), findsOneWidget);
    phoneNeedsYou.value = 0;
    await t.pump();
    await t.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const ValueKey('bar')), findsNothing);
    expect(TopZone.lowestBar.value, 96);
  });

  testWidgets('NT-03 hidden on composer pages; tap opens the list',
      (t) async {
    var opened = 0;
    onReviewNeedsYou = () => opened++;
    addTearDown(() => onReviewNeedsYou = null);
    await _pump(t, 393, 1, 3);
    await t.tap(find.text('Review'));
    expect(opened, 1);
    await t.tap(find.text('3 need you'));
    expect(opened, 2);
    await t.pumpWidget(MaterialApp(
        home: NotificationPopovers(
            child: const AttentionBarHidden(child: Scaffold()))));
    await t.pump();
    await t.pump();
    await t.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const ValueKey('bar')), findsNothing);
  });
}
