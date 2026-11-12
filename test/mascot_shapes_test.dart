import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/mochi.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/agent_appearance.dart';
import 'package:snippet/theme.dart';

class _AppearanceClient extends DaemonClient {
  _AppearanceClient() : super('https://daemon.invalid', 'test-token');
  final shapes = <String?>[];
  final colors = <String?>[];

  @override
  Future<void> setAgentShape(String agentId, String? shape) async =>
      shapes.add(shape);

  @override
  Future<void> setAgentColor(String agentId, String? color) async =>
      colors.add(color);
}

void main() {
  test('shape names map to shapes and fall back to mochi', () {
    expect(mascotShapeNamed('bunny'), MascotShape.bunny);
    expect(mascotShapeNamed('onigiri'), MascotShape.onigiri);
    expect(mascotShapeNamed('nope'), MascotShape.mochi);
    expect(mascotShapeNamed(null), MascotShape.mochi);
  });

  test('agents carry their shape and the remembered map drives the mascot', () {
    final a = CoordinationAgent.fromJson({'id': 'ada', 'shape': 'cat'});
    expect(a.shape, 'cat');
    rememberAgentShapes([('ada', a.shape)]);
    expect(mascotShapeFor('ada'), MascotShape.cat);
    setRememberedAgentShape('ada', null);
    expect(mascotShapeFor('ada'), MascotShape.mochi);
    rememberAgentShapes(const []);
  });

  testWidgets(
      'appearance panel renders both Avatar and Colour sections and Done closes it',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    rememberAgentShapes(const []);
    rememberAgentColors(const []);
    addTearDown(() {
      rememberAgentShapes(const []);
      rememberAgentColors(const []);
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final client = _AppearanceClient();
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Builder(
          builder: (ctx) => TextButton(
            onPressed: () =>
                showAgentAppearance(ctx, client, 'ada', 'Ada'),
            child: const Text('Open'),
          ),
        ),
      ),
    ));

    await tester.tap(find.text('Open'));
    await tester.pumpAndSettle();

    expect(find.text('Ada appearance'), findsOneWidget);
    expect(find.text('AVATAR'), findsOneWidget);
    expect(find.text('COLOUR'), findsOneWidget);

    await tester.tap(find.byTooltip('Cat'));
    await tester.pumpAndSettle();
    expect(client.shapes, ['cat']);
    expect(find.byType(AgentAppearancePicker), findsOneWidget);

    await tester.tap(find.byTooltip(mochiPalette.first.$1));
    await tester.pumpAndSettle();
    expect(client.colors, hasLength(1));
    expect(find.byType(AgentAppearancePicker), findsOneWidget);

    await tester.tap(find.text('Done'));
    await tester.pumpAndSettle();
    expect(find.byType(AgentAppearancePicker), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
