import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/mochi.dart';
import 'package:snippet/screens/desktop_shell.dart';
import 'package:snippet/screens/session.dart' show TerminalHost, TerminalInfo;
import 'package:snippet/screens/session_list_row.dart';
import 'package:snippet/screens/session_side_panel.dart';
import 'package:snippet/screens/tasks/task_kanban.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/theme.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _Client extends DaemonClient {
  _Client() : super('https://daemon.invalid', 'test');

  final DeviceEventHub _events = DeviceEventHub.local();

  @override
  DeviceEventHub get deviceEvents => _events;

  @override
  Future<FsListing> fs(String? path) async => FsListing.fromJson({
        'path': path ?? '/workspace',
        'parent': null,
        'entries': const [
          {'name': 'lib', 'path': '/workspace/lib', 'is_dir': true, 'git': true},
        ],
      });

  @override
  Future<GitStatus> gitStatus(String workspaceOrSession) async =>
      GitStatus.fromJson({
        'branch': 'feat/dshell',
        'repo': true,
        'files': const [],
      });

  @override
  Future<List<SessionInfo>> sessions({String? folder, int? limit}) async =>
      const [];

  @override
  Future<List<TaskItem>> tasks({String? status, String? agentId, int? limit}) async =>
      const [];
}

SessionInfo _session(
  String id, {
  String status = 'idle',
  Map<String, dynamic>? attention,
  int lastActive = 1000,
}) =>
    SessionInfo.fromJson({
      'id': id,
      'title': 'Chat $id',
      'folder': '/workspace/repo',
      'last_active': lastActive,
      if (status != 'idle') 'status': status,
      if (attention != null) 'attention': attention,
    });

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('desktop sidebar puts Needs you first with warn colour',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: SizedBox(
          width: 340,
          height: 900,
          child: Sidebar(
            instances: const [],
            active: null,
            client: _Client(),
            selectedSessionId: null,
            sessions: [
              _session('q',
                  status: 'waiting_for_input',
                  attention: const {'type': 'question', 'text': 'Which?'}),
              _session('rev', status: 'in_review'),
              _session('inp', status: 'waiting_for_input'),
              _session('norm', status: 'idle'),
            ],
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
            health: const {},
            onRefreshHealth: () {},
            topInset: false,
            mobileHome: MobileHome.chats,
            onMobileHome: (_) {},
            settingsSection: null,
            onSettingsSection: (_) {},
            agent: null,
            onAgent: (_) {},
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));

    final needsYou = find.text('Needs you');
    expect(needsYou, findsOneWidget);
    final headerText = tester.widget<Text>(needsYou);
    expect(headerText.style?.color, AppColors.run);
    expect(find.text('Question'), findsOneWidget);
    expect(find.text('In review'), findsOneWidget);
    expect(find.text('Needs input'), findsOneWidget);

    // Needs you appears above the project group header.
    final needsTop = tester.getTopLeft(needsYou).dy;
    final repoHeader = find.descendant(
        of: find.byType(SessionGroupHeader), matching: find.text('repo'));
    expect(repoHeader, findsOneWidget);
    final repoTop = tester.getTopLeft(repoHeader).dy;
    expect(needsTop, lessThan(repoTop));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('session tab chip shows agent icon and running/warn status marks',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final client = _Client();
    final runningTab = ShellTab.session(
      client: client,
      instanceUrl: 'https://daemon.invalid',
      sessionId: 's1',
      title: 'Agent work',
    );
    final inputTab = ShellTab.session(
      client: client,
      instanceUrl: 'https://daemon.invalid',
      sessionId: 's2',
      title: 'Needs boss',
    );

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Row(children: [
          TopWorkspaceTabChip(
            tab: runningTab,
            isActive: true,
            status: 'running',
            agentId: 'scout',
            canClose: true,
            onTap: () {},
            onClose: () {},
          ),
          TopWorkspaceTabChip(
            tab: inputTab,
            isActive: false,
            status: 'waiting_for_input',
            canClose: true,
            onTap: () {},
            onClose: () {},
          ),
        ]),
      ),
    ));
    await tester.pump();

    expect(find.byType(AgentMochi), findsOneWidget);

    // Running mark: 6x6 filled grey circle (v5 `.dt.w`).
    expect(
      find.byWidgetPredicate((w) {
        if (w is! Container) return false;
        final d = w.decoration;
        return d is BoxDecoration &&
            d.shape == BoxShape.circle &&
            d.color == AppColors.fg2;
      }),
      findsOneWidget,
    );

    // Needs-input mark: 7x7 hollow warn ring.
    expect(
      find.byWidgetPredicate((w) {
        if (w is! Container) return false;
        final d = w.decoration;
        if (d is! BoxDecoration || d.shape != BoxShape.circle) return false;
        final border = d.border;
        return border is Border &&
            border.top.color == AppColors.run &&
            border.top.width == 1.5;
      }),
      findsOneWidget,
    );

    // Active tab raised surface chip with border2.
    expect(
      find.byWidgetPredicate((w) {
        if (w is! AnimatedContainer) return false;
        final d = w.decoration;
        if (d is! BoxDecoration) return false;
        final border = d.border;
        return d.color == AppColors.tint2 &&
            border is Border &&
            border.top.color == AppColors.border2;
      }),
      findsOneWidget,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('rail tools omit the top-right token meter', (tester) async {
    final tab = ShellTab.session(
      client: _Client(),
      instanceUrl: 'https://daemon.invalid',
      sessionId: 's1',
      title: 'Session',
    );
    final status = MacSessionStatus(
      HarnessState.fromJson({
        'status': 'idle',
        'workspace': '/workspace',
        'last_prompt_tokens': 121000,
        'context_window': 200000,
      }),
      false,
    );
    final tools = buildShellRailTools(
      activeTab: tab,
      macSessionStatus: status,
      isRightPanelActive: (_) => false,
      onToggleRightPanel: (_) {},
      onSessionAction: (_, [__]) {},
      onOpenGoalPopover: (_) {},
      onAgentAction: (_) {},
    );

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: Row(children: tools)),
    ));
    await tester.pump();

    expect(find.text('121k'), findsNothing);
    expect(find.byTooltip('Context 121k of 200k'), findsNothing);
    expect(find.byTooltip('Session actions'), findsOneWidget);
  });

  testWidgets('Tasks tab opens TaskKanban and Back/Forward navigate history',
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

    // Back and Forward chevrons are always visible in the top bar.
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.byTooltip('Forward'), findsOneWidget);
    expect(find.byTooltip('Tasks'), findsWidgets);

    await tester.tap(find.byTooltip('Tasks').first);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(TaskKanban), findsOneWidget);

    // Back returns to Mission Control; Forward goes back to Tasks.
    await tester.tap(find.byTooltip('Back'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(TaskKanban), findsNothing);

    await tester.tap(find.byTooltip('Forward'));
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(TaskKanban), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    DaemonClient.wsConnector = null;
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('SessionSidePanel shows segmented header and terminals dock',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final host = TerminalHost(
      terms: const [
        TerminalInfo(id: 't1', title: 'flutter test', alive: true, live: true),
        TerminalInfo(id: 't2', title: 'zsh', alive: false, live: false),
      ],
      focus: 0,
      buildView: (id, {required bool mobileKeys}) => const SizedBox(),
      onFocus: (_) {},
      onRequestNew: () {},
      onRequestClose: (_) {},
    );

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: SizedBox(
          width: 320,
          height: 700,
          child: SessionSidePanel(
            client: _Client(),
            workspacePath: '/workspace',
            sessionId: 's1',
            changesCount: 6,
            host: host,
            onTogglePanel: (_) {},
            onOpenFile: (_, __) {},
          ),
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 300));

    // Fixed header with Files | Changes 6; no overflow menu (actions live in
    // the session header).
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Changes'), findsOneWidget);
    expect(find.text('6'), findsOneWidget);
    expect(find.text('Lanes'), findsNothing);
    expect(find.byTooltip('Scheduled, checkpoints'), findsNothing);
    // Standalone header is hidden when hosted inside SessionSidePanel.
    expect(find.text('File Tree'), findsNothing);

    // Docked terminals section with running/idle rows and collapse chevron.
    expect(find.text('Terminals'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('flutter test'), findsOneWidget);
    expect(find.text('running'), findsOneWidget);
    expect(find.text('zsh'), findsOneWidget);
    expect(find.text('idle'), findsOneWidget);

    await tester.tap(find.text('Terminals'));
    await tester.pump();
    expect(find.text('flutter test'), findsNothing);

    // Switching to Changes renders GitDiffSidebarPanel without duplicate header.
    await tester.tap(find.text('Changes'));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Git Diff'), findsNothing);

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
