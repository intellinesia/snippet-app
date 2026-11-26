import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/phosphor_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:snippet/api.dart';
import 'package:snippet/mochi.dart';
import 'package:snippet/chat/chat_style.dart';
import 'package:snippet/chat/run_head.dart';
import 'package:snippet/models.dart';
import 'package:snippet/presence.dart';
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
    int? beforeSequence,
    bool latest = false,
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
        const Presence(state: 'waiting', detail: 'lead'),
      ),
      'waiting on lead',
    );
    expect(PresenceStore.chatWord(const Presence(state: 'idle')), '');
    expect(PresenceStore.chatWord(const Presence(state: 'thinking')), '');
  });

  testWidgets('sent-only human bubble shows no ticks or delivery line',
      (t) async {
    await _open(t, DirectThreadPage(events: [_ev('h1', 1, 'human', 'hi')]));
    expect(find.byIcon(PhIcons.checkCircle), findsNothing);
    expect(find.text('Delivered'), findsNothing);
    expect(find.textContaining('Read '), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('delivered human bubble shows Delivered only on last human message',
      (t) async {
    await _open(
      t,
      DirectThreadPage(
        events: [
          _ev('h1', 1, 'human', 'first'),
          _ev('h2', 2, 'human', 'second'),
        ],
        deliveries: {
          'h1': MessageDelivery(
            deliveredAt: DateTime(2026, 11, 12, 10, 0, 2),
            readAt: DateTime(2026, 11, 12, 10, 0, 3),
          ),
          'h2': MessageDelivery(deliveredAt: DateTime(2026, 11, 12, 10, 0, 4)),
        },
      ),
    );
    expect(find.text('Delivered'), findsOneWidget);
    expect(find.textContaining('Read '), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('read human bubble shows Read time under last human message',
      (t) async {
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
    expect(find.text('Read 10:00 am'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('flat agent prose groups runs with stamps',
      (t) async {
    await _open(
      t,
      DirectThreadPage(events: [
        _ev('a1', 1, 'agent', 'hello'),
        _ev('a2', 2, 'agent', 'second'),
      ]),
    );
    expect(find.text('10:00'), findsNothing);
    expect(find.byType(ChatSystemLine), findsOneWidget);
    // The list is reversed, so build order runs newest first.
    final rows =
        t.widgetList<SoftLane>(find.byType(SoftLane)).toList().reversed.toList();
    expect(rows, hasLength(2));
    expect(rows[0].first, isTrue);
    expect(rows[0].last, isFalse);
    expect(rows[1].first, isFalse);
    expect(rows[1].last, isTrue);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('15-minute gap and day change insert ChatSystemLine stamps',
      (t) async {
    final now = DateTime.now();
    final yesterday = DateTime(now.year, now.month, now.day - 1, 22, 15);
    final todayMorning = DateTime(now.year, now.month, now.day, 9, 0);
    final todayLater = DateTime(now.year, now.month, now.day, 9, 20);
    CoordinationEvent at(String id, int seq, String kind, DateTime ts) =>
        CoordinationEvent.fromJson({
          'event_id': id,
          'thread_id': 'thread',
          'sequence': seq,
          'actor_kind': kind,
          'actor_id': kind == 'human' ? 'local' : 'growth',
          'idempotency_key': 'k-$id',
          'created_at': ts.toUtc().toIso8601String(),
          'payload': {'body': 'msg $id'},
        });

    await _open(
      t,
      DirectThreadPage(events: [
        at('1', 1, 'agent', yesterday),
        at('2', 2, 'agent', todayMorning),
        at('3', 3, 'agent', todayLater),
      ]),
    );
    expect(find.text('Yesterday 10:15 pm'), findsOneWidget);
    expect(find.text('Today 9:00 am'), findsOneWidget);
    expect(find.text('Today 9:20 am'), findsOneWidget);
    final rows = t.widgetList<SoftLane>(find.byType(SoftLane)).toList();
    expect(rows, hasLength(3));
    expect(rows.every((r) => r.first && r.last), isTrue);
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
    // Phone typing is an avatar, a 74 x 28 pill and a line, not a bubble.
    expect(
      find.descendant(
        of: find.byKey(const Key('agentTypingRow')),
        matching: find.byType(AgentMochi),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(
        of: find.byKey(const Key('agentTypingRow')),
        matching: find.text('Growth'),
      ),
      findsNothing,
    );

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
    expect(find.byType(ChatBubble), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

}
