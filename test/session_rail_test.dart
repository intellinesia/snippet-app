
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/session_rail.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/wake_models.dart';

class _Counting extends DaemonClient {
  _Counting() : super('http://127.0.0.1:9090', 'tok');
  final calls = <String>[];
  Never _no(String name) {
    calls.add(name);
    throw Exception('offline');
  }

  @override
  Future<GitStatus> gitStatus(String session) async => _no('git');
  @override
  Future<List<SessionInfo>> sessions({String? folder, int? limit}) async =>
      _no('sessions');
  @override
  Future<List<Map<String, dynamic>>> bgList(String session) async => _no('bg');
  @override
  Future<WakeSchedule?> wake(String owner, {String? name}) async => _no('wake');
  @override
  Future<KeepWarmEntry?> keepWarmFor(String owner) async => _no('warm');
  @override
  Future<List<TaskItem>> tasks({String? status, String? agentId, int? limit}) async =>
      _no('tasks');
}

Widget _rail(DaemonClient client, String status, {bool mc = false}) => MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: SessionRail(
          client: client,
          sessionId: mc ? 'mission-control' : 'sess-1',
          state: HarnessState.fromJson({'status': status, 'workspace': '/tmp/ws'}),
          isMissionControl: mc,
          profileLabel: 'Default',
          resumeMode: 'ask',
          onModel: () {},
          onWakes: () {},
          onGoal: () {},
          onCycleResume: () {},
        ),
      ),
    );

void main() {
  testWidgets('a turn refreshes only the worktree and processes', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues({});
    final client = _Counting();
    await tester.pumpWidget(_rail(client, 'idle'));
    await tester.pump();
    expect(client.calls.toSet(), {'git', 'sessions', 'bg', 'wake', 'warm', 'tasks'});
    client.calls.clear();
    await tester.pumpWidget(_rail(client, 'running'));
    await tester.pump();
    expect(client.calls, unorderedEquals(['git', 'bg']));
    debugDefaultTargetPlatformOverride = null;
  });

}
