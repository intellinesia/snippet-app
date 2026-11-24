import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/mobile_home/agents_home.dart';
import 'package:snippet/screens/mobile_home/create_agent_phone.dart';

import 'hm_pump.dart';

class _C extends DaemonClient {
  _C() : super('http://127.0.0.1:9', 'tok');
  @override
  Future<ServerConfig> getConfig({bool force = false}) async =>
      ServerConfig.fromJson({'profiles': []});
}

void main() {
  for (final w in hmWidths) {
    for (final s in hmScales) {
      hmSpec('HM-11 at $w x $s', (t) async {
        await hmPump(t, PhoneCreateAgentPage(client: _C()), w, s, h: 900);
        hmExpectTargets(t);
        final field = t.getSize(find.byType(TextField).first.evaluate().isEmpty
            ? find.byType(Scaffold)
            : find.ancestor(
                of: find.byType(TextField).first,
                matching: find.byType(Container)).first);
        expect(field.width, closeTo(w - 32, 0.6));
        expect(field.height, greaterThanOrEqualTo(48));
        final btn = t.getSize(find.byKey(const ValueKey('create-button')));
        expect(btn.width, closeTo(w - 32, 0.6));
        expect(btn.height, greaterThanOrEqualTo(48));
        expect(find.text('Add a name'), findsOneWidget);
        for (final sw in find.byType(SpecSwitch).evaluate()) {
          expect(t.getSize(find.byWidget(sw.widget)), const Size(48, 48));
        }
        expect(find.byType(SpecSwitch), findsNWidgets(2));
        await t.enterText(find.byType(TextField).first, 'Ada');
        await t.pump();
        expect(find.text('Add a name'), findsNothing);
        // ignore: avoid_print
        print('HM11 w=$w s=$s field=$field button=$btn');
      });
    }
  }
}
