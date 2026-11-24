import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/canvas/canvas_client.dart';
import 'package:snippet/canvas/canvas_models.dart';
import 'package:snippet/canvas/canvas_screen.dart';
import 'package:snippet/quiet.dart';
import 'package:snippet/screens/artifact_viewer_controls.dart';
import 'package:snippet/theme.dart';

class _EmptyClient implements CanvasClient {
  @override
  Future<CanvasSnapshot> fetchCanvas() async => const CanvasSnapshot(
        canvasId: 'c',
        rev: 3,
        frames: [
          CanvasFrame(
              id: 'a', title: 'Home', x: 0, y: 0, w: 390, h: 800, rev: 1),
          CanvasFrame(
              id: 'b', title: 'Pricing', x: 500, y: 0, w: 390, h: 800, rev: 1),
        ],
      );
  @override
  Future<Uint8List> fetchThumbPng(String frameId, double scale, {int? rev}) =>
      Future.error('no thumbs in test');
  @override
  Future<List<CanvasElementRect>> fetchLayout(String frameId,
          {int? rev}) async =>
      const [];
  @override
  Future<String?> hitTestRemote(String frameId, double x, double y) async =>
      null;
  @override
  Future<List<CanvasPin>> fetchPins() async => const [];
  @override
  Future<CanvasPin> createPin({
    required String frameId,
    String? elId,
    required double dx,
    required double dy,
    required String text,
  }) =>
      throw UnimplementedError();
  @override
  Future<CanvasPin> patchPin(String pinId, {String? status, String? reply}) =>
      throw UnimplementedError();
  @override
  Future<List<CanvasOpBatch>> fetchOps({int since = 0}) async => const [];
  @override
  Future<int> revertBatch(String batchId) async => 0;
  @override
  Stream<CanvasRevEvent> get revEvents => const Stream.empty();
  @override
  Stream<void> get onReconnected => const Stream.empty();
  @override
  void dispose() {}
}

void main() {
  quietTabBarTest();
  viewerControlTests();
  late SemanticsHandle semantics;

  void done() {
    semantics.dispose();
    debugDefaultTargetPlatformOverride = null;
  }

  Future<void> pumpAt(WidgetTester tester, double width) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(1400, 900);
    addTearDown(tester.view.reset);
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    semantics = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: width,
          height: 700,
          child: CanvasScreen(client: _EmptyClient(), onClose: () {}),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
  }

  for (final w in [320.0, 560.0, 1100.0]) {
    testWidgets('canvas lays out without overflow at pane width $w',
        (tester) async {
      await pumpAt(tester, w);
      expect(tester.takeException(), isNull);
      final strip = find.bySemanticsLabel('Show outline');
      final search = find.text('Find a frame or element');
      if (w < 900) {
        expect(search, findsNothing);
        if (w >= 560) expect(strip, findsOneWidget);
      } else {
        expect(search, findsOneWidget);
      }
      // The toolbar is never wider than the pane.
      final fit = find.bySemanticsLabel('Fit');
      final more = find.bySemanticsLabel('More canvas actions');
      expect(fit.evaluate().isNotEmpty || more.evaluate().isNotEmpty, isTrue);
      for (final e in fit.evaluate()) {
        final r = tester.getRect(find.byWidget(e.widget));
        expect(r.right, lessThanOrEqualTo(w + 0.5));
      }
      done();
    });
  }

  testWidgets('outline strip opens the rail as an overlay in a narrow pane',
      (tester) async {
    await pumpAt(tester, 600);
    await tester.tap(find.bySemanticsLabel('Show outline'));
    await tester.pump();
    expect(find.text('Find a frame or element'), findsOneWidget);
    await tester.tap(find.bySemanticsLabel('Hide outline'));
    await tester.pump();
    expect(find.text('Find a frame or element'), findsNothing);
    expect(tester.takeException(), isNull);
    done();
  });
}

void quietTabBarTest() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('phone tab bar stays a bar at ${scale}x text', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(393, 852);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: child!,
        ),
        home: Scaffold(
          body: const SizedBox.expand(),
          bottomNavigationBar: QuietTabBar(
              selected: QuietPlace.agents, onSelect: (_) {}, onNew: () {}),
        ),
      ));
      await tester.pump();
      expect(tester.takeException(), isNull);
      final h = tester.getSize(find.byType(QuietTabBar)).height;
      // ignore: avoid_print
      print('TABBAR scale=$scale height=$h');
      expect(h, lessThan(120));
    });
  }
}

void viewerControlTests() {
  for (final phone in [false, true]) {
    testWidgets(
        'viewer controls measure at least the target size '
        '(${phone ? 'phone 48' : 'desktop 44'})', (tester) async {
      debugDefaultTargetPlatformOverride =
          phone ? TargetPlatform.android : TargetPlatform.linux;
      final want = phone ? 48.0 : 44.0;
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme().copyWith(visualDensity: VisualDensity.compact),
        home: Scaffold(
          body: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            ArtifactSourceToggle(source: false, onChanged: (_) {}),
            ArtifactVersionLine(text: 'Version 2', multi: true, onTap: () {}),
            ArtifactActionButton(label: 'Open in browser', onPressed: () {}),
          ]),
        ),
      ));
      final sizes = {
        'Preview': tester.getSize(find
            .ancestor(of: find.text('Preview'), matching: find.byType(SizedBox))
            .first),
        'Source': tester.getSize(find
            .ancestor(of: find.text('Source'), matching: find.byType(SizedBox))
            .first),
        'Version': tester.getSize(find.byType(ArtifactVersionLine)),
        'Open in browser': tester.getSize(find.byType(TextButton)),
      };
      // ignore: avoid_print
      print('VIEWER ${phone ? 'phone' : 'desktop'} $sizes');
      for (final e in sizes.entries) {
        expect(e.value.height, greaterThanOrEqualTo(want), reason: e.key);
      }
      expect(sizes['Open in browser']!.width, greaterThanOrEqualTo(want));
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
