import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/mobile_home/agent_context_phone.dart';
import 'package:snippet/screens/phone_agent_page.dart' show shortPath;

import 'hm_pump.dart';

class _C extends DaemonClient {
  _C() : super('http://127.0.0.1:9', 'tok');
}

void main() {
  final agent = CoordinationAgent.fromJson({
    'id': 'sashy',
    'display_name': 'Sashy',
    'handle': 'sashy',
    'status': 'active'
  });
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
  final opened = <String>[];
  for (final w in hmWidths) {
    for (final s in hmScales) {
      hmSpec('HM-06 at $w x $s', (t) async {
        opened.clear();
        await hmPump(
            t,
            AgentContextPage(
                client: _C(),
                agent: agent,
                sessions: sessions,
                onOpenSession: (x) => opened.add(x.id)),
            w,
            s,
            h: 1200);
        await t.pump(const Duration(milliseconds: 200));
        hmExpectTargets(t);
        expect(find.text('In progress'), findsOneWidget);
        expect(find.text('Visual QA: Quiet Build 1'), findsOneWidget);
        expect(opened, isEmpty);
        await t.tap(find.text('Visual QA: Quiet Build 1'));
        await t.pump();
        expect(opened, ['s1']);
        await t.tap(find.text('Files').first);
        await t.pump();
        expect(find.text('In progress'), findsNothing);
        expect(find.text(shortPath('/home/me/proj')), findsOneWidget);
        await t.tap(find.text('Tasks'));
        await t.pump();
        expect(find.text('Loading'), findsOneWidget);
        await t.ensureVisible(find.text('Memory'));
        await t.pump();
        await t.tap(find.text('Memory'));
        await t.pump();
        expect(find.text('No memory yet'), findsOneWidget);
        hmExpectTargets(t);
      });
    }
  }
}
