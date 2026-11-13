import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/api.dart';
import 'package:snippet/mochi.dart';
import 'package:snippet/models.dart';
import 'package:snippet/motion.dart';
import 'package:snippet/screens/agents_sidebar_panel.dart';
import 'package:snippet/screens/desktop_shell.dart';
import 'package:snippet/screens/mobile_bottom_bar.dart';
import 'package:snippet/screens/mobile_chrome.dart';
import 'package:snippet/screens/mission_control/coordination_agent_detail.dart';
import 'package:snippet/screens/session.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/widgets.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _Client extends DaemonClient {
  _Client() : super('https://daemon.invalid', 'test');

  final DeviceEventHub _deviceEvents = DeviceEventHub.local();

  @override
  DeviceEventHub get deviceEvents => _deviceEvents;

  @override
  Future<ServerConfig> getConfig({bool force = false}) async =>
      ServerConfig.fromJson({
        'profiles': [
          {'name': 'claude', 'provider': 'claude-code'},
        ],
      });
}

class _Socket extends StreamChannelMixin implements WebSocketChannel {
  final _controller = StreamController<dynamic>.broadcast();
  @override
  Stream get stream => _controller.stream;
  @override
  late final WebSocketSink sink = _Sink(_controller.sink);
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
  @override
  String? get protocol => null;
  @override
  Future<void> get ready => Future.value();

  void push(Map<String, dynamic> payload) =>
      _controller.add(jsonEncode(payload));
}

class _Sink implements WebSocketSink {
  final StreamSink _sink;
  _Sink(this._sink);
  @override
  void add(dynamic data) {}
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future addStream(Stream stream) => Future.value();
  @override
  Future close([int? closeCode, String? closeReason]) => _sink.close();
  @override
  Future get done => _sink.done;
}

SessionInfo _session(
  String id,
  String title,
  String status, {
  bool settled = false,
  Map<String, dynamic>? attention,
}) {
  final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
  return SessionInfo.fromJson({
    'id': id,
    'title': title,
    'status': status,
    'last_active': now - 60,
    'folder': '/home/dev/code/snippet-mobile',
    'settled': settled,
    if (attention != null) 'attention': attention,
  });
}

void main() {
  testWidgets(
      'phone shell launches on Sessions home with MobileBottomBar and opens MC from avatar',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    DaemonClient.wsConnector =
        (uri, {connectTimeout, pingInterval}) => _Socket();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    try {
      SharedPreferences.setMockInitialValues({
        'instances':
            '[{"name":"Local","url":"http://127.0.0.1:9090","token":"tok"}]',
      });

      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: const DesktopShell(),
      ));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      final shell = tester.widget<MobileShell>(find.byType(MobileShell));
      expect(shell.chatsOpen, isTrue);
      expect(find.byType(MobileHomeHeader), findsWidgets);
      expect(find.byTooltip('New session'), findsOneWidget);
      expect(find.byType(MobileBottomBar), findsOneWidget);
      expect(find.byType(MobileMissionBar).hitTestable(), findsNothing);

      await tester.tap(find.byTooltip('Mission Control').first);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      expect(tester.widget<MobileShell>(find.byType(MobileShell)).chatsOpen,
          isFalse);
      expect(find.byType(MobileMissionBar), findsOneWidget);
      expect(find.byType(MobileBottomBar), findsNothing);
      expect(find.byTooltip('New session'), findsNothing);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    } finally {
      tester.view.reset();
      DaemonClient.wsConnector = null;
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      'Sidebar MC badge counts all unsettled sessions needing attention and Settings uses MobileHomeHeader',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {

    Widget buildSidebar(
      MobileHome home, {
      List<SessionInfo> sessions = const [],
      CoordinationAgent? agent,
      SettingsPage? section,
    }) {
      return MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Sidebar(
            instances: const [],
            active: null,
            client: _Client(),
            selectedSessionId: null,
            sessions: sessions,
            sessionsLoading: false,
            onRefreshSessions: () {},
            onNewSession: () {},
            onSelectInstance: (_) {},
            onOpenMissionControl: () {},
            onOpenSession: (_, __, ___) {},
            onAddInstance: () {},
            onRenameInstance: (_, __) {},
            onRemoveInstance: (_) {},
            onSessionDeleted: (_) {},
            health: const {'https://daemon.invalid': true},
            onRefreshHealth: () {},
            topInset: false,
            mobileHome: home,
            onMobileHome: (_) {},
            settingsSection: section,
            onSettingsSection: (_) {},
            agent: agent,
            onAgent: (_) {},
          ),
        ),
      );
    }

    await tester.pumpWidget(buildSidebar(
      MobileHome.chats,
      sessions: [
        _session('s1', 'Waiting', 'waiting_for_input'),
        _session('s2', 'Attention', 'idle', attention: {'kind': 'review'}),
        _session('s3', 'Settled', 'waiting_for_input', settled: true),
      ],
    ));
    await tester.pumpAndSettle();
    expect(
        find.descendant(
            of: find.byType(MobileHomeHeader), matching: find.text('2')),
        findsOneWidget);

    await tester.pumpWidget(buildSidebar(MobileHome.agents));
    await tester.pumpAndSettle();
    expect(find.byTooltip('New agent or group'), findsOneWidget);
    expect(find.descendant(
        of: find.byType(MobileBottomBar),
        matching: find.text('New agent or group')), findsNothing);
    expect(find.byType(MobileBottomBar), findsOneWidget);
    expect(find.byType(AgentsSidebarPanel), findsOneWidget);

    await tester.pumpWidget(buildSidebar(
      MobileHome.agents,
      agent: CoordinationAgent.fromJson(
          {'id': 'scout', 'display_name': 'Scout', 'handle': 'scout'}),
    ));
    await tester.pump();
    expect(find.byType(CoordinationAgentDetail), findsOneWidget);
    expect(find.byType(MobileBottomBar), findsNothing);
    expect(find.byTooltip('New session'), findsNothing);

    await tester.pumpWidget(buildSidebar(MobileHome.settings));
    await tester.pumpAndSettle();
    expect(find.byType(MobileHomeHeader), findsWidgets);
    expect(find.byType(MobileBottomBar), findsNothing);
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.byTooltip('Mission Control'), findsNothing);

    await tester.pumpWidget(buildSidebar(
      MobileHome.settings,
      section: SettingsPage.general,
    ));
    await tester.pump();
    expect(find.byType(MobileBottomBar), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      'Session header drops leading avatar and model, shows folder when idle, and WorkingDots + layers when active',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final socket = _Socket();
    DaemonClient.wsConnector = (uri, {connectTimeout, pingInterval}) => socket;
    try {

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: SessionScreen(
        client: DaemonClient('https://daemon.invalid', 'test'),
        sessionId: 'sess-1',
        title: 'Phone Chrome',
        profile: 'claude',
        onMenu: () {},
      ),
    ));
    await tester.pump();

    final started =
        DateTime.now().subtract(const Duration(minutes: 4)).toUtc().toIso8601String();
    socket.push({
      'id': 'sess-1',
      'status': 'idle',
      'workspace': '/home/dev/code/snippet-mobile',
      'profile': 'claude',
      'events': [],
      'lanes': [],
    });
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(MobileBackBar), findsOneWidget);
    expect(
        find.descendant(
            of: find.byType(MobileBackBar), matching: find.byType(MochiIcon)),
        findsNothing);
    expect(find.text('snippet-mobile'), findsOneWidget);
    expect(find.textContaining('claude'), findsNothing);
    expect(find.byTooltip('Shell'), findsOneWidget);
    expect(find.byTooltip('Parallel agents'), findsNothing);

    socket.push({
      'id': 'sess-1',
      'status': 'running',
      'workspace': '/home/dev/code/snippet-mobile',
      'turn_started_at': started,
      'events': [],
      'lanes': [
        {
          'id': 'lane-1',
          'title': 'Worker',
          'status': 'running',
          'started_at': started,
        }
      ],
    });
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(WorkingDots), findsOneWidget);
    expect(find.textContaining('Working 4m · snippet-mobile'), findsOneWidget);
    final layers = find.byTooltip('Parallel agents');
    expect(layers, findsOneWidget);
    final layersIcon = tester.widget<AppIcon>(
        find.descendant(of: layers, matching: find.byType(AppIcon)).first);
    expect(layersIcon.name, 'layers');
    expect(
        find.descendant(
            of: find.byType(MobileBackBar),
            matching: find.byType(WorkingMochi)),
        findsNothing);

    await socket.sink.close();
    await tester.pump(const Duration(milliseconds: 800));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 800));
    } finally {
      DaemonClient.wsConnector = null;
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
