import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'package:snippet/api.dart';
import 'package:snippet/github_models.dart';
import 'package:snippet/goal_models.dart';
import 'package:snippet/models.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/screens/git.dart';
import 'package:snippet/screens/session_panels.dart';
import 'package:snippet/screens/tasks/task_detail_screen.dart';

// Design-parity checks for the session tools pages (round 5 mockups).

String _ago(Duration d) => DateTime.now().toUtc().subtract(d).toIso8601String();

Map<String, dynamic> _task(String id, String title, String agent, String status, {String? goal}) => {
      'id': id, 'title': title, 'description': 'Readiness probe fails on cold starts. Raise the startup grace and verify with rolling restarts.',
      'status': status, 'session_id': 's-$id', 'thread_id': 'th-$id', 'created_by_kind': 'agent', 'created_by_id': agent,
      'created_at': _ago(const Duration(hours: 3)), 'updated_at': _ago(const Duration(minutes: 9)),
      if (goal != null) ...{'goal_id': 'g1', 'goal_title': goal},
      'work_plan': [
        {'step': 'Reproduce the cold-start failure', 'status': 'done'},
        {'step': 'Raise startup grace to 15 s', 'status': 'done'},
        {'step': 'Verify 3 rolling restarts', 'status': 'in_progress'},
      ],
    };

Map<String, dynamic> _pr(int n, String title, String author, List<String> checks, String review) => {
      'number': n, 'title': title, 'author': {'login': author}, 'headRefName': 'fix/notch-idle-cpu', 'baseRefName': 'main',
      'state': 'OPEN', 'reviewDecision': review, 'additions': 41, 'deletions': 18, 'updatedAt': _ago(const Duration(hours: 2)),
      'url': 'https://github.com/x/y/pull/$n',
      'statusCheckRollup': [for (final c in checks) {'name': 'ci', 'status': c == 'pending' ? 'IN_PROGRESS' : 'COMPLETED', 'conclusion': c == 'pending' ? '' : c}],
    };

class _Daemon extends DaemonClient {
  _Daemon() : super('https://daemon.invalid', 'test-token');

  @override
  late final DeviceEventHub deviceEvents = DeviceEventHub.local();

  @override
  Future<GitStatus> gitStatus(String session) async => GitStatus.fromJson({
        'ok': true, 'branch': 'lane/sidebar-polish', 'upstream': 'origin/lane/sidebar-polish', 'ahead': 2, 'behind': 0, 'clean': false,
        'files': [
          {'path': 'lib/screens/sidebar.dart', 'x': 'M', 'y': ' ', 'staged': true},
          {'path': 'lib/screens/agent_card.dart', 'x': 'M', 'y': ' ', 'staged': true},
          {'path': 'lib/screens/session_list_row.dart', 'x': ' ', 'y': 'M', 'unstaged': true},
          {'path': 'test/goldens/sidebar_390.png', 'x': '?', 'y': '?', 'untracked': true, 'unstaged': true},
        ],
      });

  @override
  Future<List<Map<String, dynamic>>> bgList(String session) async => [
        {'id': 'p1', 'command': 'flutter run -d linux', 'pid': 48213, 'running': true},
        {'id': 'p2', 'command': 'cloudflared tunnel run snippet', 'pid': 47102, 'running': true},
        {'id': 'p3', 'command': 'npm run build', 'pid': 47001, 'running': false, 'status': '0'},
      ];

  @override
  Future<String> bgLog(String session, String id, {int tail = 300}) async =>
      'Launching lib/main.dart on Linux in debug mode…\nBuilding Linux application…\n✓ Built build/linux/x64/debug/bundle/snippet';

  @override
  Future<Map<String, ({int files, int add, int del})>> checkpointStats(String session, List<String> ids) async => {
        'c4': (files: 3, add: 10, del: 2), 'c3': (files: 2, add: 4, del: 1), 'c2': (files: 0, add: 0, del: 0), 'c1': (files: 5, add: 30, del: 9),
      };

  @override
  Future<GithubStatus?> githubStatus(String session) async => _gh;

  @override
  Future<({List<PrSummary> prs, String? next})> githubPrPage(String session, String filter, {String? cursor, int? limit}) async => (
        prs: [
          PrSummary.fromJson(_pr(280, 'Notch HUD: stop the idle CPU spin', 'wren', ['SUCCESS', 'SUCCESS'], 'REVIEW_REQUIRED')..['reviewRequests'] = [{'login': 'me'}]),
          PrSummary.fromJson(_pr(284, 'Sidebar density on the 44pt grid', 'me', ['pending'], 'APPROVED')),
          PrSummary.fromJson(_pr(272, 'Theme sync across daemon and client', 'rook', ['FAILURE'], 'CHANGES_REQUESTED')),
        ],
        next: null,
      );

  @override
  Future<PrDetail> githubPr(String session, int number) async => PrDetail.fromJson({
        ..._pr(280, 'Notch HUD: stop the idle CPU spin', 'wren', ['SUCCESS', 'SUCCESS'], 'APPROVED'),
        'body': 'Moves the idle tick off the display link so the HUD stops waking the CPU every frame.',
        'mergeable': 'MERGEABLE', 'mergeStateStatus': 'CLEAN', 'createdAt': _ago(const Duration(hours: 2)),
        'files': [
          {'path': 'macos/Runner/Notch.swift', 'additions': 30, 'deletions': 12, 'changeType': 'MODIFIED'},
          {'path': 'lib/macos_notch.dart', 'additions': 8, 'deletions': 4, 'changeType': 'MODIFIED'},
          {'path': 'test/notch_test.dart', 'additions': 3, 'deletions': 2, 'changeType': 'MODIFIED'},
        ],
        'commits': [
          {'oid': 'abc1234', 'messageHeadline': 'Move idle tick', 'authors': [{'login': 'wren'}], 'committedDate': _ago(const Duration(hours: 2))},
          {'oid': 'def5678', 'messageHeadline': 'Test', 'authors': [{'login': 'wren'}], 'committedDate': _ago(const Duration(hours: 1))},
        ],
        'reviews': [{'author': {'login': 'me'}, 'state': 'APPROVED', 'body': '', 'submittedAt': _ago(const Duration(minutes: 30)), 'id': 'r1'}],
        'comments': [],
        'threads': [],
      });

  @override
  Future<String> githubPrDiff(String session, int number) async => '';

  final _tasks = [
    _task('t-252', 'Sidebar search', 'rook', 'in_review'),
    _task('t-248', 'Theme sync across daemon and client', 'rook', 'in_progress'),
    _task('t-244', 'Staging probe startup grace', 'moss', 'in_review', goal: 'Staging stays green on deploy'),
    _task('t-250', 'Token audit', 'pip', 'todo'),
    _task('t-241', 'Golden baselines', 'wren', 'done'),
  ];

  @override
  Future<List<TaskItem>> tasks({String? status, String? agentId, int? limit}) async =>
      _tasks.map(TaskItem.fromJson).where((t) => status == null || t.status.wire == status).toList();

  @override
  Future<List<TaskItem>> recentTasks({required String status, required int limit}) async =>
      (await tasks()).where((t) => t.status.wire == status).take(limit).toList();

  @override
  Future<TaskItem> getTask(String id) async => TaskItem.fromJson(_tasks.firstWhere((t) => t['id'] == id, orElse: () => _tasks[2]));

  @override
  Future<List<TaskAgent>> taskAgents(String id) async => [
        TaskAgent.fromJson({'task_id': id, 'agent_id': 'moss', 'role': 'implementer', 'status': 'working', 'work_session_id': 's-$id', 'scope': 'deploy/', 'added_at': _ago(const Duration(hours: 3))}),
      ];

  @override
  Future<TaskLinks> taskLinks(String id) async => const TaskLinks();

  @override
  Future<List<TaskTurn>> taskTurns(String id) async => const [];

  @override
  Future<List<BoardEntry>> taskLog(String taskId, {int limit = 50}) async => [
        BoardEntry.fromJson({'id': 2, 'agent_id': 'moss', 'kind': 'progress', 'summary': 'restarts 2 of 3 green', 'created_at': _ago(const Duration(minutes: 30))}),
        BoardEntry.fromJson({'id': 1, 'agent_id': 'moss', 'kind': 'noted', 'summary': 'passed the turn to you · review', 'created_at': _ago(const Duration(minutes: 12))}),
      ];

  @override
  Future<List<SessionInfo>> sessions({String? folder, int? limit}) async => [
        SessionInfo.fromJson({'id': 's-t-244', 'folder': '/worktrees/probe', 'origin_folder': '/repo/snippet-service', 'branch': 'fix/probe-grace', 'total_changes': {'files': 2, 'added': 12, 'removed': 3}}),
      ];

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => const [];

  @override
  Future<GoalDetail> goal(String id) async => GoalDetail.fromJson({
        'id': 'g1', 'title': 'Staging stays green on deploy', 'outcome': 'Deploys never page', 'status': 'open', 'requester': 'boss',
        'created_at': _ago(const Duration(days: 2)), 'closed_at': null,
        'progress': {'done': 2, 'total': 3}, 'evidence': {'have': 1, 'total': 2}, 'attention': null,
        'acceptance': [
          {'criterion': 'Deploys pass readiness on a cold pool', 'method': 'rolling restarts', 'evidence': 'T-244 rolling restarts'},
          {'criterion': 'Alert fires within 2 min of a failed probe', 'method': 'probe test', 'evidence': null},
        ],
        'plan': [
          {'n': 1, 'task_id': 't-241', 'title': 'Probe timings', 'depends_on': []},
          {'n': 2, 'task_id': 't-244', 'title': 'Startup grace', 'depends_on': [1]},
          {'n': 3, 'task_id': 't-253', 'title': 'Probe alert', 'depends_on': [2]},
        ],
        'tasks': [
          {'id': 't-241', 'slice': 1, 'title': 'Probe timings', 'status': 'done', 'agent': 'moss'},
          {'id': 't-244', 'slice': 2, 'title': 'Startup grace', 'status': 'done', 'agent': 'moss'},
          {'id': 't-253', 'slice': 3, 'title': 'Probe alert', 'status': 'todo', 'agent': 'moss', 'waiting_on': ['t-244']},
        ],
        'blockers': [],
      });
}

const _gh = GithubStatus(available: true, repo: 'intellinesia/snippet-mobile', viewer: 'me', permission: 'ADMIN');

class _Socket extends StreamChannelMixin implements WebSocketChannel {
  final _c = StreamController<dynamic>.broadcast();
  @override
  Stream get stream => _c.stream;
  @override
  late final WebSocketSink sink = _Sink(_c.sink);
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
  final StreamSink _s;
  _Sink(this._s);
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

List<Checkpoint> _cps() {
  final now = DateTime.now();
  DateTime at(int dDay, int h, int m) => DateTime(now.year, now.month, now.day - dDay, h, m);
  return [
    for (final (id, t) in [('c4', at(0, 9, 41)), ('c3', at(0, 9, 28)), ('c2', at(0, 9, 12)), ('c1', at(1, 18, 2))])
      Checkpoint.fromJson({'id': id, 'label': '', 'created_at': t.toIso8601String()}),
  ];
}


Future<void> _phone(WidgetTester tester, Widget page, {bool pushed = false}) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  SharedPreferences.setMockInitialValues({});
  DaemonClient.wsConnector = (uri, {connectTimeout, pingInterval}) => _Socket();
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  final nav = GlobalKey<NavigatorState>();
  await tester.pumpWidget(MaterialApp(
      navigatorKey: nav,
      theme: buildAppTheme(),
      home: pushed ? const Scaffold() : page));
  if (pushed) {
    nav.currentState!.push(MaterialPageRoute<void>(builder: (_) => page));
  }
  for (var i = 0; i < 4; i++) {
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 30)));
    await tester.pump(const Duration(milliseconds: 300));
  }
}

Future<void> _settle(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox());
  await tester.pump(const Duration(seconds: 2));
  DaemonClient.wsConnector = null;
  debugDefaultTargetPlatformOverride = null;
  tester.view.reset();
}

void main() {
  testWidgets('checkpoints: the newest has no Restore or Fork', (tester) async {
    await _phone(tester, Scaffold(body: SessionCheckpointsPanel(
        checkpoints: _cps(), onRewind: (_) {}, onFork: (_) {})));
    expect(find.text('Checkpoints \u00b7 4'), findsOneWidget);
    expect(find.text('Restore'), findsNWidgets(3));
    expect(find.text('Fork'), findsNWidgets(3));
    await _settle(tester);
  });

  testWidgets('git: untracked reads U and Commit stays live with no message', (tester) async {
    await _phone(tester, GitScreen(client: _Daemon(), sessionId: 's1', onClose: () {}));
    expect(find.text('U'), findsOneWidget);
    expect(find.text('Commit 2'), findsOneWidget);
    await tester.tap(find.text('Commit 2'));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Enter a commit message'), findsOneWidget);
    await _settle(tester);
  });

  testWidgets('task detail: short id and capitalised holder', (tester) async {
    await _phone(tester, TaskDetailScreen(client: _Daemon(), taskId: 't-244'));
    expect(find.text('T-244'), findsOneWidget);
    expect(find.text('Moss'), findsWidgets);
    await _settle(tester);
  });

}
