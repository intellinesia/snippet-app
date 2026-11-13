import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/screens/mobile_session_home.dart';

void main() {
  testWidgets('the Listening pill opens voice when tapped', (tester) async {
    var taps = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: MobileSearchHeader(
          controller: TextEditingController(),
          focusNode: FocusNode(),
          hint: 'Search sessions',
          onChanged: (_) {},
          listening: true,
          onListening: () => taps++,
        ),
      ),
    ));
    await tester.tap(find.text('Listening'));
    expect(taps, 1);
  });
}
