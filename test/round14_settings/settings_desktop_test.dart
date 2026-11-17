import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
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


Future<void> _shot(WidgetTester t, String name) async {
  const dir = String.fromEnvironment('SHOT_DIR');
  if (dir.isEmpty) return;
  await t.runAsync(() async {
    final b = t.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('shot')));
    final img = await b.toImage();
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  const pages = {
    'machines': SettingsPage.general,
    'models': SettingsPage.models,
    'routing': SettingsPage.routing,
    'accounts': SettingsPage.accounts,
    'usage': SettingsPage.usage,
    'memory': SettingsPage.memory,
    'wakes': SettingsPage.wakes,
    'keepwarm': SettingsPage.keepWarm,
    'scheduled': SettingsPage.scheduled,
    'vault': SettingsPage.vault,
    'websearch': SettingsPage.webSearch,
    'voice': SettingsPage.voice,
    'appearance': SettingsPage.appearance,
  };

  for (final e in pages.entries) {
    testWidgets('desktop settings renders ${e.key}',
        variant: TargetPlatformVariant.only(TargetPlatform.linux),
        (tester) async {
      tester.view.physicalSize = const Size(1280, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(RepaintBoundary(
        key: const ValueKey('shot'),
        child: MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            backgroundColor: AppColors.bg,
            body: DesktopSettingsPage(
              client: _FakeDaemon(),
              instances: const [_linux, _mac],
              active: _linux,
              onRemove: (_) {},
              onBack: () {},
              initialSection: e.value,
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      await _shot(tester, e.key);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 10));
    });
  }
}
