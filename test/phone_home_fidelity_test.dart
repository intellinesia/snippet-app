import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/mochi.dart';
import 'package:snippet/models.dart';
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
}

final _now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

SessionInfo _session(
  String id,
  String title,
  String status, {
  String folder = '/home/dev/code/snippet-mobile',
  String? branch,
  Map<String, dynamic>? changes,
  Map<String, dynamic>? attention,
  bool settled = false,
  String? agentId,
  String? profile,
}) =>
    SessionInfo.fromJson({
      'id': id,
      'title': title,
      'status': status,
      'last_active': _now - 600,
      'folder': folder,
      if (branch != null) 'branch': branch,
      if (changes != null) 'changes': changes,
      if (attention != null) 'attention': attention,
      'settled': settled,
      if (settled) 'settled_at': _now - 3600,
      if (agentId != null) 'agent_id': agentId,
      if (profile != null) 'profile': profile,
    });

Widget _phoneHarness({
  required List<SessionInfo> sessions,
  bool listening = false,
  int? mcAttention,
  VoidCallback? onOpenMissionControl,
  VoidCallback? onMobileMenu,
  VoidCallback? onNewSession,
  MobileHome mobileHome = MobileHome.chats,
}) {
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
          onNewSession: onNewSession ?? () {},
          onSelectInstance: (_) {},
          onOpenMissionControl: onOpenMissionControl ?? () {},
          onOpenSession: (_, __, ___) {},
          onAddInstance: () {},
          onRenameInstance: (_, __) {},
          onRemoveInstance: (_) {},
          onSessionDeleted: (_) {},
          health: const {'https://daemon.invalid': true},
          onRefreshHealth: () {},
          topInset: false,
          mobileHome: mobileHome,
          mobileTopBar: const Text('Ignored shell bar'),
          onMobileMenu: onMobileMenu,
          onMobileHome: (_) {},
          settingsSection: null,
          onSettingsSection: (_) {},
          agent: null,
          onAgent: (_) {},
          listening: listening,
          mcAttention: mcAttention,
      ),
    ),
  );
}

void main() {
  testWidgets('phone header renders MC button with voice ring, badge, New session and inline search',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      var mcTapped = 0;
      var moreTapped = 0;
      await tester.pumpWidget(_phoneHarness(
        sessions: [_session('s1', 'Work', 'idle')],
        listening: true,
        mcAttention: 2,
        onOpenMissionControl: () => mcTapped++,
        onNewSession: () => moreTapped++,
      ));
      for (var i = 0; i < 20; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }

      expect(find.text('Ignored shell bar'), findsNothing);
      expect(find.byType(MobileHomeTopBar), findsOneWidget);
      expect(find.byType(MissionControlDock), findsOneWidget);
      expect(find.byTooltip('Voice call'), findsOneWidget);
      expect(find.text('Listening'), findsNothing);
      expect(find.text('2'), findsOneWidget);

      final mcMochi = tester.widget<MochiIcon>(find.byType(MochiIcon));
      expect(mcMochi.size, 24);
      expect(mcMochi.color, AppColors.ok);

      await tester.tap(find.byTooltip('Mission Control, voice on'));
      await tester.tap(find.byTooltip('New session'));
      await tester.pump();
      expect(mcTapped, 1);
      expect(moreTapped, 1);

      // Badge and voice ring clear when count is 0 and listening is off.
      await tester.pumpWidget(_phoneHarness(
        sessions: [_session('s1', 'Work', 'idle')],
        listening: false,
        mcAttention: 0,
      ));
      await tester.pumpAndSettle();
      expect(find.text('2'), findsNothing);
      expect(find.byTooltip('Mission Control'), findsOneWidget);
      expect(find.byTooltip('Start voice'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('cross-project Needs you group renders state labels, project chip, and removes from project groups',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(_phoneHarness(sessions: [
        _session(
          'q',
          'Question session',
          'idle',
          folder: '/home/dev/code/alpha',
          attention: {'type': 'question'},
        ),
        _session(
          'r',
          'Review session',
          'in_review',
          folder: '/home/dev/code/beta',
        ),
        _session(
          'i',
          'Input session',
          'waiting_for_input',
          folder: '/home/dev/code/gamma',
          profile: 'claude',
        ),
        _session(
          'n',
          'Normal gamma',
          'idle',
          folder: '/home/dev/code/gamma',
          branch: 'feat/p',
          changes: {'added': 12, 'removed': 3},
        ),
      ]));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(seconds: 1));

      expect(find.byType(SessionGroupHeader), findsNothing);
      expect(find.text('Needs you'), findsNothing);

      // The Now section holds all 3 attention sessions as live cards.
      final nowLabel = find.widgetWithText(MobileSectionLabel, 'Now');
      expect(nowLabel, findsOneWidget);
      expect(find.descendant(of: nowLabel, matching: find.text('3')),
          findsOneWidget);
      expect(find.byType(LiveSessionCard), findsNWidgets(3));

      // alpha and beta have no remaining sessions, so no folder sections.
      expect(find.widgetWithText(MobileSectionLabel, 'alpha'), findsNothing);
      expect(find.widgetWithText(MobileSectionLabel, 'beta'), findsNothing);

      // gamma retains only the normal session (count 1).
      final gammaHeader = find.widgetWithText(MobileSectionLabel, 'gamma');
      expect(gammaHeader, findsOneWidget);
      expect(find.descendant(of: gammaHeader, matching: find.text('1')),
          findsOneWidget);
      expect(find.byType(SessionListRow), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(SessionListRow),
              matching: find.text('Normal gamma')),
          findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(LiveSessionCard),
              matching: find.text('Normal gamma')),
          findsNothing);

      expect(find.textContaining('Question'), findsWidgets);
      expect(find.textContaining('In review'), findsOneWidget);
      expect(find.textContaining('Needs input'), findsOneWidget);

      // Project tags appear on live cards.
      expect(find.text('alpha'), findsOneWidget);
      expect(find.text('beta'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(LiveSessionCard), matching: find.text('gamma')),
          findsOneWidget);

      // Phone provider mark uses size 18 inside the 20px box.
      final logo = tester.widget<ProviderLogo>(find.byType(ProviderLogo));
      expect(logo.size, 18);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('row formatting handles untitled weight, unread time, folder label fg3, and phone Settled card',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await tester.pumpWidget(_phoneHarness(sessions: [
        _session('u', '   ', 'idle', folder: '/home/dev/code/repo'),
        _session('z', 'Archived fix', 'idle', settled: true),
      ]));
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pump(const Duration(seconds: 1));

      final untitled = tester.widget<Text>(find.text('(untitled)'));
      expect(untitled.style?.color, AppColors.fg3);
      expect(untitled.style?.fontWeight, FontWeight.w400);

      final repoHeader = find.widgetWithText(MobileSectionLabel, 'repo');
      final repoLabel = tester.widget<Text>(
          find.descendant(of: repoHeader, matching: find.text('repo')));
      expect(repoLabel.style?.color, AppColors.fg3);

      final settledHeader = find.text('Settled');
      expect(settledHeader, findsOneWidget);
      // Settled is the last card in the scrolling list.
      expect(
        find.ancestor(of: settledHeader, matching: find.byType(ListView)),
        findsWidgets,
      );
      final settledCard = find.ancestor(
          of: settledHeader, matching: find.byType(MobileGroupCard));
      final settledIcon = tester.widget<AppIcon>(find
          .descendant(of: settledCard, matching: find.byType(AppIcon))
          .first);
      expect(settledIcon.name, 'archive');
      expect(find.descendant(of: settledCard, matching: find.text('1')),
          findsOneWidget);
      expect(
          tester
              .widgetList<AppIcon>(
                  find.descendant(of: settledCard, matching: find.byType(AppIcon)))
              .any((i) => i.name == 'chevron-right'),
          isTrue);
      final reveal = find.descendant(
          of: settledCard, matching: find.byType(Reveal));
      expect(find.text('Archived fix'), findsNothing);
      expect(tester.widget<Reveal>(reveal).show, isFalse);

      await tester.tap(settledHeader);
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.widget<Reveal>(reveal).show, isTrue);
      expect(find.text('Archived fix'), findsOneWidget);
      await tester.tap(settledHeader);
      await tester.pump(const Duration(milliseconds: 400));

      // Unread row highlights timestamp in fg1 vs fg4.
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: SessionListRow(
            session: _session('ur', 'Unread row', 'idle'),
            unread: true,
            onTap: () {},
          ),
        ),
      ));
      await tester.pump();
      final ts = tester.widget<Text>(find.text('10m'));
      expect(ts.style?.color, AppColors.fg1);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  test('MobileHome.chats has label Sessions',
      () {
    expect(MobileHome.chats.label, 'Sessions');
    expect(MobileHome.agents.label, 'Agents');
  });
}
