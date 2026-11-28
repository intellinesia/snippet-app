import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/chat/chat_info.dart';
import 'package:snippet/models.dart';
import 'package:snippet/mobile_kit.dart';
import 'package:snippet/theme.dart';

import 'hm_pump.dart';

class _C extends DaemonClient {
  _C() : super('http://127.0.0.1:9', 'tok');
  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => [
        for (final i in ['a1', 'a2', 'a3'])
          CoordinationAgent.fromJson(
              {'id': i, 'display_name': 'Agent $i', 'handle': i}),
      ];
}

void main() {
  final group = GroupSummary.fromJson({
    'id': 'g1',
    'title': 'Canvas review',
    'created_at': '2026-11-21T10:00:00Z',
    'lead': 'a1',
    'members': [
      {'kind': 'human', 'id': 'me'},
      {'kind': 'agent', 'id': 'a1'},
      {'kind': 'agent', 'id': 'a2'},
    ],
  });
  for (final w in hmWidths) {
    for (final s in hmScales) {
      hmSpec('HM-07 at $w x $s', (t) async {
        await hmPump(t, GroupInfoPanel(client: _C(), group: group), w, s,
            h: 1400);
        await t.pump(const Duration(milliseconds: 200));
        hmExpectTargets(t);
        expect(find.text('Group info'), findsWidgets);
        expect(find.text('Add member'), findsOneWidget);
        expect(find.text('3 members - created 21 Nov'), findsOneWidget);
        expect(find.byType(MkToggle), findsOneWidget);
        expect(find.byType(MkRow), findsNWidgets(3));
        final leave = t.widget<Text>(find.text('Leave group'));
        expect(leave.style!.color, AppColors.danger);
        final mute = t.widget<Text>(find.text('Mute notifications'));
        expect(mute.style!.color, isNot(AppColors.danger));
      });
    }
  }
}
