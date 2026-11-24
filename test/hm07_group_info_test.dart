import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/chat/chat_info.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/mobile_home/agents_home.dart';
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
        expect(t.takeException(), isNull);
        expect(find.text('Group info'), findsOneWidget);
        expect(find.text('Add member'), findsOneWidget);
        expect(find.text('3 members - created 21 Nov'), findsOneWidget);
        final add = t.getSize(find.ancestor(
            of: find.text('Add member'),
            matching: find.byType(ConstrainedBox)).first);
        expect(add.height, greaterThanOrEqualTo(48));
        final sw = t.getSize(find.byType(SpecSwitch));
        expect(sw, const Size(48, 48));
        for (final r in find.byType(MarkRow).evaluate()) {
          final z = t.getSize(find.byWidget(r.widget));
          expect(z.height, greaterThanOrEqualTo(56));
          expect(z.width, w);
        }
        expect(find.byType(MarkRow), findsNWidgets(3));
        final leave = t.widget<Text>(find.text('Leave group'));
        expect(leave.style!.color, AppColors.danger);
        final mute = t.widget<Text>(find.text('Mute notifications'));
        expect(mute.style!.color, isNot(AppColors.danger));
        // ignore: avoid_print
        print('HM07 w=$w s=$s add=$add switch=$sw');
      });
    }
  }
}
