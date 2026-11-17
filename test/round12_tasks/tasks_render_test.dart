import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/tasks/task_sheet.dart';
import 'package:snippet/screens/tasks/tasks_panel.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/theme.dart';

class _Daemon extends DaemonClient {
  _Daemon() : super('https://daemon.invalid', 'test-token');

  final DeviceEventHub _hub = DeviceEventHub.local();
  @override
  DeviceEventHub get deviceEvents => _hub;

  final moves = <String, TaskStatus>{};
  late final List<Map<String, dynamic>> items = _items();

  static String _ago(int minutes) => DateTime.now()
      .toUtc()
      .subtract(Duration(minutes: minutes))
      .toIso8601String();

  static List<Map<String, dynamic>> _items() => [
        {
          'id': 't1',
          'title': 'Group cards share the bubble lane',
          'status': 'in_review',
          'created_by_kind': 'agent',
          'created_by_id': 'rook',
          'status_reason': 'cards sit in the avatar lane at a fixed width',
          'updated_at': _ago(5),
        },
        {
          'id': 't2',
          'title': 'Post the round 10 build to the beta channel',
          'status': 'blocked',
          'status_reason': 'Waiting on your approval to upload',
          'updated_at': _ago(30),
        },
        {
          'id': 't3',
          'title': 'Restyle group and agent chat cards',
          'status': 'in_progress',
          'description':
              'The approval, document and task cards in group chats look unlike the rest of the app. Rook is moving them to the grouped-row style, with clean previews instead of raw markdown.\n\nSecond paragraph is not shown.',
          'session_id': 's1',
          'created_by_kind': 'agent',
          'created_by_id': 'rook',
          'updated_at': _ago(40),
          'work_plan': [
            {'step': 'Read how agent cards are built', 'status': 'done'},
            {
              'step': 'Rebuild the approval card as grouped segments',
              'status': 'done'
            },
            {'step': 'Update the card tests', 'status': 'in_progress'},
            {'step': 'Render and compare with the mockup', 'status': 'pending'},
          ],
        },
        {
          'id': 't4',
          'title': 'Daily LinkedIn sync scrape',
          'status': 'in_progress',
          'updated_at': _ago(0),
        },
        {
          'id': 't5',
          'title': 'Follow up with the hackathon organisers',
          'status': 'failed',
          'status_reason': 'A safety check stopped this work from starting',
          'updated_at': _ago(90),
        },
        {
          'id': 't6',
          'title': 'Write the release notes',
          'status': 'todo',
          'updated_at': _ago(120),
        },
        {
          'id': 't7',
          'title': 'Old finished chore',
          'status': 'done',
          'updated_at': _ago(500),
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
  Future<TaskItem> getTask(String id) async =>
      TaskItem.fromJson(items.firstWhere((t) => t['id'] == id));

  @override
  Future<List<SessionInfo>> sessions({String? folder, int? limit}) async => [
        SessionInfo.fromJson({'id': 's1', 'folder': '/w/snippet-mobile'}),
      ];

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => [
        CoordinationAgent.fromJson({
          'id': 'rook',
          'full_name': 'Rook',
          'handle': 'rook',
          'kind': 'agent',
          'status': 'active',
        }),
      ];

  @override
  Future<List<BoardEntry>> taskLog(String id, {int limit = 50}) async => [
        BoardEntry.fromJson({
          'id': 2,
          'agent_id': 'rook',
          'kind': 'noted',
          'summary': 'Cards fill the bubble lane rather than hugging their content',
          'created_at': '2026-11-17T08:39:00Z',
        }),
        BoardEntry.fromJson({
          'id': 1,
          'agent_id': 'mc',
          'kind': 'noted',
          'summary': 'Turn passed from Mission Control to Rook',
          'created_at': '2026-11-17T08:31:00Z',
        }),
      ];

  @override
  Future<List<TaskTurn>> taskTurns(String id) async => const [];

  @override
  Future<TaskItem> setTaskStatus(String id, TaskStatus status) async {
    moves[id] = status;
    final row = items.firstWhere((t) => t['id'] == id);
    row['status'] = status.wire;
    return TaskItem.fromJson(row);
  }
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

void _phone(WidgetTester tester) {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.reset);
}

/// A phone test; the platform override must be cleared inside the test body.
void _test(String name, Future<void> Function(WidgetTester t) body) {
  testWidgets(name, (t) async {
    try {
      await body(t);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

Widget _app(Widget child) => MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: RepaintBoundary(
          key: const ValueKey('shot'),
          child: ColoredBox(
            color: AppColors.bg,
            child: SafeArea(child: child),
          ),
        ),
      ),
    );

void main() {
  _test('phone list: Active sections, counts and the Up next tab', (t) async {
    _phone(t);
    final c = _Daemon();
    await t.pumpWidget(_app(TasksPanel(client: c, phoneHeader: false)));
    await t.pumpAndSettle();

    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Up next'), findsOneWidget);
    for (final s in ['Ready for review', 'Needs you', 'Working', 'Stopped']) {
      expect(find.byKey(ValueKey('section-$s')), findsOneWidget, reason: s);
    }
    expect(find.text('Updated 5 min ago'), findsNothing,
        reason: 'newest is the task updated just now');
    expect(find.textContaining('Updated '), findsOneWidget);
    expect(find.textContaining('Plan 3 of 4 · Update the card tests'),
        findsOneWidget);
    expect(find.textContaining('Just started'), findsOneWidget);
    expect(find.text('Write the release notes'), findsNothing);
    expect(find.text('Old finished chore'), findsNothing);
    await _shot(t, 'tasks_active');

    await t.tap(find.byKey(const ValueKey('tab-upNext')));
    await t.pumpAndSettle();
    expect(find.text('Write the release notes'), findsOneWidget);
    expect(find.text('Restyle group and agent chat cards'), findsNothing);
    expect(find.byKey(const ValueKey('section-Up next')), findsOneWidget);
    await _shot(t, 'tasks_upnext');
  });

  _test('search reaches done tasks', (t) async {
    _phone(t);
    await t.pumpWidget(_app(TasksPanel(client: _Daemon(), phoneHeader: false)));
    await t.pumpAndSettle();
    await t.tap(find.byTooltip('Search tasks'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField), 'chore');
    await t.pumpAndSettle();
    expect(find.text('Old finished chore'), findsOneWidget);
  });

  _test('checkbox asks before marking done', (t) async {
    _phone(t);
    final c = _Daemon();
    await t.pumpWidget(_app(TasksPanel(client: c, phoneHeader: false)));
    await t.pumpAndSettle();
    await t.tap(find.byKey(const ValueKey('check-t4')));
    await t.pumpAndSettle();
    expect(find.text('Mark as done?'), findsOneWidget);
    expect(c.moves, isEmpty);
    await t.tap(find.text('Mark done'));
    await t.pumpAndSettle();
    expect(c.moves['t4'], TaskStatus.done);
    expect(find.text('Daily LinkedIn sync scrape'), findsNothing);
  });

  _test('tapping a row opens the sheet', (t) async {
    _phone(t);
    final c = _Daemon();
    await t.pumpWidget(_app(TasksPanel(client: c, phoneHeader: false)));
    await t.pumpAndSettle();
    await t.tap(find.text('Restyle group and agent chat cards'));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('task-sheet-title')), findsOneWidget);
    expect(find.text('What Rook did'), findsOneWidget);
    expect(find.text('Decisions and updates'), findsOneWidget);
    expect(find.text('Resources'), findsOneWidget);
    expect(find.textContaining('Second paragraph'), findsNothing);
    expect(find.text('Update the card tests'), findsOneWidget);
  });

  _test('sheet render', (t) async {
    _phone(t);
    final c = _Daemon();
    await t.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        backgroundColor: Colors.black,
        body: RepaintBoundary(
          key: const ValueKey('shot'),
          child: Stack(children: [
            const ColoredBox(color: Colors.black, child: SizedBox.expand()),
            Positioned(
              top: 52,
              left: 0,
              right: 0,
              bottom: 0,
              child: TaskSheet(client: c, taskId: 't3', onClose: () {}),
            ),
          ]),
        ),
      ),
    ));
    await t.pumpAndSettle();
    await _shot(t, 'task_sheet');
  });

  _test('review sheet offers approve and send back', (t) async {
    _phone(t);
    final c = _Daemon();
    await t.pumpWidget(_app(TaskSheet(client: c, taskId: 't1', onClose: () {})));
    await t.pumpAndSettle();
    await t.scrollUntilVisible(
        find.byKey(const ValueKey('task-sheet-approve')), 200,
        scrollable: find.byType(Scrollable).first);
    await t.tap(find.byKey(const ValueKey('task-sheet-approve')));
    await t.pumpAndSettle();
    expect(c.moves['t1'], TaskStatus.done);
  });
}
