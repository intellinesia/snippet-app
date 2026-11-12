import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/mochi.dart';
import 'package:snippet/screens/desktop_shell.dart';
import 'package:snippet/screens/sidebar_mode.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/widgets.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

SessionInfo _s(String id, {bool settled = false, String? status}) =>
    SessionInfo.fromJson({
      'id': id,
      'title': 'Chat $id',
      'folder': '/workspace/repo',
      'last_active': 1000,
      'settled': settled,
      if (status != null) 'status': status,
    });

class _Client extends DaemonClient {
  _Client() : super('https://daemon.invalid', 'test');

  @override
  late final DeviceEventHub deviceEvents = DeviceEventHub.local();
}

Widget _sidebar({
  DaemonClient? client,
  List<SessionInfo>? sessions,
  VoidCallback? onOpenPalette,
  VoidCallback? onNewSession,
}) {
  return MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: SizedBox(
        width: 800,
        height: 900,
        child: Sidebar(
          instances: const [],
          active: null,
          client: client,
          selectedSessionId: null,
          sessions: sessions ?? const [],
          sessionsLoading: false,
          onRefreshSessions: () {},
          onNewSession: onNewSession ?? () {},
          onSelectInstance: (_) {},
          onOpenMissionControl: () {},
          onOpenSession: (_, __, ___) {},
          onAddInstance: () {},
          onRenameInstance: (_, __) {},
          onRemoveInstance: (_) {},
          onSessionDeleted: (_) {},
          health: const {},
          onRefreshHealth: () {},
          topInset: false,
          onOpenPalette: onOpenPalette,
          mobileHome: MobileHome.chats,
          onMobileHome: (_) {},
          settingsSection: null,
          onSettingsSection: (_) {},
          agent: null,
          onAgent: (_) {},
        ),
      ),
    ),
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    sidebarAgentsFirst.value = false;
  });
  tearDown(() {
    sidebarAgentsFirst.value = false;
  });

  testWidgets('.sctl shows the Sessions|Agents segment and search field',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await tester.pumpWidget(_sidebar(client: _Client(), sessions: [_s('a')]));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Sessions'), findsOneWidget);
    expect(find.text('Agents'), findsOneWidget);
    expect(find.byType(TextField), findsOneWidget);
    // The old Mission Control sidebar row is gone.
    expect(find.text('Mission Control'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('search field opens the palette when one is wired',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    var opened = false;
    await tester.pumpWidget(_sidebar(
      client: _Client(),
      sessions: [_s('a')],
      onOpenPalette: () => opened = true,
    ));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.byType(TextField), findsNothing);
    expect(find.text('Ctrl+K'), findsOneWidget);
    await tester.tap(find.text('Search'));
    await tester.pump();
    expect(opened, isTrue);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Agents segment flips the sidebar mode', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await tester.pumpWidget(_sidebar(client: _Client(), sessions: [_s('a')]));
    await tester.pump(const Duration(milliseconds: 400));

    await tester.tap(find.byKey(const ValueKey('sidebar-mode-agents')));
    await tester.pump(const Duration(milliseconds: 400));
    expect(sidebarAgentsFirst.value, isTrue);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('settled chats keep their pinned header on desktop',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await tester.pumpWidget(_sidebar(
      client: _Client(),
      sessions: [_s('a'), _s('b', settled: true)],
    ));
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('Settled'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Mission Control tab chip is icon-only with a count badge',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    var tapped = false;
    final tab = ShellTab.session(
      client: _Client(),
      instanceUrl: 'https://daemon.invalid',
      sessionId: 'mission-control',
      title: 'Mission Control',
    );
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: TopWorkspaceTabChip(
          tab: tab,
          isActive: true,
          status: null,
          canClose: false,
          onTap: () => tapped = true,
          attentionCount: 3,
        ),
      ),
    ));
    await tester.pump();

    expect(tab.isMissionControl, isTrue);
    expect(find.byType(MochiIcon), findsOneWidget);
    expect(find.text('Mission Control'), findsNothing);
    expect(find.text('3'), findsOneWidget);
    await tester.tap(find.byType(TopWorkspaceTabChip));
    expect(tapped, isTrue);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Mission Control tab chip hides the badge at zero',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final tab = ShellTab.session(
      client: _Client(),
      instanceUrl: 'https://daemon.invalid',
      sessionId: 'mission-control',
      title: 'Mission Control',
    );
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: TopWorkspaceTabChip(
          tab: tab,
          isActive: false,
          status: null,
          canClose: false,
          onTap: () {},
          attentionCount: 0,
        ),
      ),
    ));
    await tester.pump();

    expect(find.byType(MochiIcon), findsOneWidget);
    expect(find.text('0'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('desktop shell top bar has hide-sidebar and new-session buttons',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    DaemonClient.wsConnector =
        (uri, {connectTimeout, pingInterval}) => _Socket();
    SharedPreferences.setMockInitialValues({
      'instances':
          '[{"name":"Local","url":"http://127.0.0.1:9090","token":"tok"}]',
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        MaterialApp(theme: buildAppTheme(), home: const DesktopShell()));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));

    expect(
        find.byWidgetPredicate(
            (w) => w is AppIcon && w.name == 'square-pen'),
        findsOneWidget);
    expect(find.byTooltip('Hide sidebar (Ctrl+B)'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    DaemonClient.wsConnector = null;
    debugDefaultTargetPlatformOverride = null;
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
}

class _Sink implements WebSocketSink {
  final StreamSink _sink;
  _Sink(this._sink);
  @override
  void add(dynamic event) {}
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future addStream(Stream stream) => Future.value();
  @override
  Future close([int? code, String? reason]) => _sink.close();
  @override
  Future get done => _sink.done;
}
