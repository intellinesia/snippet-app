import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/mobile_home/agent_context_phone.dart';

import 'hm_pump.dart';

class _C extends DaemonClient {
  _C() : super('http://127.0.0.1:9', 'tok');
}

void main() {
  final agent = CoordinationAgent.fromJson(
      {'id': 'sashy', 'display_name': 'Sashy', 'handle': 'sashy', 'status': 'active'});
  final sessions = [
    SessionInfo.fromJson({
      'id': 's1',
      'agent_id': 'sashy',
      'title': 'Visual QA: Quiet Build 1',
      'status': 'running',
      'running': true,
      'folder': '/home/me/proj',
      'last_active': DateTime.now().millisecondsSinceEpoch ~/ 1000 - 60,
    })
  ];
  for (final w in hmWidths) {
    for (final s in hmScales) {
      hmSpec('HM-06 at $w x $s', (t) async {
        await hmPump(t,
            AgentContextPage(client: _C(), agent: agent, sessions: sessions), w, s,
            h: 1200);
        await t.pump(const Duration(milliseconds: 200));
        hmExpectTargets(t);
        final tabW = w / 4;
        for (var i = 0; i < 4; i++) {
          final z = t.getSize(find.byKey(ValueKey('tab-$i')));
          expect(z.width, closeTo(tabW, 0.6));
          expect(z.height, 48);
        }
        final u = t.getRect(find.byKey(const ValueKey('tab-underline')));
        final tab0 = t.getRect(find.byKey(const ValueKey('tab-0')));
        expect(u.left, closeTo(tab0.left + 14, 0.6));
        expect(u.width, closeTo(tabW - 28, 0.6));
        expect(u.height, 2);
        final card = t.getSize(find.byKey(const ValueKey('ctx-card')).first);
        expect(card.width, closeTo(w - 32, 0.6));
        expect(card.height, greaterThanOrEqualTo(56));
        await t.tap(find.text('Tasks').first);
        await t.pump();
        expect(t.getRect(find.byKey(const ValueKey('tab-underline'))).left,
            closeTo(t.getRect(find.byKey(const ValueKey('tab-2'))).left + 14, 0.6));
        // ignore: avoid_print
        print('HM06 w=$w s=$s tab=${tabW} underline=${u.width} card=$card');
      });
    }
  }
}
