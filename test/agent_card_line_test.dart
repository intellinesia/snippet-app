import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/agent_card.dart';
import 'package:snippet/swr.dart';

class _Client extends DaemonClient {
  _Client() : super('https://daemon.invalid', 'test-token');
  final _events = DeviceEventHub.local();
  @override
  DeviceEventHub get deviceEvents => _events;
}

CoordinationAgent _agent({Map<String, dynamic>? last, int working = 0}) =>
    CoordinationAgent.fromJson({
      'id': 'growth',
      'display_name': 'Growth Advisor',
      'handle': 'growth',
      'task_counts': {'in_progress': working},
      if (last != null) 'last_message': last,
    });

Future<void> _pump(WidgetTester t, CoordinationAgent a) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  await t.pumpWidget(MaterialApp(
      home: Scaffold(body: AgentCard(client: _Client(), agent: a, onOpen: () {}))));
  await t.pump();
  debugDefaultTargetPlatformOverride = null;
}

void main() {
  testWidgets('an agent with no messages says so instead of Available',
      (t) async {
    await _pump(t, _agent());
    expect(find.text('No messages yet'), findsOneWidget);
    expect(find.text('Available'), findsNothing);
    expect(find.byKey(const ValueKey('agent-working')), findsNothing);
  });

  testWidgets('a working agent keeps its last message and gets the working ring',
      (t) async {
    await _pump(t,
        _agent(last: {'text': 'Claimed the plan task', 'from': 'agent'}, working: 1));
    expect(find.text('Claimed the plan task'), findsOneWidget);
    expect(find.text('Working'), findsNothing);
    expect(find.byKey(const ValueKey('agent-ring')), findsOneWidget);
  });

  test('agentRowTime: now under a minute, clock time today, weekday this week', () {
    final n = DateTime(2026, 11, 13, 9, 30);
    expect(agentRowTime(n.subtract(const Duration(seconds: 20)), now: n), 'now');
    expect(agentRowTime(DateTime(2026, 11, 13, 8, 5), now: n), '08:05');
    expect(agentRowTime(DateTime(2026, 11, 12, 18, 36), now: n), 'Thu');
    expect(agentRowTime(DateTime(2026, 10, 2, 18, 36), now: n), '2 Oct');
  });
}
