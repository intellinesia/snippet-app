import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/agent_model_page.dart';
import 'package:snippet/theme.dart';

import 'support/wake_fakes.dart';

class _ModelClient extends FakeWakeClient {
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

CoordinationAgent _agent({String? desk}) => CoordinationAgent.fromJson({
      'id': 'scout',
      'display_name': 'Revenue Scout',
      'profile': 'argon',
      if (desk != null) 'desk_model': desk,
      'max_context_tokens': 128000,
    });

Future<void> _pump(
    WidgetTester tester, _ModelClient c, CoordinationAgent a) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 1200);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(body: AgentModelPage(client: c, agent: a)),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('one list until the desk is separated, then a desk list',
      (tester) async {
    final c = _ModelClient();
    await _pump(tester, c, _agent());
    expect(find.text('Works on'), findsOneWidget);
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
    final c = _ModelClient();
    await _pump(tester, c, _agent(desk: 'claude'));
    expect(find.text('Desk runs on'), findsOneWidget);
    await tester.tap(find.text('Separate desk model'));
    await tester.pumpAndSettle();
    expect(c.desks, [null]);
    expect(find.text('Desk runs on'), findsNothing);
  });

  testWidgets('picking a work model sets only the agent profile',
      (tester) async {
    final c = _ModelClient();
    await _pump(tester, c, _agent());
    await tester.tap(find.text('claude'));
    await tester.pumpAndSettle();
    expect(c.profiles, ['claude']);
    expect(c.desks, isEmpty);
  });

  testWidgets('context edit calls the daemon and refuses below 16k',
      (tester) async {
    final c = _ModelClient();
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
