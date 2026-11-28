import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/toast_avoid.dart';

// Regression: the home header stayed registered under a pushed chat page, so
// phone banners floated ~200px down over the transcript.
void main() {
  testWidgets('a bar under a pushed page stops counting', (t) async {
    ToastBands.reset();
    final nav = GlobalKey<NavigatorState>();
    await t.pumpWidget(MaterialApp(
      navigatorKey: nav,
      home: Scaffold(
        body: Column(children: [
          const SizedBox(height: 40),
          ToastAvoid(child: Container(height: 150, color: Colors.black)),
        ]),
      ),
    ));
    await t.pump();
    expect(ToastBands.bottom.value, 190);

    nav.currentState!.push(MaterialPageRoute<void>(
        builder: (_) => const Scaffold(body: SizedBox.expand())));
    await t.pumpAndSettle();
    expect(ToastBands.bottom.value, 0);

    nav.currentState!.pop();
    await t.pumpAndSettle();
    expect(ToastBands.bottom.value, 190);
  });
}
