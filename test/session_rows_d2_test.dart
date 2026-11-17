import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/models.dart';

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

}
