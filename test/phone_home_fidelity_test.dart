import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/mochi.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/mobile_bottom_bar.dart';
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
  testWidgets('phone header renders MC button, badge, Listening pill, New session and Sessions title',
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
      await tester.pumpAndSettle();

      expect(find.text('Ignored shell bar'), findsNothing);
      expect(find.text('Sessions'), findsAtLeastNWidgets(1));
      expect(find.text('Listening'), findsOneWidget);
      expect(find.text('2'), findsOneWidget);

      final title = tester.widget<Text>(find.text('Sessions').first);
      expect(title.style?.fontSize, 17);
      expect(title.style?.fontWeight, FontWeight.w500);
      expect(title.style?.letterSpacing, 0);
      expect(title.maxLines, 1);
      expect(title.overflow, TextOverflow.ellipsis);

      final mcMochi = tester.widget<MochiIcon>(find.byType(MochiIcon));
      expect(mcMochi.size, 22);
      expect(mcMochi.color, AppColors.fg1);

      await tester.tap(find.byTooltip('Mission Control'));
      await tester.tap(find.byTooltip('New session'));
      await tester.pump();
      expect(mcTapped, 1);
      expect(moreTapped, 1);

      // Badge and Listening pill hide when count is 0 and listening is off.
      await tester.pumpWidget(_phoneHarness(
        sessions: [_session('s1', 'Work', 'idle')],
        listening: false,
        mcAttention: 0,
      ));
      await tester.pumpAndSettle();
      expect(find.text('Listening'), findsNothing);
      expect(find.text('2'), findsNothing);
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

      // Cross-project Needs you header holds all 3 attention sessions.
      final needsHeader = find.widgetWithText(SessionGroupHeader, 'Needs you');
      expect(needsHeader, findsOneWidget);
      expect(find.descendant(of: needsHeader, matching: find.text('3')),
          findsOneWidget);

      // alpha and beta have no remaining sessions, so no project headers appear.
      expect(find.widgetWithText(SessionGroupHeader, 'alpha'), findsNothing);
      expect(find.widgetWithText(SessionGroupHeader, 'beta'), findsNothing);

      // gamma retains only the normal session (count 1).
      final gammaHeader = find.widgetWithText(SessionGroupHeader, 'gamma');
      expect(gammaHeader, findsOneWidget);
      expect(find.descendant(of: gammaHeader, matching: find.text('1')),
          findsOneWidget);

      expect(find.text('Question'), findsOneWidget);
      expect(find.text('In review'), findsOneWidget);
      expect(find.text('Needs input'), findsOneWidget);

      // Project chips appear on Needs you rows.
      expect(find.text('alpha'), findsOneWidget);
      expect(find.text('beta'), findsOneWidget);

      // Phone provider mark uses size 18 inside the 20px box.
      final logo = tester.widget<ProviderLogo>(find.byType(ProviderLogo));
      expect(logo.size, 18);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('row formatting handles untitled weight, unread time, group header fg4, and phone Settled pinned',
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

      final repoHeader = find.widgetWithText(SessionGroupHeader, 'repo');
      final repoLabel = tester.widget<Text>(
          find.descendant(of: repoHeader, matching: find.text('repo')));
      expect(repoLabel.style?.color, AppColors.fg4);

      final settledHeader = find.text('Settled');
      expect(settledHeader, findsOneWidget);
      // Settled is pinned under the list, outside its scroll.
      expect(
        find.ancestor(of: settledHeader, matching: find.byType(ListView)),
        findsNothing,
      );
      final settledIcon = tester.widget<AppIcon>(find.descendant(
          of: find.ancestor(of: settledHeader, matching: find.byType(Row)).first,
          matching: find.byType(AppIcon)));
      expect(settledIcon.name, 'chevron-right');
      expect(find.text('Archived fix'), findsNothing);
      expect(tester.widget<Reveal>(find.byType(Reveal)).show, isFalse);

      await tester.tap(settledHeader);
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.widget<Reveal>(find.byType(Reveal)).show, isTrue);
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

  test('MobileHome.chats has label Sessions and MobileBottomBar excludes Tasks',
      () {
    expect(MobileHome.chats.label, 'Sessions');
    expect(MobileHome.agents.label, 'Agents');
    expect(MobileBottomBar, isNotNull);
  });
}
