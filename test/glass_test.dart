import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/glass.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget glass) => tester
      .pumpWidget(MaterialApp(home: Scaffold(body: Center(child: glass))));

  testWidgets('Glass with a radius shows one BackdropFilter', (tester) async {
    await pump(
        tester,
        const Glass(
          radius: BorderRadius.all(Radius.circular(12)),
          child: SizedBox(width: 24, height: 24),
        ));
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('Glass circle shows one BackdropFilter', (tester) async {
    await pump(tester, const Glass(child: SizedBox(width: 24, height: 24)));
    expect(find.byType(BackdropFilter), findsOneWidget);
  });

  testWidgets('Glass.enabled = false shows no BackdropFilter', (tester) async {
    Glass.enabled = false;
    addTearDown(() => Glass.enabled = true);
    await pump(
        tester,
        const Glass(
          radius: BorderRadius.all(Radius.circular(12)),
          child: SizedBox(width: 24, height: 24),
        ));
    expect(find.byType(BackdropFilter), findsNothing);
  });
}
