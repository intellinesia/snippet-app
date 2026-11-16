import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/group_messaging.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/theme.dart';

class _C extends DaemonClient {
  _C(this.thread) : super('https://daemon.invalid', 't');
  final List<CoordinationEvent> thread;
  final _hub = DeviceEventHub.local();
  @override
  DeviceEventHub get deviceEvents => _hub;
  @override
  Future<List<CoordinationEvent>> groupEvents(String id,
          {int after = 0, int limit = 100}) async =>
      thread;
  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => [];
}

CoordinationEvent _e(String id, int seq, String kind, String actor,
        Map<String, dynamic> p) =>
    CoordinationEvent.fromJson({
      'event_id': id,
      'sequence': seq,
      'event_type': 'group_message',
      'actor_kind': kind,
      'actor_id': actor,
      'idempotency_key': 'k$id',
      'created_at': DateTime.utc(2026, 11, 14, 10, 0, seq).toIso8601String(),
      'payload': p,
    });

void main() {
  testWidgets('group cards span the content width', (t) async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    t.view.physicalSize = const Size(390, 844);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    final group = GroupSummary.fromJson({
      'id': 'g1',
      'title': 'Sidebar polish crew',
      'members': [
        {'kind': 'agent', 'id': 'rook'},
        {'kind': 'agent', 'id': 'pip'},
        {'kind': 'human', 'id': 'local'},
      ],
    });
    final c = _C([
      _e('1', 1, 'human', 'local', {'body': 'Rook, finish the row heights.'}),
      _e('2', 2, 'agent', 'rook',
          {'body': 'Rows are on the 44pt grid and goldens pass.'}),
      _e('3', 3, 'agent', 'rook', {
        'body': '',
        'tool_activity': [
          {'tool': 'change_files', 'summary': 'Edited lib/rows.dart'},
          {'tool': 'bash', 'summary': 'flutter test'}
        ]
      }),
      _e('4', 4, 'agent', 'pip', {
        'body': 'Approve the deploy?',
        'approval': {
          'title': 'Deploy to staging',
          'summary': 'Runs deploy.sh',
          'status': 'pending'
        }
      }),
      _e('5', 5, 'agent', 'pip', {'body': 'Copy reads fine.'}),
    ]);
    await t.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: GroupThreadScreen(client: c, group: group)));
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 80));
    }
    final widths = find
        .ancestor(
            of: find.text('Runs deploy.sh'),
            matching: find.byType(DecoratedBox))
        .evaluate()
        .map((e) => (e.renderObject as RenderBox).size.width);
    expect(widths, contains(358.0));
    debugDefaultTargetPlatformOverride = null;
  });
}
