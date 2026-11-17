import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/plan_card.dart';


Future<void> _shot(WidgetTester t, String name) async {
  const dir = String.fromEnvironment('SHOT_DIR');
  if (dir.isEmpty) return;
  await t.runAsync(() async {
    final b = t.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('shot')));
    final img = await b.toImage();
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Widget _app(Widget child) => MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: RepaintBoundary(
          key: const ValueKey('shot'),
          child: ColoredBox(
            color: AppColors.bg,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 56, 16, 16),
              child: Align(alignment: Alignment.topCenter, child: child),
            ),
          ),
        ),
      ),
    );

void _phone(WidgetTester tester) {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.reset);
}

List<Map> _steps(int done, {bool live = true}) => [
      for (final (i, s) in const [
        'Find where the header reads the plan',
        'Hook plan updates into the socket',
        'Rename step to plan in five places',
        'Update the six wording tests',
        'Run analyze and the touched tests',
        'Build 20 and hand over the APK',
        'Commit and push',
      ].indexed)
        {
          'step': s,
          'status': i < done
              ? 'done'
              : i == done && live
                  ? 'in_progress'
                  : 'pending',
        }
    ];

void main() {
  testWidgets('shows where the plan is and what comes next', (t) async {
    _phone(t);
    await t.pumpWidget(_app(PlanProgressCard(
        steps: _steps(4),
        explanation:
            'Header kept a stale step because only a status change refreshed it.')));
    expect(find.text('Plan 5 of 7'), findsOneWidget);
    expect(find.text('Run analyze and the touched tests'), findsOneWidget);
    expect(find.text('Next: Build 20 and hand over the APK'), findsOneWidget);
    expect(find.text('Commit and push'), findsNothing);
    await _shot(t, 'plan_closed');
    await t.tap(find.text('Plan 5 of 7'));
    await t.pump();
    expect(find.text('Commit and push'), findsOneWidget);
    expect(find.textContaining('stale step'), findsOneWidget);
    await _shot(t, 'plan_open');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a finished plan says so', (t) async {
    _phone(t);
    await t.pumpWidget(_app(PlanProgressCard(steps: _steps(7))));
    expect(find.text('Plan done · 7 of 7'), findsOneWidget);
    expect(find.textContaining('Next:'), findsNothing);
    await _shot(t, 'plan_done');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('with no live step the first open one leads', (t) async {
    _phone(t);
    await t.pumpWidget(_app(PlanProgressCard(steps: _steps(2, live: false))));
    expect(find.text('Plan 3 of 7'), findsOneWidget);
    expect(find.text('Rename step to plan in five places'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
