import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/mochi.dart';
import 'package:snippet/screens/agent_appearance.dart';
import 'package:snippet/screens/create_agent_form.dart';
import 'package:snippet/theme.dart';

class _Client extends DaemonClient {
  _Client() : super('https://daemon.invalid', 'test-token');

  String? prompt;
  String? nick;
  String? built;
  final saved = <String?>[];
  bool failSave = false;

  @override
  Future<void> buildCoordinationAgent(String prompt,
      {String? nickname, String? character}) async {
    this.prompt = prompt;
    nick = nickname;
    built = character;
  }

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => const [];

  @override
  Future<void> setAgentCharacter(String agentId, String? character) async {
    if (failSave) throw Exception('nope');
    saved.add(character);
    setRememberedAgentCharacter(agentId, character);
  }
}

void main() {
  setUp(() {
    rememberAgentCharacters(const []);
    addTearDown(() => rememberAgentCharacters(const []));
  });

  void desktopTest(String name, Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
      try {
        await body(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  Future<void> pumpForm(WidgetTester tester, _Client c) async {
    tester.view.physicalSize = const Size(600, 1000);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await CharacterRoster.load();
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
          body: SingleChildScrollView(
              child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: CreateAgentForm(client: c)))),
    ));
    await tester.pump(const Duration(milliseconds: 100));
  }

  String stageId(WidgetTester tester) => tester
      .widget<AgentCharacter>(find.byKey(const ValueKey('agent-stage')))
      .characterId;

  desktopTest('picking a character changes the stage', (tester) async {
    await pumpForm(tester, _Client());
    expect(stageId(tester), '01');
    await tester.tap(find.byKey(const ValueKey('character-03')));
    await tester.pump();
    expect(stageId(tester), '03');
  });

  desktopTest('button label follows the name and create sends character',
      (tester) async {
    final c = _Client();
    await pumpForm(tester, c);
    expect(find.text('Build agent'), findsOneWidget);
    await tester.enterText(find.byType(TextField).last, 'Juno');
    await tester.pump();
    expect(find.text('Build Juno'), findsOneWidget);
    expect(find.text('Build agent'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('character-04')));
    await tester.enterText(find.byType(TextField).first,
        'A code reviewer that reads pull requests.');
    await tester.tap(find.text('Build Juno'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.built, '04');
    expect(c.nick, 'Juno');
    expect(c.prompt, 'A code reviewer that reads pull requests.');
  });

  desktopTest('the Appearance grid saves the character and updates it',
      (tester) async {
    final c = _Client();
    tester.view.physicalSize = const Size(600, 1400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await CharacterRoster.load();
    rememberAgentCharacters(const [('rook', '02')]);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
          body: SingleChildScrollView(
              child: AgentAppearancePicker(
                  client: c, agentId: 'rook', onDone: () {}))),
    ));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.byTooltip('Character 07'));
    await tester.pump();
    expect(c.saved, ['07']);
    expect(agentCharacterFor('rook'), '07');

    c.failSave = true;
    await tester.tap(find.byTooltip('Character 09'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(agentCharacterFor('rook'), '07');
    await tester.pump(const Duration(seconds: 4));

    c.failSave = false;
    await tester.tap(find.text('Use default'));
    await tester.pump(const Duration(milliseconds: 100));
    expect(c.saved.last, isNull);
    expect(agentCharacterFor('rook'), isNull);
    expect(find.text('Avatar'), findsNothing);
    expect(find.text('Colour'), findsNothing);
  });
}
