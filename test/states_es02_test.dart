import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/quiet.dart';
import 'package:snippet/widgets.dart' show AppIcon;

Future<void> _pump(WidgetTester t, double w, double scale, Widget child) async {
  t.view.physicalSize = Size(w, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    builder: (c, ch) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: ch!),
    home: Scaffold(body: Align(alignment: Alignment.topLeft, child: child)),
  ));
}

void main() {
  for (final w in [360.0, 393.0, 430.0]) {
    for (final s in [1.0, 1.35, 2.0]) {
      testWidgets('banner at $w x$s', (t) async {
        await _pump(t, w, s,
            QuietOfflineBanner(machine: 'Studio Mac', since: '14:02', onRetry: () {}));
        expect(t.takeException(), isNull);
        final box = t.getRect(find.byKey(const ValueKey('offline-banner')));
        expect(box.left, 16);
        expect(box.width, w - 32);
        expect(box.top, 8);
        expect(box.height, greaterThanOrEqualTo(56));
        final target = t.getRect(find.byKey(const ValueKey('offline-retry')));
        expect(target.height, greaterThanOrEqualTo(48));
        expect(target.width, greaterThanOrEqualTo(48));
        // Centred on the right, inside the card.
        expect(target.right, w - 20);
        expect(target.center.dy, closeTo(box.center.dy, 0.5));
        final glyph = t.getRect(find.byType(AppIcon).first);
        expect(glyph.size, const Size(20, 20));
      });
    }
  }

  testWidgets('no timestamp omits sub line; retry disables while pending',
      (t) async {
    final c = Completer<void>();
    await _pump(t, 393, 1,
        QuietOfflineBanner(machine: 'Mac', onRetry: () => c.future));
    expect(find.textContaining('Last updated'), findsNothing);
    expect(t.getSize(find.byKey(const ValueKey('offline-banner'))).height, 56);
    await t.tap(find.byKey(const ValueKey('offline-retry')));
    await t.pump();
    expect(find.text('Retrying'), findsOneWidget);
    c.complete();
    await t.pump();
    await t.pump();
    expect(find.text('Retry'), findsOneWidget);
  });
}
