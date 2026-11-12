import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/screens/group_messaging.dart';
import 'package:snippet/screens/mission_control/mission_control_state.dart';
import 'package:snippet/screens/session_coordination_cards.dart';

const _post = '''[group_message]
thread_id: group:1
title: jh
from: human:human
mentions: x-scout
reply_expected: true
note: this post is waiting on the group.
body: @x-scout what's trending?
second line
[/group_message]''';

const _added = '''[group_added]
thread_id: group:1
title: jh
members: x-scout, snippet
lead: snippet
note: you were added to this group chat.
[/group_added]''';

GroupSummary _group() => GroupSummary.fromJson({
      'id': 'group:1',
      'title': 'jh',
      'members': [
        {'kind': 'human', 'id': 'human'},
        {'kind': 'agent', 'id': 'x-scout'},
        {'kind': 'agent', 'id': 'snippet'},
      ],
      'lead': 'snippet',
      'created_at': '2026-11-12T00:00:00Z',
    });

class _Client extends DaemonClient {
  _Client() : super('https://daemon.invalid', 'test-token');
  final _events = DeviceEventHub.local();
  @override
  DeviceEventHub get deviceEvents => _events;

  final removed = <String>[];
  bool deleted = false;

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => const [];

  @override
  Future<GroupSummary> updateGroup(String id,
      {String? title,
      String? lead,
      List<String>? addMembers,
      List<String>? removeMembers}) async {
    removed.addAll(removeMembers ?? const []);
    return _group();
  }

  @override
  Future<void> deleteGroup(String id) async => deleted = true;
}

void main() {
  test('parses a group post with a multi-line body', () {
    final m = parseGroupMessage(_post)!;
    expect(m.added, isFalse);
    expect(m.title, 'jh');
    expect(m.fromLabel, 'You');
    expect(m.mentions, ['x-scout']);
    expect(m.replyExpected, isTrue);
    expect(m.body, "@x-scout what's trending?\nsecond line");
  });

  test('parses the added notice', () {
    final m = parseGroupMessage(_added)!;
    expect(m.added, isTrue);
    expect(m.members, ['x-scout', 'snippet']);
    expect(m.lead, 'snippet');
    expect(parseGroupMessage('[direct_message]\nbody: x\n[/direct_message]'),
        isNull);
  });

  testWidgets('desk cards show who, where and what', (tester) async {
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: Column(children: [
      GroupMessageCard(message: parseGroupMessage(_post)!),
      GroupMessageCard(message: parseGroupMessage(_added)!),
    ]))));
    expect(find.textContaining('You in jh'), findsOneWidget);
    expect(find.textContaining('Reply expected'), findsOneWidget);
    expect(find.textContaining('Added to jh'), findsOneWidget);
    expect(find.textContaining('[group_message]'), findsNothing);
  });

  testWidgets('members sheet removes an agent and deletes the group',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final client = _Client();
    var gone = false;
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(
            body: SingleChildScrollView(
                child: GroupMembersSheet(
                    client: client,
                    group: _group(),
                    onDeleted: () => gone = true)))));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('remove-x-scout')));
    await tester.pumpAndSettle();
    expect(client.removed, ['x-scout']);
    expect(find.byKey(const ValueKey('remove-human')), findsNothing);
    await tester.tap(find.text('Delete group'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Delete group').last);
    await tester.pumpAndSettle();
    expect(client.deleted, isTrue);
    expect(gone, isTrue);
    await tester.pump(const Duration(seconds: 10));
    debugDefaultTargetPlatformOverride = null;
  });
}
