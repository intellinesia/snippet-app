import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/agent_character.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/agent_records.dart';
import 'package:snippet/screens/session.dart';
import 'package:snippet/theme.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _Client extends DaemonClient {
  _Client() : super('http://127.0.0.1:9090', 'tok');

  final deleted = <String>[];

  @override
  Future<List<SessionInfo>> sessions({String? folder, int? limit}) async => [
        SessionInfo.fromJson({
          'id': 'sess-r8',
          'title': 'Sidebar density',
          'status': 'idle',
          'agent_id': 'rook',
          'branch': 'main',
        }),
      ];

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => [
        CoordinationAgent.fromJson({
          'id': 'rook',
          'display_name': 'Rook',
          'handle': 'rook',
          'character': '01',
          'status': 'active',
          'profile': 'claude-opus',
          'task_counts': {'in_progress': 3, 'todo': 2},
          'presence': {'state': 'idle'},
        }),
      ];

  @override
  Future<List<InboxEntry>> agentInbox(String agentId,
          {String? contains,
          String? kind,
          int? before,
          int limit = 50}) async =>
      [
        for (final id in [9, 8])
          InboxEntry.fromJson({'id': id, 'from_kind': 'agent', 'text': 'x'}),
      ];

  @override
  Future<List<MemoryScope>> memoryScopes() async => [
        MemoryScope.fromJson(
            {'key': 'agent:rook', 'kind': 'agent', 'entries': 48}),
      ];

  @override
  Future<ServerConfig> getConfig({bool force = false}) async =>
      ServerConfig.fromJson({
        'profiles': [
          {'name': 'claude-opus', 'provider': 'anthropic'},
          {'name': 'gpt', 'provider': 'openai'},
        ],
      });

  @override
  Future<void> deleteSession(String sessionId) async => deleted.add(sessionId);
}

Future<void> _shot(WidgetTester t, String name) async {
  const dir = String.fromEnvironment('SHOT_DIR');
  if (dir.isEmpty) return;
  await t.runAsync(() async {
    final b = t.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('shot')));
    final img = await b.toImage();
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 250));
  }
  // Character images decode on the real event loop.
  await t
      .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 300)));
  await t.pump(const Duration(milliseconds: 250));
  // The audio plugin has no host in tests.
  t.takeException();
}

Future<_Client> _setUp(WidgetTester t, TargetPlatform platform, Size size,
    Widget Function(_Client) home) async {
  debugDefaultTargetPlatformOverride = platform;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  SharedPreferences.setMockInitialValues({'inbox_seen_rook': 5});
  final sockets = <_Socket>[];
  DaemonClient.wsConnector = (uri, {connectTimeout, pingInterval}) {
    final s = _Socket(uri);
    sockets.add(s);
    return s;
  };
  addTearDown(() => DaemonClient.wsConnector = null);
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = size;
  addTearDown(t.view.reset);
  await t.runAsync(() async {
    await CharacterRoster.load();
    await ThemeManager.instance.setName('stone');
  });
  final client = _Client();
  await t.pumpWidget(RepaintBoundary(
    key: const ValueKey('shot'),
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: home(client),
    ),
  ));
  await t.pump(const Duration(milliseconds: 200));
  final attach = sockets.where((s) => s.uri.path.contains('attach'));
  if (attach.isNotEmpty) {
    attach.last.controller.add(jsonEncode({
      'wire': 'snapshot',
      'session_id': 'sess-r8',
      'workspace': '/tmp/proj',
      'status': 'idle',
      'events': [],
      'goal': null,
      'lanes': [
        {
          'id': 'l1',
          'title': 'Golden baselines',
          'status': 'running',
          'started_at': '',
          'profile': 'gpt'
        },
        {'id': 'l2', 'title': 'Lint', 'status': 'running', 'started_at': ''},
        {'id': 'l3', 'title': 'Docs', 'status': 'running', 'started_at': ''},
      ],
      'counts': {'changed_files': 4, 'open_prs': 1, 'processes': 2},
    }));
  }
  await _settle(t);
  return client;
}

Future<void> _unmount(WidgetTester t) async {
  await t.pumpWidget(const SizedBox.shrink());
  await t.pump();
  debugDefaultTargetPlatformOverride = null;
}

Future<void> _scrollEnd(WidgetTester t, Finder scroll) async {
  await t.drag(scroll, const Offset(0, -3000));
  await _settle(t);
}

Widget _session(_Client c) => SessionScreen(
    client: c, sessionId: 'sess-r8', title: 'Sidebar density', onMenu: () {});

Widget _agentHome(_Client c) => Builder(
      builder: (ctx) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => openAgentActions(ctx,
                client: c, agentId: 'rook', agentName: 'Rook'),
            child: const Text('open'),
          ),
        ),
      ),
    );

void main() {
  testWidgets('session actions on a phone', (t) async {
    await _setUp(t, TargetPlatform.android, const Size(390, 844), _session);
    await t.tap(find.text('Sidebar density').first);
    await _settle(t);
    expect(find.text('Lanes'), findsOneWidget);
    expect(find.text('3 running'), findsOneWidget);
    expect(find.text('Set a goal'), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 250));
    }
    await _shot(t, 'session-phone');
    final scroll = find.descendant(
        of: find.byType(Drawer), matching: find.byType(SingleChildScrollView));
    await _scrollEnd(t, scroll);
    expect(find.text('Delete session'), findsOneWidget);
    await _shot(t, 'session-phone-end');
    await _unmount(t);
  });

  testWidgets('session actions on desktop', (t) async {
    await _setUp(t, TargetPlatform.macOS, const Size(460, 820), _session);
    await t.tap(find.byTooltip('Session actions'));
    await _settle(t);
    expect(find.text('Wakes and schedule'), findsOneWidget);
    await _shot(t, 'session-desktop');
    await _unmount(t);
  });

  testWidgets('delete session confirms, deletes and leaves', (t) async {
    final c = await _setUp(
        t,
        TargetPlatform.android,
        const Size(390, 844),
        (c) => Builder(builder: (ctx) {
              return Navigator(
                onGenerateRoute: (_) =>
                    MaterialPageRoute<void>(builder: (_) => _session(c)),
              );
            }));
    await t.tap(find.text('Sidebar density').first);
    await _settle(t);
    final scroll = find.descendant(
        of: find.byType(Drawer), matching: find.byType(SingleChildScrollView));
    await _scrollEnd(t, scroll);
    await t.tap(find.text('Delete session'));
    await _settle(t);
    expect(c.deleted, isEmpty);
    await t.tap(find.text('Delete').last);
    await _settle(t);
    expect(c.deleted, ['sess-r8']);
    await _unmount(t);
  });

  testWidgets('agent actions on a phone', (t) async {
    await _setUp(t, TargetPlatform.android, const Size(390, 844), _agentHome);
    await t.tap(find.text('open'));
    await _settle(t);
    expect(find.text('2 new'), findsOneWidget);
    expect(find.text('5 open'), findsOneWidget);
    expect(find.text('48 entries'), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
    await _shot(t, 'agent-phone');
    await _scrollEnd(t, find.byType(SingleChildScrollView).last);
    expect(find.text('Delete agent'), findsOneWidget);
    await _shot(t, 'agent-phone-end');
    await _unmount(t);
  });

  testWidgets('agent actions on desktop', (t) async {
    await _setUp(t, TargetPlatform.macOS, const Size(460, 820), _agentHome);
    await t.tap(find.text('open'));
    await _settle(t);
    expect(find.text('Name and appearance'), findsOneWidget);
    await _shot(t, 'agent-desktop');
    await _unmount(t);
  });
}

class _Socket extends StreamChannelMixin implements WebSocketChannel {
  _Socket(this.uri);
  final Uri uri;
  final controller = StreamController<dynamic>.broadcast();
  @override
  Stream get stream => controller.stream;
  @override
  late final WebSocketSink sink = _Sink();
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
  @override
  void add(dynamic data) {}
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future addStream(Stream stream) => Future.value();
  @override
  Future close([int? closeCode, String? closeReason]) => Future.value();
  @override
  Future get done => Future.value();
}
