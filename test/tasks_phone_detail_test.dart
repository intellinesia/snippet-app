import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/tasks/task_phone.dart';
import 'package:snippet/screens/tasks/task_phone_detail.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/widgets.dart';

class Fake extends DaemonClient {
  Fake(this.row, {this.refuse = false, this.entries = const []})
      : super('https://daemon.invalid', 'test-token');
  final DeviceEventHub _hub = DeviceEventHub.local();
  @override
  DeviceEventHub get deviceEvents => _hub;
  Map<String, dynamic> row;
  bool refuse;
  List<Map<String, dynamic>> entries;
  @override
  Future<TaskItem> getTask(String id) async => TaskItem.fromJson(row);
  @override
  Future<List<BoardEntry>> taskLog(String taskId, {int limit = 50}) async =>
      entries.map(BoardEntry.fromJson).toList();
  @override
  Future<TaskLinks> taskLinks(String id) async =>
      const TaskLinks(blockedBy: ['other']);
  @override
  Future<List<TaskItem>> tasks({String? status, String? agentId, int? limit}) async =>
      [TaskItem.fromJson(row), TaskItem.fromJson({'id': 'other', 'title': 'Other task'})];
  @override
  Future<List<CoordinationAgent>> coordinationAgents() async =>
      [CoordinationAgent.fromJson({'id': 'buddy', 'display_name': 'Buddy'})];
  @override
  Future<List<SessionInfo>> sessions({String? folder, int? limit}) async =>
      [SessionInfo.fromJson({'id': 's1', 'folder': '/x/proj', 'agent_id': 'buddy'})];
  @override
  Future<List<ArtifactInfo>> artifacts(String session) async => [
        const ArtifactInfo(id: 'a1', title: 'Plan doc', kind: 'document', caption: '', versions: [
          ArtifactVersion(n: 1, createdAt: 1, entry: '', source: '', url: '')
        ])
      ];
  @override
  Future<TaskItem> setTaskStatus(String id, TaskStatus status) async {
    if (refuse) throw Exception('cannot be moved to done by hand');
    row = {...row, 'status': status.wire};
    return TaskItem.fromJson(row);
  }
}

Map<String, dynamic> row(String status, {String desc = 'Ship it.'}) => {
      'id': 't1',
      'title': 'Re-QA toast principle',
      'status': status,
      'priority': 2,
      'created_by_kind': 'human',
      'created_by_id': 'me',
      'session_id': 's1',
      'description': desc,
    };

Widget wrap(double scale, Widget home) => MaterialApp(
      theme: buildAppTheme(),
      builder: (c, ch) => MediaQuery(
          data: MediaQuery.of(c).copyWith(
              textScaler: TextScaler.linear(scale), disableAnimations: true),
          child: ch!),
      home: home,
    );

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

Future<void> pump(WidgetTester tester, Fake c, double w, double scale) async {
  SharedPreferences.setMockInitialValues({});
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = Size(w, 852);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
      wrap(scale, TaskPhoneDetail(key: UniqueKey(), client: c, taskId: 't1')));
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  for (final w in [360.0, 393.0, 430.0]) {
    for (final scale in [1.0, 1.35, 2.0]) {
      phoneTest('detail w=$w s=$scale', (tester) async {
        await pump(tester, Fake(row('in_review')), w, scale);
        expect(tester.takeException(), isNull);
        final title = tester.getTopLeft(find.text('Re-QA toast principle'));
        expect(tester.widget<Text>(find.text('Re-QA toast principle')).style!.fontSize, 20);
        expect(title.dx, 16);
        final btn = tester.getRect(find.byKey(const ValueKey('mark-done')));
        expect(btn.width, w - 32);
        expect(btn.height, greaterThanOrEqualTo(48));
        expect(btn.left, 16);
        expect(852 - btn.bottom, 16);
        expect(find.text('Approve and mark done'), findsOneWidget);
        // tags
        final tag = tester.getRect(find.text('Review').first);
        final facts = [
          tester.getRect(find.text('Owner')),
          tester.getRect(find.text('Created by')),
        ];
        final val = tester.getTopLeft(find.text('Buddy'));
        expect(facts[0].left, 16);
        // Owner row, avatar at x124 and name at x156
        expect(val.dx, 156);
        for (final k in ['session-row', 'blocked-other']) {
          final r = tester.getRect(find.byKey(ValueKey(k)).first);
          expect(r.height, greaterThanOrEqualTo(56), reason: k);
          expect(r.width, w);
        }
        final blockedRect =
            tester.getRect(find.byKey(const ValueKey('blocked-other')).first);
        final blockedIcon = tester.widget<AppIcon>(find.descendant(
            of: find.byKey(const ValueKey('blocked-other')),
            matching: find.byWidgetPredicate(
                (x) => x is AppIcon && x.name == 'x')));
        expect(blockedIcon.size, 16);
        expect(blockedIcon.color, AppColors.fg1);
        final card = tester.getRect(find.byKey(const ValueKey('result-a1')));
        expect(card.left, 16);
        expect(card.width, w - 32);
        expect(card.height, greaterThanOrEqualTo(72));
        // ignore: avoid_print
        print('w=$w s=$scale title=$title button=$btn ownerLabel=${facts[0]} value=$val card=$card tag=$tag blocked=$blockedRect iconSize=${blockedIcon.size}');
        expect(find.text('Activity'), findsNothing);
        expect(find.text('Decisions and updates'), findsNothing);
        // body scrolls above the pinned button
        final list = tester.getRect(find.byKey(const ValueKey('task-detail-scroll')));
        expect(list.bottom, lessThanOrEqualTo(btn.top));
      });
    }
  }

  for (final st in ['todo', 'in_progress', 'in_review', 'blocked', 'done', 'cancelled']) {
    phoneTest('mark done visibility $st', (tester) async {
      await pump(tester, Fake(row(st, desc: '')), 393, 1);
      final shown = {'todo', 'in_progress', 'in_review'}.contains(st);
      expect(find.byKey(const ValueKey('mark-done')), shown ? findsOneWidget : findsNothing);
      expect(find.text('Brief'), findsNothing);
      expect(find.byType(DraggableScrollableSheet), findsNothing);
    });
  }

  phoneTest('mark done completes and refusal toasts', (tester) async {
    final ok = Fake(row('in_progress'));
    await pump(tester, ok, 393, 1);
    await tester.tap(find.byKey(const ValueKey('mark-done')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(ok.row['status'], 'done');
    expect(find.byKey(const ValueKey('mark-done')), findsNothing);
    final no = Fake(row('in_progress'), refuse: true);
    await pump(tester, no, 393, 1);
    await tester.tap(find.byKey(const ValueKey('mark-done')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.textContaining('cannot be moved'), findsOneWidget);
    expect(find.byKey(const ValueKey('mark-done')), findsOneWidget);
    await tester.pump(const Duration(seconds: 10));
  });

  phoneTest('activity and brief appear when present', (tester) async {
    final c = Fake(row('todo', desc: List.filled(30, 'line').join('\n')), entries: [
      {'id': 1, 'agent_id': 'buddy', 'kind': 'noted', 'summary': 'Picked it up', 'created_at': '2026-11-25T10:00:00Z'}
    ]);
    await pump(tester, c, 393, 1);
    expect(find.text('Activity'), findsOneWidget);
    expect(find.text('Picked it up'), findsOneWidget);
    expect(find.text('Brief'), findsOneWidget);
    expect(find.byKey(const ValueKey('brief-more')), findsOneWidget);
    final more = tester.getRect(find.byKey(const ValueKey('brief-more')));
    expect(more.height, 48);
    // ignore: avoid_print
    print('brief-more height=${more.height}');
  });

  phoneTest('amber only on the in-review hand, never red', (tester) async {
    Set<Color> pageColours() {
      final out = <Color>{};
      void walk(InlineSpan? s) {
        if (s is! TextSpan) return;
        if (s.style?.color != null) out.add(s.style!.color!);
        s.children?.forEach(walk);
      }
      for (final e in find.byType(Text).evaluate()) {
        final w = e.widget as Text;
        if (w.style?.color != null) out.add(w.style!.color!);
        walk(w.textSpan);
      }
      for (final e in find.byType(Icon).evaluate()) {
        final c = (e.widget as Icon).color;
        if (c != null) out.add(c);
      }
      for (final e in find.byType(AppIcon).evaluate()) {
        final c = (e.widget as AppIcon).color;
        if (c != null) out.add(c);
      }
      return out;
    }

    for (final st in ['todo', 'done']) {
      await pump(tester, Fake(row(st)), 393, 1);
      final colours = pageColours();
      expect(colours.contains(AppColors.run), isFalse,
          reason: 'amber present on $st detail');
      expect(colours.contains(AppColors.danger), isFalse,
          reason: 'red present on $st detail');
    }
    await pump(tester, Fake(row('in_review')), 393, 1);
    final runIcons = find.byWidgetPredicate(
        (x) => x is Icon && x.color == AppColors.run);
    expect(runIcons, findsOneWidget);
    final hand = tester.widget<AppIcon>(find.byWidgetPredicate(
        (x) => x is AppIcon && x.name == 'hand'));
    expect(hand.color, AppColors.run);
    final colours = pageColours();
    expect(colours.contains(AppColors.danger), isFalse);
    // ignore: avoid_print
    print('detail in_review runIcons=${runIcons.evaluate().length} '
        'hand size=${hand.size} color=${hand.color}');
  });
}
