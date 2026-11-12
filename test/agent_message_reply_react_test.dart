import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:snippet/api.dart';
import 'package:snippet/composer/composer_card.dart';
import 'package:snippet/message_reactions.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/agent_messaging.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/widgets.dart';

CoordinationEvent _ev(
  String id,
  int seq,
  String actorKind,
  String body, {
  String actorId = '',
  Map<String, dynamic> extra = const {},
}) =>
    CoordinationEvent.fromJson({
      'event_id': id,
      'sequence': seq,
      'actor_kind': actorKind,
      'actor_id': actorId.isEmpty
          ? (actorKind == 'human' ? 'local' : 'growth')
          : actorId,
      'idempotency_key': 'k-$id',
      'created_at': DateTime.utc(2026, 11, 12, 10, 0, seq).toIso8601String(),
      'payload': {'body': body, ...extra},
    });

class _FakeClient extends DaemonClient {
  _FakeClient(this.thread) : super('https://daemon.invalid', 'test-token');

  final List<CoordinationEvent> thread;
  final List<Map<String, String?>> sent = [];
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
  }) async =>
      List<CoordinationEvent>.of(thread);

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => const [];

  @override
  Future<List<InboxEntry>> agentInbox(
    String agentId, {
    String? contains,
    String? kind,
    int? before,
    int limit = 50,
  }) async =>
      const [];

  @override
  Future<void> markAgentThreadRead({
    required String peerId,
    String actorKind = 'human',
    String actorId = 'local',
  }) async {}

  @override
  Future<CoordinationEvent> sendAgentMessage({
    required String toAgentId,
    required String body,
    String fromKind = 'human',
    String fromId = 'local',
    String? idempotencyKey,
    String? originSession,
    String? replyTo,
    String? reaction,
  }) async {
    sent.add({
      'to': toAgentId,
      'body': body,
      'reply_to': replyTo,
      'reaction': reaction,
    });
    final ev = _ev(
      'sent-${sent.length}',
      thread.length + 1,
      fromKind,
      body,
      actorId: fromId,
      extra: {
        if (replyTo != null) 'reply_to': replyTo,
        if (reaction != null) ...{'kind': 'reaction', 'reaction': reaction},
      },
    );
    thread.add(ev);
    return ev;
  }
}

Future<void> _open(
  WidgetTester t,
  _FakeClient client, {
  Size size = const Size(390, 844),
}) async {
  t.view.physicalSize = size * 3;
  t.view.devicePixelRatio = 3;
  addTearDown(t.view.reset);
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
}

Future<void> _pumpFrames(WidgetTester t, [int n = 6]) async {
  for (var i = 0; i < n; i++) {
    await t.pump(const Duration(milliseconds: 60));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('CoordinationEvent getters and sendAgentMessage serialize reply_to and reaction',
      () async {
    final ev = CoordinationEvent.fromJson({
      'event_id': 'e9',
      'payload': {
        'body': '',
        'kind': 'reaction',
        'reply_to': 'e1',
        'reaction': 'check',
      },
    });
    expect(ev.replyTo, 'e1');
    expect(ev.reaction, 'check');

    final oldOverrides = HttpOverrides.current;
    HttpOverrides.global = null;
    addTearDown(() => HttpOverrides.global = oldOverrides);

    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    Map<String, dynamic>? posted;
    server.listen((req) async {
      req.response.persistentConnection = false;
      final raw = await utf8.decoder.bind(req).join();
      posted = jsonDecode(raw) as Map<String, dynamic>;
      req.response
        ..statusCode = 202
        ..headers.contentType = ContentType.json
        ..write(jsonEncode({'event_id': 'e10', 'payload': posted}));
      await req.response.close();
    });
    final client = DaemonClient('http://127.0.0.1:${server.port}', 'tok');
    await client.sendAgentMessage(
      toAgentId: 'growth',
      body: '',
      replyTo: 'e1',
      reaction: 'thumbs_up',
    );
    expect(posted?['reply_to'], 'e1');
    expect(posted?['reaction'], 'thumbs_up');
  });

  testWidgets(
      'reply renders quoted line and two reactions on one message render one chip with count 2 and no extra bubbles',
      (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final client = _FakeClient([
        _ev('m1', 1, 'agent', 'Should we ship the new onboarding copy today?'),
        _ev('m2', 2, 'human', 'Yes, ship it after CI finishes.', extra: {
          'reply_to': 'm1',
        }),
        _ev('r1', 3, 'human', '', actorId: 'local', extra: {
          'kind': 'reaction',
          'reply_to': 'm1',
          'reaction': 'check',
        }),
        _ev('r2', 4, 'agent', '', actorId: 'growth', extra: {
          'kind': 'reaction',
          'reply_to': 'm1',
          'reaction': 'check',
        }),
      ]);

      await _open(t, client);

      // Only the 2 real messages render as Bubble widgets; the 2 reactions fold.
      expect(find.byType(Bubble), findsNWidgets(2));

      // The reply renders a QuotedReplyLine with the target message text.
      final quoted = find.byType(QuotedReplyLine);
      expect(quoted, findsOneWidget);
      expect(
        find.descendant(
          of: quoted,
          matching: find.text('Should we ship the new onboarding copy today?'),
        ),
        findsOneWidget,
      );

      // Two `check` reactions on `m1` render one reaction chip with count 2.
      final chips = find.byType(MessageReactionChips);
      expect(chips, findsOneWidget);
      expect(
        find.descendant(of: chips, matching: find.text('2')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: chips, matching: find.byType(AppIcon)),
        findsOneWidget,
      );

      await t.pumpWidget(const SizedBox());
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      'long-press offers Reply and 5 icon reactions; Reply sets banner, clear and send pass reply_to',
      (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final client = _FakeClient([
        _ev('m1', 1, 'agent', 'Ready for review on branch feat/x.'),
      ]);
      await _open(t, client);

      await t.longPress(find.text('Ready for review on branch feat/x.'));
      await _pumpFrames(t);

      expect(find.byType(MessageActionRow), findsOneWidget);
      expect(find.text('Reply'), findsOneWidget);
      // 1 reply icon + 5 reaction icons inside the action row, never emoji.
      expect(
        find.descendant(
          of: find.byType(MessageActionRow),
          matching: find.byType(AppIcon),
        ),
        findsNWidgets(6),
      );

      // Tap Reply -> pending reply banner appears above composer.
      await t.tap(find.text('Reply'));
      await _pumpFrames(t);
      expect(find.byType(PendingReplyBanner), findsOneWidget);
      expect(find.text('Replying to Growth'), findsOneWidget);

      // Clear button dismisses the pending reply.
      await t.tap(find.byTooltip('Clear reply'));
      await _pumpFrames(t);
      expect(find.byType(PendingReplyBanner), findsNothing);

      // Long-press again, choose Reply, and send a message -> passes reply_to.
      await t.longPress(find.text('Ready for review on branch feat/x.'));
      await _pumpFrames(t);
      await t.tap(find.text('Reply'));
      await _pumpFrames(t);

      await t.enterText(find.byType(TextField), 'Looks good to merge');
      await t.pump();
      await t.tap(find.byType(ComposerSendButton));
      await _pumpFrames(t);

      expect(client.sent.length, 1);
      expect(client.sent.single['body'], 'Looks good to merge');
      expect(client.sent.single['reply_to'], 'm1');
      expect(client.sent.single['reaction'], isNull);
      expect(find.byType(PendingReplyBanner), findsNothing);

      await t.pumpWidget(const SizedBox());
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('desktop hover shows action row and sends icon reaction immediately',
      (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final client = _FakeClient([
        _ev('m1', 1, 'agent', 'Finished running benchmarks.'),
      ]);
      await _open(t, client, size: const Size(1280, 800));

      expect(find.byType(MessageActionRow), findsNothing);

      final gesture = await t.createGesture(kind: PointerDeviceKind.mouse);
      await gesture.addPointer(location: Offset.zero);
      addTearDown(gesture.removePointer);
      await t.pump();

      await gesture
          .moveTo(t.getCenter(find.text('Finished running benchmarks.')));
      await _pumpFrames(t);

      expect(find.byType(MessageActionRow), findsOneWidget);

      await t.tap(find.byTooltip('Eyes'));
      await _pumpFrames(t);

      expect(client.sent.length, 1);
      expect(client.sent.single['reply_to'], 'm1');
      expect(client.sent.single['reaction'], 'eyes');
      expect(client.sent.single['body'], '');
      expect(find.byType(MessageReactionChips), findsOneWidget);

      await t.pumpWidget(const SizedBox());
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('tapping a quoted reply line scrolls back to the target message',
      (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final items = <CoordinationEvent>[
        _ev('m0', 1, 'agent', 'Initial spec note at top of thread.'),
        for (var i = 1; i <= 24; i++)
          _ev('f$i', i + 1, i.isEven ? 'agent' : 'human',
              'Filler message number $i with enough text to scroll vertically.'),
        _ev('mLast', 26, 'human', 'Replying to the very first note.', extra: {
          'reply_to': 'm0',
        }),
      ];
      final client = _FakeClient(items);
      await _open(t, client);

      expect(find.byType(QuotedReplyLine), findsOneWidget);
      expect(
        find.ancestor(
          of: find.text('Initial spec note at top of thread.'),
          matching: find.byType(Bubble),
        ),
        findsNothing,
      );

      await t.tap(find.byType(QuotedReplyLine));
      await _pumpFrames(t, 10);

      expect(
        find.ancestor(
          of: find.text('Initial spec note at top of thread.'),
          matching: find.byType(Bubble),
        ),
        findsOneWidget,
      );

      await t.pumpWidget(const SizedBox());
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
