import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/mobile_session_home.dart';
import 'package:snippet/screens/session_list_row.dart';
import 'package:snippet/screens/tasks/task_common.dart';
import 'package:snippet/screens/tasks/task_list.dart';
import 'package:snippet/theme.dart';

void main() {
  test('SessionInfo and TaskItem parse optional D2 wire fields', () {
    final full = SessionInfo.fromJson({
      'id': 's1',
      'folder': '/code/app',
      'conversation': 'default',
      'title': 'Work on D2',
      'status': 'running',
      'last_active': 1700000000,
      'running': true,
      'plan': {
        'done': 2,
        'total': 5,
        'current': 'Wire PR cache',
        'step_started_at': 1700000100,
      },
      'lanes': {
        'running': 2,
        'items': [
          {
            'id': 'l1',
            'title': 'Review',
            'agent': 'reviewer',
            'activity': 'Reading diffs',
          },
          {
            'id': 'l2',
            'title': 'Tests',
            'agent': null,
            'activity': null,
          },
        ],
      },
      'next_wake_at': 1700000500,
      'pr': {
        'number': 280,
        'title': 'Add session rows',
        'state': 'open',
        'checks': 'passing',
        'mergeable': true,
        'url': 'https://github.com/org/repo/pull/280',
      },
    });
    expect(full.plan?.done, 2);
    expect(full.plan?.total, 5);
    expect(full.plan?.current, 'Wire PR cache');
    expect(full.plan?.stepStartedAt, 1700000100);
    expect(full.lanes?.running, 2);
    expect(full.lanes?.items.length, 2);
    expect(full.lanes?.items.first.activity, 'Reading diffs');
    expect(full.nextWakeAt, 1700000500);
    expect(full.pr?.number, 280);
    expect(full.pr?.state, 'open');
    expect(full.pr?.checks, 'passing');
    expect(full.pr?.mergeable, true);

    final older = SessionInfo.fromJson({
      'id': 's2',
      'folder': '/code/app',
      'conversation': 'default',
      'title': 'Old daemon',
      'status': 'idle',
      'last_active': 1700000000,
    });
    expect(older.plan, isNull);
    expect(older.lanes, isNull);
    expect(older.nextWakeAt, isNull);
    expect(older.pr, isNull);

    final task = TaskItem.fromJson({
      'id': 't1',
      'title': 'Build D2',
      'status': 'in_progress',
      'plan_done': 2,
      'plan_total': 5,
    });
    expect(task.planDone, 2);
    expect(task.planTotal, 5);
  });

  testWidgets('LiveSessionCard renders plan step, lanes, and open PR actions',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    var reviewed = false;
    var merged = false;
    final session = SessionInfo.fromJson({
      'id': 's1',
      'folder': '/code/app',
      'conversation': 'default',
      'title': 'Session hero',
      'status': 'running',
      'running': true,
      'last_active': now - 60,
      'running_since': now - 3600,
      'plan': {
        'done': 2,
        'total': 5,
        'current': 'Wire PR cache',
        'step_started_at': now - 14 * 60,
      },
      'lanes': {
        'running': 2,
        'items': [
          {'id': 'l1', 'title': 'Tests', 'activity': 'Reading diffs'},
        ],
      },
      'pr': {
        'number': 280,
        'title': 'Add D2',
        'state': 'open',
        'checks': 'passing',
        'mergeable': true,
        'url': 'https://github.com/org/repo/pull/280',
      },
    });

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: LiveSessionCard(
          session: session,
          onTap: () {},
          onReviewPr: () => reviewed = true,
          onMergePr: () => merged = true,
        ),
      ),
    ));

    expect(find.text('Plan 3/5 · Snippet'), findsOneWidget);
    expect(find.text('14m'), findsOneWidget);
    expect(find.byKey(const Key('card-progress')), findsOneWidget);
    expect(find.text('Working'), findsNothing);
    expect(find.text('Wire PR cache'), findsOneWidget);
    expect(find.text('2 lanes · Reading diffs'), findsOneWidget);
    expect(find.text('PR #280 · checks passing'), findsOneWidget);
    expect(find.text('Review'), findsOneWidget);
    expect(find.text('Merge'), findsOneWidget);

    await tester.tap(find.text('Review'));
    await tester.tap(find.text('Merge'));
    expect(reviewed, isTrue);
    expect(merged, isTrue);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('SessionListRow renders step on active and wake on quiet rows',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final wakeDt = DateTime(2026, 11, 16, 8, 0); // Monday 08:00 local
    final wakeTs = wakeDt.millisecondsSinceEpoch ~/ 1000;

    final active = SessionInfo.fromJson({
      'id': 's1',
      'folder': '/code/app',
      'conversation': 'default',
      'title': 'Active desktop row',
      'status': 'running',
      'running': true,
      'last_active': now - 30,
      'branch': 'feat/d2',
      'plan': {
        'done': 2,
        'total': 5,
        'current': 'Wire PR cache',
        'step_started_at': now - 14 * 60,
      },
      'pr': {
        'number': 280,
        'title': 'Add D2',
        'state': 'open',
        'checks': 'passing',
        'mergeable': true,
        'url': 'https://github.com/org/repo/pull/280',
      },
    });
    final quiet = SessionInfo.fromJson({
      'id': 's2',
      'folder': '/code/app',
      'conversation': 'default',
      'title': 'Quiet row',
      'status': 'idle',
      'last_active': now - 3600,
      'branch': 'main',
      'next_wake_at': wakeTs,
    });

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: SizedBox(
          width: 320,
          child: Column(
            children: [
              SessionListRow(
                session: active,
                onTap: () {},
                onReviewPr: () {},
                onMergePr: () {},
              ),
              SessionListRow(session: quiet, onTap: () {}),
            ],
          ),
        ),
      ),
    ));

    // Plan progress moved to the home hero; the row only shows working dots.
    expect(find.text('plan 3/5 · 14m'), findsNothing);
    expect(find.text('PR #280 · checks passing'), findsOneWidget);
    expect(find.text('wakes Mon 08:00'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('TaskPlanProgress and TaskRow show progress bar and step x of y',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
    final task = TaskItem.fromJson({
      'id': 't1',
      'title': 'Ship D2',
      'status': 'in_progress',
      'plan_done': 2,
      'plan_total': 5,
    });

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Column(
          children: [
            const TaskPlanProgress(done: 2, total: 5),
            TaskRow(task: task, onTap: () {}),
          ],
        ),
      ),
    ));

    expect(find.text('plan 3/5'), findsNWidgets(2));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
