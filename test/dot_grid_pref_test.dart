import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/screens/mobile_session_home.dart';

void main() {
  testWidgets('the dot grid follows its saved toggle', (tester) async {
    SharedPreferences.setMockInitialValues({'phone_dot_grid': false});
    await DotGridPref.instance.init();
    await tester.pumpWidget(const Directionality(
        textDirection: TextDirection.ltr,
        child: DotField(child: SizedBox.expand())));
    Finder grid() => find.descendant(
        of: find.byType(DotField), matching: find.byType(CustomPaint));
    expect(grid(), findsNothing);
    await DotGridPref.instance.set(true);
    await tester.pump();
    expect(grid(), findsOneWidget);
    expect((await SharedPreferences.getInstance()).getBool('phone_dot_grid'),
        isTrue);
  });
}
