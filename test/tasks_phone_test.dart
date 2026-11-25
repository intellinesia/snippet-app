import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:snippet/api.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/tasks/task_phone.dart';
import 'package:snippet/screens/tasks/task_phone_list.dart';
import 'package:snippet/screens/tasks/tasks_panel.dart';
import 'package:snippet/theme.dart';

class FakeTasks extends DaemonClient {
  FakeTasks(this.items) : super('https://daemon.invalid', 'test-token');
  final DeviceEventHub _hub = DeviceEventHub.local();
  @override
  DeviceEventHub get deviceEvents => _hub;
  List<Map<String, dynamic>> items;

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
        SessionInfo.fromJson({'id': 's1', 'folder': '/x/proj', 'agent_id': 'buddy'})
      ];
  @override
  Future<List<CoordinationAgent>> coordinationAgents() async =>
      [CoordinationAgent.fromJson({'id': 'buddy', 'display_name': 'Buddy'})];
}

Map<String, dynamic> task(String id, String status,
        {String kind = 'agent', int priority = 2, String session = 's1', int ageMin = 4}) =>
    {
      'id': id,
      'title': 'Task $id of the coordinator panel',
      'status': status,
      'priority': priority,
      'created_by_kind': kind,
      'created_by_id': kind == 'human' ? 'me' : 'lead',
      'session_id': session,
      'updated_at':
          DateTime.now().subtract(Duration(minutes: ageMin)).toUtc().toIso8601String(),
    };

Widget wrap(double scale, Widget home) => MaterialApp(
      theme: buildAppTheme(),
      builder: (c, ch) => MediaQuery(
          data: MediaQuery.of(c).copyWith(
              textScaler: TextScaler.linear(scale), disableAnimations: true),
          child: ch!),
      home: home,
    );

/// The platform override must be cleared before the test body returns.
void phoneTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  final rows = <Map<String, dynamic>>[
    task('r1', 'in_review'),
    task('b1', 'blocked', kind: 'human'),
    task('f1', 'failed'),
    task('p1', 'in_progress'),
    task('t1', 'todo', priority: 0),
    for (var i = 0; i < 7; i++) task('d$i', 'done', ageMin: 10 + i),
    task('c1', 'cancelled', ageMin: 30),
    task('anon', 'todo', session: 'zz', priority: 1),
  ];
  for (final w in [360.0, 393.0, 430.0]) {
    for (final scale in [1.0, 1.35, 2.0]) {
      phoneTest('tasks root w=$w s=$scale', (tester) async {
        SharedPreferences.setMockInitialValues({});
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(w, 852);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
            wrap(scale, Scaffold(body: TasksPanel(client: FakeTasks(rows)))));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(tester.takeException(), isNull);
        final title = tester.getTopLeft(find.text('Tasks').last);
        expect(tester.widget<Text>(find.text('Tasks').last).style!.fontSize, 28);
        expect(title.dx, 16);
        // chips
        final chips = [
          for (final k in ['all', 'mine', 'agents'])
            tester.getRect(find.byKey(ValueKey('chip-$k')))
        ];
        for (final c in chips) {
          expect(c.height, 44);
        }
        expect(chips[0].left, 16);
        expect(chips[1].left - chips[0].right, 8);
        expect(chips[2].left - chips[1].right, 8);
        // plus
        final plus = tester.getRect(find.bySemanticsLabel('New task'));
        expect(plus.width, greaterThanOrEqualTo(48));
        expect(plus.right, w - 4);
        // rows
        final cards = find.byType(PhoneTaskCard);
        expect(cards, findsWidgets);
        for (final e in cards.evaluate()) {
          final r = tester.getRect(find.byElementPredicate((x) => x == e));
          expect(r.width, w);
          expect(r.height, greaterThanOrEqualTo(56));
        }
        // order: needs you rows first, anon todo shows no owner
        final first = tester.getRect(find.byKey(const ValueKey('t-r1')));
        final glyphHand = find.descendant(
            of: find.byKey(const ValueKey('t-r1')), matching: find.byType(Icon));
        expect(glyphHand, findsWidgets);
        final titleX = tester.getTopLeft(find.descendant(
            of: find.byKey(const ValueKey('t-r1')),
            matching: find.textContaining('Task r1'))).dx;
        expect(titleX, 52);
        final av = tester.getRect(find.descendant(
            of: find.byKey(const ValueKey('t-r1')),
            matching: find.byType(OwnerAvatar)));
        expect(av.right, w - 16);
        expect(av.size, const Size(28, 28));
        final hair = tester.getRect(find
            .descendant(
                of: find.byKey(const ValueKey('t-r1')),
                matching: find.byType(ColoredBox))
            .last);
        expect(hair.left, 52);
        expect(hair.right, w - 16);
        // ignore: avoid_print
        print('w=$w s=$scale avatar=$av hairline=$hair');
        // done folded to 5
        await tester.scrollUntilVisible(find.byKey(const ValueKey('done-fold')), 300,
            scrollable: find.byType(Scrollable).first);
        expect(find.textContaining('Show 3 more'), findsOneWidget);
        expect(find.byKey(const ValueKey('t-d6')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('done-fold')));
        await tester.pump();
        await tester.scrollUntilVisible(find.byKey(const ValueKey('t-c1')), 300,
            scrollable: find.byType(Scrollable).first);
        expect(find.byKey(const ValueKey('t-c1')), findsOneWidget);
        expect(tester.takeException(), isNull);
      });
    }
  }

  phoneTest('filters and empties', (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap(
        1, Scaffold(body: TasksPanel(client: FakeTasks([task('a', 'todo')])))));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.tap(find.byKey(const ValueKey('chip-mine')));
    await tester.pump();
    expect(find.text('Nothing here'), findsOneWidget);
    expect(find.text('No tasks created by you.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chip-agents')));
    await tester.pump();
    expect(find.byKey(const ValueKey('t-a')), findsOneWidget);

    await tester.pumpWidget(
        wrap(1, Scaffold(body: TasksPanel(client: FakeTasks([]), key: UniqueKey()))));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('No tasks yet'), findsOneWidget);
    expect(find.text('New task'), findsWidgets);
  });
}
