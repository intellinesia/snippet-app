import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/agent_messaging.dart';
import 'package:snippet/swr.dart';

CoordinationEvent _ev(
  String id,
  int seq,
  String actorKind,
  String body, {
  Map<String, dynamic> extra = const {},
}) => CoordinationEvent.fromJson({
  'event_id': id,
  'thread_id': 'thread',
  'sequence': seq,
  'actor_kind': actorKind,
  'actor_id': actorKind == 'human' ? 'local' : 'growth',
  'idempotency_key': 'k-$id',
  'created_at': DateTime(2026, 11, 12, 10, 0, seq).toIso8601String(),
  'payload': {'body': body, ...extra},
});

class _Client extends DaemonClient {
  _Client(this.page, {this.agents = const []})
    : super('https://daemon.invalid', 'test-token');

  DirectThreadPage page;
  final List<CoordinationAgent> agents;
  final _events = DeviceEventHub.local();

  @override
  DeviceEventHub get deviceEvents => _events;

  @override
  Future<DirectThreadPage> agentThreadPage({
    required String peerId,
    String actorKind = 'human',
    String actorId = 'local',
    int afterSequence = 0,
    int limit = 100,
  }) async => page;

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => agents;

  @override
  Future<List<InboxEntry>> agentInbox(
    String agentId, {
    String? contains,
    String? kind,
    int? before,
    int limit = 50,
  }) async => const [];

  @override
  Future<void> markAgentThreadRead({
    required String peerId,
    String actorKind = 'human',
    String actorId = 'local',
  }) async {}
}

Future<_Client> _open(
  WidgetTester t,
  DirectThreadPage page, {
  List<CoordinationAgent> agents = const [],
  bool embedded = false,
  VoidCallback? onClose,
  Size size = const Size(390, 844),
}) async {
  t.view.physicalSize = size * 3;
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final client = _Client(page, agents: agents);
  await t.pumpWidget(
    MaterialApp(
      home: AgentThreadScreen(
        client: client,
        agentId: 'growth',
        agentName: 'Growth',
        embedded: embedded,
        onClose: onClose,
      ),
    ),
  );
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  return client;
}

void _presence(_Client client, String state, {String agent = 'growth'}) {
  client.presence.handle({
    'kind': 'agent_presence',
    'session': 'session-1',
    'agent': agent,
    'state': state,
    'detail': '',
    'since': DateTime.now().millisecondsSinceEpoch ~/ 1000,
  });
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('long transcript is reversed and opens on the newest message', (
    t,
  ) async {
    final events = [
      for (var i = 1; i <= 80; i++)
        _ev('e$i', i, i.isEven ? 'human' : 'agent', 'message number $i'),
    ];
    await _open(t, DirectThreadPage(events: events));
    final list = t.widget<ListView>(find.byType(ListView).first);
    expect(list.reverse, isTrue);
    final pos = t.state<ScrollableState>(find.byType(Scrollable).first).position;
    expect(pos.pixels, 0);
    expect(find.textContaining('message number 80'), findsOneWidget);
    expect(find.textContaining('message number 1 '), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('presence for another agent does not rebuild message rows', (
    t,
  ) async {
    final deliveries = {
      'h1': MessageDelivery(readAt: DateTime(2026, 11, 12, 10, 0, 2)),
    };
    final client = await _open(
      t,
      DirectThreadPage(
        events: [_ev('h1', 1, 'human', 'hi'), _ev('a1', 2, 'agent', 'yo')],
        deliveries: deliveries,
      ),
    );
    final before = debugAgentMessageRowBuilds;
    expect(before, greaterThan(0));

    _presence(client, 'running', agent: 'other');
    await t.pump();
    expect(debugAgentMessageRowBuilds, before);

    // The reverse case: this agent flipping state only touches the typing slot.
    _presence(client, 'running');
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(debugAgentMessageRowBuilds, before);
    await t.pumpWidget(const SizedBox());
  });
}
