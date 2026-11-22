import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:snippet/api.dart';
import 'package:snippet/chat/agent_panel_body.dart';
import 'package:snippet/models.dart';

import 'support/wake_fakes.dart';

class _Client extends FakeWakeClient {
  _Client({this.taskList = const [], List<SessionInfo> sessions = const []}) {
    sessionList = sessions;
  }
  final List<TaskItem> taskList;
  String? askedAgent = 'unset';

  @override
  Future<List<TaskItem>> tasks({
    String? status,
    String? agentId,
    int? limit,
  }) async {
    askedAgent = agentId;
    return taskList;
  }
}

TaskItem _task(String id, String status) => TaskItem.fromJson({
      'id': id,
      'title': 'Task $id',
      'status': status,
      'updated_at': DateTime.now()
          .subtract(const Duration(hours: 2))
          .toUtc()
          .toIso8601String(),
    });

SessionInfo _ask() => SessionInfo.fromJson({
      'id': 's1',
      'title': 'GeckoView goal',
      'status': 'waiting_for_input',
      'last_active': DateTime.now().millisecondsSinceEpoch ~/ 1000 - 600,
    });

Future<void> _pump(WidgetTester t, _Client c) async {
  SharedPreferences.setMockInitialValues({});
  t.view.physicalSize = const Size(400, 1800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    home: Scaffold(
      body: SingleChildScrollView(
        child: AgentPanelBody(
          client: c,
          agentId: 'lead',
          name: 'Lead',
          sub: 'Coordinator',
          header: const Text('Context 98k / 556k'),
          onInbox: () {},
          onBoard: () {},
          onMemory: () {},
          onTasks: () {},
          settings: [AgentSettingRow('activity', 'Automated wakes', '', () {})],
        ),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('sections run Needs you, Now, Go to, then the context meter',
      (t) async {
    final c = _Client(
        taskList: [_task('a', 'in_review'), _task('b', 'todo')],
        sessions: [_ask()]);
    await _pump(t, c);
    double y(String s) => t.getTopLeft(find.text(s)).dy;
    expect(c.askedAgent, isNull);
    expect(find.text('Oldest first'), findsOneWidget);
    expect(find.text('Task a'), findsOneWidget);
    expect(find.text('GeckoView goal'), findsOneWidget);
    expect(y('Needs you'), lessThan(y('Now')));
    expect(y('Now'), lessThan(y('Go to')));
    expect(y('Go to'), lessThan(y('Settings')));
    expect(y('Settings'), lessThan(y('Context 98k / 556k')));
    expect(find.text('2 open'), findsOneWidget);
  });

  testWidgets('Needs you is hidden when nothing waits', (t) async {
    await _pump(t, _Client(taskList: [_task('b', 'todo')]));
    expect(find.text('Needs you'), findsNothing);
    expect(find.text('Now'), findsOneWidget);
    expect(find.text('Go to'), findsOneWidget);
  });
}
