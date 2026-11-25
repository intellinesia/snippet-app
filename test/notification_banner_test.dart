import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide testWidgets;
import 'package:flutter_test/flutter_test.dart' as ft show testWidgets;
import 'package:snippet/notification_banner.dart';
import 'package:snippet/notification_popovers.dart';
import 'package:snippet/notification_sync.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/top_zone.dart';
import 'package:snippet/widgets.dart' show AppIcon;

void testWidgets(String name, Future<void> Function(WidgetTester) body) =>
    ft.testWidgets(name, (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await body(t);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

const _sizes = [Size(360, 780), Size(393, 852), Size(430, 932)];
const _scales = [1.0, 1.35, 2.0];

Future<void> _pump(WidgetTester t, Size size, double scale,
    {double? topBar}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  TopZone.reset();
  if (topBar != null) TopZone.register('attention', topBar);
  await t.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(
            textScaler: TextScaler.linear(scale),
            padding: const EdgeInsets.only(top: 44)),
        child: child!),
    home: const NotificationPopovers(child: Scaffold(body: SizedBox.expand())),
  ));
  await t.pump();
}

void _seed() {
  foregroundNotifications.drain();
  for (final i in [1, 2, 3, 4]) {
    foregroundNotifications.add({
      'kind': 'done',
      'title': 'Task $i done',
      'body': 'snippet-mobile - Sashy',
      'session': 's$i',
      'url': 'u',
    });
  }
  foregroundNotifications.add({
    'kind': 'waiting',
    'title': 'Lead',
    'body': 'Approve the release build for snippet-mobile before it ships',
    'session': 'sw',
    'url': 'u',
  });
}

void main() {
  tearDown(() {
    TopZone.reset();
    foregroundNotifications.drain();
  });

  for (final size in _sizes) {
    for (final scale in _scales) {
      for (final bar in <double?>[null, 96 + 48]) {
        testWidgets('NT-01 stack ${size.width.toInt()} x$scale bar=$bar',
            (t) async {
          _seed();
          await _pump(t, size, scale, topBar: bar);
          await t.pumpAndSettle();
          final cards = find.byType(NotificationBanner);
          expect(cards, findsNWidgets(3), reason: 'at most 3 visible');
          final top = (bar ?? 96) + 8;
          var y = top;
          for (var i = 0; i < 3; i++) {
            final r = t.getRect(cards.at(i));
            expect(r.left, 16);
            expect(r.width, size.width - 32);
            expect(r.height, greaterThanOrEqualTo(72));
            expect(r.top, closeTo(y, .01));
            y = r.bottom + 8;
          }
          // Newest on top: the needs-you item was added last.
          expect(
              find.descendant(
                  of: cards.first, matching: find.text('Needs you')),
              findsOneWidget);
          expect(
              find.descendant(
                  of: cards.first,
                  matching: find.byWidgetPredicate(
                      (w) => w is AppIcon && w.name == 'hand')),
              findsOneWidget);
          for (var i = 1; i < 3; i++) {
            final amber = find.descendant(
                of: cards.at(i),
                matching: find.byWidgetPredicate((w) =>
                    (w is AppIcon && w.color == AppColors.run) ||
                    (w is Text && w.style?.color == AppColors.run)));
            expect(amber, findsNothing, reason: 'information is neutral');
          }
          expect(
              find.descendant(
                  of: find.byType(NotificationPopovers),
                  matching: find.byWidgetPredicate((w) =>
                      w is DecoratedBox &&
                      w.decoration is BoxDecoration &&
                      (w.decoration as BoxDecoration).boxShadow != null)),
              findsNothing);
          final show = find.text('Show all 5');
          final dismiss = find.text('Dismiss all');
          expect(show, findsOneWidget);
          expect(dismiss, findsOneWidget);
          for (final f in [show, dismiss]) {
            final target = find.ancestor(
                of: f, matching: find.byType(ConstrainedBox)).first;
            expect(t.getSize(target).height, greaterThanOrEqualTo(48));
          }
          expect(t.getTopLeft(show).dx, 16 + 0, skip: scale != 1 && false);
          expect(t.getTopLeft(dismiss).dy, greaterThan(y - 8 - 1));
          expect(t.takeException(), isNull);
          await t.pumpWidget(const SizedBox());
          await t.pump(const Duration(seconds: 31));
        });
      }
    }
  }

  testWidgets('NT-01 empty draws no layer, empty title shows nothing',
      (t) async {
    foregroundNotifications.drain();
    foregroundNotifications.add({'kind': 'done', 'title': ' ', 'body': 'x'});
    await _pump(t, _sizes[1], 1);
    await t.pumpAndSettle();
    expect(find.byType(NotificationBanner), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('NT-01 lifetime: information 6 s, needs-you 30 s',
      (t) async {
    foregroundNotifications.drain();
    foregroundNotifications
        .add({'kind': 'done', 'title': 'Info', 'session': 'a', 'url': 'u'});
    foregroundNotifications.add(
        {'kind': 'waiting', 'title': 'Ask', 'session': 'b', 'url': 'u'});
    await _pump(t, _sizes[1], 1);
    await t.pump(const Duration(seconds: 5));
    expect(find.text('Info'), findsOneWidget);
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();
    expect(find.text('Info'), findsNothing);
    expect(find.text('Ask'), findsOneWidget);
    await t.pump(const Duration(seconds: 24));
    await t.pumpAndSettle();
    expect(find.text('Ask'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('NT-01 swipe either way dismisses', (t) async {
    foregroundNotifications.drain();
    foregroundNotifications
        .add({'kind': 'done', 'title': 'Left', 'session': 'a', 'url': 'u'});
    foregroundNotifications
        .add({'kind': 'done', 'title': 'Right', 'session': 'b', 'url': 'u'});
    await _pump(t, _sizes[1], 1);
    await t.pumpAndSettle();
    await t.fling(find.text('Right'), const Offset(400, 0), 2000);
    await t.pumpAndSettle();
    expect(find.text('Right'), findsNothing);
    await t.fling(find.text('Left'), const Offset(-400, 0), 2000);
    await t.pumpAndSettle();
    expect(find.text('Left'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}
