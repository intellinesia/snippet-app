import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:snippet/api.dart';
import 'package:snippet/chat/decided_card.dart';
import 'package:snippet/chat/group_notice.dart';
import 'package:snippet/components.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/group_messaging.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/theme.dart';

class _Client extends DaemonClient {
  _Client(this.evs) : super('https://daemon.invalid', 'test-token');
  final List<CoordinationEvent> evs;
  final _hub = DeviceEventHub.local();
  @override
  DeviceEventHub get deviceEvents => _hub;
  @override
  Future<List<CoordinationEvent>> groupEvents(String id,
          {int after = 0, int limit = 100}) async =>
      evs;
}

CoordinationEvent _ev(int seq, String type, String kind, String actor,
        Map<String, dynamic> payload) =>
    CoordinationEvent.fromJson({
      'event_id': 'e$seq',
      'sequence': seq,
      'event_type': type,
      'actor_kind': kind,
      'actor_id': actor,
      'idempotency_key': 'k$seq',
      'created_at': DateTime.utc(2026, 11, 14, 9, seq).toIso8601String(),
      'payload': payload,
    });

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('decided cards tint each outcome tag', (t) async {
    await t.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Column(children: [
          for (final k in DecidedKind.values)
            DecidedCard(kind: k, title: 'title ${k.name}', subtitle: 'sub'),
        ]),
      ),
    ));
    final tones = {
      for (final tag in t.widgetList<Tag>(find.byType(Tag))) tag.label: tag.tone
    };
    expect(tones, {
      'Approved': Tone.ok,
      'Denied': Tone.danger,
      'Answered': Tone.accent,
      'Skipped': Tone.neutral,
      'Outdated': Tone.neutral,
    });
    expect(find.text('title approved'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('group header subtitle follows the turn, replying, then count',
      (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    Future<void> open(Map<String, dynamic> extra) async {
      final g = GroupSummary.fromJson({
        'id': 'g1',
        'title': 'Crew',
        'members': [
          {'kind': 'agent', 'id': 'rook'},
          {'kind': 'agent', 'id': 'moss'},
          {'kind': 'human', 'id': 'local'},
        ],
        ...extra,
      });
      await t.pumpWidget(const SizedBox());
      await t.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: GroupThreadScreen(client: _Client([]), group: g),
      ));
      for (var i = 0; i < 6; i++) {
        await t.pump(const Duration(milliseconds: 80));
      }
    }

    await open({});
    expect(find.text('3 members'), findsOneWidget);
    await open({
      'replying': ['moss']
    });
    expect(find.textContaining('is replying'), findsOneWidget);
    await open({
      'turn': {'agent': 'rook', 'since': 1}
    });
    expect(find.textContaining('has the turn'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('turn passes and verdicts render as notices', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final g = GroupSummary.fromJson({
      'id': 'g1',
      'title': 'Crew',
      'members': [
        {'kind': 'agent', 'id': 'rook'},
        {'kind': 'agent', 'id': 'moss'},
      ],
    });
    final c = _Client([
      _ev(1, 'task.lease_transferred', 'agent', 'rook',
          {'from_agent_id': 'rook', 'to_agent_id': 'moss'}),
      _ev(2, 'task.verdict', 'human', 'local',
          {'verdict': 'approved', 'by': 'human', 'task_id': 'T-9'}),
      _ev(3, 'task.verdict', 'agent', 'rook',
          {'verdict': 'sent_back', 'by': 'rook', 'task_id': 'T-8'}),
    ]);
    await t.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: GroupThreadScreen(client: c, group: g),
    ));
    for (var i = 0; i < 8; i++) {
      await t.pump(const Duration(milliseconds: 80));
    }
    final kinds = t.widgetList<GroupNotice>(find.byType(GroupNotice)).map((n) => n.kind);
    expect(kinds, unorderedEquals([
      GroupNoticeKind.turn,
      GroupNoticeKind.approved,
      GroupNoticeKind.sentBack,
    ]));
    expect(find.text('You approved T-9'), findsOneWidget);
    await t.pumpWidget(const SizedBox());
    debugDefaultTargetPlatformOverride = null;
  });
}
