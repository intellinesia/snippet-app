import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/mochi.dart';
import 'package:snippet/models.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/widgets.dart';
import 'package:snippet/screens/session_list_row.dart';
import 'package:snippet/screens/shell_models.dart';
import 'package:snippet/screens/sidebar.dart';

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

SessionInfo _s(String id, String title, String status,
        {String folder = '/home/dev/code/snippet-mobile',
        String? branch,
        Map<String, dynamic>? changes,
        int? since,
        String? agentId,
        String? profile}) =>
    SessionInfo.fromJson({
      'id': id,
      'title': title,
      'status': status,
      'last_active': _now - 600,
      'folder': folder,
      if (branch != null) 'branch': branch,
      if (changes != null) 'changes': changes,
      if (since != null) 'running_since': since,
      if (agentId != null) 'agent_id': agentId,
      if (profile != null) 'profile': profile,
    });

Future<void> _pump(WidgetTester tester, Size size, TargetPlatform p,
    {List<SessionInfo>? sessions}) async {
  debugDefaultTargetPlatformOverride = p;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
        body: Sidebar(
      instances: const [],
      active: null,
      client: _Client(),
      selectedSessionId: 'b',
      sessions: sessions ??
          [
            _s('a', 'Redo voice settings subpage', 'waiting_for_input',
                branch: 'main',
                changes: {'files': 4, 'added': 120, 'removed': 31}),
            _s('b', 'Richer session cards', 'running',
                branch: 'cards',
                since: _now - 260,
                changes: {'files': 2, 'added': 88, 'removed': 12}),
            _s('c', 'Release pipeline fix', 'idle',
                folder: '/home/dev/code/snippet-service', branch: 'main'),
            _s('d', 'Notes', 'idle', folder: ''),
          ],
      sessionsLoading: false,
      onRefreshSessions: () {},
      onNewSession: () {},
      onSelectInstance: (_) {},
      onOpenMissionControl: () {},
      onOpenSession: (_, __, ___) {},
      onAddInstance: () {},
      onRenameInstance: (_, name) {},
      onRemoveInstance: (_) {},
      onSessionDeleted: (_) {},
      health: const {},
      onRefreshHealth: () {},
      topInset: false,
      mobileHome: MobileHome.chats,
      onMobileHome: (_) {},
      settingsSection: null,
      onSettingsSection: (_) {},
      agent: null,
      onAgent: (_) {},
    )),
  ));
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pump(const Duration(seconds: 2));
}

void main() {
  testWidgets('phone cards show project, status, branch and diff',
      (tester) async {
    try {
      await _pump(tester, const Size(390, 700), TargetPlatform.android);
      expect(
          find.widgetWithText(SessionGroupHeader, 'Needs you'), findsOneWidget);
      expect(find.widgetWithText(SessionGroupHeader, 'snippet-mobile'),
          findsOneWidget);
      expect(find.text('snippet-mobile'), findsNWidgets(2));
      expect(find.text('~/code/snippet-mobile'), findsNothing);
      expect(find.bySemanticsLabel(RegExp('^Needs input')), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('^Working')), findsOneWidget);
      expect(find.text('+88'), findsOneWidget);
      expect(find.text('-12'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('desktop cards pin Needs you and keep the same detail',
      (tester) async {
    try {
      await _pump(tester, const Size(300, 520), TargetPlatform.macOS);
      expect(
          find.widgetWithText(SessionGroupHeader, 'Needs you'), findsOneWidget);
      expect(find.text('snippet-mobile'), findsNWidgets(2));
      expect(find.bySemanticsLabel(RegExp('^Working')), findsOneWidget);
      expect(find.text('+88'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('empty phone list offers to start a session', (tester) async {
    try {
      await _pump(tester, const Size(390, 700), TargetPlatform.android,
          sessions: const []);
      expect(find.text('No sessions yet'), findsOneWidget);
      // Only the header's +, no second button in the empty state.
      expect(find.byTooltip('New session'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('desktop keeps Settled at the bottom until expanded',
      (tester) async {
    try {
      final settled = SessionInfo.fromJson({
        'id': 'z',
        'title': 'Old chat',
        'settled': true,
        'settled_at': _now - 3600,
        'last_active': _now - 90000,
      });
      await _pump(tester, const Size(300, 520), TargetPlatform.macOS,
          sessions: [_s('a', 'Live chat', 'idle'), settled]);
      final header = tester.getTopLeft(find.text('Settled')).dy;
      expect(header, greaterThan(tester.getBottomLeft(find.text('Live chat')).dy));
      expect(find.text('Old chat'), findsNothing);
      await tester.tap(find.text('Settled'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final mid = tester.widget<AnimatedOpacity>(find.ancestor(
          of: find.text('Old chat'), matching: find.byType(AnimatedOpacity)).first);
      expect(mid.opacity, 1);
      final fade = tester.renderObject<RenderBox>(find.ancestor(
          of: find.text('Old chat'), matching: find.byType(AnimatedSize)).first);
      final midH = fade.size.height;
      await tester.pump(const Duration(milliseconds: 400));
      expect(fade.size.height, greaterThan(midH));
      expect(find.text('Old chat'), findsOneWidget);
      expect(tester.getTopLeft(find.text('Old chat')).dy,
          greaterThan(tester.getBottomLeft(find.text('Settled')).dy));
      expect(tester.getTopLeft(find.text('Settled')).dy, lessThan(header));
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('mobile Settled animates open', (tester) async {
    try {
      final settled = SessionInfo.fromJson({
        'id': 'z',
        'title': 'Old chat',
        'settled': true,
        'settled_at': _now - 3600,
        'last_active': _now - 90000,
      });
      await _pump(tester, const Size(390, 700), TargetPlatform.android,
          sessions: [_s('a', 'Live chat', 'idle'), settled]);
      if (find.text('Old chat').evaluate().isEmpty) {
        await tester.tap(find.text('Settled'));
        await tester.pump(const Duration(milliseconds: 600));
      }
      final box = tester.renderObject<RenderBox>(find
          .ancestor(of: find.text('Old chat'), matching: find.byType(AnimatedSize))
          .first);
      final full = box.size.height;
      expect(full, greaterThan(0));
      await tester.tap(find.text('Settled'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final mid = box.size.height;
      expect(mid, inExclusiveRange(0, full));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Old chat'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('working row shows Working and no time', (tester) async {
    try {
      await _pump(tester, const Size(300, 520), TargetPlatform.macOS,
          sessions: [
            _s('a', 'Running task', 'running', since: _now - 60),
            _s('b', 'Idle task', 'idle'),
          ]);
      final workingRow = find.ancestor(
          of: find.text('Running task'), matching: find.byType(SessionListRow));
      expect(
          find.descendant(of: workingRow, matching: find.byType(WorkingDots)),
          findsOneWidget);
      expect(
          find.descendant(of: workingRow, matching: find.text('Working')),
          findsOneWidget);
      expect(
          find.descendant(of: workingRow, matching: find.text('10m')),
          findsNothing);

      final idleRow = find.ancestor(
          of: find.text('Idle task'), matching: find.byType(SessionListRow));
      expect(
          find.descendant(of: idleRow, matching: find.text('Working')),
          findsNothing);
      expect(
          find.descendant(of: idleRow, matching: find.text('10m')),
          findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('folder group headers are plain labels that do not collapse',
      (tester) async {
    try {
      await _pump(tester, const Size(300, 520), TargetPlatform.macOS,
          sessions: [
            _s('a', 'Redo voice settings subpage', 'idle', branch: 'main'),
            _s('b', 'Richer session cards', 'running', branch: 'cards'),
          ]);
      final header = find.widgetWithText(SessionGroupHeader, 'snippet-mobile');
      expect(find.descendant(of: header, matching: find.byType(AnimatedOpacity)),
          findsNothing);
      await tester.tap(find.text('snippet-mobile'));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.text('Redo voice settings subpage'), findsOneWidget);
      expect(find.text('Richer session cards'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      'phone Needs you header colour and 20px mark',
      (tester) async {
    try {
      await _pump(tester, const Size(390, 700), TargetPlatform.android,
          sessions: [
            _s('a', 'Needs input chat', 'waiting_for_input', agentId: 'scout'),
          ]);
      final header = find.widgetWithText(SessionGroupHeader, 'Needs you');

      final label = tester.widget<Text>(
          find.descendant(of: header, matching: find.text('Needs you')));
      expect(label.style?.color, AppColors.run);

      final mochi = tester.widget<AgentMochi>(find.byType(AgentMochi));
      expect(mochi.size, 20);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
