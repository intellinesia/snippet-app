import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/api.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/models.dart';
import 'package:snippet/phosphor_icons.dart';
import 'package:snippet/screens/agent_view_mode.dart';
import 'package:snippet/screens/agents_sidebar_panel.dart';
import 'package:snippet/theme.dart';

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

  testWidgets(
      'desktop nested sessions stay collapsed until the user expands the row',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    openAgentTab.value = 'a1';
    addTearDown(() => openAgentTab.value = null);
    final session = SessionInfo.fromJson({
      'id': 'nested-1',
      'title': 'Nested QA session',
      'agent_id': 'a1',
      'status': 'idle',
      'last_active': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
    final client = _CustomAgentsClient([
      CoordinationAgent.fromJson({
        'id': 'a1',
        'display_name': 'Builder',
        'handle': 'builder',
        'last_message': {'text': 'Idle snapshot', 'from': 'agent'},
      }),
    ]);
    int? reportedCount;

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AgentsSidebarPanel(
          client: client,
          sessions: [session],
          embedded: true,
          onAgentCountChanged: (n) => reportedCount = n,
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();

    expect(reportedCount, 1);
    expect(find.text('Builder'), findsOneWidget);
    expect(find.text('Nested QA session'), findsNothing);
    expect(
        find.byKey(const ValueKey('agent-expansion-toggle')), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('agent-expansion-toggle')));
    await tester.pump();

    expect(find.text('Nested QA session'), findsOneWidget);
    final chatIcon = tester
        .widget<Icon>(find.byKey(const ValueKey('nested-session-chat-icon')));
    expect(chatIcon.icon, PhIcons.chatText);
    expect(
        tester.getSize(find.byKey(const ValueKey('nested-session-chat-icon'))),
        const Size(12, 12));

    final nestedRow = find.descendant(
        of: find.byKey(const ValueKey('nested-nested-1')),
        matching: find.byType(AnimatedContainer));
    expect(nestedRow, findsOneWidget);
    expect(tester.getSize(nestedRow).height, 26);
    final nestedContainer = tester.widget<AnimatedContainer>(nestedRow);
    expect(nestedContainer.padding, const EdgeInsets.only(left: 36, right: 10));
    final nestedTitle = tester.widget<Text>(find.text('Nested QA session'));
    expect(nestedTitle.style?.fontSize, 12);
    expect(nestedTitle.style?.fontWeight, FontWeight.w400);
    expect(nestedTitle.style?.color, AppColors.fg2);
    final nestedTime = tester.widget<Text>(find.text('now'));
    expect(nestedTime.style?.fontSize, 11);
    expect(nestedTime.style?.fontWeight, FontWeight.w400);
    expect(nestedTime.style?.color, AppColors.fg3);
    debugDefaultTargetPlatformOverride = null;
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

  @override
  Future<List<GroupSummary>> groups() async => const [];

  @override
  Future<List<DirectThreadSummary>> directThreads({
    String actorKind = 'human',
    String actorId = 'local',
  }) async =>
      const [];

  @override
  Future<List<TaskItem>> tasks(
          {String? status, String? agentId, int? limit}) async =>
      const [];
}
