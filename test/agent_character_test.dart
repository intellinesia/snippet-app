
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/ambient_loop.dart';
import 'package:snippet/mochi.dart';
import 'package:snippet/models.dart';
import 'package:snippet/theme.dart';

void main() {
  setUp(() {
    rememberAgentCharacters(const []);
  });

  tearDown(() {
    rememberAgentCharacters(const []);
  });

  test('roster loads all 36 characters and eye styles as WebP assets',
      () async {
    final roster = await CharacterRoster.load();
    expect(roster.characters.length, 36);
    expect(roster.eyeStyles.keys, containsAll(['glossy-black', 'white-pill']));
    final c04 = roster.character('04')!;
    expect(c04.over, isNotNull);
    expect(CharacterRoster.plateAsset('04', c04.body256),
        'assets/avatars/04/body-256.webp');
    expect(CharacterRoster.plateAsset('04', c04.over!),
        'assets/avatars/04/over-512.webp');
    expect(CharacterRoster.eyeAsset(roster.eyeStyle('glossy-black')!.files['open']!),
        'assets/avatars/eyes/glossy-black-open.webp');
  });

  test('pose math animates working, waiting and needs, and stays static under reduced motion',
      () {
    final workingMid =
        AgentCharacter.poseForState(AgentCharacterState.working, 100, 0.45);
    expect(workingMid.bodyDy, lessThan(0));
    expect(workingMid.shadowScale, lessThan(1.0));
    expect(workingMid.shadowOpacity, lessThan(1.0));

    final waitingBlink =
        AgentCharacter.poseForState(AgentCharacterState.waiting, 100, 3.85);
    expect(waitingBlink.blinkClosedOpacity, equals(1.0));

    final waitingGlance =
        AgentCharacter.poseForState(AgentCharacterState.waiting, 100, 2.4);
    expect(waitingGlance.glanceX, greaterThan(0));

    final donePose =
        AgentCharacter.poseForState(AgentCharacterState.done, 100, 1.0);
    expect(donePose.eyeState, 'happy');
    expect(donePose.bodyDy, 0);

    final needsPerk =
        AgentCharacter.poseForState(AgentCharacterState.needs, 100, 2.68);
    expect(needsPerk.eyeState, 'wide');
    expect(needsPerk.bodyDy, lessThan(0));

    final reducedWorking = AgentCharacter.poseForState(
      AgentCharacterState.working,
      100,
      0.45,
      reducedMotion: true,
    );
    expect(reducedWorking.bodyDy, 0);
    expect(reducedWorking.shadowScale, 1.0);
    expect(reducedWorking.glanceX, 0);
    expect(reducedWorking.eyeState, 'open');
  });

  testWidgets(
      'AgentCharacter renders every state, layers shadow/body/eyes/over, picks 256 vs 512 and shares one ticker',
      (tester) async {
    await CharacterRoster.load();

    // 1x DPR at size 60 -> 256 plate; size 200 at 2x DPR -> 512 plate.
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    for (final state in AgentCharacterState.values) {
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Center(
            child: AgentCharacter('04', size: 60, state: state, staggerKey: 'a'),
          ),
        ),
      ));
      await tester.pump();
      final images = tester
          .widgetList<Image>(find.byType(Image))
          .map((img) => (img.image as AssetImage).assetName)
          .toList();
      expect(images, contains('assets/avatars/04/shadow-256.webp'));
      expect(images, contains('assets/avatars/04/body-256.webp'));
      expect(images, contains('assets/avatars/04/over-256.webp'));
      final expectedEye = switch (state) {
        AgentCharacterState.done => 'assets/avatars/eyes/glossy-black-happy.webp',
        AgentCharacterState.needs => 'assets/avatars/eyes/glossy-black-wide.webp',
        AgentCharacterState.sleeping => 'assets/avatars/eyes/glossy-black-closed.webp',
        _ => 'assets/avatars/eyes/glossy-black-open.webp',
      };
      expect(images, contains(expectedEye));
      final expectsClock = state == AgentCharacterState.working ||
          state == AgentCharacterState.waiting ||
          state == AgentCharacterState.needs ||
          state == AgentCharacterState.sleeping;
      expect(AmbientClock.instance.isRunning, expectsClock,
          reason: 'state=$state');
    }

    // High-DPI large render switches to 512 plates.
    tester.view.devicePixelRatio = 2.0;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: const Scaffold(
        body: Center(
          child: AgentCharacter('01',
              size: 160, state: AgentCharacterState.working, staggerKey: 'rook'),
        ),
      ),
    ));
    await tester.pump();
    final hiImages = tester
        .widgetList<Image>(find.byType(Image))
        .map((img) => (img.image as AssetImage).assetName)
        .toList();
    expect(hiImages, contains('assets/avatars/01/shadow-512.webp'));
    expect(hiImages, contains('assets/avatars/01/body-512.webp'));
    expect(AmbientClock.instance.isRunning, isTrue);

    // Offstage / TickerMode disabled stops listening to AmbientClock.
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: const Scaffold(
        body: TickerMode(
          enabled: false,
          child: AgentCharacter('01',
              size: 160, state: AgentCharacterState.working, staggerKey: 'rook'),
        ),
      ),
    ));
    await tester.pump();
    expect(AmbientClock.instance.isRunning, isFalse);

    // Unmount cleanly stops clock.
    await tester.pumpWidget(const SizedBox.shrink());
    expect(AmbientClock.instance.isRunning, isFalse);
  });

  testWidgets('AgentCharacter stays static under reduced motion',
      (tester) async {
    await CharacterRoster.load();

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: const MediaQuery(
        data: MediaQueryData(disableAnimations: true),
        child: Scaffold(
          body: Row(children: [
            AgentCharacter('01',
                size: 64, state: AgentCharacterState.working, staggerKey: 'r'),
            AgentCharacter('02',
                size: 64, state: AgentCharacterState.waiting, staggerKey: 'p'),
            AgentCharacter('04',
                size: 64, state: AgentCharacterState.needs, staggerKey: 'm'),
          ]),
        ),
      ),
    ));
    await tester.pump();
    expect(AmbientClock.instance.isRunning, isFalse);

    // Zero-duration pump advances clock only if something schedules frames;
    // transforms remain at rest (no vertical hop or glance offset).
    await tester.pump(const Duration(milliseconds: 500));
    expect(AmbientClock.instance.isRunning, isFalse);
    for (final t in tester.widgetList<Transform>(find.byType(Transform))) {
      expect(t.transform.getTranslation().x, 0);
      expect(t.transform.getTranslation().y, 0);
    }
  });

  testWidgets(
      'AgentMochi renders the stored character, else the daemon default',
      (tester) async {
    await CharacterRoster.load();

    final withChar = CoordinationAgent.fromJson({
      'id': 'rook',
      'display_name': 'Rook',
      'handle': 'rook',
      'character': '01',
    });
    final legacy = CoordinationAgent.fromJson({
      'id': 'ada',
      'display_name': 'Ada',
      'handle': 'ada',
    });
    expect(withChar.character, '01');
    expect(legacy.character, isNull);

    rememberAgentCharacters([(withChar.id, withChar.character), (legacy.id, legacy.character)]);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: const Scaffold(
        body: Row(children: [
          AgentMochi('rook', size: 48),
          AgentMochi('ada', size: 48),
        ]),
      ),
    ));
    await tester.pump();

    final shown = tester
        .widgetList<AgentCharacter>(find.byType(AgentCharacter))
        .map((c) => c.characterId)
        .toList();
    expect(shown, ['01', '34']);
  });

  test('default characters match the daemon hash and skip 01 and 14', () {
    expect(defaultAgentCharacter('snippet'), '01');
    expect(defaultAgentCharacter('mission-control'), '14');
    expect(defaultAgentCharacter('deep-researcher'), '17');
    expect(defaultAgentCharacter('rook'), '29');
    for (var i = 0; i < 200; i++) {
      final c = defaultAgentCharacter('agent-$i');
      expect(c == '01' || c == '14', isFalse, reason: 'agent-$i got $c');
    }
  });

}
