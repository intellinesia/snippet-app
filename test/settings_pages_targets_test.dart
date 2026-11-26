import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/wake_models.dart';
import 'package:snippet/screens/inference_profiles.dart';
import 'package:snippet/screens/vault.dart';
import 'package:snippet/screens/wakes_screen.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/theme.dart';

import 'support/wake_fakes.dart';

class _Daemon extends DaemonClient {
  _Daemon() : super('https://daemon.invalid', 'test-token');

  @override
  late final DeviceEventHub deviceEvents = DeviceEventHub.local();

  Map<String, dynamic> config = {};
  List<String> secrets = [];

  @override
  Future<ServerConfig> getConfig({bool force = false}) async =>
      ServerConfig.fromJson(config);

  @override
  Future<List<String>> vaultList() async => secrets;
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1000, 900);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(body: child),
  ));
  await tester.pumpAndSettle();
}

void desktop(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  desktop('vault highlights an existing target secret', (tester) async {
    final c = _Daemon()..secrets = ['A_KEY', 'GITHUB_TOKEN'];
    await _pump(
        tester,
        VaultScreen(
            client: c,
            embedded: true,
            chromeless: true,
            targetId: 'GITHUB_TOKEN'));
    expect(find.byKey(const Key('settings-target-GITHUB_TOKEN')),
        findsOneWidget);
    // The add form is closed; its Name field hint is absent.
    expect(find.text('Use it as \$NAME in shell commands.'), findsNothing);
  });

  desktop('vault opens the add form prefilled for a missing target',
      (tester) async {
    final c = _Daemon()..secrets = ['A_KEY'];
    await _pump(
        tester,
        VaultScreen(
            client: c,
            embedded: true,
            chromeless: true,
            targetId: 'GITHUB_TOKEN'));
    expect(find.byKey(const Key('settings-target-GITHUB_TOKEN')),
        findsNothing);
    expect(find.text('Use it as \$NAME in shell commands.'), findsOneWidget);
    final fields = tester.widgetList<EditableText>(find.byType(EditableText));
    expect(fields.first.controller.text, 'GITHUB_TOKEN');
    expect(fields.last.focusNode.hasFocus, isTrue);
    expect(find.text('Save secret'), findsOneWidget);
  });

  desktop('models highlights the target profile', (tester) async {
    final c = _Daemon()
      ..config = {
        'profiles': [
          {
            'name': 'claude',
            'provider': 'anthropic',
            'model': 'sonnet',
            'active': true,
            'usable': true,
          },
          {
            'name': 'antigravity',
            'provider': 'google',
            'model': 'gemini',
            'active': false,
            'usable': true,
          },
        ],
      };
    await _pump(
        tester,
        InferenceProfilesScreen(
            client: c,
            embedded: true,
            chromeless: true,
            targetId: 'antigravity'));
    expect(find.byKey(const Key('settings-target-antigravity')),
        findsOneWidget);
    expect(find.text('Profiles'), findsNothing);
  });

  desktop('wakes leaves keep warm to its own page', (tester) async {
    var opened = false;
    final c = FakeWakeClient(
      warmState: KeepWarmEntry.fromJson(keepWarmJson()),
    );
    await _pump(
        tester,
        WakesScreen(
            client: c,
            embedded: true,
            chromeless: true,
            onOpenKeepWarm: () => opened = true));
    // Keep warm has its own Settings page (spec_settings D2); Wakes neither
    // manages nor summarises it.
    expect(find.byKey(const ValueKey('warm-scout')), findsNothing);
    expect(find.byType(Switch), findsNothing);
    expect(find.byKey(const Key('keep-warm-summary')), findsNothing);
    expect(opened, isFalse);
  });
}
