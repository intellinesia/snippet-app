import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:snippet/api.dart';
import 'package:snippet/composer/voice_note.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/group_messaging.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/chat/chat_style.dart';
import 'package:snippet/message_reactions.dart';

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

      expect(find.text('Argon'), findsOneWidget);

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
}
