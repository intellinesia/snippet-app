import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/screens/mobile_home/autonomy_phone.dart';

import 'hm_pump.dart';

class _C extends DaemonClient {
  _C() : super('http://127.0.0.1:9', 'tok');
  String? set;
  @override
  Future<Map<String, dynamic>> leadAutonomy() async => {
        'mode': 'plan',
        'tool_overrides': {'Shell': 'ask', 'Web': 'act'},
        'summary': {'rounds': 14, 'asked': 2, 'failed': 0},
      };
  @override
  Future<Map<String, dynamic>> leadSetAutonomy(Map<String, dynamic> c) async {
    set = c['mode'] as String?;
    return {'mode': set, 'tool_overrides': {'Shell': 'ask', 'Web': 'act'}};
  }
}

void main() {
  for (final w in hmWidths) {
    for (final s in hmScales) {
      hmSpec('HM-10 autonomy at $w x $s', (t) async {
        final c = _C();
        await hmPump(t, AutonomyPhonePage(client: c), w, s, h: 1200);
        await t.pump(const Duration(milliseconds: 100));
        expect(t.takeException(), isNull);
        final seg = t.getSize(find.byKey(const ValueKey('autonomy-seg')));
        expect(seg.width, closeTo(w - 32, 0.6));
        expect(seg.height, greaterThanOrEqualTo(48));
        for (final m in ['ask', 'plan', 'act']) {
          expect(t.getSize(find.byKey(ValueKey('seg-$m'))).height,
              greaterThanOrEqualTo(44));
        }
        for (final k in ['Shell', 'Web']) {
          expect(t.getSize(find.byKey(ValueKey('override-$k'))).height,
              greaterThanOrEqualTo(48));
        }
        expect(find.text('14 rounds   2 asked   0 failed'), findsOneWidget);
        await t.tap(find.byKey(const ValueKey('seg-act')));
        await t.pump();
        expect(c.set, 'act');
        // ignore: avoid_print
        print('HM10 w=$w s=$s seg=$seg');
      });
    }
  }
}
