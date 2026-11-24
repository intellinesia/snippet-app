import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/wake_models.dart';
import 'package:snippet/screens/mobile_home/agents_home.dart';
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
  Future<AgentReach> agentReach(String agentId) async => const AgentReach(
      policy: {},
      channels: {
        'push': ReachChannel(enabled: true, quietHours: false),
        'voice': ReachChannel(enabled: false, quietHours: false),
      });
}

void main() {
  for (final w in hmWidths) {
    for (final s in hmScales) {
      hmSpec('HM-12 wake at $w x $s', (t) async {
        await hmPump(t, PhoneWakePage(client: _C(), owner: 'ada', name: 'Ada'), w, s,
            h: 1600);
        await t.pump(const Duration(milliseconds: 200));
        hmExpectTargets(t);
        final card = t.getSize(find.byKey(const ValueKey('rule-w1')));
        expect(card.width, closeTo(w - 32, 0.6));
        expect(card.height, greaterThanOrEqualTo(88));
        for (final sw in find.byType(SpecSwitch).evaluate()) {
          expect(t.getSize(find.byWidget(sw.widget)), const Size(48, 48));
        }
        await t.tap(find.text('morning'));
        await t.pump();
        expect(find.text('Save rule'), findsOneWidget);
        final save = t.getSize(find.byKey(const ValueKey('btn-Save rule')));
        final cancel = t.getSize(find.byKey(const ValueKey('btn-Cancel')));
        expect(save.height, greaterThanOrEqualTo(48));
        expect(cancel.height, greaterThanOrEqualTo(48));
        await t.enterText(find.byType(TextField), '');
        await t.pump();
        expect(
            t.widget<Container>(find.byKey(const ValueKey('btn-Save rule'))).decoration,
            isA<BoxDecoration>().having(
                (d) => d.color, 'disabled fill', isNot(const Color(0xFFEDEDEA))));
        // ignore: avoid_print
        print('HM12 w=$w s=$s card=$card save=$save cancel=$cancel');
      });
      hmSpec('HM-12 reach at $w x $s', (t) async {
        await hmPump(t, PhoneReachPage(client: _C(), agentId: 'ada', name: 'Ada'), w, s,
            h: 900);
        await t.pump(const Duration(milliseconds: 200));
        hmExpectTargets(t);
        expect(find.byType(SpecSwitch), findsNWidgets(3));
        for (final sw in find.byType(SpecSwitch).evaluate()) {
          expect(t.getSize(find.byWidget(sw.widget)), const Size(48, 48));
        }
        for (final r in find.byType(SwitchRow).evaluate()) {
          expect(t.getSize(find.byWidget(r.widget)).height, greaterThanOrEqualTo(48));
        }
      });
    }
  }
}
