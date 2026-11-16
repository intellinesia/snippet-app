import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/api.dart';
import 'package:snippet/chat/stage_header.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/session.dart';
import 'package:snippet/theme.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class FakeClient extends DaemonClient {
  FakeClient() : super('http://127.0.0.1:9090', 'tok');

  @override
  Future<List<SessionInfo>> sessions({String? folder, int? limit}) async => [
        SessionInfo.fromJson({
          'id': 'sess-r4',
          'title': 'Header test',
          'status': 'running',
          'agent_id': 'rook',
          'plan': {'done': 3, 'total': 5, 'current': 'Run the goldens'},
        }),
      ];

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => [
        CoordinationAgent.fromJson(
            {'id': 'rook', 'display_name': 'Rook', 'handle': 'rook'}),
      ];
}

Future<_Socket> _pumpSession(WidgetTester tester, Map<String, dynamic> snap,
    {Size size = const Size(390, 844)}) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  SharedPreferences.setMockInitialValues({});
  final sockets = <_Socket>[];
  DaemonClient.wsConnector = (uri, {connectTimeout, pingInterval}) {
    final s = _Socket(uri);
    sockets.add(s);
    return s;
  };
  addTearDown(() => DaemonClient.wsConnector = null);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: SessionScreen(
      client: FakeClient(),
      sessionId: 'sess-r4',
      title: 'Header test',
      onMenu: () {},
    ),
  ));
  await tester.pump(const Duration(milliseconds: 200));
  final attach = sockets.lastWhere((s) => s.uri.path.contains('attach'));
  attach.controller.add(jsonEncode({
    'wire': 'snapshot',
    'session_id': 'sess-r4',
    'workspace': '/tmp/proj',
    ...snap,
  }));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
  return attach;
}

void main() {
  testWidgets('running: stage header subtitle, step, lanes pill, quick actions',
      (tester) async {
    await _pumpSession(tester, {
      'status': 'running',
      'events': [],
      'lanes': [
        {'id': 'l1', 'title': 'Goldens', 'status': 'running', 'started_at': ''},
        {'id': 'l2', 'title': 'Note', 'status': 'running', 'started_at': ''},
      ],
    });
    expect(find.byType(StageHeader), findsOneWidget);
    expect(find.text('Rook · Run the goldens · step 4 of 5'), findsOneWidget);
    expect(find.text('2 lanes'), findsOneWidget);
    expect(find.text('Interrupt'), findsOneWidget);
    expect(find.text('Hand off'), findsOneWidget);
    expect(find.text('Fork from here'), findsOneWidget);
    expect(find.text('Steer Rook, or queue for later'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('idle: no quick actions, hint names the agent', (tester) async {
    await _pumpSession(tester, {'status': 'idle', 'events': []});
    expect(find.text('Interrupt'), findsNothing);
    expect(find.text('Message Rook'), findsOneWidget);
    expect(find.textContaining('2 lanes'), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('approval pending: waiting on you and the asks row',
      (tester) async {
    final at = DateTime.now()
            .subtract(const Duration(minutes: 2, seconds: 5))
            .millisecondsSinceEpoch ~/
        1000;
    await _pumpSession(tester, {
      'status': 'waiting_for_input',
      'events': [
        {
          'kind': 'approval_request',
          'tool_name': 'bash',
          'summary': 'git push',
          'index': 1,
          'total': 1,
          'at': at,
        },
      ],
    });
    expect(find.text('Rook · waiting on you'), findsOneWidget);
    expect(find.text('Rook asks · step 4 of 5'), findsOneWidget);
    expect(find.text('waiting 2 min'), findsOneWidget);
    expect(find.text('Approve'), findsOneWidget);
    expect(find.text('Deny'), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    debugDefaultTargetPlatformOverride = null;
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
