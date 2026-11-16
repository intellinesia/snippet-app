import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/accounts_screen.dart';
import 'package:snippet/screens/routing_screen.dart';
import 'package:snippet/screens/settings_panel.dart';
import 'package:snippet/theme.dart';

class _Daemon extends DaemonClient {
  _Daemon() : super('http://127.0.0.1:1', 'tok');

  @override
  Future<ServerConfig> getConfig({bool force = false}) async =>
      ServerConfig.fromJson({
        'profiles': [
          {'name': 'opus', 'provider': 'anthropic', 'model': 'claude-opus-4-6', 'has_key': true, 'active': true, 'models': []},
          {'name': 'flash', 'provider': 'gemini', 'model': 'gemini-flash', 'has_key': true, 'active': false, 'models': []},
        ],
        'active': 'opus',
        'routing': {'mission': ['opus', 'flash']},
      });

  @override
  Future<Map<String, List<Account>>> getAccounts() async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    return {
      'chatgpt': [
        Account.fromJson({
          'id': 'a1',
          'label': 'main',
          'active': true,
          'usage': {
            'primary': {'used_percent': 42, 'window_minutes': 300, 'resets_at': now + 3600},
            'secondary': {'used_percent': 18, 'window_minutes': 10080, 'resets_at': now + 86400},
          },
        }),
      ],
    };
  }
}

Widget _host(Widget child) => MaterialApp(
    theme: buildAppTheme(), home: Scaffold(body: child));

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('routing leads with the session model from the active profile',
      variant: TargetPlatformVariant.only(TargetPlatform.linux), (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(RoutingScreen(client: _Daemon(), embedded: true)));
    await tester.pumpAndSettle();
    // Unset routes also show a Session model placeholder pill.
    expect(find.text('Session model'), findsWidgets);
    expect(find.text('Active profile'), findsWidgets);
    expect(find.text('Primary · set in profiles'), findsOneWidget);
  });

  testWidgets('accounts name each rate window in words',
      variant: TargetPlatformVariant.only(TargetPlatform.linux), (tester) async {
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_host(AccountsScreen(client: _Daemon(), embedded: true)));
    await tester.pumpAndSettle();
    expect(find.textContaining('5-hour window 42%'), findsOneWidget);
    expect(find.textContaining('Weekly window 18%'), findsOneWidget);
  });

  testWidgets('approvals sheet returns the chosen mode',
      variant: TargetPlatformVariant.only(TargetPlatform.android), (tester) async {
    tester.view.physicalSize = const Size(390, 844);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    bool? picked;
    await tester.pumpWidget(_host(Builder(
      builder: (context) => TextButton(
        onPressed: () async =>
            picked = await showApprovalsSheet(context, manual: true),
        child: const Text('open'),
      ),
    )));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.text('Approvals'), findsOneWidget);
    expect(find.text('Pause for approval on each change'), findsOneWidget);
    await tester.tap(find.text('Yolo'));
    await tester.pumpAndSettle();
    expect(picked, isFalse);
  });
}
