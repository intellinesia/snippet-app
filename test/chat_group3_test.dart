import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/chat/chat_card.dart';
import 'package:snippet/media_views.dart';
import 'package:snippet/theme.dart';

// Spec C CH-16 PDF chip (48 high, at most 280), CH-05 pending tint card at W.
void main() {
  for (final vw in [360.0, 393.0, 430.0]) {
    for (final scale in [1.0, 1.35, 2.0]) {
      testWidgets('pdf chip and approval card at $vw x$scale', (t) async {
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
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                const FileChip(path: '/tmp/report.pdf'),
                const SizedBox(height: 8),
                ChatCard(fill: AppColors.surface2, children: const [
                  NeedsYouRow(trailing: 'Sashy - 12:41'),
                  SizedBox(height: 12),
                ]),
              ]),
            ),
          ),
        ));
        final chip = t.getRect(find.byType(FileChip));
        final card = t.getRect(find.byType(ChatCard));
        // ignore: avoid_print
        print('W $vw x$scale chip=${chip.width}x${chip.height} card=${card.width}');
        expect(chip.height, greaterThanOrEqualTo(48));
        expect(chip.width, lessThanOrEqualTo(280));
        expect(card.width, vw - 32);
        expect(find.text('Needs you'), findsOneWidget);
        expect(t.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }
}
