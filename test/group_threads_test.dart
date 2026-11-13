import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/group_messaging.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/chat/chat_style.dart';

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
