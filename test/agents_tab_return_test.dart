import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/agent_card.dart';
import 'package:snippet/screens/agents_sidebar_panel.dart';
import 'package:snippet/screens/desktop_shell.dart';
import 'package:snippet/screens/mobile_home/mobile_home_screen.dart';
import 'package:snippet/screens/lead/coordination_agent_detail.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/widgets.dart';

class _Client extends DaemonClient {
  _Client(String url) : super(url, 'test');

  final _events = DeviceEventHub.local();
  Completer<List<CoordinationAgent>>? hold;
  int calls = 0;

  @override
  DeviceEventHub get deviceEvents => _events;

  @override
  Future<ServerConfig> getConfig({bool force = false}) async =>
      ServerConfig.fromJson({'profiles': []});

  @override
  Future<List<GroupSummary>> groups() async => const [];

  @override
  Future<List<CoordinationAgent>> coordinationAgents() {
    calls++;
    final list = [
      for (final n in ['Ada', 'Bo'])
        CoordinationAgent.fromJson(
            {'id': n.toLowerCase(), 'display_name': n, 'handle': n}),
    ];
    final h = hold;
    return h == null ? Future.value(list) : h.future;
  }
}

Widget _sidebar(_Client client, {CoordinationAgent? agent}) => MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Sidebar(
          instances: const [],
          active: null,
          client: client,
          selectedSessionId: null,
          sessions: const [],
          sessionsLoading: false,
          onRefreshSessions: () {},
          onNewSession: () {},
          onSelectInstance: (_) {},
          onOpenLead: () {},
          onOpenSession: (_, __, ___) {},
          onAddInstance: () {},
          onRenameInstance: (_, __) {},
          onRemoveInstance: (_) {},
          onSessionDeleted: (_) {},
          health: {client.baseUrl: true},
          onRefreshHealth: () {},
          topInset: false,
          mobileHome: agent == null ? MobileHome.chats : MobileHome.agents,
          onMobileHome: (_) {},
          settingsSection: null,
          onSettingsSection: (_) {},
          agent: agent,
          onAgent: (_) {},
        ),
      ),
    );

void _expectRowsNoSpinner() {
  expect(find.byType(AgentCard), findsNWidgets(2));
  expect(find.byType(AppLoading), findsNothing);
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('back from an agent keeps the same home, no reload frame',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final client = _Client('https://return-a.invalid');
    await tester.pumpWidget(_sidebar(client));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('everyone-handle')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('asleep-fold')));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('agent-row-ada')), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-row-bo')), findsOneWidget);
    final before = tester.state(find.byType(MobileHomeScreen));

    await tester.pumpWidget(_sidebar(client,
        agent: CoordinationAgent.fromJson(
            {'id': 'ada', 'display_name': 'Ada', 'handle': 'ada'})));
    await tester.pump();
    expect(find.byType(CoordinationAgentDetail), findsOneWidget);
    expect(
        find.byKey(const ValueKey('agent-row-ada')).hitTestable(), findsNothing);

    client.hold = Completer();
    await tester.pumpWidget(_sidebar(client));
    await tester.pump();
    expect(find.byKey(const ValueKey('agent-row-ada')), findsOneWidget);
    expect(find.byKey(const ValueKey('agent-row-bo')), findsOneWidget);
    expect(identical(tester.state(find.byType(MobileHomeScreen)), before),
        isTrue);
    client.hold!.complete([]);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a remounted panel paints the last list while it refreshes',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final client = _Client('https://return-b.invalid');
    Widget panel() => MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: AgentsSidebarPanel(client: client)));
    await tester.pumpWidget(panel());
    await tester.pumpAndSettle();
    _expectRowsNoSpinner();

    await tester.pumpWidget(const SizedBox.shrink());
    client.hold = Completer();
    final calls = client.calls;
    await tester.pumpWidget(panel());
    _expectRowsNoSpinner();
    await tester.pump(const Duration(milliseconds: 16));
    _expectRowsNoSpinner();
    expect(client.calls, greaterThan(calls));
    client.hold!.complete([
      for (final n in ['Ada', 'Bo'])
        CoordinationAgent.fromJson(
            {'id': n.toLowerCase(), 'display_name': n, 'handle': n}),
    ]);
    await tester.pumpAndSettle();
    _expectRowsNoSpinner();
    debugDefaultTargetPlatformOverride = null;
  });
}
