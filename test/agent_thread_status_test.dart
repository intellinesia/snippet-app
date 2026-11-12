import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/presence.dart';
import 'package:snippet/screens/agent_messaging.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/widgets.dart';

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
  _Client(this.page) : super('https://daemon.invalid', 'test-token');

  DirectThreadPage page;
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
  Future<List<CoordinationAgent>> coordinationAgents() async => const [];

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

Future<_Client> _open(WidgetTester t, DirectThreadPage page) async {
  t.view.physicalSize = const Size(390, 844) * 3;
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
  final client = _Client(page);
  await t.pumpWidget(
    MaterialApp(
      home: AgentThreadScreen(
        client: client,
        agentId: 'growth',
        agentName: 'Growth',
      ),
    ),
  );
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
  return client;
}

void _presence(_Client client, String state, {String detail = ''}) {
  client.presence.handle({
    'kind': 'agent_presence',
    'session': 'session-1',
    'agent': 'growth',
    'state': state,
    'detail': detail,
    'since': DateTime.now().millisecondsSinceEpoch ~/ 1000,
  });
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('DirectThreadPage parses deliveries', () {
    final page = DirectThreadPage.fromJson({
      'events': [
        {
          'event_id': 'e1',
          'payload': {'body': 'hi'},
        },
      ],
      'deliveries': {
        'e1': {'delivered_at': '2026-11-12T10:00:01Z', 'read_at': null},
      },
    });
    expect(page.events.single.eventId, 'e1');
    expect(
      page.deliveries['e1']!.deliveredAt,
      DateTime.parse('2026-11-12T10:00:01Z'),
    );
    expect(page.deliveries['e1']!.readAt, isNull);
  });

  test('DirectThreadPage tolerates missing deliveries', () {
    final page = DirectThreadPage.fromJson({
      'events': [
        {
          'event_id': 'e1',
          'payload': {'body': 'hi'},
        },
      ],
    });
    expect(page.events, hasLength(1));
    expect(page.deliveries, isEmpty);
  });

  test('PresenceStore.chatWord maps chat states', () {
    expect(PresenceStore.chatWord(const Presence(state: 'running')), 'working');
    expect(
      PresenceStore.chatWord(
        const Presence(state: 'tool', detail: 'Running view_task_board'),
      ),
      'working',
    );
    expect(
      PresenceStore.chatWord(const Presence(state: 'waiting')),
      'waiting on you',
    );
    expect(
      PresenceStore.chatWord(const Presence(state: 'waiting', detail: 'user')),
      'waiting on you',
    );
    expect(
      PresenceStore.chatWord(
        const Presence(state: 'waiting', detail: 'mission-control'),
      ),
      'waiting on mission-control',
    );
    expect(PresenceStore.chatWord(const Presence(state: 'idle')), '');
    expect(PresenceStore.chatWord(const Presence(state: 'thinking')), '');
  });

  testWidgets('sent-only human bubble shows one tick', (t) async {
    await _open(t, DirectThreadPage(events: [_ev('h1', 1, 'human', 'hi')]));
    expect(find.byIcon(Icons.done), findsOneWidget);
    expect(find.byIcon(Icons.done_all), findsNothing);
    final icon = t.widget<Icon>(find.byIcon(Icons.done));
    expect(icon.size, 14);
    expect(icon.color, AppColors.fg3);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('delivered human bubble shows two ticks in fg3', (t) async {
    await _open(
      t,
      DirectThreadPage(
        events: [_ev('h1', 1, 'human', 'hi')],
        deliveries: {
          'h1': MessageDelivery(deliveredAt: DateTime(2026, 11, 12, 10, 0, 2)),
        },
      ),
    );
    expect(find.byIcon(Icons.done), findsNothing);
    expect(find.byIcon(Icons.done_all), findsOneWidget);
    final icon = t.widget<Icon>(find.byIcon(Icons.done_all));
    expect(icon.color, AppColors.fg3);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('read human bubble shows two ticks in accent', (t) async {
    await _open(
      t,
      DirectThreadPage(
        events: [_ev('h1', 1, 'human', 'hi')],
        deliveries: {
          'h1': MessageDelivery(
            deliveredAt: DateTime(2026, 11, 12, 10, 0, 2),
            readAt: DateTime(2026, 11, 12, 10, 0, 3),
          ),
        },
      ),
    );
    expect(find.byIcon(Icons.done_all), findsOneWidget);
    final icon = t.widget<Icon>(find.byIcon(Icons.done_all));
    expect(icon.color, AppColors.accent);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('agent bubble shows time without ticks', (t) async {
    await _open(t, DirectThreadPage(events: [_ev('a1', 1, 'agent', 'hello')]));
    expect(find.text('10:00'), findsOneWidget);
    expect(find.byIcon(Icons.done), findsNothing);
    expect(find.byIcon(Icons.done_all), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('typing row needs a read human message and running presence', (
    t,
  ) async {
    final deliveries = {
      'h1': MessageDelivery(readAt: DateTime(2026, 11, 12, 10, 0, 2)),
    };
    final client = await _open(
      t,
      DirectThreadPage(
        events: [_ev('h1', 1, 'human', 'hi')],
        deliveries: deliveries,
      ),
    );
    expect(find.byKey(const Key('agentTypingRow')), findsNothing);

    _presence(client, 'running');
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('agentTypingRow')), findsOneWidget);
    expect(find.byKey(const Key('agentTypingDots')), findsOneWidget);

    client.page = DirectThreadPage(
      events: [_ev('h1', 1, 'human', 'hi'), _ev('a1', 2, 'agent', 'on it')],
      deliveries: deliveries,
    );
    client.deviceEvents.add({'kind': 'coordination_event'});
    await t.pump(const Duration(milliseconds: 400));
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('agentTypingRow')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('typing row stays hidden before the human message is read', (
    t,
  ) async {
    final client = await _open(
      t,
      DirectThreadPage(
        events: [_ev('h1', 1, 'human', 'hi')],
        deliveries: {
          'h1': MessageDelivery(deliveredAt: DateTime(2026, 11, 12, 10, 0, 2)),
        },
      ),
    );
    _presence(client, 'running');
    await t.pump();
    await t.pump(const Duration(milliseconds: 100));
    expect(find.byKey(const Key('agentTypingRow')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('auto ack renders nothing', (t) async {
    await _open(
      t,
      DirectThreadPage(
        events: [
          _ev(
            'a1',
            1,
            'agent',
            'Growth has your message and is working on it.',
            extra: {'auto': 'ack'},
          ),
        ],
      ),
    );
    expect(
      find.text('Growth has your message and is working on it.'),
      findsNothing,
    );
    expect(find.byType(Bubble), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}
