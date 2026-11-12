import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/agent_messaging.dart';
import 'package:snippet/screens/agent_view_switcher.dart';
import 'package:snippet/swr.dart';

class _Client extends DaemonClient {
  _Client() : super('https://daemon.invalid', 'test-token');
  final _events = DeviceEventHub.local();
  final boardCalls = <(String?, bool, String?)>[];
  final inboxKinds = <String?>[];

  @override
  DeviceEventHub get deviceEvents => _events;

  @override
  Future<List<CoordinationEvent>> agentThread(
          {required String peerId,
          String actorKind = 'human',
          String actorId = 'local',
          int afterSequence = 0,
          int limit = 100}) async =>
      [];

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

Future<void> _pick(WidgetTester t, String label) async {
  await t.tap(find.text('Growth').first);
  await _settle(t);
  await t.tap(find.text(label).last);
  await _settle(t);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
  });
  tearDown(() => debugDefaultTargetPlatformOverride = null);

  testWidgets('the phone title switches views and filters and opens actions',
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
    expect(find.text('Chat'), findsOneWidget);

    await t.tap(find.text('Growth').first);
    await _settle(t);
    for (final row in ['Inbox', 'Board', 'Desk session', 'More actions']) {
      expect(find.text(row), findsOneWidget, reason: row);
    }
    expect(find.text('Show'), findsNothing);
    await t.tap(find.text('Board'));
    await _settle(t);

    expect(find.text('Board'), findsOneWidget);
    expect(find.text('By task'), findsNothing, reason: 'no chips row');
    expect(client.boardCalls.last, (null, false, null));

    await _pick(t, 'Waiting');
    expect(find.text('Board · Waiting'), findsOneWidget);
    expect(client.boardCalls.last, (null, true, null));

    await _pick(t, 'Inbox');
    expect(find.text('Inbox'), findsOneWidget);
    await _pick(t, 'Task rooms');
    expect(find.text('Inbox · Task rooms'), findsOneWidget);
    expect(client.inboxKinds.last, 'room');

    await _pick(t, 'More actions');
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
    expect(find.text('Board'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
