import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/canvas/canvas_screen.dart';
import 'package:snippet/screens/artifact_viewer.dart';
import 'package:snippet/screens/artifacts_screen.dart';
import 'package:snippet/screens/mobile_home/quiet_home.dart';
import 'package:snippet/theme.dart';

import 'canvas_layout_test.dart' show EmptyCanvasClient;

class _Daemon extends DaemonClient {
  _Daemon() : super('http://127.0.0.1:9', 'tok');
  @override
  Future<List<Map<String, dynamic>>> getArtifactCards() async => [
        {'id': 'c1', 'kind': 'canvas', 'title': 'Pricing board'},
      ];
}

void main() {
  for (final phone in [true, false]) {
    final want = phone ? 48.0 : 44.0;
    final tag = phone ? 'phone' : 'desktop';
    Future<void> setUpEnv(WidgetTester t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = phone ? const Size(393, 852) : const Size(1400, 900);
      addTearDown(t.view.reset);
      debugDefaultTargetPlatformOverride =
          phone ? TargetPlatform.android : TargetPlatform.linux;
    }

    testWidgets('artifacts chips and New canvas measure $want ($tag)',
        (tester) async {
      await setUpEnv(tester);
      await tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(body: ArtifactsScreen(client: _Daemon()))));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final chip = tester.getSize(find
          .ancestor(of: find.text('All'), matching: find.byType(Container))
          .first);
      final fresh = tester.getSize(find.ancestor(
          of: find.text('New canvas'), matching: find.byType(SizedBox)).first);
      // ignore: avoid_print
      print('ARTIFACTS $tag chip=$chip newCanvas=$fresh');
      expect(chip.height, want);
      expect(fresh.height, want);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('viewer More and Close measure $want ($tag)', (tester) async {
      await setUpEnv(tester);
      await tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
              body: ArtifactViewer(
                  client: _Daemon(), session: 's', id: 'a', onClose: () {}))));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      if (phone) {
        for (final tip in ['More', 'Close']) {
          final s = tester.getSize(find.byTooltip(tip));
          // ignore: avoid_print
          print('VIEWER phone $tip=$s');
          expect(s.width, greaterThanOrEqualTo(want));
          expect(s.height, greaterThanOrEqualTo(want));
        }
      }
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('canvas pills and toolbar measure $want ($tag)',
        (tester) async {
      await setUpEnv(tester);
      await tester.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          home: CanvasScreen(
              client: EmptyCanvasClient(),
              title: 'Pricing board',
              onClose: () {})));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      final sizes = <String, Size>{};
      for (final l in ['Fit', 'Steps', 'Share', 'Select']) {
        for (final e in find.bySemanticsLabel(l).evaluate()) {
          sizes['toolbar $l'] = tester.getSize(find.byWidget(e.widget));
        }
      }
      for (final e in find.byType(Tooltip).evaluate()) {
        final m = (e.widget as Tooltip).message ?? '';
        if (m.startsWith('Pins,') ||
            m.startsWith('Back from canvas') ||
            m.startsWith('Steps history')) {
          sizes['pill ${m.split(',').first}'] =
              tester.getSize(find.byWidget(e.widget));
        }
      }
      final more = find.byTooltip('More');
      if (more.evaluate().isNotEmpty) sizes['more'] = tester.getSize(more);
      // ignore: avoid_print
      print('CANVAS $tag $sizes');
      expect(sizes.keys.where((k) => k.startsWith('pill')), isNotEmpty);
      for (final e in sizes.entries) {
        expect(e.value.height, greaterThanOrEqualTo(want), reason: e.key);
      }
      if (phone) {
        expect(find.text('Pricing board'), findsOneWidget);
        expect(find.textContaining('Canvas  r'), findsNothing);
        expect(find.text('r3'), findsOneWidget);
      }
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('home header icons and trailing do not overlap', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(393, 852);
    addTearDown(tester.view.reset);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
            body: QuietPlaceHeader(
                title: 'Agents',
                onNewMenu: (_) {},
                onSearch: () {},
                onSettings: () {},
                trailing: const Text('3h')))));
    final rects = [
      for (final l in ['New', 'Search', 'Settings'])
        tester.getRect(find.bySemanticsLabel(l)),
      tester.getRect(find.text('3h')),
    ];
    for (var i = 0; i < rects.length; i++) {
      for (var j = i + 1; j < rects.length; j++) {
        expect(rects[i].overlaps(rects[j]), isFalse, reason: '$i vs $j');
      }
    }
    debugDefaultTargetPlatformOverride = null;
  });
}
