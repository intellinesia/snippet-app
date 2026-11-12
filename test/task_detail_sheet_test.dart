import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/tasks/task_detail_screen.dart';
import 'package:snippet/swr.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _Daemon extends DaemonClient {
  _Daemon() : super('https://daemon.invalid', 'test-token');

  @override
  late final DeviceEventHub deviceEvents = DeviceEventHub.local();

  @override
  Future<TaskItem> getTask(String id) async => TaskItem.fromJson({
        'id': 't1',
        'title': 'Fix the demo voice',
        'description': 'Speak ISE as “Ice”.',
        'status': 'in_review',
        'session_id': 's1',
        'thread_id': 'th1',
        'created_by_kind': 'agent',
        'created_by_id': 'mc',
        'created_at': '2026-11-01T10:00:00Z',
        'updated_at': '2026-11-12T10:00:00Z',
        'work_plan': [
          {'step': 'Draft the fix', 'status': 'done'},
          {'step': 'Verify the demo', 'status': 'in_progress'},
        ],
      });

  @override
  Future<List<TaskAgent>> taskAgents(String id) async => [
        TaskAgent.fromJson({
          'task_id': 't1',
          'agent_id': 'snippet',
          'role': 'implementer',
          'status': 'waiting',
          'work_session_id': 's1',
          'scope': 'src/tts',
          'added_at': '2026-11-01T10:00:00Z',
        }),
        TaskAgent.fromJson({
          'task_id': 't1',
          'agent_id': 'mc',
          'role': 'reviewer',
          'status': 'waiting',
          'added_at': '2026-11-01T10:00:00Z',
        }),
      ];

  @override
  Future<TaskLinks> taskLinks(String id) async => const TaskLinks();

  @override
  Future<List<TaskTurn>> taskTurns(String id) async => [
        TaskTurn.fromJson({
          'id': 1,
          'agent_id': 'snippet',
          'session_id': 's1',
          'started_at': '2026-11-12T09:00:00Z',
          'ended_at': '2026-11-12T09:30:00Z',
          'files': ['src/tts/x.dart'],
          'commits': ['abc123 fix acronyms'],
        }),
      ];

  @override
  Future<List<BoardEntry>> taskLog(String id, {int limit = 50}) async => [
        BoardEntry.fromJson({
          'id': 1,
          'agent_id': 'snippet',
          'kind': 'reported',
          'summary': 'v5 delivered: ISE spoken as Ice',
          'created_at': '2026-11-12T09:31:00Z',
        }),
      ];

  @override
  Future<List<SessionInfo>> sessions({String? folder, int? limit}) async => [
        SessionInfo.fromJson({
          'id': 's1',
          'folder': '/worktrees/demo',
          'origin_folder': '/repo',
          'branch': 'feat/demo',
          'total_changes': {'files': 3, 'added': 30, 'removed': 4},
        }),
      ];

  @override
  Future<List<TaskItem>> tasks(
          {String? status, String? agentId, int? limit}) async =>
      const [];
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

Future<void> _phone(WidgetTester tester, Widget child) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  DaemonClient.wsConnector = (uri, {connectTimeout, pingInterval}) => _Socket();
  addTearDown(() => DaemonClient.wsConnector = null);
  tester.view.physicalSize = const Size(390, 780);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: child));
  await tester.pumpAndSettle();
}

void phoneTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  phoneTest('summary sheet shows title, byline, cards and segment',
      (tester) async {
    await _phone(tester, TaskDetailScreen(client: _Daemon(), taskId: 't1'));

    expect(find.text('Fix the demo voice'), findsWidgets);
    expect(find.text('In review'), findsWidgets);
    expect(find.text('snippet'), findsWidgets);
    expect(find.text('mc'), findsWidgets);
    for (final key in [
      'Status',
      'Agents',
      'Reviewer',
      'Branch',
      'Owned paths',
    ]) {
      expect(find.text(key), findsOneWidget, reason: key);
    }
    expect(find.text('feat/demo'), findsOneWidget);
    expect(find.text('src/tts'), findsOneWidget);
    expect(find.text('Brief'), findsOneWidget);
    expect(find.textContaining('Speak ISE'), findsOneWidget);
    expect(find.text('Report'), findsOneWidget);
    expect(find.textContaining('v5 delivered'), findsWidgets);
    for (final tab in ['Summary', 'Plan', 'Log', 'Changes']) {
      expect(find.text(tab), findsWidgets, reason: tab);
    }
  });

  phoneTest('segment switches plan, log and changes', (tester) async {
    await _phone(tester, TaskDetailScreen(client: _Daemon(), taskId: 't1'));

    await tester.tap(find.text('Plan'));
    await tester.pumpAndSettle();
    expect(find.textContaining('Plan ·'), findsOneWidget);
    expect(find.text('Draft the fix'), findsOneWidget);
    expect(find.text('snippet'), findsWidgets);

    await tester.tap(find.text('Log'));
    await tester.pumpAndSettle();
    expect(find.textContaining('v5 delivered'), findsWidgets);

    await tester.tap(find.text('Changes'));
    await tester.pumpAndSettle();
    expect(find.text('src/tts/x.dart'), findsOneWidget);
    expect(find.text('abc123 fix acronyms'), findsOneWidget);

    await tester.tap(find.text('Summary'));
    await tester.pumpAndSettle();
    expect(find.text('Owned paths'), findsOneWidget);
  });
}
