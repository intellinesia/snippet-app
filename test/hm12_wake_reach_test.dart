import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/wake_models.dart';
import 'package:snippet/mobile_kit.dart';
import 'package:snippet/screens/mobile_home/wake_reach_phone.dart';

import 'hm_pump.dart';

class _C extends DaemonClient {
  _C() : super('http://127.0.0.1:9', 'tok');
  @override
  Future<WakeList> wakes() async => WakeList.fromJson({
        'wakes': [
          {
            'id': 'w1',
            'owner': 'ada',
            'name': 'morning',
            'kind': 'every',
            'set_by': 'user',
            'schedule_text': 'Daily 08:00',
            'brief': 'Summarise overnight PRs',
            'enabled': true,
          },
          {
            'id': 'w2',
            'owner': 'ada',
            'name': 'review',
            'kind': 'every',
            'set_by': 'user',
            'schedule_text': 'Weekdays 17:00',
            'brief': 'Review open work',
            'enabled': false,
          },
        ]
      });
  @override
  Future<List<AgentWatch>> agentWatches(String agentId) async => [];
  @override
  Future<AgentReach> agentReach(String agentId) async =>
      const AgentReach(policy: {}, channels: {
        'push': ReachChannel(enabled: true, quietHours: false),
        'voice': ReachChannel(enabled: false, quietHours: false),
      });
}

void main() {
  for (final w in hmWidths) {
    for (final s in hmScales) {
      hmSpec('HM-12 wake at $w x $s', (t) async {
        await hmPump(
            t, PhoneWakePage(client: _C(), owner: 'ada', name: 'Ada'), w, s,
            h: 1600);
        await t.pump(const Duration(milliseconds: 200));
        // MkToggle is a 44 high target inside a taller row.
        hmExpectTargets(t);
        expect(find.text('Schedules'), findsOneWidget);
        expect(t.getSize(find.byKey(const ValueKey('rule-w1'))).height,
            greaterThanOrEqualTo(48));
        expect(find.byType(MkToggle), findsNWidgets(2));
        await t.tap(find.text('morning'));
        await t.pumpAndSettle();
        expect(find.text('Edit wake'), findsOneWidget);
        expect(find.text('Save rule'), findsOneWidget);
        expect(find.text('Cancel'), findsOneWidget);
        await t.enterText(find.byType(TextField), '');
        await t.pump();
        expect(t.widget<MkPill>(find.widgetWithText(MkPill, 'Save rule')).onTap,
            isNull);
        await t.enterText(find.byType(TextField), 'daily 09:00');
        await t.pump();
        expect(t.widget<MkPill>(find.widgetWithText(MkPill, 'Save rule')).onTap,
            isNotNull);
      });
      hmSpec('HM-12 reach at $w x $s', (t) async {
        await hmPump(
            t, PhoneReachPage(client: _C(), agentId: 'ada', name: 'Ada'), w, s,
            h: 900);
        await t.pump(const Duration(milliseconds: 200));
        hmExpectTargets(t);
        expect(find.text('Channels'), findsOneWidget);
        expect(find.byType(MkToggle), findsNWidgets(3));
        expect(
            t.widget<MkToggle>(find.byType(MkToggle).first).onChanged, isNull);
      });
    }
  }
}
