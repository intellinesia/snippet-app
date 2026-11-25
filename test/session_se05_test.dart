import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/screens/new_session_draft.dart';
import 'package:snippet/theme.dart';

class _Client extends DaemonClient {
  _Client() : super('http://127.0.0.1:1', 'test');
}

Widget _wrap(double scale, Widget home) => MaterialApp(
      theme: buildAppTheme(),
      builder: (c, ch) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: ch!),
      home: home,
    );

void main() {
  for (final w in [360.0, 393.0, 430.0]) {
    for (final s in [1.0, 1.35, 2.0]) {
      testWidgets('new session w=$w s=$s', (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = Size(w, 852);
        addTearDown(t.view.reset);
        await t.pumpWidget(_wrap(
            s,
            NewSessionDraft(
                client: _Client(),
                machineLabel: 'Mac mini',
                folder: '/Users/x/snippet-mobile-all',
                layout: NewSessionLayout.phone,
                onStart: (a, b, c, d) async {})));
        await t.pump();
        expect(t.takeException(), isNull);
        // Card: 16 inset, full content width, min 330.
        final card = t.getRect(find
            .ancestor(
                of: find.text('What should it do?'),
                matching: find.byType(Container))
            .last);
        expect(card.left, 16);
        expect(card.width, w - 32);
        expect(card.height, greaterThanOrEqualTo(330));
        // Chips: hit area 44 high; folder chip names the folder.
        expect(t.getRect(find.bySemanticsLabel('snippet-mobile-all')).height, 44);
        // Disabled Start is visible and 120 x 48.
        final start = t.getRect(find.bySemanticsLabel('Start'));
        expect(start.size, const Size(120, 48));
        await t.enterText(find.byType(TextField), 'Do the thing');
        await t.pump();
        expect(find.bySemanticsLabel('Start'), findsOneWidget);
      });
    }
  }

  testWidgets('keyboard open at 360 x 640 does not overflow', (t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(360, 640);
    t.view.viewInsets = const FakeViewPadding(bottom: 300);
    addTearDown(t.view.reset);
    await t.pumpWidget(_wrap(
        1,
        NewSessionDraft(
            client: _Client(),
            machineLabel: 'Mac mini',
            folder: '/a/b',
            layout: NewSessionLayout.phone,
            onStart: (a, b, c, d) async {})));
    await t.pump();
    expect(t.takeException(), isNull);
  });
}
