import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/tasks/task_common.dart';
import 'package:snippet/screens/tasks/task_list.dart';

class _Fake extends DaemonClient {
  _Fake() : super('http://feed-test', 't');
  final asked = <String, int>{};
  @override
  Future<List<TaskItem>> recentTasks(
      {required String status, required int limit}) async {
    asked[status] = limit;
    final have = status == 'done' ? 250 : 3;
    return [
      for (var i = 0; i < (have < limit ? have : limit); i++)
        TaskItem.fromJson({
          'id': '$status-$i',
          'title': 'Task $i',
          'status': status,
          'updated_at': '2026-11-0${(i % 9) + 1}T00:00:00Z',
        }),
    ];
  }
}

void main() {
  testWidgets('feed loads 100 per status and pages with Load more',
      (tester) async {
    final c = _Fake();
    final feed = TaskFeed(c, onChange: () {});
    await tester.runAsync(feed.refresh);
    expect(c.asked['done'], 100);
    expect(c.asked['todo'], 100);
    expect(feed.tasks.where((t) => t.status == TaskStatus.done).length, 100);
    expect(feed.hasMore(TaskStatus.done), isTrue);
    expect(feed.hasMore(TaskStatus.todo), isFalse);

    await tester.runAsync(() => feed.loadMore(TaskStatus.done));
    expect(c.asked['done'], 200);
    expect(c.asked['todo'], 100);
    await tester.runAsync(() => feed.loadMore(TaskStatus.done));
    expect(feed.tasks.where((t) => t.status == TaskStatus.done).length, 250);
    expect(feed.hasMore(TaskStatus.done), isFalse);
    feed.dispose();
    await tester.pump(const Duration(minutes: 5));
  });

  testWidgets('a group with more shows Load more', (tester) async {
    TaskStatus? asked;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: TaskList(
          tasks: [
            TaskItem.fromJson(
                {'id': 'a', 'title': 'Old work', 'status': 'done'}),
          ],
          onOpen: (_) {},
          onRefresh: () async {},
          hasMore: (s) => s == TaskStatus.done,
          onLoadMore: (s) async => asked = s,
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('Load more'), findsOneWidget);
    await tester.tap(find.text('Load more'));
    await tester.pump();
    expect(asked, TaskStatus.done);
  });
}
