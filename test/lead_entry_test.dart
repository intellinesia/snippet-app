import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/lead/lead_state.dart';
import 'package:snippet/screens/mobile_home/quiet_home.dart';
import 'package:snippet/theme.dart';

CoordinationAgent _agent(String id, {bool lead = false}) =>
    CoordinationAgent.fromJson({
      'id': id,
      'display_name': id,
      'handle': id,
      'status': 'active',
      if (lead) 'kind': 'lead',
    });

void main() {
  test('Lead resolves to the dedicated session, others to their chat', () {
    expect(agentOpensLeadSession(_agent('lead')), isTrue);
    expect(agentOpensLeadSession(_agent('x', lead: true)), isTrue);
    expect(agentOpensLeadSession(_agent('snippet')), isFalse);
  });

  testWidgets('Lead avatar and Ask Lead both resolve to the Lead session',
      (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.reset);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final sem = tester.ensureSemantics();
    final opened = <String>[];
    final lead = _agent('lead', lead: true);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: QuietHomeScreen(
          sessions: const [],
          agents: [lead, _agent('snippet')],
          onOpenSession: (_) {},
          onOpenSessions: () {},
          onSettings: () {},
          onSearch: () {},
          // Mirrors the shell: every agent tap goes through the one opener.
          onOpenAgent: (a) =>
              opened.add(agentOpensLeadSession(a) ? 'lead-session' : a.id),
          onOpenLead: () => opened.add('lead-session'),
        ),
      ),
    ));
    await tester.tap(find.text('lead'));
    await tester.tap(find.text('snippet'));
    expect(opened, ['lead-session', 'snippet']);
    sem.dispose();
    debugDefaultTargetPlatformOverride = null;
  });
}
