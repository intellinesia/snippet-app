import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/screens/agents_sidebar_panel.dart';

class _Client extends DaemonClient {
  _Client() : super('https://daemon.invalid', 'test-token');

  final _events = DeviceEventHub.local();

  @override
  DeviceEventHub get deviceEvents => _events;

  CoordinationAgent _agent(String id, String name, String? at) =>
      CoordinationAgent.fromJson({
        'id': id,
        'display_name': name,
        'handle': id,
        'role': 'r',
        'status': 'active',
        if (at != null)
          'last_message': {'text': 'hi', 'from': 'agent', 'at': at},
      });

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => [
        _agent('a', 'Alpha', '2026-11-10T10:00:00Z'),
        _agent('b', 'Bravo', '2026-11-12T10:00:00Z'),
        _agent('c', 'Charlie', null),
      ];

  @override
  Future<List<GroupSummary>> groups() async => [
        GroupSummary.fromJson({
          'id': 'g1',
          'title': 'Crew',
          'members': const [],
          'last_event_at': '2026-11-11T10:00:00Z',
          'created_at': '2026-11-01T00:00:00Z',
        }),
      ];
}

void main() {
  testWidgets('agents and groups share one list, newest first', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: AgentsSidebarPanel(client: _Client()))));
    await tester.pumpAndSettle();
    // v5 groups the phone list; everything here is Recent, agents newest
    // first, then groups.
    expect(find.text('Recent'), findsOneWidget);
    final ys = [
      for (final t in ['Bravo', 'Alpha', 'Charlie', 'Crew'])
        tester.getTopLeft(find.text(t)).dy
    ];
    expect(ys, [...ys]..sort());
    expect(find.text('GROUPS'), findsNothing);
    expect(find.text('Groups'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
