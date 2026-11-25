import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/screens/session_recorder_page.dart';
import 'package:snippet/theme.dart';

Widget _wrap(double scale, Widget home) => MaterialApp(
      theme: buildAppTheme(),
      builder: (c, ch) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: ch!),
      home: Scaffold(body: home),
    );

const _saved = [
  SavedRecording('24 Nov', 'Wire the wake', Duration(minutes: 2, seconds: 41)),
  SavedRecording('23 Nov', 'Fix chips', Duration(minutes: 5)),
  SavedRecording('22 Nov', 'Docs', Duration(seconds: 50)),
];

void main() {
  for (final w in [360.0, 393.0, 430.0]) {
    for (final s in [1.0, 1.35, 2.0]) {
      testWidgets('recorder w=$w s=$s', (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = Size(w, 852);
        addTearDown(t.view.reset);
        var stopped = false;
        await t.pumpWidget(_wrap(
            s,
            SessionRecorderPage(
                sessionTitle: 'Wire the wake',
                recording: true,
                elapsed: const Duration(minutes: 2, seconds: 41),
                onRecord: () {},
                onStop: () => stopped = true,
                saved: _saved)));
        await t.pump();
        expect(t.takeException(), isNull);
        expect(find.text('02:41'), findsNWidgets(2));
        final stop = t.getRect(find.bySemanticsLabel('Stop'));
        expect(stop.height, greaterThanOrEqualTo(48));
        expect(stop.width, greaterThanOrEqualTo(48));
        expect(find.text('Saved recordings: 3'), findsOneWidget);
        await t.tap(find.text('Stop'));
        expect(stopped, true);
        await t.pumpWidget(_wrap(
            s,
            SessionRecorderPage(
                sessionTitle: 'x',
                recording: false,
                elapsed: Duration.zero,
                onRecord: () {},
                onStop: () {})));
        final rec = t.getRect(find.bySemanticsLabel('Record'));
        expect(rec.width, w - 32);
        expect(rec.height, greaterThanOrEqualTo(48));
      });

      for (final withEvents in [true, false]) {
        testWidgets('replay w=$w s=$s events=$withEvents', (t) async {
          t.view.devicePixelRatio = 1;
          t.view.physicalSize = Size(w, 852);
          addTearDown(t.view.reset);
          Duration? seek;
          await t.pumpWidget(_wrap(
              s,
              SessionReplayPage(
                sessionTitle: 'Wire the wake',
                total: const Duration(minutes: 2, seconds: 41),
                position: const Duration(seconds: 100),
                playing: false,
                onSeek: (d) => seek = d,
                onToggle: () {},
                events: withEvents
                    ? const [
                        ReplayEvent(Duration(seconds: 5), 'Read the spec'),
                        ReplayEvent(Duration(seconds: 90), 'Edited the file'),
                        ReplayEvent(Duration(seconds: 150), 'Ran tests'),
                      ]
                    : const [],
              )));
          await t.pump();
          expect(t.takeException(), isNull);
          expect(t.getRect(find.bySemanticsLabel('Replay position')).height,
              greaterThanOrEqualTo(48));
          expect(t.getSize(find.bySemanticsLabel('Play')), const Size(56, 56));
          expect(find.text('01:40'), findsOneWidget);
          expect(find.text('02:41'), findsOneWidget);
          expect(find.text('Edited the file'), withEvents ? findsOneWidget : findsNothing);
          // Screen reader increase action moves the thumb.
          final h = t.ensureSemantics();
          t.semantics.performAction(
              find.semantics.byLabel('Replay position'), SemanticsAction.increase);
          expect(seek, isNotNull);
          expect(seek! > const Duration(seconds: 100), true);
          h.dispose();
        });
      }
    }
  }
}
