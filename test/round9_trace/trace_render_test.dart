import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/screens/session.dart';
import 'package:snippet/transcript.dart';

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

List<DenseToolRow> _rows({bool live = false}) => [
      const DenseToolRow(
        tool: 'bash',
        args: {'command': 'rg -n "springTo" lib | head'},
        result: {'status': 'ok', 'data': {'exit_code': 0, 'stdout': 'a\nb'}},
      ),
      const DenseToolRow(
        tool: 'read_file',
        args: {'path': 'lib/screens/mobile_shell.dart'},
        result: {'status': 'ok', 'data': {'content': 'x'}},
      ),
      const DenseToolRow(
        tool: 'change_files',
        args: {
          'changes': [
            {
              'action': 'create',
              'path': 'lib/page_stack.dart',
              'content': 'a\nb\nc\n'
            }
          ]
        },
        result: {'status': 'ok'},
      ),
      const DenseToolRow(
        tool: 'change_files',
        args: {
          'changes': [
            {
              'action': 'replace',
              'path': 'lib/screens/sidebar.dart',
              'find': 'a\nb',
              'with': 'c'
            }
          ]
        },
        result: {'status': 'ok'},
      ),
      const DenseToolRow(
        tool: 'bash',
        args: {'command': 'flutter analyze lib'},
        result: {
          'status': 'ok',
          'data': {'exit_code': 0, 'stdout': '6 issues found.'}
        },
      ),
      const DenseToolRow(
        tool: 'bash',
        args: {'command': 'flutter test test/page_stack_test.dart'},
        result: {
          'status': 'ok',
          'data': {
            'exit_code': 1,
            'stdout': '00:08 +30 -3: Some tests failed.',
            'duration_ms': 41000
          }
        },
      ),
      const DenseToolRow(
        tool: 'web_search',
        args: {'query': 'spring settle time'},
        result: {'status': 'ok', 'data': {'duration_ms': 8000}},
      ),
    ];

void main() {
  testWidgets('closed and open steps card', (tester) async {
    _phone(tester);
    final rows = _rows();
    await tester.pumpWidget(_app(CollapsedActivity(rows)));
    await tester.pumpAndSettle();
    expect(find.text('7 steps', findRichText: true), findsNothing);
    expect(find.textContaining('7 steps', findRichText: true), findsOneWidget);
    expect(find.byType(WorkLine), findsOneWidget);
    await _shot(tester, 'trace-closed');

    await tester.tap(find.byType(WorkLine));
    await tester.pumpAndSettle();
    expect(find.byType(DenseToolRow), findsNWidgets(7));
    await _shot(tester, 'trace-open');
    expect(tester.takeException(), isNull);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('live run header', (tester) async {
    _phone(tester);
    final rows = [
      ..._rows().take(2),
      const DenseToolRow(
          tool: 'read_file', args: {'path': 'lib/settings_panel.dart'}),
    ];
    await tester.pumpWidget(_app(CollapsedActivity(rows, running: true)));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(RunSpinner), findsOneWidget);
    expect(find.textContaining('Step 3', findRichText: true), findsOneWidget);
    await _shot(tester, 'trace-live');
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('single step is one rounded segment', (tester) async {
    _phone(tester);
    await tester.pumpWidget(_app(CollapsedActivity([_rows()[2]])));
    await tester.pumpAndSettle();
    expect(find.byType(WorkLine), findsNothing);
    expect(find.byType(DenseToolRow), findsOneWidget);
    await _shot(tester, 'trace-single');
    debugDefaultTargetPlatformOverride = null;
  });
}
