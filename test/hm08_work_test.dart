import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/mobile_home/agent_work_phone.dart';

import 'hm_pump.dart';

Map<String, dynamic> _in(int id, String kind, {String from = 'agent', String thread = 't'}) => {
      'id': id,
      'thread_id': thread,
      'from_kind': from,
      'from_id': 'x',
      'source': kind == 'offer' ? 'offer' : 'message',
      if (kind == 'question') 'post_kind': 'question',
      'text': 'Body of entry $id that is quite long and should ellipsise at one line on a phone screen',
      'created_at': DateTime.now().subtract(const Duration(minutes: 5)).toUtc().toIso8601String(),
    };

class _C extends DaemonClient {
  _C() : super('http://127.0.0.1:9', 'tok');
  @override
  Future<List<InboxEntry>> agentInbox(String agentId,
          {String? contains, String? kind, int? before, int limit = 50}) async =>
      [
        InboxEntry.fromJson(_in(3, 'question', thread: 'q')),
        InboxEntry.fromJson(_in(2, 'offer', thread: 'o')),
        InboxEntry.fromJson(_in(1, 'message', thread: 'm')),
      ];
  @override
  Future<List<TaskItem>> tasks({String? status, String? agentId, int? limit}) async => [
        for (final (i, st) in ['todo', 'todo', 'in_progress', 'done'].indexed)
          TaskItem.fromJson({'id': 'k$i', 'title': 'Task $i', 'status': st}),
      ];
}

void main() {
  for (final w in hmWidths) {
    for (final s in hmScales) {
      hmSpec('HM-08 at $w x $s', (t) async {
        await hmPump(t,
            AgentWorkPage(client: _C(), agentId: 'sashy', agentName: 'Sashy'), w, s,
            h: 1200);
        await t.pump(const Duration(milliseconds: 200));
        hmExpectTargets(t);
        for (var i = 0; i < 2; i++) {
          final z = t.getSize(find.byKey(ValueKey('tab-$i')));
          expect(z.width, closeTo(w / 2, 0.6));
          expect(z.height, 48);
        }
        for (final id in [1, 2, 3]) {
          expect(t.getSize(find.byKey(ValueKey('inbox-$id'))).height,
              greaterThanOrEqualTo(64));
        }
        expect(find.text('Needs you'), findsOneWidget);
        expect(find.text('Assignment'), findsOneWidget);
        await t.tap(find.text('Board'));
        await t.pump();
        expect(find.text('Todo  2'), findsOneWidget);
        expect(find.text('Doing  1'), findsOneWidget);
        expect(find.text('Done  1'), findsOneWidget);
        final card = t.getSize(find.byKey(const ValueKey('board-card')).first);
        expect(card.width, closeTo(w - 32, 0.6));
        expect(card.height, greaterThanOrEqualTo(48));
        // ignore: avoid_print
        print('HM08 w=$w s=$s tab=${w / 2} card=$card');
      });
    }
  }
}
