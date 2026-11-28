import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide testWidgets;
import 'package:flutter_test/flutter_test.dart' as ft show testWidgets;
import 'package:snippet/notification_banner.dart';
import 'package:snippet/phone_heads_up.dart';
import 'package:snippet/notification_popovers.dart';
import 'package:snippet/notification_sync.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/top_zone.dart';

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
  TopZone.register('page', 96);
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
      testWidgets('heads-up ${size.width.toInt()} x$scale', (t) async {
        _seed();
        await _pump(t, size, scale, topBar: 96 + 48);
        await t.pumpAndSettle();
        // One heads-up at a time, newest first, over the page bar.
        final card = find.byType(PhoneHeadsUp);
        expect(card, findsOneWidget);
        expect(find.byType(NotificationBanner), findsNothing);
        final r = t.getRect(card);
        expect(r.left, 8);
        expect(r.width, size.width - 16);
        expect(r.top, closeTo(44 + 6, .01));
        expect(find.text('Lead'), findsOneWidget);
        expect(find.text('+4'), findsOneWidget);
        expect(t.getSize(find.byKey(const ValueKey('heads-up-more'))).height,
            greaterThanOrEqualTo(44));
        expect(t.takeException(), isNull);
        await t.pumpWidget(const SizedBox());
        await t.pump(const Duration(seconds: 31));
      });
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

  testWidgets('heads-up lifetime: information 5 s, needs-you 8 s', (t) async {
    foregroundNotifications.drain();
    foregroundNotifications
        .add({'kind': 'done', 'title': 'Info', 'session': 'a', 'url': 'u'});
    foregroundNotifications
        .add({'kind': 'waiting', 'title': 'Ask', 'session': 'b', 'url': 'u'});
    await _pump(t, _sizes[1], 1);
    // The newest (the ask) shows first; the update waits behind it.
    await t.pump(const Duration(seconds: 4));
    expect(find.text('Ask'), findsOneWidget);
    expect(find.text('Info'), findsNothing);
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();
    expect(find.text('Info'), findsNothing, reason: 'expired at 5 s');
    expect(find.text('Ask'), findsOneWidget);
    await t.pump(const Duration(seconds: 3));
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
