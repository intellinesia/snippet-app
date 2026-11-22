import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/shell_models.dart';
import 'package:snippet/screens/sidebar.dart';
import 'package:snippet/screens/mobile_home/home_style.dart';
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
  Future<Map<String, dynamic>> leadAutonomy() async => {...autonomy};

  @override
  Future<Map<String, dynamic>> leadSetAutonomy(
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
              onOpenLead: () {},
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

      // Render with 15 sessions: resting One thing screen keeps rows tucked in Everyone.
      await tester.pumpWidget(buildWidget(allSessions));
      await tester.pumpAndSettle();
      expect(find.text('Recent'), findsNothing);
      expect(find.text('Session Title 0'), findsNothing);

      // Open Everyone sheet to inspect all 15 human-managed sessions in order.
      await tester.tap(find.byKey(const ValueKey('everyone-handle')));
      await tester.pumpAndSettle();
      expect(find.text('Your sessions'), findsOneWidget);
      expect(find.text('15'), findsOneWidget);
      expect(find.text('Session Title 0'), findsOneWidget);
      expect(find.text('Session Title 1'), findsOneWidget);
      expect(find.text('Session Title 2'), findsOneWidget);
      final ys = [
        for (var i = 0; i < 15; i++)
          tester.getTopLeft(find.text('Session Title $i')).dy
      ];
      for (var i = 1; i < ys.length; i++) {
        expect(ys[i], greaterThan(ys[i - 1]),
            reason: 'row $i after row ${i - 1}');
      }
      await tester.tap(find.byKey(const ValueKey('everyone-sheet-handle')));
      await tester.pumpAndSettle();

      // Search reaches past the resting screen to every matching chat.
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      await tester.enterText(
          _field('Search agents, groups and sessions'), 'Title 13');
      await tester.pumpAndSettle();
      expect(find.text('Session Title 13'), findsOneWidget);

      // Search for nonexistent chat
      await tester.enterText(
          _field('Search agents, groups and sessions'), 'Session Title 99');
      await tester.pumpAndSettle();
      expect(find.text('Nothing matches'), findsOneWidget);
      await tester.enterText(_field('Search agents, groups and sessions'), '');
      await tester.pumpAndSettle();

      // Older sessions still show inside Search/Everyone without a Recent header.
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
          onOpenLead: () {},
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

    if (find.byKey(const ValueKey('everyone-handle')).evaluate().isNotEmpty) {
      await tester.tap(find.byKey(const ValueKey('everyone-handle')));
      await tester.pumpAndSettle();
    }

    expect(find.text('Real User Chat'), findsWidgets);
    expect(find.text('Agent Mailbox'), findsNothing);
    expect(find.text('inbox-builder'), findsNothing);
  });
}
