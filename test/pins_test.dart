import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/pins.dart';
import 'package:snippet/screens/agent_card.dart';
import 'package:snippet/screens/agents_sidebar_panel.dart';
import 'package:snippet/screens/mobile_session_home.dart';
import 'package:snippet/screens/session_list_row.dart';
import 'package:snippet/screens/shell_models.dart';
import 'package:snippet/screens/sidebar.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/widgets.dart';

class _Client extends DaemonClient {
  _Client() : super('https://daemon.invalid', 'test');

  final DeviceEventHub _deviceEvents = DeviceEventHub.local();

  @override
  DeviceEventHub get deviceEvents => _deviceEvents;

  @override
  Future<ServerConfig> getConfig({bool force = false}) async =>
      ServerConfig.fromJson({
        'profiles': [
          {'name': 'claude', 'provider': 'claude-code'},
        ],
      });

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => [
        CoordinationAgent.fromJson({
          'id': 'a1',
          'display_name': 'Alpha',
          'handle': 'alpha',
          'role': 'r',
          'status': 'active',
          'last_message': {
            'text': 'older',
            'from': 'agent',
            'at': '2026-11-10T10:00:00Z'
          },
        }),
        CoordinationAgent.fromJson({
          'id': 'a2',
          'display_name': 'Bravo',
          'handle': 'bravo',
          'role': 'r',
          'status': 'active',
          'last_message': {
            'text': 'newer',
            'from': 'agent',
            'at': '2026-11-12T10:00:00Z'
          },
        }),
      ];

  @override
  Future<List<GroupSummary>> groups() async => [
        GroupSummary.fromJson({
          'id': 'g1',
          'title': 'Ops Crew',
          'members': const [],
          'last_event_at': '2026-11-09T10:00:00Z',
          'created_at': '2026-11-01T00:00:00Z',
        }),
      ];
}

final _now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

SessionInfo _session(
  String id,
  String title, {
  String status = 'idle',
  String folder = '/home/dev/code/snippet-mobile',
}) =>
    SessionInfo.fromJson({
      'id': id,
      'title': title,
      'status': status,
      'last_active': _now - 600,
      'folder': folder,
      'settled': false,
    });

Widget _phoneHarness({required List<SessionInfo> sessions}) {
  return MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: Sidebar(
        instances: const [],
        active: null,
        client: _Client(),
        selectedSessionId: null,
        sessions: sessions,
        sessionsLoading: false,
        onRefreshSessions: () {},
        onNewSession: () {},
        onSelectInstance: (_) {},
        onOpenMissionControl: () {},
        onOpenSession: (_, __, ___) {},
        onAddInstance: () {},
        onRenameInstance: (_, __) {},
        onRemoveInstance: (_) {},
        onSessionDeleted: (_) {},
        health: const {'https://daemon.invalid': true},
        onRefreshHealth: () {},
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

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    Pins.instance.clear();
  });

  test('Pins toggles, keeps most-recently-pinned order, and persists', () async {
    expect(Pins.instance.isPinned(Pins.session, 's1'), isFalse);
    expect(Pins.instance.pinnedAt(Pins.session, 's1'), isNull);

    await Pins.instance.toggle(Pins.session, 's1');
    await Pins.instance.toggle(Pins.session, 's2');

    expect(Pins.instance.isPinned(Pins.session, 's1'), isTrue);
    expect(Pins.instance.isPinned(Pins.session, 's2'), isTrue);
    final t1 = Pins.instance.pinnedAt(Pins.session, 's1')!;
    final t2 = Pins.instance.pinnedAt(Pins.session, 's2')!;
    expect(t2, greaterThan(t1));
    expect(Pins.instance.ids(Pins.session), ['s2', 's1']);

    await Pins.instance.toggle(Pins.agent, 'a1', host: 'https://host-a');
    expect(
        Pins.instance.isPinned(Pins.agent, 'a1', host: 'https://host-a'),
        isTrue);
    expect(
        Pins.instance.isPinned(Pins.agent, 'a1', host: 'https://host-b'),
        isFalse);

    Pins.instance.clear();
    expect(Pins.instance.isPinned(Pins.session, 's1'), isFalse);

    await Pins.instance.load();
    expect(Pins.instance.isPinned(Pins.session, 's1'), isTrue);
    expect(Pins.instance.isPinned(Pins.session, 's2'), isTrue);
    expect(Pins.instance.ids(Pins.session), ['s2', 's1']);
    expect(
        Pins.instance.isPinned(Pins.agent, 'a1', host: 'https://host-a'),
        isTrue);

    await Pins.instance.toggle(Pins.session, 's2');
    expect(Pins.instance.isPinned(Pins.session, 's2'), isFalse);
    expect(Pins.instance.ids(Pins.session), ['s1']);
  });

  testWidgets(
      'pinned session shows in Pinned section on phone home without repeating below',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await Pins.instance.toggle(Pins.session, 's1');
      await tester.pumpWidget(_phoneHarness(sessions: [
        _session('s1', 'Pinned work', folder: '/home/dev/code/alpha'),
        _session('s2', 'Other work', folder: '/home/dev/code/beta'),
      ]));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(seconds: 1));

      final pinnedHeader = find.widgetWithText(MobileSectionLabel, 'Pinned');
      expect(pinnedHeader, findsOneWidget);
      expect(find.descendant(of: pinnedHeader, matching: find.text('1')),
          findsOneWidget);
      expect(find.text('Pinned work'), findsOneWidget);
      expect(find.widgetWithText(MobileSectionLabel, 'alpha'), findsNothing);
      expect(find.widgetWithText(MobileSectionLabel, 'beta'), findsOneWidget);

      final pinnedRow = find.ancestor(
          of: find.text('Pinned work'), matching: find.byType(SessionListRow));
      expect(
        tester
            .widgetList<AppIcon>(
                find.descendant(of: pinnedRow, matching: find.byType(AppIcon)))
            .any((i) => i.name == 'pin'),
        isTrue,
      );

      await tester.longPress(find.text('Other work'));
      await tester.pumpAndSettle();
      expect(find.text('Pin'), findsOneWidget);
      await tester.tap(find.text('Pin'));
      await tester.pumpAndSettle();

      expect(find.descendant(of: pinnedHeader, matching: find.text('2')),
          findsOneWidget);
      expect(find.widgetWithText(MobileSectionLabel, 'beta'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('pinned agents and groups sort to top with pin icon and menu',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(
          MaterialApp(home: Scaffold(body: AgentsSidebarPanel(client: _Client()))));
      await tester.pumpAndSettle();

      await tester.longPress(find.text('Ops Crew'));
      await tester.pumpAndSettle();
      expect(find.text('Pin'), findsOneWidget);
      await tester.tap(find.text('Pin'));
      await tester.pumpAndSettle();

      expect(find.text('Pinned'), findsOneWidget);
      final crewY = tester.getTopLeft(find.text('Ops Crew')).dy;
      final bravoY = tester.getTopLeft(find.text('Bravo')).dy;
      expect(crewY, lessThan(bravoY));

      await tester.longPress(find.text('Alpha'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Pin'));
      await tester.pumpAndSettle();

      final alphaCard = find.ancestor(
          of: find.text('Alpha'), matching: find.byType(AgentCard));
      expect(
        tester
            .widgetList<AppIcon>(
                find.descendant(of: alphaCard, matching: find.byType(AppIcon)))
            .any((i) => i.name == 'pin'),
        isTrue,
      );
      expect(tester.getTopLeft(find.text('Alpha')).dy,
          lessThan(tester.getTopLeft(find.text('Ops Crew')).dy));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
