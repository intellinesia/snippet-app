import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/accounts_screen.dart';
import 'package:snippet/screens/inference_profile_editor.dart';
import 'package:snippet/screens/inference_profiles.dart';
import 'package:snippet/screens/usage.dart';
import 'package:snippet/screens/vault.dart';
import 'package:snippet/settings_form.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/widgets.dart';

class _FakeDaemon extends DaemonClient {
  _FakeDaemon() : super('https://daemon.invalid', 'test-token');

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

void main() {
  testWidgets('profile card has its provider logo and does not show token or session count',
      (tester) async {
    final client = _FakeDaemon()
      ..config = {
        'profiles': [
          {
            'name': 'gpt-4o',
            'provider': 'openai',
            'model': 'gpt-4o',
            'active': true,
            'usable': true,
          }
        ],
      };

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: InferenceProfilesScreen(client: client, embedded: true),
      ),
    ));

    await tester.pumpAndSettle();

    // The name and model are shown
    expect(find.text('gpt-4o'), findsOneWidget);
    expect(find.text('openai · gpt-4o'), findsOneWidget);

    // No session count and no token count
    expect(find.textContaining('session'), findsNothing);
    expect(find.textContaining('tok'), findsNothing);

    final logos = tester.widgetList<ProviderLogo>(find.byType(ProviderLogo));
    expect(logos.any((l) => l.provider == 'openai'), isTrue);
    final icons = tester.widgetList<AppIcon>(find.byType(AppIcon));
    expect(icons.any((icon) => icon.name == 'cpu'), isFalse);
  });

  testWidgets(
      'rebuilding parent does not cause embedded InferenceProfilesScreen to flicker',
      (tester) async {
    final client = _FakeDaemon()
      ..config = {
        'profiles': [
          {
            'name': 'claude-3-5-sonnet',
            'provider': 'anthropic',
            'model': 'claude-3-5-sonnet-20241022',
            'active': true,
            'usable': true,
          }
        ],
      };

    final rebuildNotifier = ValueNotifier<int>(0);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: ValueListenableBuilder<int>(
          valueListenable: rebuildNotifier,
          builder: (context, value, _) {
            return Column(
              children: [
                Text('Rebuild count: $value'),
                Expanded(
                  child: InferenceProfilesScreen(
                      client: client, embedded: true),
                ),
              ],
            );
          },
        ),
      ),
    ));

    await tester.pumpAndSettle();
    expect(find.text('claude-3-5-sonnet'), findsOneWidget);

    // Trigger parent rebuild
    rebuildNotifier.value++;
    // Pump a single frame without waiting for any microtasks/futures.
    await tester.pump();

    // It should STILL be rendering the profile, never disappearing or shrinking
    expect(find.text('claude-3-5-sonnet'), findsOneWidget);
  });

  testWidgets('vault secret does not render masked dots placeholder',
      (tester) async {
    final client = _FakeDaemon()..secrets = ['API_SECRET_KEY'];

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: VaultScreen(client: client, embedded: true),
      ),
    ));

    await tester.pumpAndSettle();

    expect(find.text('API_SECRET_KEY'), findsOneWidget);
    expect(find.text('••••••'), findsNothing);
    expect(find.textContaining('••'), findsNothing);
  });

  test('Devin provider logo, usability, and usage label match spec', () {
    expect(providerLogoAsset('devin'), 'assets/providers/devin.svg');
    expect(providerLogoAsset('windsurf'), 'assets/providers/devin.svg');
    expect(providerLogoIsColour('devin'), isFalse);
    expect(usageProviderTitle('devin'), 'Devin');

    final profile = InferenceProfile.fromJson({
      'name': 'devin-swe',
      'provider': 'devin',
      'model': 'swe-2',
      'has_key': false,
    });
    expect(profile.usable, isTrue);
  });

  testWidgets(
    'Accounts provider titles match descriptor table and unknown provider has no add action',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      expect(
        ['chatgpt', 'xai', 'claude-code', 'devin']
            .map(accountProviderTitle)
            .toList(),
        ['ChatGPT', 'xAI / SuperGrok', 'Claude Code', 'Devin'],
      );
      expect(accountProviderTitle('mystery-cli'), 'mystery-cli');

      final client = _DummyDevinDaemon()
        ..accounts = {
          'chatgpt': const [],
          'xai': const [],
          'claude-code': const [],
          'devin': const [],
          'mystery-cli': [
            Account.fromJson({'id': 'u1', 'label': 'u1', 'active': false}),
          ],
        };

      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: AccountsScreen(client: client, embedded: true),
        ),
      ));
      await tester.pumpAndSettle();

      final headers = tester
          .widgetList<SettingsGroup>(find.byType(SettingsGroup))
          .map((g) => g.header)
          .toList();
      expect(
        headers,
        ['ChatGPT', 'xAI / SuperGrok', 'Claude Code', 'Devin', 'mystery-cli'],
      );
      expect(find.text('Add account'), findsNWidgets(4));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'Devin CLI status card, sign-in flow, paste fallback, and non-removable main account',
    (tester) async {
      tester.view.physicalSize = const Size(1280, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final client = _DummyDevinDaemon();
      final launched = <Uri>[];

      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: InferenceProfileEditor(
            client: client,
            embedded: true,
            existing: InferenceProfile.fromJson({
              'name': 'devin',
              'provider': 'devin',
              'model': 'swe-2',
            }),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(
        find.text(
            'Add a Devin account under Accounts, or run devin auth login on the machine running Snippet (over SSH add --force-manual-token-flow).'),
        findsOneWidget,
      );

      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: AccountsScreen(
            client: client,
            embedded: true,
            launchExternal: (uri) async => launched.add(uri),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('DEVIN'), findsOneWidget);
      expect(find.text('devin-main'), findsOneWidget);
      await tester.tap(find.text('devin-main'));
      await tester.pumpAndSettle();
      expect(find.text('Devin'), findsOneWidget);
      expect(find.text('Remove account'), findsNothing);

      await tester.tap(find.text('Accounts'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add account').last);
      await tester.pumpAndSettle();

      expect(find.text('Add Devin account'), findsOneWidget);
      expect(
        find.text(
            'Sign in to each Devin account from here. The Devin CLI login on this machine, if any, shows as main.'),
        findsOneWidget,
      );
      expect(find.text('Sign in'), findsOneWidget);
      expect(find.text('Paste a key instead'), findsOneWidget);

      await tester.tap(find.text('Paste a key instead'));
      await tester.pumpAndSettle();
      expect(
          find.text('windsurf_api_key or credentials.toml'), findsOneWidget);
      await tester.tap(find.text('Add account'));
      await tester.pumpAndSettle();
      expect(
        find.text('Paste the windsurf_api_key from credentials.toml.'),
        findsNWidgets(2),
      );

      await tester.tap(find.text('Use browser sign-in instead'));
      await tester.pumpAndSettle();
      expect(find.text('Sign in'), findsOneWidget);

      await tester.tap(find.text('Sign in'));
      await tester.pumpAndSettle();

      expect(
        launched.map((u) => u.toString()).toList(),
        ['https://app.devin.ai/auth/cli/continue?x'],
      );
      expect(find.text('Code'), findsOneWidget);
      expect(find.text('Finish'), findsOneWidget);

      client.completeError = 'Expired Devin code';
      await tester.enterText(find.byType(TextField), 'bad-code');
      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();
      expect(find.text('Expired Devin code'), findsOneWidget);

      client.completeError = null;
      await tester.enterText(find.byType(TextField), 'valid-code-123');
      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();

      expect(
        client.completedCalls,
        [('devin', 'd1', 'valid-code-123', null)],
      );
      expect(find.text('Finish sign-in'), findsNothing);
      expect(find.text('d1'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.linux),
  );

  testWidgets(
    'Mobile Devin sign-in opens link, prompts for code, and completes account',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final client = _DummyDevinDaemon()
        ..accounts = {
          'chatgpt': const [],
          'xai': const [],
          'claude-code': const [],
          'devin': const [],
        };
      final launched = <Uri>[];

      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: AccountsScreen(
            client: client,
            embedded: true,
            launchExternal: (uri) async => launched.add(uri),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.scrollUntilVisible(find.text('DEVIN'), 200);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add account').last);
      await tester.pumpAndSettle();

      expect(find.text('Name this account'), findsOneWidget);
      await tester.tap(find.text('Add'));
      await tester.pumpAndSettle();

      expect(
        launched.map((u) => u.toString()).toList(),
        ['https://app.devin.ai/auth/cli/continue?x'],
      );
      expect(find.text('Paste the Devin code'), findsOneWidget);
      await tester.enterText(find.byType(TextField), 'mobile-code-7');
      await tester.tap(find.text('Finish'));
      await tester.pumpAndSettle();

      expect(
        client.completedCalls,
        [('devin', 'd1', 'mobile-code-7', null)],
      );
      expect(find.text('d1'), findsOneWidget);
    },
    variant: TargetPlatformVariant.only(TargetPlatform.android),
  );
}

class _DummyDevinDaemon extends _FakeDaemon {
  Map<String, List<Account>> accounts = {
    'chatgpt': const [],
    'xai': const [],
    'claude-code': const [],
    'devin': [
      Account.fromJson({
        'id': 'main',
        'label': 'devin-main',
        'active': true,
      }),
    ],
  };

  final List<(String, String, String, String?)> completedCalls = [];
  String? completeError;

  @override
  Future<Map<String, dynamic>> reasoningSpec(
          String provider, String model) async =>
      const {'options': <String>[]};

  @override
  Future<Map<String, dynamic>> cliAgentStatus(String provider) async => {
        'installed': true,
        'signed_in': false,
      };

  @override
  Future<Map<String, List<Account>>> getAccounts() async => accounts;

  @override
  Future<Map<String, dynamic>> addAccount(String provider,
      {String? label, String? token}) async {
    return {
      'id': 'd1',
      'verification_uri': 'https://app.devin.ai/auth/cli/continue?x',
      'needs_code': true,
    };
  }

  @override
  Future<Map<String, dynamic>> completeAccount(
      String provider, String id, String code,
      {String? label}) async {
    if (completeError != null) throw completeError!;
    completedCalls.add((provider, id, code, label));
    accounts = {
      ...accounts,
      provider: [
        ...(accounts[provider] ?? const []),
        Account.fromJson({
          'id': id,
          'label': label ?? '',
          'active': false,
        }),
      ],
    };
    return {'id': id};
  }
}
