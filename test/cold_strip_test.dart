import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/composer/cold_strip.dart';
import 'package:snippet/transcript.dart';

void main() {
  testWidgets('cold strip offers lean and full', (tester) async {
    var lean = 0, full = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ColdStrip(
            resumeTokens: 152000, onLean: () => lean++, onFull: () => full++),
      ),
    ));
    expect(find.text('Cold'), findsOneWidget);
    expect(find.textContaining('~152k tokens'), findsOneWidget);
    await tester.tap(find.text('Lean'));
    await tester.tap(find.text('Full'));
    expect((lean, full), (1, 1));
  });

  testWidgets('lean continuation shows a divider', (tester) async {
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(body: SystemRow(step: 'continued_lean', reasoning: '')),
    ));
    expect(find.textContaining('Continued lean'), findsOneWidget);
  });
}
