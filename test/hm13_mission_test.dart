import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/goal_models.dart';
import 'package:snippet/screens/mobile_home/mission_phone.dart';

import 'hm_pump.dart';

GoalDetail _detail() => GoalDetail.fromJson({
      'id': 'g1',
      'title': 'Ship v17 phone',
      'outcome': 'All phone screens match the v17 frames',
      'plan': [
        for (var i = 1; i <= 5; i++) {'n': i, 'task_id': 't$i', 'title': 'Step $i'}
      ],
      'tasks': [
        {'id': 't1', 'status': 'done', 'agent': 'Sashy'},
        {'id': 't2', 'status': 'done', 'agent': 'Buddy'},
        {'id': 't3', 'status': 'blocked', 'status_reason': 'needs frames', 'agent': 'Sashy'},
        {'id': 't4', 'status': 'in_progress', 'agent': 'Buddy'},
      ],
    });

void main() {
  for (final w in hmWidths) {
    for (final s in hmScales) {
      hmSpec('HM-13 at $w x $s', (t) async {
        final d = _detail();
        await hmPump(t, Column(children: [MissionBar(detail: d, onTap: () {})]), w, s, h: 900);
        hmExpectTargets(t);
        final bar = t.getSize(find.byKey(const ValueKey('mission-bar')));
        expect(bar.width, w);
        expect(bar.height, greaterThanOrEqualTo(48));
        final track = t.getSize(find.byKey(const ValueKey('mission-track')));
        expect(track.width, closeTo(w - 32, 0.6));
        expect(track.height, 4);
        expect(find.text('2 of 5'), findsOneWidget);
        expect(find.text('Blocked: Step 3'), findsOneWidget);
        await hmPump(t, MissionPage(detail: d), w, s, h: 1800);
        hmExpectTargets(t);
        final bt = t.getSize(find.byKey(const ValueKey('board-track')));
        expect(find.text('40 percent'), findsOneWidget);
        expect(bt.height, 6);
        if (s == 1.0) expect(bt.width, closeTo(w - 32 - 68, 0.6));
        for (var i = 1; i <= 5; i++) {
          expect(t.getSize(find.byKey(ValueKey('step-$i'))).height,
              greaterThanOrEqualTo(72));
        }
        expect(find.text('Done'), findsNothing); // joined with owner
        expect(find.textContaining('Blocked: needs frames'), findsOneWidget);
        expect(find.textContaining('Not started'), findsOneWidget);
        // ignore: avoid_print
        print('HM13 w=$w s=$s bar=$bar track=$track board=$bt');
      });
    }
  }
}
