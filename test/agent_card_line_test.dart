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

CoordinationAgent _agent(
        {Map<String, dynamic>? last,
        Map<String, dynamic>? presence,
        int needsYou = 0}) =>
    CoordinationAgent.fromJson({
      'id': 'growth',
      'display_name': 'Growth Advisor',
      'handle': 'growth',
      'needs_you': needsYou,
      if (presence != null) 'presence': presence,
      if (last != null) 'last_message': last,
    });

Future<void> _pump(WidgetTester t, CoordinationAgent a,
    {int unread = 0}) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  await t.pumpWidget(MaterialApp(
      home: Scaffold(
          body: AgentCard(
              client: _Client(), agent: a, onOpen: () {}, unread: unread))));
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

  testWidgets('a working agent shows its presence line and the state ring',
      (t) async {
    await _pump(t, _agent(
        last: {'text': 'Claimed the plan task', 'from': 'agent'},
        presence: {'state': 'working', 'detail': 'cargo test'}));
    expect(find.text('Working · cargo test'), findsOneWidget);
    expect(find.text('Claimed the plan task'), findsNothing);
    expect(find.byKey(const ValueKey('agent-working')), findsOneWidget);
  });

  testWidgets('an idle agent falls back to its last message', (t) async {
    await _pump(t, _agent(
        last: {'text': 'Claimed the plan task', 'from': 'agent'},
        presence: {'state': 'idle'}));
    expect(find.text('Claimed the plan task'), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-working')), findsNothing);
  });

  testWidgets('a waiting agent asks for you', (t) async {
    await _pump(t,
        _agent(presence: {'state': 'waiting', 'detail': 'user'}));
    expect(find.text('Waiting on you'), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-working')), findsOneWidget);
  });

  testWidgets('unread shows the dot left of the avatar', (t) async {
    await _pump(t, _agent(), unread: 2);
    expect(find.byKey(const ValueKey('agent-unread-dot')), findsOneWidget);
  });
}
