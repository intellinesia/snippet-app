import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:snippet/api.dart';
import 'package:snippet/chat/chat_style.dart';
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
        const Presence(state: 'waiting', detail: 'mission-control'),
      ),
      'waiting on mission-control',
    );
    expect(PresenceStore.chatWord(const Presence(state: 'idle')), '');
    expect(PresenceStore.chatWord(const Presence(state: 'thinking')), '');
  });

  testWidgets('sent-only human bubble shows no ticks or delivery line',
      (t) async {
    await _open(t, DirectThreadPage(events: [_ev('h1', 1, 'human', 'hi')]));
    expect(find.byIcon(Icons.done), findsNothing);
    expect(find.byIcon(Icons.done_all), findsNothing);
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

  testWidgets('agent bubble omits per-bubble time and groups runs with stamps',
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
    final bubbles = t.widgetList<ChatBubble>(find.byType(ChatBubble)).toList();
    expect(bubbles, hasLength(2));
    expect(bubbles[0].tail, isFalse);
    expect(bubbles[1].tail, isTrue);
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
    final bubbles = t.widgetList<ChatBubble>(find.byType(ChatBubble)).toList();
    expect(bubbles, hasLength(3));
    expect(bubbles.every((b) => b.tail), isTrue);
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
    expect(
      find.descendant(
        of: find.byKey(const Key('agentTypingRow')),
        matching: find.byType(ChatBubble),
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

  testWidgets('phone header has no back or tasks button', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final agent = CoordinationAgent.fromJson({
        'id': 'growth',
        'display_name': 'Growth',
        'task_counts': {
          'todo': 1,
          'in_progress': 2,
          'in_review': 0,
          'blocked': 0,
          'done': 4,
        },
      });
      await _open(t, DirectThreadPage(events: const []), agents: [agent]);
      expect(find.byType(ChatHeader), findsOneWidget);
      expect(ChatHeader.overlap, 92);
      expect(t.widget<MochiDisc>(find.byType(MochiDisc)).size, 36);
      final tasksBtn = find.byWidgetPredicate(
        (w) => w is ChatGlassButton && w.icon == 'task',
      );
      expect(tasksBtn, findsNothing);
      expect(find.byType(ChatGlassButton), findsNothing);
      await t.pumpWidget(const SizedBox());
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('desktop header shows switcher button and optional close', (
    t,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      var closed = false;
      await _open(
        t,
        DirectThreadPage(events: const []),
        size: const Size(1280, 800),
        onClose: () => closed = true,
      );
      expect(find.byType(ChatHeader), findsOneWidget);
      expect(
        find.byWidgetPredicate(
          (w) => w is ChatGlassButton && w.icon == 'layers',
        ),
        findsOneWidget,
      );
      final closeBtn = find.byWidgetPredicate(
        (w) => w is ChatGlassButton && w.icon == 'x',
      );
      expect(closeBtn, findsOneWidget);
      await t.tap(closeBtn);
      await t.pump();
      expect(closed, isTrue);
      await t.pumpWidget(const SizedBox());
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('embedded mode hides ChatHeader', (t) async {
    await _open(t, DirectThreadPage(events: const []), embedded: true);
    expect(find.byType(ChatHeader), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}
