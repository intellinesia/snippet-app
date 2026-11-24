import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/chat/runs_dock.dart';
import 'package:snippet/theme.dart';

// Spec C CH-12: dock 48 tall at W, sheet rows 56, detail page opens from a row.
void main() {
  const runs = [
    RunLine('sashy', 'Sashy', 'Working', 'Visual QA'),
    RunLine('buddy', 'Buddy', 'Working', 'Home screens'),
    RunLine('ada', 'Ada', 'Failed', 'Tests', failed: true),
  ];
  for (final vw in [360.0, 393.0, 430.0]) {
    for (final scale in [1.0, 1.35, 2.0]) {
      testWidgets('runs dock at $vw x$scale', (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = Size(vw, 852);
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(t.view.reset);
        await t.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          builder: (c, w) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: w!),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Column(children: [
                RunsDock(runs: runs, onOpen: () {}),
                const RunsSheet(runs: runs),
              ]),
            ),
          ),
        ));
        final dock = t.getRect(find.byType(RunsDock));
        final row = t.getRect(find.byKey(const ValueKey('run-sashy')));
        // ignore: avoid_print
        print('W $vw x$scale dock=${dock.width}x${dock.height} row=${row.height}');
        expect(dock.width, vw - 32);
        expect(dock.height, greaterThanOrEqualTo(48));
        if (scale == 1.0) expect(dock.height, 56); // 48 plus the 8 gap
        expect(row.height, greaterThanOrEqualTo(56));
        await t.tap(find.byKey(const ValueKey('run-sashy')));
        await t.pumpAndSettle();
        expect(find.byKey(const ValueKey('open-chat')), findsOneWidget);
        expect(t.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }
}
