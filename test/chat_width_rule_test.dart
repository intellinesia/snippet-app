import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/chat/chat_style.dart';
import 'package:snippet/theme.dart';

// Spec C section G plus v19 D1: user bubble keeps the 0.79 W cap; agent
// prose has no bubble, while cards still take the full column.
void main() {
  for (final vw in [360.0, 393.0, 430.0]) {
    for (final scale in [1.0, 1.35, 2.0]) {
      testWidgets('user bubble cap and full-width cards at $vw x$scale', (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = Size(vw, 852);
        addTearDown(t.view.reset);
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        Widget row(String k, bool mine, bool fill) => ChatBubbleRow(
              key: Key(k),
              mine: mine,
              fill: fill,
              child: fill
                  ? Container(height: 40, color: Colors.red)
                  : ChatBubble(mine: mine, child: SizedBox(width: 1000, height: 40)),
            );
        await t.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          builder: (c, w) => MediaQuery(
              data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
              child: w!),
          home: Scaffold(
              body: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: SingleChildScrollView(child: Column(children: [
              row('u', true, false),
              row('c', false, true),
            ])),
          )),
        ));
        final w = vw - 32;
        Rect of(String k, Type ty) => t.getRect(find
            .descendant(of: find.byKey(Key(k)), matching: find.byType(ty))
            .first);
        final u = of('u', ChatBubble);
        final c = of('c', Container);
        // ignore: avoid_print
        print('W $vw x$scale user=${u.width.toStringAsFixed(1)} right=${u.right} '
            'card=${c.width} cardL=${c.left}');
        expect(u.right, vw - 16);
        expect(u.width, closeTo(w * 0.79, 0.5));
        expect(find.byType(ChatBubble), findsOneWidget);
        expect(c.left, 16);
        expect(c.right, vw - 16);
        expect(t.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }
}
