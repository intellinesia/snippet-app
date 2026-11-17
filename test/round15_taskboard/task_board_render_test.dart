import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/tasks/task_board.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/theme.dart';

class _Daemon extends DaemonClient {
  _Daemon() : super('https://daemon.invalid', 'test-token');

  final DeviceEventHub _hub = DeviceEventHub.local();
  @override
  DeviceEventHub get deviceEvents => _hub;

  static String _ago(int m) =>
      DateTime.now().toUtc().subtract(Duration(minutes: m)).toIso8601String();

  late final items = <Map<String, dynamic>>[
    {
      'id': 'ac218e00',
      'title': 'Agent tools: wait action, scoped profiles',
      'status': 'in_review',
      'created_by_kind': 'agent',
      'created_by_id': 'snippet',
      'status_reason': 'Reviewer verdict pending',
      'updated_at': _ago(20),
    },
    {
      'id': 'a41c0b00',
      'title': 'Desktop redesign: round 5 sidebar, cards, settings',
      'status': 'in_progress',
      'created_by_kind': 'agent',
      'created_by_id': 'snippet',
      'session_id': 's1',
      'updated_at': _ago(14),
      'work_plan': [
        {'step': 'Compact sidebar rows, 32 px', 'status': 'done'},
        {'step': 'Cards in round 5 style', 'status': 'in_progress'},
        {'step': 'Settings: nav, list, editor', 'status': 'pending'},
        {'step': 'Build 23 and screenshots', 'status': 'pending'},
      ],
    },
    {
      'id': '58e81700',
      'title': 'Daily LinkedIn sync',
      'status': 'in_progress',
      'created_by_kind': 'agent',
      'created_by_id': 'snippet',
      'updated_at': _ago(2),
    },
    {
      'id': '7d2f9e00',
      'title': 'Profile the daemon CPU use',
      'status': 'todo',
      'created_by_kind': 'agent',
      'created_by_id': 'mission-control',
      'updated_at': _ago(30),
    },
    {
      'id': '09c68300',
      'title': 'Short tool names accepted as aliases',
      'status': 'done',
      'created_by_kind': 'agent',
      'created_by_id': 'snippet',
      'updated_at': _ago(1),
    },
  ];

  @override
  Future<List<TaskItem>> recentTasks(
          {required String status, required int limit}) async =>
      (await tasks()).where((t) => t.status.wire == status).take(limit).toList();

  @override
  Future<List<TaskItem>> tasks(
          {String? status, String? agentId, int? limit}) async =>
      items.map(TaskItem.fromJson).toList();

  @override
  Future<List<SessionInfo>> sessions({String? folder, int? limit}) async => [
        SessionInfo.fromJson(
            {'id': 's1', 'folder': '/w/snippet', 'branch': 'feat/redesign-all'}),
      ];

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => [
        for (final (id, n) in [('snippet', 'snippet'), ('mission-control', 'mission-control')])
          CoordinationAgent.fromJson({
            'id': id,
            'full_name': n,
            'handle': id,
            'kind': 'agent',
            'status': 'active',
          }),
      ];

  @override
  Future<List<TaskAgent>> taskAgents(String id) async => [
        TaskAgent.fromJson({
          'task_id': id,
          'agent_id': 'snippet',
          'role': 'worker',
          'status': 'active',
          'work_session_id': 's1',
        }),
        TaskAgent.fromJson(
            {'task_id': id, 'agent_id': 'mission-control', 'role': 'reviewer'}),
      ];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('desktop board: grouped list beside the selected task', (t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1280, 800);
    addTearDown(t.view.reset);

    await t.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: RepaintBoundary(
          key: const ValueKey('shot'),
          child: ColoredBox(
            color: AppColors.bg,
            child: TaskBoard(client: _Daemon()),
          ),
        ),
      ),
    ));
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 300));

    expect(find.text('Task board'), findsOneWidget);
    expect(find.text('Needs review'), findsWidgets);
    expect(find.text('In flight'), findsOneWidget);
    expect(find.text('Done today'), findsOneWidget);
    expect(find.text('Open room'), findsOneWidget);

    await t.tap(find.text('Desktop redesign: round 5 sidebar, cards, settings'));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.text('Open room'), findsOneWidget);
    expect(find.text('Open session'), findsOneWidget);
    expect(find.text('Message'), findsOneWidget);
    expect(find.text('Plan'), findsOneWidget);
    expect(find.text('People'), findsOneWidget);

    const dir = String.fromEnvironment('SHOT_DIR');
    if (dir.isNotEmpty) {
      await t.runAsync(() async {
        final b = t.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('shot')));
        final img = await b.toImage();
        final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
        File('$dir/task_board.png').writeAsBytesSync(bytes!.buffer.asUint8List());
      });
    }
  });
}
