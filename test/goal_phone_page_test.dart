import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/api.dart';
import 'package:snippet/goal_models.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/goals/goal_phone_page.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/theme.dart';

class Fake extends DaemonClient {
  Fake(this.json) : super('https://daemon.invalid', 'test-token');
  final DeviceEventHub _hub = DeviceEventHub.local();
  @override
  DeviceEventHub get deviceEvents => _hub;
  Map<String, dynamic> json;
  @override
  Future<GoalDetail> goal(String id) async => GoalDetail.fromJson(json);
  @override
  Future<List<SessionInfo>> sessions({String? folder, int? limit}) async =>
      [SessionInfo.fromJson({'id': 's1', 'folder': '/x/proj', 'title': 'Sashy build'})];
  @override
  Future<List<CoordinationAgent>> coordinationAgents() async =>
      [CoordinationAgent.fromJson({'id': 'sashy', 'display_name': 'Sashy'})];
}

Map<String, dynamic> goalJson({bool withAcceptance = true}) => {
      'id': 'g1',
      'title': 'Launch goals',
      'outcome': 'Ship it',
      'status': 'open',
      'requester': 'boss',
      'created_at': '2026-10-30T10:00:00Z',
      'progress': {'done': 3, 'total': 5},
      'evidence': {'have': 0, 'total': 0},
      'acceptance': withAcceptance
          ? [
              {'criterion': 'List shows progress', 'method': 'm', 'evidence': null}
            ]
          : [],
      'plan': [],
      'tasks': [
        {'id': 't1', 'title': 'Done one', 'status': 'done', 'session_id': 's1', 'agent': 'sashy', 'updated_at': DateTime.now().subtract(const Duration(minutes: 12)).toUtc().toIso8601String()},
        {'id': 't2', 'title': 'Blocked one', 'status': 'blocked', 'session_id': 's1', 'agent': 'sashy', 'updated_at': DateTime.now().subtract(const Duration(minutes: 5)).toUtc().toIso8601String()},
        {'id': 't3', 'title': 'Open one', 'status': 'todo'},
      ],
      'blockers': [],
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

void main() {
  for (final w in [360.0, 393.0, 430.0]) {
    for (final scale in [1.0, 1.35, 2.0]) {
      phoneTest('goal page w=$w s=$scale', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(w, 852);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
            wrap(scale, GoalPhonePage(client: Fake(goalJson()), goalId: 'g1')));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(tester.takeException(), isNull);
        final track = tester.getRect(find.byKey(const ValueKey('goal-track')));
        expect(track.left, 16);
        if (scale == 1.0) expect(track.width, w - 100);
        expect(track.right, lessThanOrEqualTo(w - 16 - 40));
        expect(track.height, 6);
        expect(find.text('60 percent'), findsOneWidget);
        expect(find.bySemanticsLabel(RegExp('Progress')), findsOneWidget);
        expect(find.text('3 of 5 tasks done   1 blocked'), findsOneWidget);
        final srow = tester.getRect(find.byKey(const ValueKey('goal-session-s1')));
        expect(srow.height, greaterThanOrEqualTo(60));
        expect(srow.width, w);
        expect(find.text('Sessions contributing'), findsOneWidget);
        for (final id in ['t1', 't2', 't3']) {
          final r = tester.getRect(find.byKey(ValueKey('goal-task-$id')));
          expect(r.height, greaterThanOrEqualTo(56), reason: id);
          expect(r.width, w);
        }
        expect(find.text('Acceptance'), findsOneWidget);
        // ignore: avoid_print
        print('w=$w s=$scale track=$track session=$srow');
      });
    }
  }

  phoneTest('no acceptance, no label', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(wrap(
        1, GoalPhonePage(client: Fake(goalJson(withAcceptance: false)), goalId: 'g1')));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('Acceptance'), findsNothing);
  });
}
