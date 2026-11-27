import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/screens/mobile_home/lead_phone.dart';

import 'hm_pump.dart';

void main() {
  for (final w in hmWidths) {
    for (final s in hmScales) {
      hmSpec('HM-09 at $w x $s', (t) async {
        await hmPump(
            t,
            ListView(children: [
              LeadHomeCard(running: 3, onTap: () {}),
              const LeadUserBubble(
                  'get Sashy and Buddy on the phone build and report back when it is done'),
              const HeardLine('get Sashy and Buddy on the phone build'),
              const LeadReply('On it. I will send both of them the brief now.'),
              const SizedBox(height: 12),
              const DelegationsCard(items: [
                Delegation('sashy', 'Sashy', 'Visual QA', 'Working'),
                Delegation('buddy', 'Buddy', 'Home screens', 'Working'),
                Delegation('ada', 'Ada', 'Tests', 'Done'),
              ]),
            ]),
            w,
            s,
            h: 1800);
        hmExpectTargets(t);
        final home = t.getSize(find.byKey(const ValueKey('lead-card')));
        expect(home.width, closeTo(w - 40, 0.6));
        expect(home.height, greaterThanOrEqualTo(72));
        final bubble = t.getRect(find.byKey(const ValueKey('lead-user-bubble')));
        expect(bubble.width, lessThanOrEqualTo((w - 40) * 0.69 + 0.6));
        expect(bubble.right, closeTo(w - 20, 0.6));
        final card = t.getSize(find.byKey(const ValueKey('delegations')));
        expect(card.width, closeTo(w - 40, 0.6));
        for (final id in ['sashy', 'buddy', 'ada']) {
          expect(t.getSize(find.byKey(ValueKey('delegation-$id'))).height,
              greaterThanOrEqualTo(48));
        }
        expect(find.text('Delegations  3'), findsOneWidget);
        expect(find.text('Working'), findsNWidgets(2));
        expect(find.text('3 delegations running'), findsOneWidget);
        // ignore: avoid_print
        print('HM09 w=$w s=$s home=$home bubble=${bubble.width} card=$card');
      });
    }
  }
}
