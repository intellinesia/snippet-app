import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:snippet/api.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/models.dart';
import 'package:snippet/mobile_kit.dart';
import 'package:snippet/mochi.dart';
import 'package:snippet/screens/mobile_home/quiet_lists.dart';
import 'package:snippet/screens/shell_models.dart';
import 'package:snippet/screens/sidebar.dart';
import 'package:snippet/screens/tasks/task_phone.dart';
import 'package:snippet/screens/tasks/task_phone_list.dart';
import 'package:snippet/screens/tasks/tasks_panel.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/widgets.dart';

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
        // Title follows the kit's large title (size and inset owned there).
        expect(tester.widget<Text>(find.text('Tasks').last).style!.fontSize,
            mkLargeTitle().fontSize);
        expect(title.dx, inInclusiveRange(16, 20));
        // connected filter group: 44 targets, 4 apart on Android
        final chips = [
          for (final k in ['All', 'Mine', 'Agents'])
            tester.getRect(find.bySemanticsLabel(RegExp('^$k, ')))
        ];
        for (final c in chips) {
          expect(c.height, 44);
        }
        expect(chips[0].left, 16);
        expect(chips[1].left - chips[0].right, 4);
        expect(chips[2].left - chips[1].right, 4);
        // New task split button beside the large title, menu holds Board view
        final plus = tester.getRect(find.bySemanticsLabel('New task'));
        final menu = tester.getRect(find.bySemanticsLabel('Task options'));
        expect(plus.height, 40);
        expect(menu.right, w - 16);
        expect(menu.left - plus.right, 2);
        expect(plus.bottom, lessThanOrEqualTo(chips[0].top));
        // rows sit in the segmented list (16 inset on Android)
        final cards = find.byType(PhoneTaskCard);
        expect(cards, findsWidgets);
        for (final e in cards.evaluate()) {
          final r = tester.getRect(find.byElementPredicate((x) => x == e));
          expect(r.width, w - 32);
          expect(r.height, greaterThanOrEqualTo(64));
        }
        // v19 amber discipline: AppColors.run only on the needs-you dot
        // (at most one per row), AppColors.danger nowhere, and Text never uses run.
        const amberIds = {'t-r1', 't-b1'};
        final amberSeen = <String>{};
        void checkColours() {
          for (final e in find.byType(PhoneTaskCard).evaluate()) {
            final cardFinder = find.byElementPredicate((x) => x == e);
            final key = (e.widget.key as ValueKey?)?.value;
            var runDots = 0;
            for (final i in find
                .descendant(of: cardFinder, matching: find.byType(Icon))
                .evaluate()) {
              final c = (i.widget as Icon).color;
              expect(c, isNot(AppColors.danger), reason: 'red icon in $key');
              expect(c, isNot(AppColors.run), reason: 'amber icon in $key');
            }
            for (final a in find
                .descendant(of: cardFinder, matching: find.byType(AppIcon))
                .evaluate()) {
              final w2 = a.widget as AppIcon;
              expect(w2.color, isNot(AppColors.danger),
                  reason: 'red AppIcon in $key');
              expect(w2.color, isNot(AppColors.run),
                  reason: 'amber AppIcon in $key');
            }
            for (final c in find
                .descendant(of: cardFinder, matching: find.byType(Container))
                .evaluate()) {
              final w2 = c.widget as Container;
              final deco = w2.decoration;
              if (deco is BoxDecoration &&
                  deco.color == AppColors.run &&
                  deco.shape == BoxShape.circle) {
                runDots++;
              }
            }
            for (final t in find
                .descendant(of: cardFinder, matching: find.byType(Text))
                .evaluate()) {
              final w2 = t.widget as Text;
              final colours = <Color?>[w2.style?.color];
              void walk(InlineSpan? s) {
                if (s is! TextSpan) return;
                colours.add(s.style?.color);
                s.children?.forEach(walk);
              }
              walk(w2.textSpan);
              expect(colours, isNot(contains(AppColors.run)),
                  reason: 'amber text in $key');
              expect(colours, isNot(contains(AppColors.danger)),
                  reason: 'red text in $key');
            }
            expect(runDots, lessThanOrEqualTo(1),
                reason: 'more than one amber dot in $key');
            if (runDots > 0) {
              expect(amberIds.contains(key), isTrue,
                  reason: 'amber dot in unexpected row $key');
              amberSeen.add('$key');
            }
          }
        }
        checkColours();
        // groups: Needs you (in_review, blocked, failed), Open, Completed
        expect(find.byKey(const ValueKey('group-Needs you')), findsOneWidget);
        // Large text pushes Open below the fold of the lazy list.
        await tester.scrollUntilVisible(
            find.byKey(const ValueKey('group-Open')), 100,
            scrollable: find.byType(Scrollable).first);
        expect(find.byKey(const ValueKey('group-Open')), findsOneWidget);
        expect(find.text('In progress'), findsNothing);
        final r1Rect = tester.getRect(find.byKey(const ValueKey('t-r1')));
        final f1Rect = tester.getRect(find.byKey(const ValueKey('t-f1')));
        final doingY = tester.getTopLeft(find.byKey(const ValueKey('group-Open'))).dy;
        expect(r1Rect.top, lessThan(doingY));
        expect(f1Rect.top, lessThan(doingY));
        // State marks: in_review & blocked use the 9 px amber dot; failed -> x.
        Finder amberDot(String key) => find.descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byWidgetPredicate((w) =>
                w is Container &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).color == AppColors.run &&
                (w.decoration as BoxDecoration).shape == BoxShape.circle));
        String iconOf(String key) => tester
            .widget<AppIcon>(find.descendant(
                of: find.byKey(ValueKey(key)), matching: find.byType(AppIcon)))
            .name;
        expect(amberDot('t-r1'), findsOneWidget);
        expect(amberDot('t-b1'), findsOneWidget);
        expect(tester.getSize(amberDot('t-r1')), const Size(9, 9));
        expect(tester.getSize(amberDot('t-b1')), const Size(9, 9));
        expect(iconOf('t-f1'), 'x');
        // priority word & time in sub line
        final r1Rich = tester.widget<Text>(find.descendant(
            of: find.byKey(const ValueKey('t-r1')),
            matching: find.byWidgetPredicate((w) => w is Text && w.textSpan != null)));
        final r1Sub = r1Rich.textSpan!.toPlainText();
        expect(r1Sub, contains('Review'));
        expect(r1Sub, contains('Buddy'));
        expect(r1Sub, contains('High'));
        expect(r1Sub, contains('4m'));
        final titleX = tester.getTopLeft(find.descendant(
            of: find.byKey(const ValueKey('t-r1')),
            matching: find.textContaining('Task r1'))).dx;
        // 16 tile inset + 16 + 40 mark slot + 14 gap
        expect(titleX, 86);
        final av = tester.getRect(find.descendant(
            of: find.byKey(const ValueKey('t-r1')),
            matching: find.byType(AgentMochi)));
        expect(av.right, closeTo(w - 32, 0.5));
        // ignore: avoid_print
        print('MEASURE w=$w s=$scale titleX=${title.dx} '
            'plus=${plus.left}..${plus.right} '
            'chipH=${chips[0].height} row=${r1Rect.width}x${r1Rect.height} '
            'textX=$titleX owner=${av.size.width}x${av.size.height}@R${av.right}');
        // Todo sits in Open after Doing, with the open ring
        await tester.scrollUntilVisible(find.byKey(const ValueKey('t-t1')), 200,
            scrollable: find.byType(Scrollable).first);
        expect(
            tester
                .widget<MkStateMark>(find.descendant(
                    of: find.byKey(const ValueKey('t-t1')),
                    matching: find.byType(MkStateMark)))
                .state,
            MkState.open);
        expect(tester.getTopLeft(find.byKey(const ValueKey('t-t1'))).dy,
            greaterThan(tester.getTopLeft(find.byKey(const ValueKey('t-p1'))).dy));
        // done folded to 5; done uses check, cancelled uses x
        await tester.scrollUntilVisible(find.byKey(const ValueKey('t-d0')), 300,
            scrollable: find.byType(Scrollable).first);
        expect(iconOf('t-d0'), 'check');
        await tester.scrollUntilVisible(find.byKey(const ValueKey('done-fold')), 300,
            scrollable: find.byType(Scrollable).first);
        expect(find.textContaining('Show 3 more'), findsOneWidget);
        expect(find.byKey(const ValueKey('t-d6')), findsNothing);
        await tester.tap(find.byKey(const ValueKey('done-fold')));
        await tester.pump();
        await tester.scrollUntilVisible(find.byKey(const ValueKey('t-c1')), 300,
            scrollable: find.byType(Scrollable).first);
        expect(find.byKey(const ValueKey('t-c1')), findsOneWidget);
        expect(iconOf('t-c1'), 'x');
        checkColours();
        // ignore: avoid_print
        print('AMBER w=$w s=$scale rows=${amberSeen.toList()..sort()}');
        expect(tester.takeException(), isNull);
      });
    }
  }

  phoneTest('MobileHome.tasks wires Sidebar to PhoneTasksRoot, not QuietTasksScreen',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.reset);
    final client = FakeTasks(rows);
    await tester.pumpWidget(wrap(
      1,
      Scaffold(
        body: Sidebar(
          instances: const [],
          active: null,
          client: client,
          selectedSessionId: null,
          sessions: const [],
          sessionsLoading: false,
          onRefreshSessions: () {},
          onNewSession: () {},
          onSelectInstance: (_) {},
          onOpenLead: () {},
          onOpenSession: (_, __, ___) {},
          onAddInstance: () {},
          onRenameInstance: (_, __) {},
          onRemoveInstance: (_) {},
          onSessionDeleted: (_) {},
          health: {client.baseUrl: true},
          onRefreshHealth: () {},
          topInset: false,
          mobileHome: MobileHome.tasks,
          onMobileHome: (_) {},
          agent: null,
          onAgent: (_) {},
        ),
      ),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.byType(PhoneTasksRoot), findsOneWidget);
    expect(find.byType(QuietTasksScreen), findsNothing);
    expect(find.bySemanticsLabel(RegExp('^All, ')), findsOneWidget);
    expect(find.bySemanticsLabel('Task options'), findsOneWidget);
    expect(find.byKey(const ValueKey('group-Needs you')), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

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
    await tester.tap(find.bySemanticsLabel(RegExp('^Mine, ')));
    await tester.pump();
    expect(find.text('Nothing here'), findsOneWidget);
    expect(find.text('No tasks created by you.'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel(RegExp('^Agents, ')));
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
