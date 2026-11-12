import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:snippet/api.dart';
import 'package:snippet/chat/agent_details.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/agent_messaging.dart';
import 'package:snippet/screens/agent_view_switcher.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/wake_models.dart';

class _Client extends DaemonClient {
  _Client() : super('https://daemon.invalid', 'test-token');
  final _events = DeviceEventHub.local();
  final boardCalls = <(String?, bool, String?)>[];
  final inboxKinds = <String?>[];

  @override
  DeviceEventHub get deviceEvents => _events;

  @override
  Future<DirectThreadPage> agentThreadPage(
          {required String peerId,
          String actorKind = 'human',
          String actorId = 'local',
          int afterSequence = 0,
          int limit = 100}) async =>
      const DirectThreadPage(events: []);

  @override
  Future<AgentNow?> agentNow(String agentId) async => null;

  @override
  Future<AgentReach> agentReach(String agentId) async =>
      const AgentReach(policy: {}, channels: {});

  @override
  Future<KeepWarmEntry?> keepWarmFor(String owner) async => null;

  @override
  Future<List<MemoryScope>> memoryScopes() async => const [];

  @override
  Future<List<TaskItem>> tasks(
          {String? status, String? agentId, int? limit}) async =>
      const [];

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => [
        CoordinationAgent.fromJson(
            {'id': 'growth', 'display_name': 'Growth', 'handle': 'growth'}),
      ];

  @override
  Future<BoardPage> agentBoardPage(String agentId,
      {String? contains,
      String? kind,
      int? before,
      bool outstanding = false,
      int limit = 50,
      String? group,
      String? correlationId,
      String? workspace}) async {
    boardCalls.add((kind, outstanding, group));
    return const BoardPage([], []);
  }

  @override
  Future<List<InboxEntry>> agentInbox(String agentId,
      {String? contains, String? kind, int? before, int limit = 50}) async {
    inboxKinds.add(kind);
    return [];
  }
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 12; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('the phone title opens the agent details sheet with tabs and actions',
      (t) async {
    t.view.physicalSize = const Size(390, 844) * 3;
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final client = _Client();
    await t.pumpWidget(MaterialApp(
        home: AgentThreadScreen(
            client: client, agentId: 'growth', agentName: 'Growth')));
    await _settle(t);

    expect(find.byType(AgentViewSwitcher), findsNothing);
    expect(find.text('Chat'), findsNothing);

    await t.tap(find.text('Growth').first);
    await _settle(t);

    expect(find.byType(AgentDetails), findsOneWidget);
    for (final label in ['Desk', 'Tasks', 'More', 'Info', 'Inbox', 'Board']) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.text('Call'), findsNothing);

    await t.tap(find.text('Board'));
    await _settle(t);
    expect(client.boardCalls.last, (null, false, null));

    await t.tap(find.text('Waiting'));
    await _settle(t);
    expect(client.boardCalls.last, (null, true, null));

    await t.tap(find.text('Inbox'));
    await _settle(t);
    await t.tap(find.text('Task rooms'));
    await _settle(t);
    expect(client.inboxKinds.last, 'room');

    await t.tap(find.text('More'));
    await _settle(t);
    expect(find.text('Actions'), findsOneWidget);
    for (final row in [
      'Memory',
      'Inference profile',
      'Nickname',
      'Avatar and colour across the app',
      'Delete agent'
    ]) {
      expect(find.text(row), findsOneWidget, reason: row);
    }
    expect(find.text('Desk session'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
