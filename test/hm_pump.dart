import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/screens/mobile_home/agents_home.dart' show StateChip;
import 'package:snippet/tap_detector.dart';
import 'package:snippet/theme.dart';

const hmWidths = [360.0, 393.0, 430.0];
const hmScales = [1.0, 1.35, 2.0];

Future<void> hmPump(WidgetTester t, Widget child, double w, double scale,
    {double h = 2400}) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = Size(w, h);
  addTearDown(t.view.reset);
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  await t.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    builder: (c, ch) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: ch!),
    home: Scaffold(body: SafeArea(child: child)),
  ));
  await t.pump(const Duration(milliseconds: 100));
}

void hmSpec(String name, Future<void> Function(WidgetTester) body) =>
    testWidgets(name, (t) async {
      try {
        await body(t);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

/// Every tap target is at least [min] high (44 for chips by spec) and nothing threw.
void hmExpectTargets(WidgetTester t, {double min = 48}) {
  expect(t.takeException(), isNull);
  final bad = <String>[];
  for (final e in find.byType(TapDetector).evaluate()) {
    final rb = e.renderObject;
    if (rb is! RenderBox || !rb.hasSize) continue;
    final h = rb.size.height;
    final chip = e.findAncestorWidgetOfExactType<StateChip>() != null;
    if (h < (chip ? 44 : min) - 0.01) bad.add('${rb.size} ${(e.widget as TapDetector).key}');
  }
  expect(bad, isEmpty, reason: 'targets under $min: $bad');
}
