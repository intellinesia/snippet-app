import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/agents_sidebar_panel.dart';
import 'package:snippet/swr.dart';

class _Client extends DaemonClient {
  _Client() : super('https://daemon.invalid', 'test-token');

  final _events = DeviceEventHub.local();

  @override
  DeviceEventHub get deviceEvents => _events;

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => [
        CoordinationAgent.fromJson({
          'id': 'needs',
          'display_name': 'Asks',
          'handle': 'asks',
          'status': 'active',
          'needs_you': 2,
        }),
        CoordinationAgent.fromJson({
          'id': 'busy',
          'display_name': 'Busy',
          'handle': 'busy',
          'status': 'active',
          'presence': {'state': 'working', 'detail': 'cargo test'},
          'last_message': {
            'text': 'hi',
            'from': 'agent',
            'at': '2026-11-12T10:00:00Z'
          },
        }),
        CoordinationAgent.fromJson({
          'id': 'idle',
          'display_name': 'Idle',
          'handle': 'idle',
          'status': 'active',
        }),
      ];

  @override
  Future<List<GroupSummary>> groups() async => [
        GroupSummary.fromJson({
          'id': 'g1',
          'title': 'Unread group',
          'members': const [],
          'unread': 3,
          'last_event_at': '2026-11-12T11:00:00Z',
          'created_at': '2026-11-01T00:00:00Z',
        }),
      ];

  @override
  Future<List<DirectThreadSummary>> directThreads(
          {String actorKind = 'human', String actorId = 'local'}) async =>
      const [];
}

void main() {
  testWidgets('phone roster sections: needs you, working, recent',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        MaterialApp(home: Scaffold(body: AgentsSidebarPanel(client: _Client()))));
    await tester.pumpAndSettle();

    expect(find.text('Needs you'), findsOneWidget);
    expect(find.text('Working'), findsOneWidget);
    expect(find.text('Recent'), findsOneWidget);

    double y(String text) => tester.getTopLeft(find.text(text)).dy;
    // Needs you: the agent with needs_you and the unread group.
    expect(y('Asks'), lessThan(y('Busy')));
    expect(y('Unread group'), lessThan(y('Busy')));
    // Working before Recent.
    expect(y('Busy'), lessThan(y('Idle')));
    // Presence wins the preview over the last message.
    expect(find.text('Working · cargo test'), findsOneWidget);
    expect(find.text('hi'), findsNothing);

    debugDefaultTargetPlatformOverride = null;
  });
}
