import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/chat/chat_card.dart';
import 'package:snippet/theme.dart';

// Spec C CH-13, CH-04 card shell: full width, plan steps at 44, track 4 high.
void main() {
  for (final vw in [360.0, 393.0, 430.0]) {
    for (final scale in [1.0, 1.35, 2.0]) {
      testWidgets('plan and chat card at $vw x$scale', (t) async {
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
          home: Scaffold(
            body: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(children: [
                const ChatCard(children: [
                  ChatCardHeader(title: 'Title', subtitle: 'sub'),
                ]),
              ]),
            ),
          ),
        ));
        final w = vw - 32;
        final card = t.getRect(find.byType(ChatCard));
        // ignore: avoid_print
        print('W $vw x$scale card=${card.width} left=${card.left}');
        expect(card.width, w);
        expect(t.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }
}
