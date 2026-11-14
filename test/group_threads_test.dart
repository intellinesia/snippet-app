import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:snippet/api.dart';
import 'package:snippet/composer/voice_note.dart';
import 'package:snippet/models.dart';
import 'package:snippet/mochi.dart';
import 'package:snippet/screens/agent_questions_card.dart';
import 'package:snippet/screens/agent_thread_cards.dart';
import 'package:snippet/screens/artifact_viewer.dart';
import 'package:snippet/screens/group_messaging.dart';
import 'package:snippet/screens/session.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/chat/chat_style.dart';
import 'package:snippet/message_reactions.dart';
import 'package:snippet/theme.dart';

void main() {
  group('GroupSummary', () {
    test('parses the wire shape', () {
      final g = GroupSummary.fromJson({
        'id': 'g1',
        'title': 'Launch',
        'members': [
          {'kind': 'agent', 'id': 'argon'},
          {'kind': 'agent', 'id': 'fable'},
          {'kind': 'human', 'id': 'local'},
        ],
        'lead': 'argon',
        'created_at': '2026-11-12T10:00:00Z',
        'last_event_at': '2026-11-12T11:00:00Z',
        'unread': 3,
      });
      expect(g.id, 'g1');
      expect(g.title, 'Launch');
      expect(g.members, hasLength(3));
      expect(g.agentIds, ['argon', 'fable']);
      expect(g.lead, 'argon');
      expect(g.lastEventAt, '2026-11-12T11:00:00Z');
      expect(g.unread, 3);
      expect(g.hasUnread, isTrue);
    });

    test('tolerates missing fields', () {
      final g = GroupSummary.fromJson({'id': 'g2'});
      expect(g.members, isEmpty);
      expect(g.lead, isNull);
      expect(g.unread, 0);
    });
  });

  group('extractGroupMentions', () {
    const ids = {'argon', 'fable'};

    test('finds member tokens in order, once each', () {
      expect(
        extractGroupMentions('hey @argon and @fable, @argon again', ids),
        ['argon', 'fable'],
      );
    });

    test('keeps everyone and drops non-members', () {
      expect(
        extractGroupMentions('@everyone please review @nobody', ids),
        ['everyone'],
      );
    });

    test('ignores mid-word and unknown tokens', () {
      expect(
        extractGroupMentions('mail@argon is not a mention, @zed is', ids),
        isEmpty,
      );
    });
  });

  group('groupMarkdownWithMentions', () {
    const ids = {'argon', 'fable'};
    test('bolds member mentions and leaves code alone', () {
      expect(
        groupMarkdownWithMentions(
            'hi @argon, see `@fable` and **done**\n```\n@argon\n```', ids),
        'hi **@argon**, see `@fable` and **done**\n```\n@argon\n```',
      );
      expect(groupMarkdownWithMentions('@nobody here', ids), '@nobody here');
    });
  });

  group('GroupThreadScreen', () {
    setUp(() {
      SharedPreferences.setMockInitialValues({});
    });

    testWidgets('agent event shows sender name and highlights a mention',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final group = GroupSummary.fromJson({
        'id': 'g1',
        'title': 'Launch',
        'members': [
          {'kind': 'agent', 'id': 'argon'},
          {'kind': 'agent', 'id': 'fable'},
          {'kind': 'human', 'id': 'local'},
        ],
        'lead': 'argon',
      });
      final client = _GroupClient([
        CoordinationEvent.fromJson({
          'event_id': 'e1',
          'sequence': 1,
          'actor_kind': 'agent',
          'actor_id': 'argon',
          'idempotency_key': 'k1',
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'payload': {'body': 'shipping today, @fable owns the notes'},
        }),
      ]);

      await tester.pumpWidget(MaterialApp(
        home: GroupThreadScreen(client: client, group: group),
      ));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(
        find.descendant(
          of: find.byType(ChatSenderName),
          matching: find.text('Argon'),
        ),
        findsOneWidget,
      );

      final body = tester.widgetList<Text>(find.byType(Text)).firstWhere(
        (t) => t.textSpan?.toPlainText().contains('@fable') ?? false,
      );
      final mention = _findSpan(body.textSpan!, '@fable');
      expect(mention, isNotNull);
      expect(mention!.style?.color, ChatColors.receivedText);
      expect(mention.style?.fontWeight, FontWeight.w500);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('a reaction on a post renders as a chip, not a message',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final group = GroupSummary.fromJson({
        'id': 'g1',
        'title': 'Launch',
        'members': [
          {'kind': 'agent', 'id': 'argon'},
          {'kind': 'human', 'id': 'local'},
        ],
      });
      final at = DateTime.now().toUtc().toIso8601String();
      final client = _GroupClient([
        CoordinationEvent.fromJson({
          'event_id': 'e1',
          'sequence': 1,
          'event_type': 'group_message',
          'actor_kind': 'agent',
          'actor_id': 'argon',
          'idempotency_key': 'k1',
          'created_at': at,
          'payload': {'body': 'shipped'},
        }),
        CoordinationEvent.fromJson({
          'event_id': 'e2',
          'sequence': 2,
          'event_type': 'group_message',
          'actor_kind': 'human',
          'actor_id': 'human',
          'idempotency_key': 'k2',
          'created_at': at,
          'payload': {
            'body': '',
            'kind': 'reaction',
            'reaction': 'thumbs_up',
            'reply_to': 'e1',
            'in_reply_to': 'e1',
          },
        }),
      ]);

      await tester.pumpWidget(MaterialApp(
        home: GroupThreadScreen(client: client, group: group),
      ));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('shipped'), findsOneWidget);
      expect(find.byType(MessageReactionChips), findsOneWidget);
      expect(find.byType(ChatBubble), findsOneWidget,
          reason: 'the reaction is a chip on the post, not its own bubble');
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('header typing status, runs, system lines and read receipts',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final group = GroupSummary.fromJson({
        'id': 'g1',
        'title': 'Launch',
        'members': [
          {'kind': 'agent', 'id': 'argon'},
          {'kind': 'agent', 'id': 'fable'},
          {'kind': 'human', 'id': 'local'},
        ],
        'lead': 'argon',
      });
      final t0 = DateTime.now().toUtc();
      final client = _GroupClient([
        CoordinationEvent.fromJson({
          'event_id': 'e1',
          'sequence': 1,
          'actor_kind': 'agent',
          'actor_id': 'argon',
          'idempotency_key': 'k1',
          'created_at': t0.toIso8601String(),
          'payload': {'body': 'On it.', 'auto': 'ack'},
        }),
        CoordinationEvent.fromJson({
          'event_id': 'e2',
          'sequence': 2,
          'actor_kind': 'agent',
          'actor_id': 'argon',
          'idempotency_key': 'k2',
          'created_at': t0.add(const Duration(minutes: 1)).toIso8601String(),
          'payload': {'body': 'First message in run'},
        }),
        CoordinationEvent.fromJson({
          'event_id': 'e3',
          'sequence': 3,
          'actor_kind': 'agent',
          'actor_id': 'argon',
          'idempotency_key': 'k3',
          'created_at': t0.add(const Duration(minutes: 2)).toIso8601String(),
          'payload': {'body': 'Second message in run'},
        }),
        CoordinationEvent.fromJson({
          'event_id': 'e4',
          'sequence': 4,
          'actor_kind': 'human',
          'actor_id': 'local',
          'idempotency_key': 'k4',
          'created_at': t0.add(const Duration(minutes: 3)).toIso8601String(),
          'payload': {
            'body': 'Thanks @argon',
            'read_by': ['argon', 'fable'],
          },
        }),
      ]);

      await tester.pumpWidget(MaterialApp(
        home: GroupThreadScreen(client: client, group: group),
      ));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byType(ChatHeader), findsOneWidget);
      expect(find.text('Argon and Fable'), findsOneWidget);
      expect(find.byType(ChatSenderName), findsOneWidget);
      expect(find.byType(ChatBubble), findsNWidgets(3));
      expect(find.textContaining('Read by Argon and Fable'), findsOneWidget);

      client.presence.handle({
        'kind': 'agent_presence',
        'session': 's1',
        'agent': 'argon',
        'state': 'typing',
        'detail': '',
        'since': DateTime.now().millisecondsSinceEpoch ~/ 1000,
      });
      await tester.pump();
      expect(find.text('Argon is typing'), findsOneWidget);

      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
        'sending a confirmed voice note uploads it and posts the marker',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final group = GroupSummary.fromJson({
        'id': 'g1',
        'title': 'Launch',
        'members': [
          {'kind': 'agent', 'id': 'argon'},
          {'kind': 'human', 'id': 'local'},
        ],
      });
      final client = _GroupClient([]);
      final voice = VoiceNoteController(client: client);
      addTearDown(voice.dispose);

      await tester.pumpWidget(MaterialApp(
        home: GroupThreadScreen(
          client: client,
          group: group,
          voiceController: voice,
        ),
      ));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      voice.debugSeedTake(Uint8List.fromList([1, 2, 3, 4]));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      expect(find.byType(VoiceNoteRecorderStrip), findsOneWidget);
      await tester.tap(find.bySemanticsLabel('Send voice note'));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 60));
      }

      expect(client.uploads, hasLength(1));
      expect(client.posted, hasLength(1));
      expect(
        client.posted.single.body,
        contains('[attached file — read it at this exact path:'),
      );
      expect(voice.hasTake, isFalse);

      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('approval payload renders DeskApprovalCard without a bubble',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final ch = _FakeWsChannel();
      DaemonClient.wsConnector = (uri, {connectTimeout, pingInterval}) {
        Timer(const Duration(milliseconds: 10),
            () => ch.incoming.add('{"wire":"snapshot"}'));
        return ch;
      };
      addTearDown(() => DaemonClient.wsConnector = null);

      final group = GroupSummary.fromJson({
        'id': 'g-approval',
        'title': 'Launch',
        'members': [
          {'kind': 'agent', 'id': 'argon'},
          {'kind': 'human', 'id': 'local'},
        ],
      });
      final client = _GroupClient([
        CoordinationEvent.fromJson({
          'event_id': 'e-app',
          'sequence': 1,
          'event_type': 'group_message',
          'actor_kind': 'agent',
          'actor_id': 'argon',
          'idempotency_key': 'ka1',
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'payload': {
            'body': 'Approval needed: run tests',
            'approval': {
              'session': 'sess-app-1',
              'approval_id': 'attn-app-1',
              'tool': 'bash',
              'summary': 'cargo test --lib',
              'task_id': 't1',
              'task_title': 'Auth fix',
              'session_title': 'Worker session',
            },
          },
        }),
      ]);

      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: GroupThreadScreen(client: client, group: group),
      ));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byType(DeskApprovalCard), findsOneWidget);
      expect(find.byType(ChatBubble), findsNothing);
      expect(
        find.descendant(
          of: find.byType(ChatSenderName),
          matching: find.text('Argon'),
        ),
        findsOneWidget,
      );
      expect(find.byType(AgentMochi), findsWidgets);
      expect(find.text('Auth fix · Worker session'), findsOneWidget);

      await tester.tap(find.text('Approve'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      final sent = jsonDecode(ch.sent.single as String) as Map;
      expect(sent['kind'], 'approve');
      expect(find.text('Approved'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
        'session question payload renders AgentQuestionsCard and quickSends',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final ch = _FakeWsChannel();
      Uri? wsUri;
      DaemonClient.wsConnector = (uri, {connectTimeout, pingInterval}) {
        wsUri = uri;
        Timer(const Duration(milliseconds: 10),
            () => ch.incoming.add('{"wire":"snapshot"}'));
        return ch;
      };
      addTearDown(() => DaemonClient.wsConnector = null);

      final group = GroupSummary.fromJson({
        'id': 'g-question',
        'title': 'Launch',
        'members': [
          {'kind': 'agent', 'id': 'argon'},
          {'kind': 'agent', 'id': 'fable'},
          {'kind': 'human', 'id': 'local'},
        ],
      });
      final at = DateTime.now().toUtc().toIso8601String();
      final client = _GroupClient([
        CoordinationEvent.fromJson({
          'event_id': 'e-q1',
          'sequence': 1,
          'event_type': 'group_message',
          'actor_kind': 'agent',
          'actor_id': 'argon',
          'idempotency_key': 'kq1',
          'created_at': at,
          'payload': {
            'body': 'Which environment?',
            'question': {
              'session': 'sess-q-1',
              'question_id': 'attn-q-1',
              'task_id': 't-q1',
              'task_title': 'Deploy job',
              'questions': [
                {
                  'id': 'env',
                  'text': 'Which environment?',
                  'answer_kind': {
                    'kind': 'single_choice',
                    'choices': [
                      {'value': 'staging', 'label': 'Staging', 'recommended': true},
                      {'value': 'prod', 'label': 'Production'},
                    ],
                  },
                },
              ],
            },
          },
        }),
        CoordinationEvent.fromJson({
          'event_id': 'e-fable',
          'sequence': 2,
          'event_type': 'group_message',
          'actor_kind': 'agent',
          'actor_id': 'fable',
          'idempotency_key': 'kq2',
          'created_at': at,
          'payload': {'body': 'Standing by while you pick.'},
        }),
      ]);

      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: GroupThreadScreen(client: client, group: group),
      ));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byType(AgentQuestionsCard), findsOneWidget);
      expect(find.byType(ChatBubble), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(ChatSenderName),
          matching: find.text('Argon'),
        ),
        findsOneWidget,
      );
      expect(find.text('Deploy job'), findsOneWidget);

      await tester.tap(find.text('Production'));
      await tester.pump();
      await tester.tap(find.text('Send'));
      await tester.pump(const Duration(milliseconds: 50));
      await tester.pump(const Duration(milliseconds: 50));

      expect(wsUri?.queryParameters['session'], 'sess-q-1');
      final sent = jsonDecode(ch.sent.single as String) as Map;
      expect(sent['kind'], 'answer');
      expect(sent['value'], 'Which environment?\n→ Production (prod)');
      expect(find.text('Answered: Production'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets(
        'task_result payload renders TaskResultCard and tap opens session',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final ch = _FakeWsChannel();
      DaemonClient.wsConnector = (_, {connectTimeout, pingInterval}) => ch;
      addTearDown(() => DaemonClient.wsConnector = null);

      final group = GroupSummary.fromJson({
        'id': 'g-result',
        'title': 'Launch',
        'members': [
          {'kind': 'agent', 'id': 'argon'},
          {'kind': 'human', 'id': 'local'},
        ],
      });
      final client = _GroupClient([
        CoordinationEvent.fromJson({
          'event_id': 'e-res',
          'sequence': 1,
          'event_type': 'group_message',
          'actor_kind': 'agent',
          'actor_id': 'argon',
          'idempotency_key': 'kr1',
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'payload': {
            'body': 'Task finished: Build API',
            'task_result': {
              'task_id': 't-res-1',
              'title': 'Build API',
              'status': 'done',
              'summary': 'Shipped **v2** endpoint.',
              'session_id': 'sess-res-1',
            },
          },
        }),
      ]);

      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: GroupThreadScreen(client: client, group: group),
      ));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byType(TaskResultCard), findsOneWidget);
      expect(find.byType(ChatBubble), findsNothing);
      expect(
        find.descendant(
          of: find.byType(ChatSenderName),
          matching: find.text('Argon'),
        ),
        findsOneWidget,
      );
      expect(find.text('Build API'), findsOneWidget);
      expect(find.text('Done'), findsOneWidget);
      expect(find.textContaining('Shipped'), findsOneWidget);

      await tester.tap(find.byType(TaskResultCard));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      final opened = tester.widget<SessionScreen>(find.byType(SessionScreen));
      expect(opened.sessionId, 'sess-res-1');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 20));
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('artifact payload renders ArtifactRow without a bubble',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      tester.view.physicalSize = const Size(390, 844) * 3;
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);

      final group = GroupSummary.fromJson({
        'id': 'g-artifact',
        'title': 'Launch',
        'members': [
          {'kind': 'agent', 'id': 'argon'},
          {'kind': 'human', 'id': 'local'},
        ],
      });
      final client = _GroupClient([
        CoordinationEvent.fromJson({
          'event_id': 'e-art',
          'sequence': 1,
          'event_type': 'group_message',
          'actor_kind': 'agent',
          'actor_id': 'argon',
          'idempotency_key': 'kart1',
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'payload': {
            'body': '',
            'artifact': {
              'id': 'art-1',
              'session': 'sess-art-1',
              'title': 'Coverage report',
              'kind': 'html',
              'version': 2,
              'caption': 'Full run',
            },
          },
        }),
      ]);

      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: GroupThreadScreen(client: client, group: group),
      ));
      for (var i = 0; i < 12; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.byType(ArtifactRow), findsOneWidget);
      expect(find.byType(ChatBubble), findsNothing);
      expect(
        find.descendant(
          of: find.byType(ChatSenderName),
          matching: find.text('Argon'),
        ),
        findsOneWidget,
      );
      expect(find.text('Coverage report'), findsOneWidget);
      expect(find.textContaining('v2'), findsOneWidget);

      await tester.pumpWidget(const SizedBox());
      debugDefaultTargetPlatformOverride = null;
    });
  });
}

InlineSpan? _findSpan(InlineSpan span, String needle) {
  if (span is TextSpan) {
    if ((span.text ?? '').contains(needle)) return span;
    for (final c in span.children ?? const <InlineSpan>[]) {
      final hit = _findSpan(c, needle);
      if (hit != null) return hit;
    }
  }
  return null;
}

class _GroupClient extends DaemonClient {
  _GroupClient(this.thread) : super('https://daemon.invalid', 'test-token');
  final List<CoordinationEvent> thread;
  final List<({String? name, int length})> uploads = [];
  final List<({String groupId, String body, List<String>? mentions})> posted =
      [];
  final _deviceEvents = DeviceEventHub.local();

  @override
  DeviceEventHub get deviceEvents => _deviceEvents;

  @override
  Future<List<CoordinationEvent>> groupEvents(
    String id, {
    int after = 0,
    int limit = 100,
  }) async =>
      thread;

  @override
  Future<String> uploadFile(List<int> bytes,
      {String? name, String? dir}) async {
    uploads.add((name: name, length: bytes.length));
    return '/tmp/uploads/${name ?? 'voice'}';
  }

  @override
  Future<CoordinationEvent> postGroup(
    String id, {
    required String body,
    List<String>? mentions,
    String? inReplyTo,
    String? reaction,
    bool remove = false,
  }) async {
    posted.add((groupId: id, body: body, mentions: mentions));
    final ev = CoordinationEvent.fromJson({
      'event_id': 'posted-${posted.length}',
      'sequence': thread.length + 1,
      'event_type': 'group_message',
      'actor_kind': 'human',
      'actor_id': 'local',
      'idempotency_key': 'kp-${posted.length}',
      'created_at': DateTime.now().toUtc().toIso8601String(),
      'payload': {'body': body},
    });
    thread.add(ev);
    return ev;
  }

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => [
        CoordinationAgent.fromJson({
          'id': 'argon',
          'display_name': 'Argon',
          'handle': 'argon',
          'status': 'active',
        }),
        CoordinationAgent.fromJson({
          'id': 'fable',
          'display_name': 'Fable',
          'handle': 'fable',
          'status': 'active',
        }),
      ];

  @override
  Future<List<ArtifactInfo>> artifacts(String session) async => const [];
}

class _FakeWsChannel extends StreamChannelMixin implements WebSocketChannel {
  final incoming = StreamController<dynamic>.broadcast();
  final sent = <dynamic>[];
  bool closed = false;

  @override
  Stream get stream => incoming.stream;
  @override
  late final WebSocketSink sink = _FakeWsSink(this);
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
  @override
  String? get protocol => null;
  @override
  Future<void> get ready => Future.value();
}

class _FakeWsSink implements WebSocketSink {
  _FakeWsSink(this.ch);
  final _FakeWsChannel ch;

  @override
  void add(dynamic data) => ch.sent.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future addStream(Stream stream) async {}
  @override
  Future close([int? closeCode, String? closeReason]) async => ch.closed = true;
  @override
  Future get done => Future.value();
}
