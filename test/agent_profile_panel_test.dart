import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/agent_profile_panel.dart';
import 'package:snippet/theme.dart';

import 'support/wake_fakes.dart';

class _ProfileClient extends FakeWakeClient {
  final profiles = <String?>[];
  final desks = <String?>[];

  @override
  Future<ServerConfig> getConfig({bool force = false}) async =>
      ServerConfig.fromJson({
        'profiles': [
          {'name': 'argon', 'provider': 'openai', 'model': 'gpt'},
          {'name': 'claude', 'provider': 'anthropic', 'model': 'opus'},
        ],
      });

  @override
  Future<void> setAgentProfile(String agentId, String? profile) async =>
      profiles.add(profile);

  @override
  Future<void> setAgentDeskProfile(String agentId, String? profile) async =>
      desks.add(profile);
}

CoordinationAgent _agent({
  String? profile = 'argon',
  String? deskProfile,
  String? deskModel,
}) =>
    CoordinationAgent.fromJson({
      'id': 'scout',
      'display_name': 'Revenue Scout',
      if (profile != null) 'profile': profile,
      if (deskProfile != null) 'desk_profile': deskProfile,
      if (deskModel != null) 'desk_model': deskModel,
      'max_context_tokens': 128000,
    });

Future<void> _pump(
    WidgetTester tester, _ProfileClient c, CoordinationAgent a) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 1200);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: AgentProfilePanel(client: c, agent: a, name: 'Revenue Scout'),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets(
      'renders routing row, profiles, status line, and tap calls setAgentProfile',
      (tester) async {
    final c = _ProfileClient();
    await _pump(
        tester, c, _agent(profile: 'claude', deskProfile: 'argon'));
    expect(find.text('Inference profile'), findsOneWidget);
    expect(find.text('Desk is on argon, moving to claude after this turn'),
        findsOneWidget);
    expect(find.text('Routing default'), findsOneWidget);
    expect(find.text('Your Routing settings for desks'), findsOneWidget);
    expect(find.text('argon'), findsOneWidget);
    expect(find.text('openai · gpt'), findsOneWidget);
    expect(find.text('claude'), findsOneWidget);
    expect(find.text('anthropic · opus'), findsOneWidget);

    await tester.tap(find.text('argon'));
    await tester.pumpAndSettle();
    expect(c.profiles, ['argon']);
    await tester.pump(const Duration(seconds: 4));
  });

  testWidgets('renders running status line when desk matches profile',
      (tester) async {
    final c = _ProfileClient();
    await _pump(tester, c, _agent(profile: 'argon', deskProfile: 'argon'));
    expect(find.text('Desk is running on argon'), findsOneWidget);
  });

  testWidgets('showAgentProfileSettings closes sheet after picking profile',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);
    final c = _ProfileClient();
    var changed = 0;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () => showAgentProfileSettings(
              ctx,
              client: c,
              agent: _agent(),
              name: 'Revenue Scout',
              onChanged: () => changed++,
            ),
            child: const Text('Open'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();
    expect(find.byType(AgentProfilePanel), findsOneWidget);

    await tester.tap(find.text('claude'));
    await tester.pumpAndSettle();
    expect(c.profiles, ['claude']);
    expect(changed, 1);
    expect(find.byType(AgentProfilePanel), findsNothing);
    await tester.pump(const Duration(seconds: 4));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('one list until the desk is separated, then a desk list',
      (tester) async {
    final c = _ProfileClient();
    await _pump(tester, c, _agent());
    expect(find.text('Desk runs on'), findsNothing);
    expect(find.text('128k'), findsOneWidget);

    await tester.tap(find.text('Separate desk model'));
    await tester.pumpAndSettle();
    expect(find.text('Tasks run on'), findsOneWidget);
    expect(find.text('Desk runs on'), findsOneWidget);
    expect(c.desks, isEmpty);

    await tester.tap(find.text('claude').last);
    await tester.pumpAndSettle();
    expect(c.desks, ['claude']);
    expect(c.profiles, isEmpty);
  });

  testWidgets('turning the toggle off clears the desk model', (tester) async {
    final c = _ProfileClient();
    await _pump(tester, c, _agent(deskModel: 'claude'));
    expect(find.text('Desk runs on'), findsOneWidget);
    await tester.tap(find.text('Separate desk model'));
    await tester.pumpAndSettle();
    expect(c.desks, [null]);
    expect(find.text('Desk runs on'), findsNothing);
  });

  testWidgets('context edit calls the daemon and refuses below 16k',
      (tester) async {
    final c = _ProfileClient();
    await _pump(tester, c, _agent());
    await tester.tap(find.text('Compact above'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '8k');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    expect(c.contexts, isEmpty);
    expect(find.textContaining('at least 16k'), findsOneWidget);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Compact above'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).last, '64k');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    expect(c.contexts, [64000]);
    expect(find.text('64k'), findsOneWidget);
  });
}
