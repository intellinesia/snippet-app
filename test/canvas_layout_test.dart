import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/canvas/canvas_client.dart';
import 'package:snippet/canvas/canvas_models.dart';
import 'package:snippet/canvas/canvas_screen.dart';
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
