import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/screens/shell_models.dart';
import 'package:snippet/screens/sidebar.dart';

int get _now => DateTime.now().millisecondsSinceEpoch ~/ 1000;

class _Fake extends DaemonClient {
  _Fake() : super('https://daemon.invalid', 'test');
  @override
  late final DeviceEventHub deviceEvents = DeviceEventHub.local();
}

SessionInfo _s(String id, String title,
        {String folder = '/home/boss/code/snippet-mobile',
        String status = 'idle',
        int ago = 600,
        int? add,
        int? del,
        int files = 0,
        bool settled = false,
        String? agent,
        String? branch,
        Map<String, dynamic>? ask}) =>
    SessionInfo.fromJson({
      'id': id,
      'title': title,
      'folder': folder,
      'status': status,
      'running': status == 'running',
      'last_active': _now - ago,
      if (add != null) 'changes': {'files': files, 'added': add, 'removed': del ?? 0},
      'settled': settled,
      if (settled) 'settled_at': _now - ago,
      if (agent != null) 'worker_agent_id': agent,
      if (branch != null) 'branch': branch,
      if (ask != null) 'attention': ask,
    });

List<SessionInfo> _sessions() => [
      _s('1', 'Slate accent and press feedback',
          status: 'running', ago: 5, add: 142, del: 31, files: 6, agent: 'snippet', branch: 'ui-polish-emil'),
      _s('2', 'TUI gets stuck when listing sessions',
          status: 'waiting_for_input', ago: 120, ask: {'type': 'approval', 'text': 'Run cargo test?'}),
      _s('3',
          'Investigate why the Android release build fails on CI after the Gradle plugin upgrade to 8.7',
          ago: 3600, add: 12873, del: 9402, files: 214, branch: 'fix/gradle'),
      _s('4', '', ago: 7200),
      _s('5', 'Add regression coverage', ago: 86400, add: 8, del: 0, files: 1, branch: 'main'),
      _s('6', 'Quarry post', folder: '/home/boss/code/technoxi', ago: 90000, add: 40, del: 12, files: 3, branch: 'quarry'),
      _s('7', 'Cisco MINT page 日本語のタイトルがとても長い場合', folder: '/home/boss/code/technoxi', ago: 200000, branch: 'main'),
      _s('8', 'Old: migrate notifications', ago: 900000, settled: true, add: 5, del: 5, files: 2),
      _s('9', 'Old: voiceprint enrol', ago: 1200000, settled: true),
      _s('10', 'Docs sweep',
          folder: '/home/boss/code/very-long-project-name-for-monorepo-backend-services-and-workers',
          ago: 300, status: 'running', add: 3, del: 1, files: 1, branch: 'feature/a-very-long-branch-name-that-keeps-going'),
    ];

Widget _sidebar({List<SessionInfo>? sessions, bool topInset = false, String? selected}) => Scaffold(
      backgroundColor: AppColors.bg,
      body: Sidebar(
        instances: const [],
        active: null,
        client: _Fake(),
        selectedSessionId: selected,
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
        health: const {},
        onRefreshHealth: () {},
        topInset: topInset,
        mobileHome: MobileHome.chats,
        onMobileHome: (_) {},
        settingsSection: null,
        onSettingsSection: (_) {},
        agent: null,
        onAgent: (_) {},
      ),
    );

Future<void> _shoot(WidgetTester tester, Widget home, Size size, String name,
    {TargetPlatform platform = TargetPlatform.android,
    Future<void> Function(WidgetTester)? after}) async {
  debugDefaultTargetPlatformOverride = platform;
  final prevOnError = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exception.toString().contains('audioplayers')) return;
    prevOnError?.call(d);
  };
  addTearDown(() => FlutterError.onError = prevOnError);
  DaemonClient.wsConnector = null;
  SharedPreferences.setMockInitialValues({});
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  final key = GlobalKey();
  await tester.pumpWidget(RepaintBoundary(
    key: key,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: home,
    ),
  ));
  for (var n = 0; n < 8; n++) {
    await tester.pump(const Duration(milliseconds: 250));
  }
  if (after != null) {
    await after(tester);
    for (var n = 0; n < 6; n++) {
      await tester.pump(const Duration(milliseconds: 250));
    }
  }
  final ex = tester.takeException();
  if (ex != null) fail('EXCEPTION in $name: $ex');
  await expectLater(find.byKey(key), matchesGoldenFile('goldens/sessions/$name.png'));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 70));
  debugDefaultTargetPlatformOverride = null;
}

bool _settledShown(WidgetTester t) => find.text('Old: voiceprint enrol').evaluate().isNotEmpty;

Future<void> _openSettled(WidgetTester t) async {
  if (!_settledShown(t)) await t.tap(find.text('Settled').first);
}

Future<void> _closeSettled(WidgetTester t) async {
  if (_settledShown(t)) {
    await t.tap(find.text('Settled').first);
    await t.pump(const Duration(milliseconds: 600));
  }
}

void main() {
  testWidgets('phone 390 selecting', (t) async {
    await _shoot(t, _sidebar(sessions: _sessions()), const Size(390, 844), 'phone_390_select',
        after: (t) async {
      await _closeSettled(t);
      await t.longPress(find.text('Add regression coverage'));
      await t.pump(const Duration(milliseconds: 600));
      await t.tap(find.text('Select').last);
      await t.pump(const Duration(milliseconds: 600));
      await t.tap(find.text('Quarry post'));
    });
  });
  testWidgets('phone 390', (t) async {
    await _shoot(t, _sidebar(sessions: _sessions()), const Size(390, 844), 'phone_390',
        after: _closeSettled);
  });
  testWidgets('phone 390 settled open', (t) async {
    await _shoot(t, _sidebar(sessions: _sessions()), const Size(390, 844), 'phone_390_settled',
        after: _openSettled);
  });
  testWidgets('phone 320', (t) async {
    await _shoot(t, _sidebar(sessions: _sessions()), const Size(320, 690), 'phone_320',
        after: _closeSettled);
  });
  testWidgets('phone empty', (t) async {
    await _shoot(t, _sidebar(sessions: const []), const Size(390, 844), 'phone_empty');
  });
  testWidgets('desktop sidebar', (t) async {
    await _shoot(t, _sidebar(sessions: _sessions(), topInset: true, selected: '1'),
        const Size(280, 800), 'desktop_sidebar',
        platform: TargetPlatform.macOS, after: _closeSettled);
  });
  testWidgets('desktop sidebar settled open', (t) async {
    await _shoot(t, _sidebar(sessions: _sessions(), topInset: true, selected: '3'),
        const Size(280, 800), 'desktop_sidebar_settled',
        platform: TargetPlatform.macOS, after: _openSettled);
  });
  testWidgets('desktop sidebar 220 wide', (t) async {
    await _shoot(t, _sidebar(sessions: _sessions(), topInset: true),
        const Size(220, 800), 'desktop_sidebar_220',
        platform: TargetPlatform.macOS, after: _closeSettled);
  });
  testWidgets('desktop empty', (t) async {
    await _shoot(t, _sidebar(sessions: const [], topInset: true), const Size(280, 800),
        'desktop_empty', platform: TargetPlatform.macOS);
  });
  testWidgets('phone 320 worst case', (t) async {
    final long = 'x' * 200;
    await _shoot(
        t,
        _sidebar(sessions: [
          _s('a', 'Waiting ${long}y',
              status: 'waiting_for_input', folder: '/home/boss/${long}z', add: 1234567, del: 987654, files: 9, branch: long),
          _s('b', 'Working', status: 'running', add: 0, del: 0, files: 0, branch: 'main', agent: 'snippet'),
          _s('c', 'Zero diff, no git', add: 0, del: 0),
          _s('d', '   '),
          _s('e', 'Exactly ten thousand', add: 10000, del: 9999, files: 2, branch: 'b'),
        ]),
        const Size(320, 690),
        'phone_320_worst',
        after: _closeSettled);
  });
}
