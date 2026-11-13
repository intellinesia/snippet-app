import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/chat/chat_info.dart';
import 'package:snippet/models.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/theme.dart';

import 'support/wake_fakes.dart';

CoordinationAgent _agent() => CoordinationAgent.fromJson({
      'id': 'scout',
      'display_name': 'Revenue Scout',
      'status': 'active',
      'profile': 'argon',
      'capabilities': ['research', 'writing'],
    });

GroupSummary _group() => GroupSummary.fromJson({
      'id': 'group:1',
      'title': 'jh',
      'members': [
        {'kind': 'human', 'id': 'human'},
        {'kind': 'agent', 'id': 'scout'},
      ],
      'lead': 'scout',
      'created_at': '2026-11-12T00:00:00Z',
    });

class _Client extends FakeWakeClient {
  _Client({this.agent, this.group, this.threadEvents = const []});

  final _events = DeviceEventHub.local();

  @override
  DeviceEventHub get deviceEvents => _events;

  final CoordinationAgent? agent;
  GroupSummary? group;
  final List<CoordinationEvent> threadEvents;

  final added = <String>[];
  final removed = <String>[];
  final leads = <String>[];
  final titles = <String>[];
  final profiles = <String?>[];
  final desks = <String?>[];
  String? deletedAgent;
  String? deletedGroup;

  @override
  Future<ServerConfig> getConfig({bool force = false}) async =>
      ServerConfig.fromJson({
        'profiles': [
          {'name': 'argon', 'provider': 'openai', 'model': 'gpt'},
          {'name': 'claude', 'provider': 'anthropic', 'model': 'opus'},
        ],
      });

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => [
        if (agent != null) agent!,
        CoordinationAgent.fromJson(
            {'id': 'scout', 'display_name': 'Revenue Scout'}),
        CoordinationAgent.fromJson({'id': 'snippet', 'display_name': 'Snippet'}),
      ];

  @override
  Future<DirectThreadPage> agentThreadPage({
    required String peerId,
    String actorKind = 'human',
    String actorId = 'local',
    int afterSequence = 0,
    int limit = 100,
  }) async =>
      DirectThreadPage(events: threadEvents);

  @override
  Future<List<CoordinationEvent>> groupEvents(String id,
          {int after = 0, int limit = 100}) async =>
      threadEvents;

  @override
  Future<GroupSummary> updateGroup(String id,
      {String? title,
      String? lead,
      List<String>? addMembers,
      List<String>? removeMembers}) async {
    final g = group!;
    if (addMembers != null) added.addAll(addMembers);
    if (removeMembers != null) removed.addAll(removeMembers);
    if (lead != null) leads.add(lead);
    if (title != null) titles.add(title);
    final members = [
      for (final m in g.members)
        if (!(removeMembers ?? const []).contains(m.id))
          {'kind': m.kind, 'id': m.id},
      for (final id in addMembers ?? const [])
        {'kind': 'agent', 'id': id},
    ];
    group = GroupSummary.fromJson({
      'id': g.id,
      'title': title ?? g.title,
      'members': members,
      'lead': lead ?? g.lead,
      'created_at': g.createdAt,
    });
    return group!;
  }

  @override
  Future<void> deleteGroup(String id) async => deletedGroup = id;

  @override
  Future<void> deleteAgent(String id) async => deletedAgent = id;

  @override
  Future<void> setAgentProfile(String agentId, String? profile) async =>
      profiles.add(profile);

  @override
  Future<void> setAgentDeskProfile(String agentId, String? profile) async =>
      desks.add(profile);
}

Widget _app(Widget child) => MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: child),
    );

void _phone(WidgetTester tester) {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('phone agent sheet shows identity, actions and model rows, no Files/Links; '
      'X closes it', (tester) async {
    _phone(tester);
    final client = _Client(agent: _agent(), threadEvents: const []);
    await tester.pumpWidget(_app(Builder(
      builder: (ctx) => Center(
        child: TextButton(
          onPressed: () => showAgentInfo(
            ctx,
            client: client,
            agentId: 'scout',
            name: 'Revenue Scout',
            agent: _agent(),
            onOpenTasks: () {},
            onOpenInbox: () {},
            onOpenBoard: () {},
            onOpenDesk: () {},
          ),
          child: const Text('open'),
        ),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('Revenue Scout'), findsOneWidget);
    expect(find.text('Active'), findsOneWidget);
    for (final label in ['Tasks', 'Inbox', 'Board', 'Desk']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    for (final tab in ['Files', 'Links']) {
      expect(find.text(tab), findsNothing, reason: tab);
    }
    expect(find.text('Tasks run on'), findsOneWidget);
    expect(find.text('Desk runs on'), findsOneWidget);
    expect(find.text('Agent ID'), findsOneWidget);
    expect(find.text('Delete agent'), findsOneWidget);

    await tester.tap(find.bySemanticsLabel('Close'));
    await tester.pumpAndSettle();
    expect(find.text('Revenue Scout'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('group sheet lists members and Add member calls updateGroup',
      (tester) async {
    _phone(tester);
    final client = _Client(group: _group());
    await tester.pumpWidget(_app(Builder(
      builder: (ctx) => Center(
        child: TextButton(
          onPressed: () => showGroupInfo(
              ctx, client: client, group: _group(), onOpenTasks: () {}),
          child: const Text('open'),
        ),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    expect(find.text('jh'), findsOneWidget);
    expect(find.text('2 members'), findsOneWidget);
    expect(find.text('You'), findsWidgets);
    expect(find.text('Revenue Scout'), findsWidgets);
    expect(find.text('Lead'), findsWidgets);

    await tester.tap(find.text('Add member'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Snippet'));
    await tester.pumpAndSettle();
    expect(client.added, ['snippet']);
    expect(client.group!.agentIds, contains('snippet'));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('desktop panel renders at 340px without overflow',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1200, 800);
    addTearDown(tester.view.reset);
    final client = _Client(agent: _agent(), threadEvents: const []);
    await tester.pumpWidget(_app(SizedBox(
      width: 340,
      height: 800,
      child: AgentInfoPanel(
        client: client,
        agentId: 'scout',
        name: 'Revenue Scout',
        agent: _agent(),
        onOpenTasks: () {},
        onChanged: () {},
        onClose: () {},
      ),
    )));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.text('Revenue Scout'), findsOneWidget);
    expect(find.text('Tasks run on'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
