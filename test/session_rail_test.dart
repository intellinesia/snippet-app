import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/session.dart';
import 'package:snippet/screens/session_rail.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/wake_models.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

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
  void push(Map<String, dynamic> p) => _controller.add(jsonEncode(p));
}

class _Sink implements WebSocketSink {
  _Sink(this._s);
  final StreamSink _s;
  @override
  void add(dynamic data) {}
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future addStream(Stream stream) => Future.value();
  @override
  Future close([int? closeCode, String? closeReason]) => _s.close();
  @override
  Future get done => _s.done;
}

class _Counting extends DaemonClient {
  _Counting() : super('http://127.0.0.1:9090', 'tok');
  final calls = <String>[];
  Never _no(String name) {
    calls.add(name);
    throw Exception('offline');
  }

  @override
  Future<GitStatus> gitStatus(String session) async => _no('git');
  @override
  Future<List<SessionInfo>> sessions({String? folder, int? limit}) async =>
      _no('sessions');
  @override
  Future<List<Map<String, dynamic>>> bgList(String session) async => _no('bg');
  @override
  Future<WakeSchedule?> wake(String owner, {String? name}) async => _no('wake');
  @override
  Future<KeepWarmEntry?> keepWarmFor(String owner) async => _no('warm');
  @override
  Future<List<TaskItem>> tasks({String? status, String? agentId, int? limit}) async =>
      _no('tasks');
}

Widget _rail(DaemonClient client, String status, {bool mc = false}) => MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: SessionRail(
          client: client,
          sessionId: mc ? 'mission-control' : 'sess-1',
          state: HarnessState.fromJson({'status': status, 'workspace': '/tmp/ws'}),
          isMissionControl: mc,
          profileLabel: 'Default',
          resumeMode: 'ask',
          onModel: () {},
          onWakes: () {},
          onGoal: () {},
          onCycleResume: () {},
        ),
      ),
    );

Future<_Socket> _pump(
  WidgetTester tester, {
  required String sessionId,
  Size size = const Size(1280, 800),
  Map<String, Object> prefs = const {},
}) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  final socket = _Socket();
  DaemonClient.wsConnector = (uri, {connectTimeout, pingInterval}) => socket;
  addTearDown(() => DaemonClient.wsConnector = null);
  SharedPreferences.setMockInitialValues(prefs);
  sessionRailCollapsed.value = false;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: SessionScreen(
      client: DaemonClient('http://127.0.0.1:9090', 'tok'),
      sessionId: sessionId,
      title: 'Test Session',
      embedded: true,
    ),
  ));
  await tester.pump();
  socket.push({'wire': 'snapshot', 'status': 'idle', 'workspace': '/tmp/ws'});
  await tester.pump(const Duration(milliseconds: 100));
  return socket;
}

Future<void> _dispose(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  debugDefaultTargetPlatformOverride = null;
}

void main() {
  testWidgets('rail shows for a session on desktop', (tester) async {
    await _pump(tester, sessionId: 'sess-1');
    expect(find.byType(SessionRail), findsOneWidget);
    expect(find.text('Autonomy'), findsOneWidget);
    expect(find.text('Workspace'), findsOneWidget);
    await _dispose(tester);
  });

  testWidgets('rail hides for agent desks and narrow windows', (tester) async {
    await _pump(tester, sessionId: 'inbox-agent-1');
    expect(find.byType(SessionRail), findsNothing);
    await _dispose(tester);

    await _pump(tester, sessionId: 'sess-1', size: const Size(800, 700));
    expect(find.byType(SessionRail), findsNothing);
    await _dispose(tester);
  });

  testWidgets('a turn refreshes only the worktree and processes', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues({});
    final client = _Counting();
    await tester.pumpWidget(_rail(client, 'idle'));
    await tester.pump();
    expect(client.calls.toSet(), {'git', 'sessions', 'bg', 'wake', 'warm', 'tasks'});
    client.calls.clear();
    await tester.pumpWidget(_rail(client, 'running'));
    await tester.pump();
    expect(client.calls, unorderedEquals(['git', 'bg']));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Mission Control shows only Autonomy and Model', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues({});
    final client = _Counting();
    await tester.pumpWidget(_rail(client, 'idle', mc: true));
    await tester.pump();
    expect(find.text('Autonomy'), findsOneWidget);
    expect(find.text('Model'), findsOneWidget);
    for (final g in ['Workspace', 'Running', 'Task', 'History']) {
      expect(find.text(g), findsNothing, reason: g);
    }
    expect(client.calls.toSet(), {'wake', 'warm'});
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('collapse toggle persists', (tester) async {
    await _pump(tester, sessionId: 'sess-1');
    await tester.tap(find.byTooltip('Hide session rail'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('Workspace'), findsNothing);
    expect(find.byTooltip('Show session rail'), findsOneWidget);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(kSessionRailCollapsedPref), isTrue);
    await _dispose(tester);
  });
}
