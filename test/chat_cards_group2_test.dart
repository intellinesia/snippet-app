import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/chat/draft_sink.dart';
import 'package:snippet/media_views.dart';
import 'package:snippet/theme.dart';

// Spec C CH-20: Use draft and Dismiss 48 high at 225:100, pasted card full W.
void main() {
  for (final vw in [360.0, 393.0, 430.0]) {
    for (final scale in [1.0, 1.35, 2.0]) {
      testWidgets('draft actions and pasted card at $vw x$scale', (t) async {
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
            body: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(children: [
                DraftActions(onUse: () {}, onDismiss: () {}),
                const SizedBox(height: 8),
                PastedTextCard(text: List.filled(40, 'line of text').join('\n')),
              ]),
            ),
          ),
        ));
        Rect btn(String l) => t.getRect(find
            .ancestor(of: find.text(l), matching: find.byType(Material))
            .first);
        final use = btn('Use draft');
        final dis = btn('Dismiss');
        final card = t.getRect(find.byType(PastedTextCard));
        // ignore: avoid_print
        print('W $vw x$scale use=${use.width.toStringAsFixed(1)}x${use.height} '
            'dismiss=${dis.width.toStringAsFixed(1)}x${dis.height} paste=${card.width}');
        expect(use.height, greaterThanOrEqualTo(48));
        if (scale == 1.0) expect(use.height, 48);
        expect(dis.height, greaterThanOrEqualTo(48));
        expect(use.width / dis.width, closeTo(2.25, 0.01));
        expect(card.width, vw - 32);
        expect(t.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }
}
