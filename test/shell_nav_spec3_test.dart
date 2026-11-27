import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/screens/mobile_home/collapsing_root.dart';
import 'package:snippet/theme.dart';

void main() {
  for (final w in [360.0, 393.0, 430.0]) {
    for (final scale in [1.0, 1.35, 2.0]) {
      testWidgets('collapsing root w=$w s=$scale', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(w, 852);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          builder: (c, ch) => MediaQuery(
              data: MediaQuery.of(c)
                  .copyWith(textScaler: TextScaler.linear(scale)),
              child: ch!),
          home: Scaffold(
            body: CollapsingRoot(
              title: 'Sessions',
              actions: const [SizedBox(width: 48, height: 48)],
              child: ListView(children: [
                const LargeTitle('Sessions'),
                for (var i = 0; i < 40; i++) SizedBox(height: 56, child: Text('row $i')),
              ]),
            ),
          ),
        ));
        expect(tester.takeException(), isNull);
        final big = find.text('Sessions').last;
        final style = tester.widget<Text>(big).style!;
        final pos = tester.getTopLeft(big);
        double inlineOpacity() => tester
            .widget<AnimatedOpacity>(find.byType(AnimatedOpacity))
            .opacity;
        final bar = tester.getRect(find.byType(AnimatedContainer));
        // ignore: avoid_print
        print('w=$w s=$scale titleSize=${style.fontSize} x=${pos.dx} bar=${bar.size} op0=${inlineOpacity()}');
        expect(style.fontSize, 34);
        expect(pos.dx, 20);
        expect(bar.height, greaterThanOrEqualTo(52));
        expect(inlineOpacity(), 0);
        await tester.drag(find.byType(ListView), const Offset(0, -30));
        await tester.pumpAndSettle();
        expect(inlineOpacity(), 1);
        final deco = tester.widget<AnimatedContainer>(find.byType(AnimatedContainer)).decoration as BoxDecoration;
        expect(deco.color, AppColors.surface1);
        expect((deco.border as Border).bottom.width, greaterThan(0));
        await tester.drag(find.byType(ListView), const Offset(0, 300));
        await tester.pumpAndSettle();
        expect(inlineOpacity(), 0);
      });
    }
  }
}
