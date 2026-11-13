import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:snippet/api.dart';
import 'package:snippet/desktop_layout.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/settings_panel.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/widgets.dart';

/// Enough of the daemon for the phone settings home: config, vault, usage,
/// ambient flag and sessions for the live count.
class _Daemon extends DaemonClient {
  _Daemon() : super('https://daemon.invalid', 'test-token');

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
            'models': [],
          }
        ],
        'manual_approval': true,
      });

  @override
  Future<List<String>> vaultList() async => ['openai', 'anthropic'];

  @override
  Future<UsageSummary> getUsage({DateTime? since}) async {
    return UsageSummary.fromJson({
      'providers': [
        {'provider': 'anthropic', 'total_tokens': 1200, 'calls': 12},
      ],
    });
  }

  @override
  Future<AmbientSettings> getAmbientSettings() async =>
      AmbientSettings(enabled: true);

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
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('phone settings home shows v5 groups and rows', (tester) async {
    tester.view.physicalSize = const Size(390, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        backgroundColor: AppColors.bg,
        body: SettingsPanel(
          client: _Daemon(),
          instances: const [
            Instance(name: 'desk', url: 'http://desk.local:8742', token: ''),
          ],
          active: const Instance(
              name: 'desk', url: 'http://desk.local:8742', token: ''),
          onRemove: (_) {},
          onClose: () {},
          embedded: true,
          onSection: (_) {},
        ),
      ),
    ));
    await tester.pumpAndSettle();

    expect(find.text('desk'), findsWidgets);
    expect(find.textContaining('Connected · 1 live'), findsOneWidget);
    for (final label in [
      'General',
      'Agents',
      'Appearance',
      'Inference profiles',
      'Routing',
      'Accounts',
      'Usage',
      'Approvals',
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
    // Row values fetched from the daemon.
    expect(find.text('1'), findsWidgets); // profile count
    expect(find.text('2'), findsWidgets); // vault count
    expect(find.text('Listening'), findsOneWidget);
  });

  testWidgets(
      'SettingsSectionView on phone uses compact header without subtitle for Appearance and Routing',
      (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    var backCount = 0;
    Widget buildView(SettingsPage page) => MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            backgroundColor: AppColors.bg,
            body: SettingsSectionView(
              client: _Daemon(),
              instances: const [
                Instance(
                    name: 'desk', url: 'http://desk.local:8742', token: ''),
              ],
              active: const Instance(
                  name: 'desk', url: 'http://desk.local:8742', token: ''),
              page: page,
              onRemove: (_) {},
              onBack: () => backCount++,
            ),
          ),
        );

    await tester.pumpWidget(buildView(SettingsPage.appearance));
    await tester.pumpAndSettle();

    expect(find.text('Appearance'), findsOneWidget);
    expect(
      find.text(
          'Theme palette, accent colour, UI typeface and code font saved on this device.'),
      findsNothing,
    );
    expect(find.text('Palette'), findsOneWidget);
    expect(find.text('Typography'), findsOneWidget);
    expect(find.text('PALETTE'), findsNothing);
    expect(find.text('TYPOGRAPHY'), findsNothing);
    expect(tester.getSize(find.byType(SettingsHeader)).height, 44);
    await tester.tap(find.byWidgetPredicate(
        (w) => w is AppIcon && w.name == 'chevron-left'));
    expect(backCount, 1);

    await tester.pumpWidget(buildView(SettingsPage.routing));
    await tester.pumpAndSettle();

    expect(find.text('Routing'), findsOneWidget);
    expect(
      find.text(
          'Which model does each kind of work, and who steps in when it hits a limit.'),
      findsNothing,
    );
    expect(tester.getSize(find.byType(SettingsHeader)).height, 44);
    expect(find.text('Mission Control'), findsOneWidget);
  });
}
