import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/agent_messaging.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/widgets.dart';

CoordinationEvent _ev(
  int n,
  String kind,
  String body, [
  Map<String, dynamic> extra = const {},
]) => CoordinationEvent.fromJson({
  'event_id': 'e$n',
  'sequence': n,
  'actor_kind': kind,
  'idempotency_key': 'k$n',
  'created_at': DateTime.now().toUtc().toIso8601String(),
  'payload': {'body': body, ...extra},
});

class _Client extends DaemonClient {
  _Client(this.thread) : super('https://daemon.invalid', 'test-token');
  final List<CoordinationEvent> thread;
  final _events = DeviceEventHub.local();

  @override
  DeviceEventHub get deviceEvents => _events;

  @override
  Future<List<CoordinationEvent>> agentThread({
    required String peerId,
    String actorKind = 'human',
    String actorId = 'local',
    int afterSequence = 0,
    int limit = 100,
  }) async => thread;
}

Future<void> _open(WidgetTester t, List<CoordinationEvent> thread) async {
  t.view.physicalSize = const Size(390, 844) * 3;
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  await t.pumpWidget(
    MaterialApp(
      home: AgentThreadScreen(
        client: _Client(thread),
        agentId: 'growth',
        agentName: 'Growth',
      ),
    ),
  );
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });

  testWidgets('ack renders as a muted line without a bubble', (t) async {
    await _open(t, [
      _ev(1, 'human', 'hello'),
      _ev(2, 'agent', 'Growth has your message and is working on it.', {
        'auto': 'ack',
      }),
    ]);
    final ack = find.text('Growth has your message and is working on it.');
    expect(ack, findsOneWidget);
    expect(find.ancestor(of: ack, matching: find.byType(Bubble)), findsNothing);
    expect(
      find.text('Working...'),
      findsOneWidget,
      reason: 'ack is not an answer',
    );
    await t.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('non-inbox origin shows a from-task caption', (t) async {
    await _open(t, [
      _ev(1, 'human', 'hello'),
      _ev(2, 'agent', 'done', {
        'origin_session': 'work-7',
        'about_task': 'task-42',
      }),
      _ev(3, 'agent', 'again', {'origin_session': 'inbox-growth'}),
      _ev(4, 'agent', 'other', {'origin_session': 'work-9'}),
    ]);
    expect(find.text('from task task-42'), findsOneWidget);
    expect(find.text('from a work session'), findsOneWidget);
    expect(find.text('Working...'), findsNothing);
    await t.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Working row follows the latest event author', (t) async {
    await _open(t, [_ev(1, 'agent', 'hi'), _ev(2, 'human', 'question')]);
    expect(find.text('Working...'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    await _open(t, [_ev(1, 'human', 'question'), _ev(2, 'agent', 'answer')]);
    expect(find.text('Working...'), findsNothing);
    await t.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
}
