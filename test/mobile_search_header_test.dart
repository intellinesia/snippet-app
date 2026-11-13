import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/screens/mobile_session_home.dart';

void main() {
  testWidgets('voice on rings the Mission Control button instead of a pill',
      (tester) async {
    Future<void> pump(bool listening) => tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: MobileSearchHeader(
              controller: TextEditingController(),
              focusNode: FocusNode(),
              hint: 'Search sessions',
              onChanged: (_) {},
              listening: listening,
              onMc: () {},
            ),
          ),
        ));
    await pump(true);
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byTooltip('Mission Control, voice on'), findsOneWidget);
    expect(find.byType(DecoratedBox), findsWidgets);
    expect(find.text('Listening'), findsNothing);
    expect(find.byTooltip('Start voice'), findsNothing);

    await pump(false);
    await tester.pump();
    expect(find.byTooltip('Mission Control'), findsOneWidget);
  });
}
