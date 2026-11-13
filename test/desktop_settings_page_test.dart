import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/desktop_settings_page.dart';
import 'package:snippet/screens/settings_panel.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/wake_models.dart';

class _FakeDaemon extends DaemonClient {
  _FakeDaemon() : super('http://linux.local:8742', 'test-token');

  bool manualApproval = true;
  int setApprovalCalls = 0;

  @override
  Future<bool> health({Duration timeout = const Duration(seconds: 2)}) async =>
      true;

  @override
  Future<ServerConfig> getConfig({bool force = false}) async =>
      ServerConfig.fromJson({
        'profiles': [
          {
            'name': 'default',
            'provider': 'anthropic',
            'model': 'claude-opus-5-5',
            'base_url': 'https://api.anthropic.com',
            'auth': 'api_key',
            'active': true,
            'models': [],
          },
        ],
        'manual_approval': manualApproval,
      });

  @override
  Future<void> setManualApproval(bool on) async {
    setApprovalCalls++;
    manualApproval = on;
  }

  @override
  Future<List<SessionInfo>> sessions({String? folder, int? limit}) async => [
        SessionInfo.fromJson({
          'id': 's1',
          'folder': '/repo',
          'status': 'running',
          'created_at': '2026-11-13T08:00:00Z',
        }),
        SessionInfo.fromJson({
          'id': 's2',
          'folder': '/repo',
          'status': 'done',
          'settled': true,
          'created_at': '2026-11-12T08:00:00Z',
        }),
      ];

  @override
  Future<KeepWarmList> keepWarm() async => KeepWarmList(
        [
          KeepWarmEntry.fromJson({
            'owner': 'scout',
            'owner_kind': 'agent',
            'session_id': 'inbox-scout',
            'enabled': true,
            'interval_minutes': 4,
            'max_idle_hours': 2,
          }),
        ],
        const KeepWarmLimits(),
      );

  @override
  Future<WakeList> wakes() async => const WakeList([], WakeLimits());

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => const [];
}

const _linux = Instance(
  name: 'snippet-linux',
  url: 'http://linux.local:8742',
  token: 'tok-1',
);
const _mac = Instance(
  name: 'studio-mac',
  url: 'http://mac.invalid:8742',
  token: 'tok-2',
);

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('DesktopSettingsPage renders v5 layout, switches sections, and calls onBack',
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final daemon = _FakeDaemon();
    var backCalls = 0;

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        backgroundColor: AppColors.bg,
        body: DesktopSettingsPage(
          client: daemon,
          instances: const [_linux, _mac],
          active: _linux,
          onRemove: (_) {},
          onBack: () => backCalls++,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Back to sessions'), findsOneWidget);
    for (final label in [
      'General',
      'Agents',
      'Appearance',
      'Machines',
      'Inference profiles',
      'Routing',
      'Accounts',
      'Usage',
      'Memory',
      'Vault',
      'Wakes',
      'Voice',
      'Scheduled',
      'Web search',
      'Theme and accent',
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }

    // Machines page content.
    expect(find.text('Computers this app can reach. Sessions run on the selected one.'),
        findsOneWidget);
    expect(find.text('snippet-linux'), findsOneWidget);
    expect(find.text('This machine · 1 live session'), findsOneWidget);
    expect(find.text('Connected'), findsOneWidget);
    expect(find.text('studio-mac'), findsOneWidget);
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Add machine'), findsOneWidget);

    // Preferences card: Approvals menu and Keep sessions warm link.
    expect(find.text('Approvals'), findsOneWidget);
    expect(find.text('Ask'), findsOneWidget);
    expect(find.text('Keep sessions warm'), findsOneWidget);
    expect(find.text('1 active'), findsOneWidget);

    await tester.tap(find.text('Approvals'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Yolo'));
    await tester.pumpAndSettle();
    expect(daemon.setApprovalCalls, 1);
    expect(daemon.manualApproval, isFalse);
    expect(find.text('Yolo'), findsOneWidget);

    // Add machine flow and back to Machines.
    await tester.tap(find.text('Add machine'));
    await tester.pumpAndSettle();
    expect(find.text('Connect a machine'), findsOneWidget);
    await tester.tap(find.text('Machines').last);
    await tester.pumpAndSettle();
    expect(find.text('studio-mac'), findsOneWidget);

    // Switch to Theme and accent.
    await tester.tap(find.text('Theme and accent'));
    await tester.pumpAndSettle();
    expect(
      find.text(
          'Theme palette, accent colour, UI typeface and code font saved on this device.'),
      findsOneWidget,
    );
    expect(find.text('Accent colour'), findsOneWidget);
    expect(find.text('Charcoal Violet'), findsWidgets);

    // Switch to Inference profiles.
    await tester.tap(find.text('Inference profiles'));
    await tester.pumpAndSettle();
    expect(find.text('Profiles'), findsOneWidget);
    expect(find.text('default'), findsOneWidget);

    // Back to Machines, then jump to Wakes via Keep sessions warm.
    await tester.tap(find.text('Machines'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Keep sessions warm'));
    await tester.pumpAndSettle();
    expect(find.text('Agent schedules and keep-warm.'), findsOneWidget);

    // Clicking Back to sessions and pressing Escape both invoke onBack.
    await tester.tap(find.text('Back to sessions'));
    await tester.pumpAndSettle();
    expect(backCalls, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(backCalls, 2);
  });

  testWidgets('legacy SettingsPanel modal entry point still renders on desktop',
      variant: TargetPlatformVariant.only(TargetPlatform.linux),
      (tester) async {
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final daemon = _FakeDaemon();
    var closed = 0;

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: SettingsPanel(
          client: daemon,
          instances: const [_linux],
          active: _linux,
          onRemove: (_) {},
          onClose: () => closed++,
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('snippet-linux'), findsWidgets);
    await tester.tap(find.text('Profiles'));
    await tester.pumpAndSettle();
    expect(find.text('default'), findsOneWidget);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(closed, 1);
  });
}
