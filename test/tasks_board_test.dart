import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:snippet/api.dart';
import 'package:snippet/mochi.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/shell_models.dart';
import 'package:snippet/screens/tasks/task_kanban.dart';
import 'package:snippet/screens/tasks/tasks_panel.dart';
import 'package:snippet/store.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/theme.dart';

class _FakeDaemon extends DaemonClient {
  _FakeDaemon(
    this.items, {
    this.sessionRows = const [],
    this.agentRows = const [],
  }) : super('https://daemon.invalid', 'test-token');

  final DeviceEventHub _deviceEvents = DeviceEventHub.local();

  @override
  DeviceEventHub get deviceEvents => _deviceEvents;

  List<Map<String, dynamic>> items;
  final List<Map<String, dynamic>> sessionRows;
  final List<Map<String, dynamic>> agentRows;
  final moves = <String, TaskStatus>{};
  bool refuse = false;

  @override
  Future<List<TaskItem>> recentTasks(
          {required String status, required int limit}) async =>
      (await tasks()).where((t) => t.status.wire == status).take(limit).toList();

  @override
  Future<List<TaskItem>> tasks(
          {String? status, String? agentId, int? limit}) async =>
      items.map(TaskItem.fromJson).toList();

  @override
  Future<List<SessionInfo>> sessions({String? folder, int? limit}) async =>
      sessionRows.map(SessionInfo.fromJson).toList();

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async =>
      agentRows.map(CoordinationAgent.fromJson).toList();

  @override
  Future<TaskItem> setTaskStatus(String id, TaskStatus status) async {
    if (refuse) throw Exception('refused');
    moves[id] = status;
    final row = items.firstWhere((t) => t['id'] == id);
    row['status'] = status.wire;
    return TaskItem.fromJson(row);
  }
}

Map<String, dynamic> _task(
  String id,
  String title,
  String status, {
  String createdByKind = '',
  String createdById = '',
  String sessionId = '',
  String description = '',
  String? currentStep,
  String? statusReason,
  String updatedAt = '',
}) =>
    {
      'id': id,
      'title': title,
      'status': status,
      'priority': 0,
      'created_by_kind': createdByKind,
      'created_by_id': createdById,
      'session_id': sessionId,
      'description': description,
      if (currentStep != null) 'current_step': currentStep,
      if (statusReason != null) 'status_reason': statusReason,
      if (updatedAt.isNotEmpty) 'updated_at': updatedAt,
    };

Future<void> _pumpBoard(
  WidgetTester tester,
  _FakeDaemon client, {
  Size size = const Size(1440, 900),
}) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(body: TaskKanban(client: client)),
  ));
  await tester.pumpAndSettle();
}

Offset _columnCenter(WidgetTester tester, String label) {
  final header = tester.getCenter(find.text(label).first);
  return Offset(header.dx + 40, header.dy + 120);
}

Future<void> _drag(WidgetTester tester, String card, String column) async {
  final gesture = await tester.startGesture(tester.getCenter(find.text(card)));
  await tester.pump(const Duration(milliseconds: 50));
  await gesture.moveTo(_columnCenter(tester, column));
  await tester.pump(const Duration(milliseconds: 50));
  await gesture.up();
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('dragging a card to another column moves the task',
      (tester) async {
    final client = _FakeDaemon([
      _task('1', 'Write the docs', 'todo'),
      _task('2', 'Ship it', 'in_progress'),
    ]);
    await _pumpBoard(tester, client);

    for (final label in ['Needs you', 'Working', 'Queued', 'Done']) {
      expect(find.text(label), findsOneWidget);
    }
    expect(find.text('2 active'), findsOneWidget);

    await _drag(tester, 'Write the docs', 'Needs you');
    expect(client.moves['1'], TaskStatus.inReview);
  });

  testWidgets('Working takes no drops: only a dispatch starts work',
      (tester) async {
    final client = _FakeDaemon([_task('1', 'Write the docs', 'todo')]);
    await _pumpBoard(tester, client);

    await _drag(tester, 'Write the docs', 'Working');
    expect(client.moves, isEmpty);
  });

  testWidgets('a move the daemon refuses is put back', (tester) async {
    final client = _FakeDaemon([_task('1', 'Write the docs', 'todo')])
      ..refuse = true;
    await _pumpBoard(tester, client);

    await _drag(tester, 'Write the docs', 'Done');
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    final queued = tester.getCenter(find.text('Queued').first).dx;
    expect((tester.getCenter(find.text('Write the docs')).dx - queued).abs(),
        lessThan(200),
        reason: 'the card must return to its column after a refusal');
  });

  testWidgets('groups statuses into four columns and handles review actions',
      (tester) async {
    final client = _FakeDaemon([
      _task('1', 'Review card one', 'in_review'),
      _task('1b', 'Review card two', 'in_review'),
      _task('2', 'Blocked card', 'blocked'),
      _task('3', 'Failed card', 'failed'),
      _task('4', 'Working card', 'in_progress'),
      _task('5', 'Queued card', 'todo'),
      _task('6', 'Done card', 'done'),
      _task('7', 'Cancelled card', 'cancelled'),
    ]);
    await _pumpBoard(tester, client);

    expect(find.text('2 active · 4 needs you'), findsOneWidget);
    final doneY = tester.getTopLeft(find.text('Done card')).dy;
    final cancelledY = tester.getTopLeft(find.text('Cancelled card')).dy;
    expect(cancelledY, greaterThan(doneY));

    expect(find.text('Approve'), findsNWidgets(2));
    expect(find.text('Send back'), findsNWidgets(2));

    await tester.tap(find.text('Send back').first);
    await tester.pumpAndSettle();
    expect(client.moves['1'], TaskStatus.inProgress);

    await tester.tap(find.text('Approve').first);
    await tester.pumpAndSettle();
    expect(client.moves['1b'], TaskStatus.done);
  });

  testWidgets('cards render step fallback, agent name, folder, and age',
      (tester) async {
    final recent =
        DateTime.now().subtract(const Duration(minutes: 12)).toUtc().toIso8601String();
    final client = _FakeDaemon(
      [
        _task(
          '1',
          'Fix TTS acronyms',
          'in_review',
          createdByKind: 'agent',
          createdById: 'snippet-1',
          sessionId: 's1',
          currentStep: 'In review · v5 delivered',
          updatedAt: recent,
        ),
        _task(
          '2',
          'Fallback description',
          'todo',
          description: 'First line only\nSecond line ignored',
        ),
      ],
      sessionRows: [
        {'id': 's1', 'folder': '/home/snippet/code/technoxi'},
      ],
      agentRows: [
        {'id': 'snippet-1', 'display_name': 'Snippet', 'handle': 'snippet'},
      ],
    );
    await _pumpBoard(tester, client);

    expect(find.text('In review · v5 delivered'), findsOneWidget);
    expect(find.text('First line only'), findsOneWidget);
    expect(find.text('Snippet · technoxi'), findsOneWidget);
    expect(find.byType(AgentMochi), findsOneWidget);

    final ageText = tester.widget<Text>(find.text('12m'));
    expect(ageText.style?.color, AppColors.run);
  });

  testWidgets('search narrows the kanban board', (tester) async {
    final client = _FakeDaemon([
      _task('1', 'Write the docs', 'todo'),
      _task('2', 'Fix the login bug', 'blocked'),
    ]);
    await _pumpBoard(tester, client);

    await tester.enterText(find.byType(TextField), 'login');
    await tester.pumpAndSettle();
    expect(find.text('Fix the login bug'), findsOneWidget);
    expect(find.text('Write the docs'), findsNothing);
  });

  testWidgets('the search narrows the tasks panel', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final client = _FakeDaemon([
        _task('1', 'Write the docs', 'todo'),
        _task('2', 'Fix the login bug', 'blocked'),
      ]);
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: TasksPanel(client: client)),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Write the docs'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'login');
      await tester.pumpAndSettle();
      expect(find.text('Fix the login bug'), findsOneWidget);
      expect(find.text('Write the docs'), findsNothing);

      await tester.enterText(find.byType(TextField), 'nothing like this');
      await tester.pumpAndSettle();
      expect(find.text('No matching tasks'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('desktop Tasks has list controls but no board entry',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final client = _FakeDaemon([_task('1', 'Desktop task', 'todo')]);
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(body: TasksPanel(client: client)),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Tasks'), findsOneWidget);
      expect(find.text('Desktop task'), findsOneWidget);
      expect(find.byTooltip('Search tasks'), findsOneWidget);
      expect(find.byTooltip('New task'), findsOneWidget);
      expect(find.byTooltip('Open board'), findsNothing);
      expect(find.byType(TaskKanban), findsNothing);
      await tester.pumpWidget(const SizedBox.shrink());
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('legacy board descriptor remains readable for mobile restore', () {
    final client = _FakeDaemon(const []);
    final tab = ShellTab.board(client: client, instanceUrl: 'http://m');
    expect(tab.key, 'http://m|tasks-board');
    expect(tab.isMissionControl, isFalse);
    expect(tabIconKind(tab), 'kanban');

    final saved = OpenTabDescriptor(
        instanceUrl: 'http://m', title: tab.title, board: true);
    expect(OpenTabDescriptor.fromJson(saved.toJson()).board, isTrue);
  });
}
