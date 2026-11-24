import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
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
