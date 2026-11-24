import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/quiet.dart';
import 'package:snippet/screens/new_menu.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/widgets.dart';

Widget _wrap(double scale, Widget child) => MaterialApp(
      theme: buildAppTheme(),
      builder: (c, ch) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: ch!,
      ),
      home: child,
    );

void main() {
  for (final w in [360.0, 393.0, 430.0]) {
    for (final scale in [1.0, 1.35, 2.0]) {
      testWidgets('tab bar w=$w scale=$scale', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(w, 852);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(_wrap(
            scale,
            Scaffold(
              bottomNavigationBar: QuietTabBar(
                  selected: QuietPlace.agents,
                  onSelect: (_) {},
                  onNew: () {}),
            )));
        expect(tester.takeException(), isNull);
        final bar = tester.getRect(find.byType(QuietTabBar));
        final capsule = tester.getRect(find
            .descendant(
                of: find.byType(QuietTabBar), matching: find.byType(Container))
            .first);
        final tabs = [
          for (final l in ['Agents', 'Sessions', 'Artifacts', 'Tasks'])
            tester.getRect(find
                .ancestor(of: find.text(l), matching: find.byType(Container))
                .first)
        ];
        final plus = tester.getRect(find
            .ancestor(
                of: find.byType(AppIcon).last,
                matching: find.byType(Container))
            .first);
        // ignore: avoid_print
        print('w=$w s=$scale bar=$bar capsule=$capsule tab=${tabs.first.size} '
            'plus=${plus.size} plusRight=${capsule.right - plus.right}');
        expect(capsule.left, 12);
        expect(capsule.width, w - 24);
        expect(plus.size, const Size(48, 48));
        for (final t in tabs) {
          expect(t.height, 48);
          expect(t.width, greaterThanOrEqualTo((w - 24 - 16 - 48 - 8) / 4 - 0.1));
        }
        for (var i = 1; i < tabs.length; i++) {
          expect(tabs[i].left, greaterThanOrEqualTo(tabs[i - 1].right - 0.01));
        }
      });
      testWidgets('new sheet w=$w scale=$scale', (tester) async {
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(w, 852);
        addTearDown(tester.view.reset);
        late BuildContext ctx;
        await tester.pumpWidget(_wrap(
            scale,
            Scaffold(body: Builder(builder: (c) {
              ctx = c;
              return const SizedBox();
            }))));
        showNewSheet(ctx,
            onNewSession: () {},
            onNewAgent: () {},
            onNewGroup: () {},
            onNewShell: () {},
            onNewTask: () {});
        await tester.pumpAndSettle();
        expect(tester.takeException(), isNull);
        final labels = ['New session', 'New agent', 'New group', 'New shell', 'New task'];
        final rects = [
          for (final l in labels)
            tester.getRect(find
                .ancestor(of: find.text(l), matching: find.byType(InkWell))
                .first)
        ];
        // ignore: avoid_print
        print('sheet w=$w s=$scale rows=${rects.map((r) => r.size).toList()}');
        for (var i = 0; i < rects.length; i++) {
          expect(rects[i].width, w);
          expect(rects[i].height, greaterThanOrEqualTo(56));
          if (i > 0) expect(rects[i].top, greaterThan(rects[i - 1].top));
        }
        final sheet = tester.getRect(find.byType(BottomSheet));
        // ignore: avoid_print
        print('sheet rect=$sheet');
        expect(sheet.width, w);
        expect(sheet.height, lessThanOrEqualTo(852 * 0.85 + 0.1));
      });
    }
  }
}
