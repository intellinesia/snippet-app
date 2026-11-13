import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:hugeicons/hugeicons.dart';
import 'package:snippet/api.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/create_agent_form.dart';
import 'package:snippet/screens/mobile_bottom_bar.dart';
import 'package:snippet/screens/shell_models.dart';
import 'package:snippet/screens/sidebar.dart';
import 'package:snippet/screens/mobile_chrome.dart';
import 'package:snippet/screens/mobile_session_home.dart';
import 'package:snippet/screens/session_list_row.dart';
import 'package:snippet/screens/mission_control_card.dart';
import 'package:snippet/theme.dart';

class _FakeTestClient extends DaemonClient {
  _FakeTestClient(this._agents) : super('https://daemon.invalid', 'test-token');

  @override
  late final DeviceEventHub deviceEvents = DeviceEventHub.local();

  final List<CoordinationAgent> _agents;

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => _agents;

  Map<String, dynamic> autonomy = {
    'on': false,
    'round_minutes': 30,
    'utc_offset_minutes': DateTime.now().timeZoneOffset.inMinutes,
  };

  @override
  Future<Map<String, dynamic>> mcAutonomy() async => {...autonomy};

  @override
  Future<Map<String, dynamic>> mcSetAutonomy(
      Map<String, dynamic> changes) async {
    autonomy = {
      ...autonomy,
      ...changes,
      'utc_offset_minutes': DateTime.now().timeZoneOffset.inMinutes,
    };
    return {...autonomy};
  }

  @override
  Future<List<TaskItem>> recentTasks(
          {required String status, required int limit}) async =>
      (await tasks())
          .where((t) => t.status.wire == status)
          .take(limit)
          .toList();

  @override
  Future<List<TaskItem>> tasks(
          {String? status, String? agentId, int? limit}) async =>
      [];
}

Finder _field(String hint) => find
    .byWidgetPredicate((w) => w is TextField && w.decoration?.hintText == hint);

void main() {
  test('agent icon maps to strokeRoundedBot', () {
    expect(hugeIconFor('agent'), HugeIcons.strokeRoundedBot);
    expect(hugeIconFor('bot'), HugeIcons.strokeRoundedBot);
  });

  testWidgets('each phone page has its search and its own New', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    SharedPreferences.setMockInitialValues({});
    try {
      tester.view.devicePixelRatio = 2.0;
      tester.view.physicalSize = const Size(390, 844) * 2.0;
      addTearDown(tester.view.reset);

      final client = _FakeTestClient([
        CoordinationAgent.fromJson({
          'id': 'a1',
          'display_name': 'Snippet',
          'handle': 'snippet',
          'role': 'assistant',
          'status': 'active',
        }),
        CoordinationAgent.fromJson({
          'id': 'a2',
          'display_name': 'Reviewer',
          'handle': 'reviewer',
          'role': 'security review',
          'status': 'active',
        }),
      ]);

      var newSessionCalled = false;
      var currentHome = MobileHome.chats;

      Widget buildTestWidget({MobileHome home = MobileHome.chats}) {
        currentHome = home;
        return MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                return Sidebar(
                  client: client,
                  active: null,
                  instances: const [],
                  health: const {},
                  sessions: [
                    SessionInfo.fromJson({
                      'id': 'mission-control',
                      'title': 'Mission Control',
                      'folder': 'my-project',
                      'last_active': 2000,
                    }),
                    SessionInfo.fromJson({
                      'id': 's1',
                      'title': 'Feature Setup',
                      'folder': 'my-project',
                      'last_active':
                          DateTime.now().millisecondsSinceEpoch ~/ 1000 - 60,
                    }),
                  ],
                  sessionsLoading: false,
                  onRefreshSessions: () async {},
                  selectedSessionId: null,
                  onOpenSession: (_, __, ___) {},
                  onNewSession: () => newSessionCalled = true,
                  onSelectInstance: (_) {},
                  onAddInstance: () {},
                  onRenameInstance: (_, __) {},
                  onRemoveInstance: (_) {},
                  onSessionDeleted: (_) {},
                  onRefreshHealth: () {},
                  topInset: false,
                  onOpenMissionControl: () {},
                  mobileHome: currentHome,
                  onMobileHome: (h) => setState(() => currentHome = h),
                  settingsSection: null,
                  onSettingsSection: (_) {},
                  agent: null,
                  onAgent: (_) {},
                );
              },
            ),
          ),
        );
      }

      // 1. Chats: the four tabs and a New
      // that starts a chat.
      await tester.pumpWidget(buildTestWidget(home: MobileHome.chats));
      await tester.pumpAndSettle();

      expect(find.byType(MissionControlCard), findsNothing);
      await tester.tap(find.byTooltip('New session'));
      await tester.pumpAndSettle();
      expect(newSessionCalled, isTrue);

      // The header carries its own inline filter field; the bar has no search.
      expect(_field('Search sessions'), findsOneWidget);
      expect(find.byTooltip('Search'), findsNothing);
      expect(
          find.descendant(
              of: find.byType(MobileBottomBar), matching: find.text('Sessions')),
          findsOneWidget);
      await tester.enterText(_field('Search sessions'), 'Nonexistent');
      await tester.pumpAndSettle();
      expect(find.text('No matching sessions'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear').first);
      await tester.pumpAndSettle();
      expect(find.text('Feature Setup'), findsOneWidget);
      expect(_field('Search sessions'), findsOneWidget);

      // 2. Tasks is a tab of its own, with its own New.
      await tester.pumpWidget(buildTestWidget(home: MobileHome.tasks));
      await tester.pumpAndSettle();
      expect(currentHome, MobileHome.tasks);
      expect(find.text('No tasks yet'), findsOneWidget);
      expect(find.byTooltip('New task'), findsOneWidget);

      // 3. Agents: flipping the home list (the header's Sessions segment)
      // shows agents, search filters them and New creates one.
      await tester.pumpWidget(buildTestWidget(home: MobileHome.chats));
      await tester.pumpAndSettle();
      setMobileAgentsList(true);
      await tester.pumpAndSettle();
      expect(find.text('Snippet'), findsOneWidget);
      expect(find.text('Reviewer'), findsOneWidget);
      expect(find.text('Feature Setup'), findsNothing);
      expect(
          (await SharedPreferences.getInstance())
              .getBool('mobile_home_agents_list'),
          isTrue);

      expect(_field('Search agents'), findsOneWidget);
      await tester.enterText(_field('Search agents'), 'review');
      await tester.pumpAndSettle();
      expect(find.text('Snippet'), findsNothing);
      expect(find.text('Reviewer'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear').first);
      await tester.pumpAndSettle();

      expect(find.byType(CreateAgentForm), findsNothing);
      await tester.tap(find.descendant(
          of: find.byType(MobileBottomBar), matching: find.text('Agents')));
      await tester.pumpAndSettle();
      expect(currentHome, MobileHome.agents);
      await tester.tap(find.byTooltip('New agent or group'));
      await tester.pumpAndSettle();
      expect(find.text('New group'), findsOneWidget);
      await tester.tap(find.text('New agent'));
      await tester.pumpAndSettle();
      expect(find.byType(CreateAgentForm), findsOneWidget);
      // Phone sheets have no close X; tapping the scrim dismisses.
      await tester.tapAt(const Offset(20, 20));
      await tester.pumpAndSettle();
      setMobileAgentsList(false);
      await tester.tap(find.descendant(
          of: find.byType(MobileBottomBar), matching: find.text('Sessions')));
      await tester.pumpAndSettle();
      expect(find.text('Feature Setup'), findsOneWidget);

      // 4. Settings has no New of its own.
      await tester.pumpWidget(buildTestWidget(home: MobileHome.settings));
      await tester.pumpAndSettle();
      for (final tip in [
        'New session',
        'New task',
        'New agent or group',
        'Create'
      ]) {
        expect(find.byTooltip(tip).hitTestable(), findsNothing);
      }
      expect(find.text('WORKSPACE'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      'mobile sessions list shows sessions chronologically inside a folder section and handles empty state and search',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      tester.view.devicePixelRatio = 2.0;
      tester.view.physicalSize = const Size(390, 844) * 2.0;
      addTearDown(tester.view.reset);

      final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
      final client = _FakeTestClient([]);

      // 15 sessions total:
      // 12 are within the last 12 hours (indices 0..11)
      // 3 are older than 12 hours (indices 12..14)
      final allSessions = List.generate(15, (i) {
        final hoursAgo = i < 12 ? (i * 0.5) : (13.0 + (i - 12));
        return SessionInfo.fromJson({
          'id': 'sess-$i',
          'title': 'Session Title $i',
          'folder': 'project',
          'last_active': (now - (hoursAgo * 3600).round()),
        });
      });

      Widget buildWidget(List<SessionInfo> sessions) {
        return MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: Sidebar(
              client: client,
              active: null,
              instances: const [],
              health: const {},
              sessions: sessions,
              sessionsLoading: false,
              onRefreshSessions: () async {},
              selectedSessionId: null,
              onOpenSession: (_, __, ___) {},
              onNewSession: () {},
              onSelectInstance: (_) {},
              onAddInstance: () {},
              onRenameInstance: (_, __) {},
              onRemoveInstance: (_) {},
              onSessionDeleted: (_) {},
              onRefreshHealth: () {},
              onOpenMissionControl: () {},
              topInset: false,
              mobileHome: MobileHome.chats,
              onMobileHome: (_) {},
              settingsSection: null,
              onSettingsSection: (_) {},
              agent: null,
              onAgent: (_) {},
            ),
          ),
        );
      }

      // Render with 15 sessions
      await tester.pumpWidget(buildWidget(allSessions));
      await tester.pumpAndSettle();

      // Recent header is removed; folder name is on trailing session card; no duplicates
      expect(find.text('Recent'), findsNothing);
      expect(find.text('10'), findsNothing);
      final folder = find.widgetWithText(MobileSectionLabel, 'project');
      expect(folder, findsOneWidget);
      expect(find.descendant(of: folder, matching: find.text('15')),
          findsOneWidget);
      expect(find.byType(SessionGroupHeader), findsNothing);
      expect(find.byType(LiveSessionCard), findsNothing);

      // Top recent items are visible once each:
      expect(find.text('Session Title 0'), findsOneWidget);
      expect(find.text('Session Title 1'), findsOneWidget);
      expect(find.text('Session Title 2'), findsOneWidget);
      final ys = [
        for (var i = 0; i < 15; i++)
          tester.getTopLeft(find.text('Session Title $i')).dy
      ];
      for (var i = 1; i < ys.length; i++) {
        expect(ys[i], greaterThan(ys[i - 1]), reason: 'row $i after row ${i - 1}');
      }

      // Search reaches past the visible rows to every matching chat.
      await tester.enterText(_field('Search sessions'), 'Title 13');
      await tester.pumpAndSettle();
      expect(find.text('Session Title 13'), findsOneWidget);

      // Search for nonexistent chat
      await tester.enterText(_field('Search sessions'), 'Session Title 99');
      await tester.pumpAndSettle();
      expect(find.text('No matching sessions'), findsOneWidget);
      await tester.enterText(_field('Search sessions'), '');
      await tester.pumpAndSettle();

      // When all sessions are older than 12 hours, Recent header is absent but folder shows them
      final oldSessionsOnly = [
        SessionInfo.fromJson({
          'id': 'old-1',
          'title': 'Ancient Chat',
          'folder': 'project',
          'last_active': now - (15 * 3600), // 15 hours ago
        }),
      ];
      await tester.pumpWidget(buildWidget(oldSessionsOnly));
      await tester.pumpAndSettle();

      expect(find.text('Recent'), findsNothing);
      expect(find.text('Ancient Chat'), findsOneWidget);

      // Empty sessions
      await tester.pumpWidget(buildWidget([]));
      await tester.pumpAndSettle();
      expect(find.text('No sessions yet'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('agent inbox sessions are not shown in chats list',
      (tester) async {
    final client = _FakeTestClient([]);
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final sessions = [
      SessionInfo.fromJson({
        'id': 'inbox-builder',
        'title': 'Agent Mailbox',
        'folder': 'inbox',
        'conversation': 'default',
        'last_active': now - 60,
      }),
      SessionInfo.fromJson({
        'id': 'sess-normal',
        'title': 'Real User Chat',
        'folder': 'project',
        'conversation': 'default',
        'last_active': now - 120,
      }),
    ];

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Sidebar(
          client: client,
          active: null,
          instances: const [],
          health: const {},
          sessions: sessions,
          sessionsLoading: false,
          onRefreshSessions: () async {},
          selectedSessionId: null,
          onOpenSession: (_, __, ___) {},
          onNewSession: () {},
          onSelectInstance: (_) {},
          onAddInstance: () {},
          onRenameInstance: (_, __) {},
          onRemoveInstance: (_) {},
          onSessionDeleted: (_) {},
          onRefreshHealth: () {},
          onOpenMissionControl: () {},
          topInset: false,
          mobileHome: MobileHome.chats,
          onMobileHome: (_) {},
          settingsSection: null,
          onSettingsSection: (_) {},
          agent: null,
          onAgent: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Real User Chat'), findsWidgets);
    expect(find.text('Agent Mailbox'), findsNothing);
    expect(find.text('inbox-builder'), findsNothing);
  });
}
