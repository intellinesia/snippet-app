import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/api.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/screens/limit_card.dart';
import 'package:snippet/state_cards.dart';

class _C extends DaemonClient {
  _C() : super('https://daemon.invalid', 'test-token');
  @override
  late final DeviceEventHub deviceEvents = DeviceEventHub.local();
}

Future<void> _pump(WidgetTester t, double w, double scale, Widget child) async {
  t.view.physicalSize = Size(w, 1600);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    builder: (c, ch) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: ch!),
    home: Scaffold(
        body: SingleChildScrollView(
            child: Align(alignment: Alignment.topLeft, child: child))),
  ));
}

void main() {
  final soon = DateTime.now()
          .add(const Duration(hours: 3, minutes: 12))
          .millisecondsSinceEpoch ~/
      1000;
  for (final w in [360.0, 393.0, 430.0]) {
    for (final s in [1.0, 1.35, 2.0]) {
      testWidgets('limit card at $w x$s', (t) async {
        await _pump(
            t,
            w,
            s,
            LimitCard(
                client: _C(),
                session: 's',
                profile: 'Claude',
                resetsAt: soon,
                options: const ['A', 'B'],
                settled: false));
        expect(t.takeException(), isNull);
        final card = t.getRect(find.byKey(const ValueKey('limit-card')));
        expect(card.left, 16);
        expect(card.width, w - 32);
        expect(card.height, greaterThanOrEqualTo(206));
        final track = t.getRect(find.byKey(const ValueKey('limit-track')));
        expect(track.height, 4);
        expect(track.width, w - 64);
        final b = find.byType(PanelButton);
        expect(b, findsNWidgets(2));
        for (final i in [0, 1]) {
          expect(t.getSize(b.at(i)).width, w - 64);
          expect(t.getSize(b.at(i)).height, greaterThanOrEqualTo(48));
        }
        if (s == 1.0) {
          expect(card.height, 206 > card.height ? 206 : card.height);
          expect(t.getSize(b.at(0)).height, 48);
          expect(t.getRect(b.at(1)).top - t.getRect(b.at(0)).bottom, 8);
          expect(t.getRect(b.at(0)).top - track.bottom, 12);
        }
      });
      testWidgets('error panel at $w x$s', (t) async {
        const out = 'l1\nl2\nl3\nl4\nl5\nl6\nl7\nl8';
        await _pump(
            t,
            w,
            s,
            ToolErrorPanel(
                title: 'flutter build web failed',
                output: out,
                onRetry: () {}));
        expect(t.takeException(), isNull);
        final card = t.getRect(find.byKey(const ValueKey('tool-error-panel')));
        expect(card.left, 16);
        expect(card.width, w - 32);
        final o = t.getRect(find.byKey(const ValueKey('tool-error-output')));
        expect(o.width, w - 32 - 28 - 4);
        expect(find.text('Show all'), findsOneWidget);
        expect(find.textContaining('l7'), findsNothing);
      });
    }
  }

  testWidgets('limit card without resetsAt: no track, fallback sub line',
      (t) async {
    await _pump(
        t,
        393,
        1,
        LimitCard(
            client: _C(),
            session: 's',
            profile: 'Claude',
            resetsAt: 0,
            options: const ['A'],
            settled: false));
    expect(find.byKey(const ValueKey('limit-track')), findsNothing);
    expect(
        find.text('It resets later. Continue on another model now, or wait.'),
        findsOneWidget);
    expect(find.text('Continue on A'), findsOneWidget);
  });

  testWidgets(
      'error panel without retry: Copy error is the only button, full width',
      (t) async {
    await _pump(
        t, 393, 1, const ToolErrorPanel(title: 'x failed', output: 'boom'));
    expect(find.text('Retry'), findsNothing);
    final copy = t.getRect(find.text('Copy error'));
    expect(find.text('Copy error'), findsOneWidget);
    final panel = t.getRect(find.byKey(const ValueKey('tool-error-panel')));
    expect(copy.center.dx, closeTo(panel.center.dx, 1));
  });
}
