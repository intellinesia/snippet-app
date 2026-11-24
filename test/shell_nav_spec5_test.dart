import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/screens/artifacts_screen.dart';
import 'package:snippet/screens/mobile_home/collapsing_root.dart';
import 'package:snippet/theme.dart';

class _Client extends DaemonClient {
  _Client() : super('http://127.0.0.1:1', 'test');
  @override
  Future<List<Map<String, dynamic>>> getArtifactCards() async => [
        for (var i = 0; i < 30; i++)
          {'id': 'a$i', 'kind': 'document', 'title': 'Doc $i', 'rev': 1}
      ];
}

Widget _wrap(double scale, Widget home) => MaterialApp(
      theme: buildAppTheme(),
      builder: (c, ch) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: ch!),
      home: home,
    );

double _op(WidgetTester t) =>
    t.widget<AnimatedOpacity>(find.byType(AnimatedOpacity).first).opacity;

void main() {
  for (final w in [360.0, 393.0, 430.0]) {
    for (final scale in [1.0, 1.35, 2.0]) {
      testWidgets('artifacts root w=$w s=$scale', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        tester.view.devicePixelRatio = 1;
        tester.view.physicalSize = Size(w, 852);
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
            _wrap(scale, ArtifactsScreen(client: _Client())));
        await tester.pump();
        await tester.pump();
        expect(tester.takeException(), isNull);
        final t = find.text('Artifacts').last;
        final style = tester.widget<Text>(t).style!;
        final pos = tester.getTopLeft(t);
        final plus = tester.getRect(find.bySemanticsLabel('New canvas'));
        // ignore: avoid_print
        print('artifacts w=$w s=$scale size=${style.fontSize} x=${pos.dx} plus=${plus.size}');
        expect(style.fontSize, 28);
        expect(pos.dx, 16);
        expect(plus.width, greaterThanOrEqualTo(48));
        expect(plus.height, greaterThanOrEqualTo(48));
        expect(_op(tester), 0);
        await tester.drag(find.byType(ListView).first, const Offset(0, -200));
        await tester.pumpAndSettle();
        expect(_op(tester), 1);
        await tester.drag(find.byType(ListView).first, const Offset(0, 600));
        await tester.pumpAndSettle();
        expect(_op(tester), 0);
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }

  // Variants D and E: pushed large title with back row and status line.
  for (final scale in [1.0, 2.0]) {
    testWidgets('large pushed bar collapses and re-expands s=$scale',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(393, 852);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(_wrap(
          scale,
          Scaffold(
            body: CollapsingRoot(
              title: 'Agent',
              leading: const SizedBox(width: 48, height: 48),
              child: ListView(children: [
                const LargeTitle('Agent', tagline: 'Working, 4m'),
                for (var i = 0; i < 40; i++)
                  SizedBox(height: 56, child: Text('row $i')),
              ]),
            ),
          )));
      expect(_op(tester), 0);
      await tester.drag(find.byType(ListView), const Offset(0, -10));
      await tester.pumpAndSettle();
      expect(_op(tester), 0, reason: 'under 24px stays expanded');
      await tester.drag(find.byType(ListView), const Offset(0, -40));
      await tester.pumpAndSettle();
      expect(_op(tester), 1);
      await tester.drag(find.byType(ListView), const Offset(0, 500));
      await tester.pumpAndSettle();
      expect(_op(tester), 0);
    });
  }
}
