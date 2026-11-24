import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/goal_models.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/group_messaging.dart';
import 'package:snippet/screens/mobile_home/mission_phone.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/theme.dart';

class _C extends DaemonClient {
  _C() : super('https://daemon.invalid', 'tok');
  final _hub = DeviceEventHub.local();
  @override
  DeviceEventHub get deviceEvents => _hub;
  @override
  Future<List<CoordinationEvent>> groupEvents(String id,
          {int after = 0, int limit = 100}) async =>
      [
        CoordinationEvent.fromJson({
          'event_id': 'e1',
          'sequence': 1,
          'actor_kind': 'agent',
          'actor_id': 'argon',
          'idempotency_key': 'k1',
          'created_at': '2026-11-24T10:00:00Z',
          'payload': {'body': 'First message of the thread'},
        }),
        for (var i = 2; i <= 30; i++)
          CoordinationEvent.fromJson({
            'event_id': 'e$i',
            'sequence': i,
            'actor_kind': 'agent',
            'actor_id': 'argon',
            'idempotency_key': 'k$i',
            'created_at': '2026-11-24T10:00:${i.toString().padLeft(2, '0')}Z',
            'payload': {'body': 'Filler message number $i'},
          }),
      ];
  @override
  Future<TaskItem> getTask(String id) async =>
      TaskItem.fromJson({'id': id, 'title': 't', 'goal_id': 'goal1'});
  @override
  Future<GoalDetail> goal(String id) async => GoalDetail.fromJson({
        'id': 'goal1',
        'title': 'Ship v17 phone',
        'plan': [
          for (var i = 1; i <= 5; i++) {'n': i, 'task_id': 't$i', 'title': 'Step $i'}
        ],
        'tasks': [
          {'id': 't3', 'status': 'blocked', 'status_reason': 'frames'},
        ],
      });
}

void main() {
  for (final w in [360.0, 393.0, 430.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('mission bar reserves its height at $w x $scale', (t) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = Size(w, 900);
        addTearDown(t.view.reset);
        final group = GroupSummary.fromJson({
          'id': 'g1',
          'title': 'Launch',
          'members': [
            {'kind': 'agent', 'id': 'argon'},
            {'kind': 'human', 'id': 'local'},
          ],
        });
        await t.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          builder: (c, ch) => MediaQuery(
              data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
              child: ch!),
          home: GroupThreadScreen(client: _C(), group: group),
        ));
        for (var i = 0; i < 12; i++) {
          await t.pump(const Duration(milliseconds: 80));
        }
        for (var k = 0; k < 3; k++) {
          await t.drag(find.byType(Scrollable).first, const Offset(0, 5000));
          for (var i = 0; i < 5; i++) {
            await t.pump(const Duration(milliseconds: 100));
          }
        }
        for (var i = 0; i < 10; i++) {
          await t.pump(const Duration(milliseconds: 80));
        }
        final bar = t.getRect(find.byKey(const ValueKey('mission-bar')));
        final msg = t.getRect(find.textContaining('First message').first);
        // ignore: avoid_print
        print('HM13R w=$w s=$scale bar.bottom=${bar.bottom} msg.top=${msg.top}');
        expect(msg.top, greaterThanOrEqualTo(bar.bottom));
        await t.pumpWidget(const SizedBox());
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }
}
