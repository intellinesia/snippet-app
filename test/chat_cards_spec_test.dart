import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/chat/chat_card.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/turn_changes_card.dart';

// v19 D2/D4: approval actions sit three across in 36-high buttons;
// turn changes is a collapsed 48-high row with no full-width review CTA.
void main() {
  for (final vw in [360.0, 393.0, 430.0]) {
    for (final scale in [1.0, 1.35, 2.0]) {
      testWidgets('approval buttons and changes card at $vw x$scale', (t) async {
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
                ApprovalDecideButtons(
                    onAllowOnce: () {}, onAlways: () {}, onDeny: () {}),
                TurnChangesCard(event: const {
                  'total_files': 7,
                  'add': 212,
                  'del': 48,
                  'files': [
                    {'path': 'lib/a.dart', 'add': 10, 'del': 2},
                    {'path': 'lib/b.dart', 'add': 10, 'del': 2},
                    {'path': 'lib/c.dart', 'add': 10, 'del': 2},
                    {'path': 'lib/d.dart', 'add': 10, 'del': 2},
                  ]
                }, onReview: () {}),
              ]),
            ),
          ),
        ));
        final w = vw - 32;
        final once = t.getRect(find.text('Allow once'));
        final onceBtn = t.getRect(find.ancestor(
            of: find.text('Allow once'), matching: find.byType(Material)).first);
        final always = t.getRect(find.ancestor(
            of: find.text('Always allow'), matching: find.byType(Material)).first);
        final deny = t.getRect(find.ancestor(
            of: find.text('Deny'), matching: find.byType(Material)).first);
        expect(find.text('Review changes'), findsNothing);
        final card = t.getRect(find.byType(TurnChangesCard));
        // ignore: avoid_print
        print('W $vw x$scale allowOnce=$onceBtn always=$always deny=$deny '
            'card=${card.width}');
        expect(onceBtn.top, always.top);
        expect(onceBtn.top, deny.top);
        final buttonWidth = (w - 16) / 3;
        expect(onceBtn.width, closeTo(buttonWidth, 0.1));
        expect(always.width, closeTo(buttonWidth, 0.1));
        expect(deny.width, closeTo(buttonWidth, 0.1));
        expect(onceBtn.height, 36);
        expect(always.height, 36);
        expect(deny.height, 36);
        expect(card.width, w);
        expect(find.text('7 files changed'), findsOneWidget);
        expect(t.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }
}
