import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/composer/cold_strip.dart';
import 'package:snippet/transcript.dart';

Widget _tab(String mode, void Function(String) onPick,
        {int? tokens = 152000}) =>
    MaterialApp(
      home: Scaffold(
        body: Center(
          child: SizedBox(
            width: 360,
            child: ColdTab(
                mode: mode, resumeTokens: tokens, onPick: onPick),
          ),
        ),
      ),
    );

void main() {
  testWidgets('ask mode offers lean and full and reports picks',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final picks = <String>[];
    await tester.pumpWidget(_tab('ask', picks.add));
    expect(find.textContaining('Cold · ~152k to re-read'), findsOneWidget);
    expect(find.text('Lean'), findsOneWidget);
    expect(find.text('Full'), findsOneWidget);
    final size = tester.getSize(find.byType(ColdTab));
    expect(size.width, lessThanOrEqualTo(360));
    expect(size.height, lessThanOrEqualTo(32));
    await tester.tap(find.text('Lean'));
    await tester.tap(find.text('Full'));
    expect(picks, ['lean', 'full']);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('lean mode shows the persisted mode and a change menu',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final picks = <String>[];
    await tester.pumpWidget(_tab('lean', picks.add));
    expect(find.text('Cold · resumes lean'), findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
    await tester.tap(find.text('Change'));
    await tester.pumpAndSettle();
    expect(find.text('Ask'), findsOneWidget);
    expect(find.text('Lean'), findsOneWidget);
    expect(find.text('Full'), findsOneWidget);
    await tester.tap(find.text('Full'));
    await tester.pumpAndSettle();
    expect(picks, ['full']);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('full mode shows the token count', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    await tester.pumpWidget(_tab('full', (_) {}));
    expect(find.textContaining('Cold · resumes full · ~152k'),
        findsOneWidget);
    expect(find.text('Change'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('lean continuation shows a divider', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SystemRow(step: 'continued_lean', reasoning: '')),
    ));
    expect(find.textContaining('Continued lean'), findsOneWidget);
  });
}
