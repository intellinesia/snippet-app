import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/session_panels.dart';
import 'package:snippet/theme.dart';

Widget _wrap(double scale, Widget home) => MaterialApp(
      theme: buildAppTheme(),
      builder: (c, ch) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: ch!),
      home: Scaffold(body: home),
    );

void main() {
  for (final w in [360.0, 393.0, 430.0]) {
    for (final s in [1.0, 1.35, 2.0]) {
      testWidgets('session panels w=$w s=$s', (t) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = Size(w, 852);
        addTearDown(t.view.reset);
        Checkpoint? restored;
        final cps = [
          for (var i = 0; i < 3; i++)
            Checkpoint.fromJson(
                {'id': 'c$i', 'label': 'Step $i', 'created_at': '2026-11-24T11:02:00Z'})
        ];
        await t.pumpWidget(_wrap(
            s,
            SessionPanelsPage(
              sessionTitle: 'Wire the wake',
              checkpoints: SessionCheckpointsPanel(
                  checkpoints: cps,
                  onRewind: (c) => restored = c,
                  onFork: (_) {}),
              lanes: const SizedBox(),
              activity: const SizedBox(),
            )));
        await t.pump();
        expect(t.takeException(), isNull);
        for (final l in ['Checkpoints', 'Lanes', 'Activity']) {
          expect(t.getRect(find.bySemanticsLabel(l)).height, 44);
        }
        final restore = find.byWidgetPredicate(
            (w) => w is Semantics && (w.properties.label ?? '').startsWith('Restore '));
        expect(restore, findsNWidgets(2)); // newest is the present state
        final r = t.getRect(restore.first);
        expect(r.size, const Size(88, 48));
        await t.tap(restore.first);
        expect(restored, isNotNull);
        final row = t.getRect(find.text('Step 1').first);
        expect(row.left, 16);
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }
}
