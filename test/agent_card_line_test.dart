import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/api.dart';
import 'package:snippet/crew_status.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/agent_card.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/widgets.dart';

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

CoordinationAgent _scout(Map<String, dynamic>? last) =>
    CoordinationAgent.fromJson({
      'id': 'x-scout',
      'display_name': 'X Scout',
      'handle': 'x_scout',
      if (last != null) 'last_message': last,
    });

Future<void> _pump(WidgetTester t, CoordinationAgent a) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  await t.pumpWidget(MaterialApp(
      home: Scaffold(
          body: AgentCard(client: _Client(), agent: a, onOpen: () {}))));
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

  testWidgets('a working agent keeps its last message and its character works',
      (t) async {
    await _pump(
        t,
        _agent(
            last: {'text': 'Claimed the plan task', 'from': 'agent'},
            working: 1));
    expect(find.text('Claimed the plan task'), findsOneWidget);
    expect(find.text('Working'), findsNothing);
    expect(find.byKey(const ValueKey('agent-avatar-working')), findsOneWidget);
  });

  testWidgets('an agent asking you shows the question, badged', (t) async {
    final a = _agent();
    final ask = SessionInfo.fromJson({
      'id': 's1',
      'title': 'Q3 churn brief',
      'agent_id': 'growth',
      'status': 'waiting_for_input',
      'last_active': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      'attention': {'type': 'question', 'text': 'Which churn figure?'},
    });
    final crew = deriveCrew([a], [ask]).single;
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AgentCard(
                client: _Client(),
                agent: a,
                crew: crew,
                group: AgentGroup.needsYou,
                onOpen: () {}))));
    await t.pump();
    debugDefaultTargetPlatformOverride = null;
    expect(find.text('Asked: Which churn figure?'), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-avatar-needs')), findsOneWidget);
  });

  testWidgets('an idle agent with a past session names it, not "No messages"',
      (t) async {
    final a = _agent();
    final done = SessionInfo.fromJson({
      'id': 's2',
      'title': 'Pricing page',
      'agent_id': 'growth',
      'status': 'waiting_for_input',
      'settled': true,
      'last_active': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
    final crew = CrewEntry(
        agent: a, state: CrewState.standingBy, sessions: [done], lead: done);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await t.pumpWidget(MaterialApp(
        home: Scaffold(
            body: AgentCard(
                client: _Client(), agent: a, crew: crew, onOpen: () {}))));
    await t.pump();
    debugDefaultTargetPlatformOverride = null;
    expect(find.text('Finished Pricing page'), findsOneWidget);
    expect(find.text('No messages yet'), findsNothing);
  });

  test('agentRowTime: now under a minute, clock time today, weekday this week',
      () {
    final n = DateTime(2026, 11, 13, 9, 30);
    expect(
        agentRowTime(n.subtract(const Duration(seconds: 20)), now: n), 'now');
    expect(agentRowTime(DateTime(2026, 11, 13, 8, 5), now: n), '8:05 am');
    expect(agentRowTime(DateTime(2026, 11, 12, 18, 36), now: n), 'Thu');
    expect(agentRowTime(DateTime(2026, 10, 2, 18, 36), now: n), '2 Oct');
  });

  test('withLastMessage swaps the preview and keeps the agent', () {
    final a = CoordinationAgent.fromJson({
      'id': 'scout',
      'display_name': 'X Scout',
      'last_message': {
        'text': 'Posted.',
        'from': 'agent',
        'at': '2026-11-13T08:00:00Z'
      },
    });
    final dm = a.withLastMessage(AgentLastMessage(
        text: 'can you look at this?',
        fromUser: true,
        at: DateTime.utc(2026, 11, 13, 9)));
    expect(dm.id, 'scout');
    expect(dm.displayName, 'X Scout');
    expect(dm.lastMessage?.text, 'can you look at this?');
    expect(dm.lastMessage?.fromUser, isTrue);
    expect(dm.lastMessage?.at, DateTime.utc(2026, 11, 13, 9));
    expect(a.withLastMessage(null).lastMessage, isNull);
  });

  test('an idle agent shows its last message instead of what it finished', () {
    final e = deriveCrew([
      _scout({
        'text': 'Draft is ready.',
        'from': 'agent',
        'at': '2026-11-08T10:00:00Z'
      })
    ], const []).single;
    expect(e.line, 'Draft is ready.');
  });

  test('your own last message is marked as yours', () {
    final e = deriveCrew([
      _scout({'text': 'Check the 320px layout', 'from': 'user'})
    ], const []).single;
    expect(e.line, 'You: Check the 320px layout');
  });

  test('no preview falls back to the old line', () {
    expect(deriveCrew([_scout(null)], const []).single.line, 'Standing by');
    expect(
        deriveCrew([
          _scout({'text': '  ', 'from': 'agent'})
        ], const []).single.line,
        'Standing by');
  });

  testWidgets(
      'desktop row spacing, avatar, preview and expansion chevron match Capy',
      (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    var toggles = 0;
    var opened = false;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 224,
            child: AgentRowShell(
              compact: false,
              avatar: const SizedBox.square(
                  key: ValueKey('test-avatar'), dimension: 28),
              name: 'Sashy',
              preview: 'Running visual QA',
              time: 'now',
              onTap: () => opened = true,
              statusKind: AgentRowStatusKind.running,
              expandable: true,
              onToggleExpansion: () => toggles++,
            ),
          ),
        ),
      ),
    ));
    await t.pump();

    final rowFinder = find.descendant(
        of: find.byType(AgentRowShell),
        matching: find.byType(AnimatedContainer));
    expect(rowFinder, findsOneWidget);
    final row = t.getRect(rowFinder);
    expect(row.height, 48);
    expect(row.left, 8);
    final avatar = t.getRect(find.byKey(const ValueKey('test-avatar')));
    expect(avatar.width, 28);
    expect(avatar.height, 28);
    expect(avatar.left - row.left, 8);
    expect(avatar.top - row.top, 7);
    final status = t.getRect(find.text('Running visual QA'));
    expect(status.top - row.top, closeTo(26, 0.1));

    expect(
        find.byKey(const ValueKey('agent-expansion-toggle')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('agent-expansion-toggle')));
    await t.pump();
    expect(toggles, 1);
    expect(opened, isFalse);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
      'desktop working rows stay one compact line and mark the avatar live',
      (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final a = _agent(
        last: {'text': 'Old direct message', 'from': 'agent'}, working: 1);
    final running = SessionInfo.fromJson({
      'id': 'run-1',
      'title': 'Quiet Build QA',
      'agent_id': 'growth',
      'status': 'running',
      'running': true,
      'last_active': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
    final crew = deriveCrew([a], [running]).single;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AgentCard(
          client: _Client(),
          agent: a,
          crew: crew,
          group: AgentGroup.working,
          onOpen: () {},
        ),
      ),
    ));
    await t.pump();

    expect(find.text('Quiet Build QA'), findsNothing);
    expect(find.text('Old direct message'), findsNothing);
    expect(find.byType(Spinner), findsNothing);
    expect(find.byKey(const ValueKey('agent-live-dot')), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('desktop agent rows carry no needs-you count', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AgentRowShell(
          avatar: const SizedBox.square(dimension: 28),
          name: 'Buddy',
          preview: '',
          onTap: () {},
          statusKind: AgentRowStatusKind.needsYou,
          needsCount: 3,
        ),
      ),
    ));
    await t.pump();
    expect(find.textContaining('needs you'), findsNothing);
    expect(find.byKey(const ValueKey('agent-needs-dot')), findsNothing);
    expect(find.text('Idle'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
