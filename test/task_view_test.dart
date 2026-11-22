import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/tasks/task_view.dart';

TaskItem _t(String id, String status,
        {int priority = 0, String updated = '2026-11-20T10:00:00Z'}) =>
    TaskItem.fromJson({
      'id': id,
      'title': id,
      'status': status,
      'priority': priority,
      'created_at': '2026-11-01T10:00:00Z',
      'updated_at': updated,
    });

SessionInfo _s({String? origin}) => SessionInfo.fromJson(
    {'id': 's', 'folder': '/tmp/wt', if (origin != null) 'origin_folder': origin});

void main() {
  test('groups follow board order and drop empty groups', () {
    final g = groupTasks([
      _t('a', 'done'),
      _t('b', 'todo'),
      _t('c', 'in_review'),
      _t('d', 'in_progress'),
    ], TaskSort.updated);
    expect([for (final x in g) x.$1], [
      TaskStatus.inReview,
      TaskStatus.inProgress,
      TaskStatus.todo,
      TaskStatus.done,
    ]);
  });

  test('sorts by updated, created and priority', () {
    final a = _t('a', 'todo', priority: 1, updated: '2026-11-20T09:00:00Z');
    final b = _t('b', 'todo', priority: 3, updated: '2026-11-20T08:00:00Z');
    final c = _t('c', 'todo', priority: 3, updated: '2026-11-20T11:00:00Z');
    expect([for (final t in sortTasks([a, b, c], TaskSort.updated)) t.id],
        ['c', 'a', 'b']);
    expect([for (final t in sortTasks([a, b, c], TaskSort.priority)) t.id],
        ['c', 'b', 'a']);
  });

  test('branch and changes only for a started task in its own worktree', () {
    final own = _s(origin: '/home/x/repo');
    expect(showWorktreeFacts(_t('a', 'todo'), own), isFalse);
    expect(showWorktreeFacts(_t('a', 'in_progress'), own), isTrue);
    expect(showWorktreeFacts(_t('a', 'in_progress'), _s()), isFalse);
    expect(showWorktreeFacts(_t('a', 'in_progress'), null), isFalse);
  });

  test('selection movement clamps and starts at the ends', () {
    expect(moveSelection(-1, 1, 4), 0);
    expect(moveSelection(-1, -1, 4), 3);
    expect(moveSelection(3, 1, 4), 3);
    expect(moveSelection(0, -1, 4), 0);
    expect(moveSelection(1, 1, 0), -1);
  });
}
