import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/api.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/agents_sidebar_panel.dart';

/// The agents panel must read like every other sidebar panel.
///
/// It did not: it drew its own 15px title while Terminals, Git Diff and the file
/// tree all render the shared `ShellSectionHeader`, and its row names were
/// hard-coded `W.label` while the canonical `ShellNavRow` is
/// `selected ? W.label : W.body`. So an idle agent was heavier than an idle
/// session in the same rail — which is what "looks like it had bold font"
/// describes. `flutter analyze` cannot see any of it.
void main() {
  testWidgets(
      'tapping agent name opens agent conversation even if agent has sessions',
      (tester) async {
    CoordinationAgent? openedAgent;
    final assignedClient = _CustomAgentsClient([
      CoordinationAgent.fromJson({
        'id': 'a1',
        'display_name': 'Builder',
        'handle': 'builder',
        'role': 'developer',
        'status': 'active',
        'assigned_sessions': [
          {
            'id': 's1',
            'title': 'feature/auth',
            'conversation': 'feature/auth',
            'last_active': 1000,
          },
        ],
      }),
    ]);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AgentsSidebarPanel(
          client: assignedClient,
          onOpenAgent: (a) => openedAgent = a,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    // The team view names the agent in its hero and in its row; tap the row.
    final agentRow = find.descendant(
        of: find.byKey(const ValueKey('agent-card-a1')),
        matching: find.text('Builder'));
    expect(agentRow, findsOneWidget);
    await tester.tap(agentRow);
    await tester.pumpAndSettle();

    expect(openedAgent, isNotNull);
    expect(openedAgent?.id, 'a1');
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 11));
  });

}

class _CustomAgentsClient extends DaemonClient {
  final List<CoordinationAgent> _agents;
  _CustomAgentsClient(this._agents)
      : super('https://daemon.invalid', 'test-token');

  final _deviceEvents = DeviceEventHub.local();

  @override
  DeviceEventHub get deviceEvents => _deviceEvents;

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => _agents;
}
