import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/chat/phone_ledger.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/tool_activity.dart';

// Spec C CH-18: ledger card at W, header 48, rows 36, collapsible.
void main() {
  final steps = [
    ToolStep(tool: 'bash', args: {'command': 'flutter test'}, result: {'data': {'exit_code': 0}}),
  ];
  for (final vw in [360.0, 393.0, 430.0]) {
    for (final scale in [1.0, 1.35, 2.0]) {
      testWidgets('ledger at $vw x$scale', (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = Size(vw, 852);
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        addTearDown(t.view.reset);
        await t.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          builder: (c, w) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: w!),
          home: Scaffold(body: PhoneLedgerCard(steps: steps)),
        ));
        final card = t.getRect(find.byType(PhoneLedgerCard));
        // ignore: avoid_print
        print('W $vw x$scale ledger=${card.width}x${card.height}');
        expect(card.width, vw);
        expect(find.text('Ledger  1 action'), findsOneWidget);
        await t.tap(find.text('Ledger  1 action'));
        await t.pump();
        expect(find.text('Ran'), findsNothing);
        expect(t.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }
}
