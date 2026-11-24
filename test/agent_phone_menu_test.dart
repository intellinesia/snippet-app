import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:snippet/api.dart';
import 'package:snippet/chat/stage_bar.dart';
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
  Future<DirectThreadPage> agentThreadPage(
          {required String peerId,
          String actorKind = 'human',
          String actorId = 'local',
          int afterSequence = 0,
          int? beforeSequence,
          bool latest = false,
          int limit = 100}) async =>
      const DirectThreadPage(events: []);

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
    // The chat view's header shows presence, not the view name.
    expect(find.text('Chat'), findsNothing);

    await t.tap(find.descendant(of: find.byType(StageBar), matching: find.text('Growth')));
    await _settle(t);
    // The chat title opens the agent page; its Work rows switch views.
    for (final row in ['Inbox', 'Board', 'Desk session']) {
      expect(find.text(row), findsOneWidget, reason: row);
    }
    expect(find.text('Tasks'), findsNothing);
    await t.tap(find.text('Board'));
    await _settle(t);

    // Board stacks on the agent page as its own page with filter chips.
    expect(find.text('By task'), findsOneWidget);
    expect(client.boardCalls.last, (null, false, null));

    // Back returns to the agent page, not the agent list.
    await t.binding.handlePopRoute();
    await _settle(t);
    expect(find.text('By task'), findsNothing);
    for (final row in ['Inbox', 'Board', 'Desk session']) {
      expect(find.text(row), findsOneWidget, reason: row);
    }
    await t.binding.handlePopRoute();
    await _settle(t);

    debugDefaultTargetPlatformOverride = null;
  });
}
