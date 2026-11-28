import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/composer/cold_strip.dart';
import 'package:snippet/theme.dart';

void main() {
  // The phone offered only Resume lean, with no way to change the mode.
  testWidgets('phone cold notice offers every resume mode', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(393, 852);
    addTearDown(t.view.reset);
    final picks = <String>[];
    await t.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
            body: Align(
                alignment: Alignment.bottomCenter,
                child: ColdTab(
                    mode: 'ask', resumeTokens: 147000, onPick: picks.add)))));
    await t.tap(find.byKey(const ValueKey('cold-resume')));
    await t.pumpAndSettle();
    expect(find.text('Lean'), findsOneWidget);
    expect(find.text('Full · ~147k'), findsOneWidget);
    expect(find.text('Ask each time'), findsOneWidget);
    await t.tap(find.text('Full · ~147k'));
    await t.pumpAndSettle();
    expect(picks, ['full']);
    debugDefaultTargetPlatformOverride = null;
  });
}
