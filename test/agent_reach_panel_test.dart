import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/screens/agent_reach_panel.dart';
import 'package:snippet/theme.dart';

Map<String, dynamic> _reachJson({bool push = true}) => {
      'agent_id': 'scout',
      'channels': {
        'chat': {'enabled': true, 'quiet_hours': false},
        'push': {'enabled': push, 'quiet_hours': true},
        'voice': {'enabled': false, 'quiet_hours': true},
        'task_room': {'enabled': true, 'quiet_hours': false},
      },
      'policy': {
        'question': ['push', 'chat'],
        'blocker': ['push', 'chat'],
        'result': ['chat'],
        'status': ['task_room'],
      },
      'in_quiet_hours': false,
      'on_call': false,
    };

class _FakeReachClient extends DaemonClient {
  _FakeReachClient() : super('https://daemon.invalid', 'test');

  Map<String, dynamic> state = _reachJson();
  final saves = <Map<String, dynamic>>[];

  @override
  Future<AgentReach> agentReach(String agentId) async =>
      AgentReach.fromJson(state);

  @override
  Future<AgentReach> setAgentReach(String agentId,
      {Map<String, List<String>>? policy,
      Map<String, Map<String, bool>>? channels}) async {
    saves.add({'policy': policy, 'channels': channels});
    final next = Map<String, dynamic>.from(state);
    if (policy != null) {
      next['policy'] = {...(state['policy'] as Map), ...policy};
    }
    if (channels != null) {
      final ch = Map<String, dynamic>.from(state['channels'] as Map);
      channels.forEach((k, v) => ch[k] = {...(ch[k] as Map), ...v});
      next['channels'] = ch;
    }
    state = next;
    return AgentReach.fromJson(state);
  }
}

Future<void> _pump(WidgetTester t, DaemonClient c) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = const Size(390, 1400);
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: AgentReachPanel(client: c, agentId: 'scout'),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

void phone(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await body(t);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  phone('shows where each kind goes and which channels are on', (t) async {
    await _pump(t, _FakeReachClient());
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Questions'), findsOneWidget);
    expect(find.text('Push, then chat'), findsNWidgets(2));
    expect(find.text('Chat'), findsWidgets);
    expect(find.text('Task room'), findsWidgets);
    expect(find.text('Always on'), findsNWidgets(2));
    expect(find.text('Held in quiet hours'), findsNWidgets(2));
  });

  phone('turning notifications off disables push', (t) async {
    final c = _FakeReachClient();
    await _pump(t, c);
    await t.tap(find.text('Notifications'));
    await t.pumpAndSettle();
    expect(c.saves.single['channels'], {
      'push': {'enabled': false}
    });
    expect(
        find.text('Nothing pings you; messages wait in chat'), findsOneWidget);
  });

  phone('picking a route for results saves that order', (t) async {
    final c = _FakeReachClient();
    await _pump(t, c);
    await t.tap(find.text('Results'));
    await t.pumpAndSettle();
    await t.tap(find.text('Voice, then push, then chat').last);
    await t.pumpAndSettle();
    expect(c.saves.single['policy'], {
      'result': ['voice', 'push', 'chat']
    });
    expect(find.text('Voice, then push, then chat'), findsOneWidget);
  });

  phone('tapping the quiet-hours line flips it for that channel', (t) async {
    final c = _FakeReachClient();
    await _pump(t, c);
    await t.tap(find.byKey(const Key('quiet-chat')));
    await t.pumpAndSettle();
    expect(c.saves.single['channels'], {
      'chat': {'quiet_hours': true}
    });
  });

  test('attention tuning parses profile, expiry and origin', () {
    final t = AmbientTuning.fromJson({
      'tuning': {'profile': 'meeting', 'expires_at': 1800000000},
      'set_by': 'mission-control',
      'reason': 'in a meeting until three',
    });
    expect(t.profile, 'meeting');
    expect(t.expiresAt, 1800000000);
    expect(t.setBy, 'mission-control');
    expect(ambientProfileLabel('with_people'), 'With people');
  });
}
