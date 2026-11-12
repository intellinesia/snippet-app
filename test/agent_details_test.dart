import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:snippet/api.dart';
import 'package:snippet/chat/agent_details.dart';
import 'package:snippet/chat/chat_style.dart';
import 'package:snippet/models.dart';
import 'package:snippet/presence.dart';
import 'package:snippet/screens/agent_messaging.dart';
import 'package:snippet/screens/agent_records.dart';
import 'package:snippet/screens/group_messaging.dart';
import 'package:snippet/screens/tasks/tasks_panel.dart';
import 'package:snippet/shell_panel.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/wake_models.dart';
import 'package:snippet/widgets.dart';

class _TestClient extends DaemonClient {
  _TestClient({
    this.nowResponse,
    this.return404ForNow = false,
  }) : super('https://daemon.invalid', 'test-token');

  final _events = DeviceEventHub.local();
  final _presence = PresenceStore();

  AgentNow? nowResponse;
  bool return404ForNow;

  bool pushEnabled = false;
  bool keepWarmEnabled = false;
  String agentStatus = 'active';
  int memoryFiles = 3;

  final releasedSeats = <(String, String)>[];
  final pushChanges = <bool>[];
  final keepWarmChanges = <bool>[];
  final statusChanges = <(String, String)>[];
  final deletedSessions = <String>[];
  final groupUpdates = <(String, List<String>?, List<String>?, String?)>[];
  final deletedGroups = <String>[];

  @override
  DeviceEventHub get deviceEvents => _events;

  @override
  PresenceStore get presence => _presence;

  @override
  Future<AgentNow?> agentNow(String agentId) async {
    if (return404ForNow) return null;
    return nowResponse;
  }

  @override
  Future<void> releaseAgentSeat(String agentId, String sessionId) async {
    releasedSeats.add((agentId, sessionId));
    if (nowResponse != null) {
      nowResponse = AgentNow(
        agentId: nowResponse!.agentId,
        presence: nowResponse!.presence,
        currentTask: nowResponse!.currentTask,
        sessions: [
          for (final s in nowResponse!.sessions)
            if (s.session != sessionId) s,
        ],
        counts: nowResponse!.counts,
        board: nowResponse!.board,
      );
    }
  }

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => [
        CoordinationAgent.fromJson({
          'id': 'growth',
          'display_name': 'Growth',
          'handle': 'growth',
          'status': agentStatus,
          'profile': 'sonnet',
          'capabilities': ['campaigns', 'analytics'],
        }),
        CoordinationAgent.fromJson({
          'id': 'research',
          'display_name': 'Research',
          'handle': 'research',
          'status': 'active',
        }),
        CoordinationAgent.fromJson({
          'id': 'builder',
          'display_name': 'Builder',
          'handle': 'builder',
          'status': 'active',
        }),
      ];

  @override
  Future<AgentReach> agentReach(String agentId) async => AgentReach(
        policy: const {},
        channels: {
          'push': ReachChannel(enabled: pushEnabled, quietHours: false),
        },
      );

  @override
  Future<AgentReach> setAgentReach(
    String agentId, {
    Map<String, List<String>>? policy,
    Map<String, Map<String, bool>>? channels,
  }) async {
    final enabled = channels?['push']?['enabled'] ?? pushEnabled;
    pushEnabled = enabled;
    pushChanges.add(enabled);
    return agentReach(agentId);
  }

  @override
  Future<KeepWarmEntry?> keepWarmFor(String owner) async =>
      KeepWarmEntry.fromJson({
        'owner': owner,
        'owner_kind': 'agent',
        'session_id': 'inbox-$owner',
        'enabled': keepWarmEnabled,
        'interval_minutes': 15,
        'max_idle_hours': 2,
        'set_by': 'user',
        'updated_at': 0,
        'warms': 0,
      });

  @override
  Future<KeepWarmEntry> setKeepWarm(
    String owner, {
    required bool enabled,
    int? intervalMinutes,
    int? maxIdleHours,
  }) async {
    keepWarmEnabled = enabled;
    keepWarmChanges.add(enabled);
    return (await keepWarmFor(owner))!;
  }

  @override
  Future<void> setAgentStatus(String agentId, String status) async {
    agentStatus = status;
    statusChanges.add((agentId, status));
  }

  @override
  Future<List<MemoryScope>> memoryScopes() async => [
        MemoryScope.fromJson({
          'key': 'agent:growth',
          'kind': 'agent',
          'label': 'Growth',
          'path': '/tmp/mem',
          'files': memoryFiles,
          'entries': 12,
        }),
      ];

  @override
  Future<void> deleteSession(String sessionId) async {
    deletedSessions.add(sessionId);
  }

  @override
  Future<List<TaskItem>> tasks(
          {String? status, String? agentId, int? limit}) async =>
      const [];

  @override
  Future<List<InboxEntry>> agentInbox(
    String agentId, {
    String? contains,
    String? kind,
    int? before,
    int limit = 50,
  }) async =>
      const [];

  @override
  Future<BoardPage> agentBoardPage(
    String agentId, {
    String? contains,
    String? kind,
    int? before,
    bool outstanding = false,
    int limit = 50,
    String? group,
    String? correlationId,
    String? workspace,
  }) async =>
      const BoardPage([], []);

  @override
  Future<DirectThreadPage> agentThreadPage({
    required String peerId,
    String actorKind = 'human',
    String actorId = 'local',
    int afterSequence = 0,
    int limit = 100,
  }) async =>
      const DirectThreadPage(events: []);

  @override
  Future<List<CoordinationEvent>> groupEvents(
    String id, {
    int after = 0,
    int limit = 100,
  }) async =>
      const [];

  @override
  Future<GroupSummary> updateGroup(
    String id, {
    String? title,
    String? lead,
    List<String>? addMembers,
    List<String>? removeMembers,
  }) async {
    groupUpdates.add((id, addMembers, removeMembers, lead));
    return GroupSummary.fromJson({
      'id': id,
      'title': title ?? 'Launch Crew',
      'members': [
        {'kind': 'human', 'id': 'local'},
        {'kind': 'agent', 'id': 'growth'},
        {'kind': 'agent', 'id': 'research'},
        for (final extra in addMembers ?? const <String>[])
          {'kind': 'agent', 'id': extra},
      ],
      'lead': lead ?? 'growth',
      'created_at': '2026-11-01T00:00:00Z',
    });
  }

  @override
  Future<void> deleteGroup(String id) async {
    deletedGroups.add(id);
  }
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 8; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  testWidgets('agent details loads /now, respects style rules, and releases stale seat',
      (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
    final nowIso =
        DateTime.now().subtract(const Duration(minutes: 12)).toIso8601String();
    final client = _TestClient(
      nowResponse: AgentNow(
        agentId: 'growth',
        presence: AgentNowPresence(
          state: 'working',
          detail: 'drafting launch post',
          since: nowIso,
          session: 'sess-1',
        ),
        sessions: [
          AgentNowSession(
            session: 'sess-active',
            taskId: 't1',
            taskTitle: 'Active draft',
            taskStatus: 'running',
            holder: true,
            since: nowIso,
            lastProgressAt: nowIso,
            stale: false,
          ),
          AgentNowSession(
            session: 'sess-stale',
            taskId: 't2',
            taskTitle: 'Hung review seat',
            taskStatus: 'in_review',
            holder: true,
            since: nowIso,
            lastProgressAt: nowIso,
            stale: true,
          ),
        ],
      ),
    );

    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AgentDetails(
          client: client,
          agentId: 'growth',
          agentName: 'Growth',
        ),
      ),
    ));
    await _settle(t);

    final nameText = t.widget<Text>(find.text('Growth'));
    expect(nameText.style?.fontSize, 20);
    expect(nameText.style?.fontWeight, FontWeight.w500);
    expect(find.text('campaigns · analytics'), findsOneWidget);
    expect(find.text('Call'), findsNothing);
    expect(find.text('working · drafting launch post'), findsOneWidget);
    expect(find.text('Active draft'), findsOneWidget);
    expect(find.text('Hung review seat'), findsOneWidget);
    expect(find.text('Release'), findsOneWidget);
    await t.tap(find.text('Release'));
    await _settle(t);
    expect(client.releasedSeats, [('growth', 'sess-stale')]);
    expect(find.text('Hung review seat'), findsNothing);
    expect(find.text('Release'), findsNothing);

    await t.scrollUntilVisible(
      find.text('sonnet'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    expect(find.text('sonnet'), findsOneWidget);
    expect(find.text('3 topics'), findsOneWidget);
    await t.pump(const Duration(seconds: 3));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('agent toggles, Call visibility, 404 fallback, reset desk, and tabs work',
      (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
    var called = 0;
    final client = _TestClient(return404ForNow: true);
    client.presence.handle({
      'kind': 'agent_presence',
      'session': 'inbox-growth',
      'agent': 'growth',
      'state': 'waiting',
      'detail': 'queued on review',
      'since': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });

    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AgentDetails(
          client: client,
          agentId: 'growth',
          agentName: 'Growth',
          onCall: () => called++,
        ),
      ),
    ));
    await _settle(t);

    expect(find.text('waiting · queued on review'), findsOneWidget);
    await t.tap(find.text('Call'));
    await _settle(t);
    expect(called, 1);

    final switches = find.byType(AppSwitch);
    expect(switches, findsNWidgets(3));

    await t.tap(switches.at(0));
    await _settle(t);
    expect(client.pushChanges, [true]);

    await t.tap(switches.at(1));
    await _settle(t);
    expect(client.keepWarmChanges, [true]);

    await t.tap(switches.at(2));
    await _settle(t);
    expect(client.statusChanges, [('growth', 'paused')]);

    await t.scrollUntilVisible(
      find.text('Reset desk session'),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await t.tap(find.text('Reset desk session'));
    await _settle(t);
    await t.tap(find.text('Reset desk session').last);
    await _settle(t);
    expect(client.deletedSessions, ['inbox-growth']);

    await t.tap(find.text('Tasks').last);
    await _settle(t);
    expect(find.byType(TasksPanel), findsOneWidget);

    await t.tap(find.text('Inbox'));
    await _settle(t);
    expect(find.byType(AgentInboxView), findsOneWidget);

    await t.tap(find.text('Board'));
    await _settle(t);
    expect(find.byType(AgentBoardView), findsOneWidget);

    // No blue accent color from ChatColors anywhere in the details widget.
    expect(
      find.byWidgetPredicate(
        (w) => w is Text && w.style?.color == ChatColors.blue,
      ),
      findsNothing,
    );
    await t.pump(const Duration(seconds: 3));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('group details renders members, adds member, shows reply rule, deletes group',
      (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
    final client = _TestClient();
    client.presence.handle({
      'kind': 'agent_presence',
      'session': 'inbox-growth',
      'agent': 'growth',
      'state': 'working',
      'detail': '',
      'since': DateTime.now().millisecondsSinceEpoch ~/ 1000,
    });
    final group = GroupSummary.fromJson({
      'id': 'g-launch',
      'title': 'Launch Crew',
      'members': const [
        {'kind': 'human', 'id': 'local'},
        {'kind': 'agent', 'id': 'growth'},
        {'kind': 'agent', 'id': 'research'},
      ],
      'lead': 'growth',
      'created_at': '2026-11-01T00:00:00Z',
    });
    GroupSummary? changed;
    var deleted = false;

    await t.pumpWidget(MaterialApp(
      home: Scaffold(
        body: AgentDetails(
          client: client,
          group: group,
          onGroupChanged: (g) => changed = g,
          onGroupDeleted: () => deleted = true,
        ),
      ),
    ));
    await _settle(t);

    final titleText = t.widget<Text>(find.text('Launch Crew'));
    expect(titleText.style?.fontSize, 20);
    expect(titleText.style?.fontWeight, FontWeight.w500);
    expect(find.text('2 agents and you'), findsOneWidget);
    expect(find.text('Growth · Lead'), findsOneWidget);
    expect(find.text('Research'), findsOneWidget);
    expect(find.text('working'), findsOneWidget);
    expect(find.text('Agents reply to each other'), findsOneWidget);
    expect(find.text('Only when mentioned'), findsOneWidget);

    await t.tap(find.text('Add member'));
    await _settle(t);
    expect(find.text('Builder'), findsOneWidget);
    await t.tap(find.text('Builder'));
    await _settle(t);
    expect(client.groupUpdates.last.$1, 'g-launch');
    expect(client.groupUpdates.last.$2, ['builder']);
    expect(changed?.agentIds, contains('builder'));

    await t.ensureVisible(find.text('Delete group'));
    await t.tap(find.text('Delete group'));
    await _settle(t);
    await t.tap(find.text('Delete group').last);
    await _settle(t);
    expect(client.deletedGroups, ['g-launch']);
    expect(deleted, isTrue);
    await t.pump(const Duration(seconds: 3));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('agentPanelRequest details opens in ShellPanelScope on header tap',
      (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
    final client = _TestClient(return404ForNow: true);
    ShellPanelRequest? opened;

    await t.pumpWidget(MaterialApp(
      home: ShellPanelScope(
        open: (req) async {
          opened = req;
          return null;
        },
        child: Scaffold(
          body: AgentThreadScreen(
            client: client,
            agentId: 'growth',
            agentName: 'Growth',
          ),
        ),
      ),
    ));
    await _settle(t);

    await t.tap(find.text('Growth').first);
    await _settle(t);

    expect(opened, isNotNull);
    expect(opened!.purpose, ShellPanelPurpose.agent);
    expect(opened!.id, 'growth');
    expect(opened!.key, endsWith('|agent|growth'));
    expect(opened!.title, 'Growth');
    expect(find.byTooltip('Switch view'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('group header tap opens group details in right pane on desktop and sheet on phone',
      (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
    final client = _TestClient();
    final group = GroupSummary.fromJson({
      'id': 'g-1',
      'title': 'Design Sync',
      'members': const [
        {'kind': 'human', 'id': 'local'},
        {'kind': 'agent', 'id': 'growth'},
      ],
      'created_at': '2026-11-01T00:00:00Z',
    });
    ShellPanelRequest? opened;

    await t.pumpWidget(MaterialApp(
      home: ShellPanelScope(
        open: (req) async {
          opened = req;
          return null;
        },
        child: Scaffold(
          body: GroupThreadScreen(client: client, group: group),
        ),
      ),
    ));
    await _settle(t);

    await t.tap(find.text('Design Sync').last);
    await _settle(t);
    expect(opened, isNotNull);
    expect(opened!.purpose, ShellPanelPurpose.agent);
    expect(opened!.id, 'group:g-1');

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    t.view.physicalSize = const Size(390, 844) * 3;
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);

    await t.pumpWidget(MaterialApp(
      home: GroupThreadScreen(client: client, group: group),
    ));
    await _settle(t);
    await t.tap(find.text('Design Sync').last);
    await _settle(t);
    expect(find.byType(AgentDetails), findsOneWidget);
    expect(find.text('1 agent and you'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
