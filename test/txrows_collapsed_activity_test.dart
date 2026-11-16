import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/screens/session.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/transcript.dart';
import 'package:snippet/widgets.dart';

List<Widget> _rows() => [
      for (var i = 0; i < 2; i++)
        DenseToolRow(
          tool: 'change_files',
          args: {
            'path': 'lib/f$i.dart',
            'action': 'replace',
            'find': 'a',
            'with': 'b',
          },
          result: const {'status': 'ok'},
        ),
      for (var i = 0; i < 6; i++)
        DenseToolRow(
          tool: 'bash',
          args: {'command': 'echo $i'},
          result: const {'data': {'exit_code': 0}},
        ),
    ];

void _usePhone() {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
}

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(body: child),
  ));
  await tester.pump();
}

void main() {
  testWidgets('collapsed line is a left-aligned chevron summary with no Show '
      'action', (tester) async {
    _usePhone();
    await _pump(tester, CollapsedActivity(_rows()));

    final summary =
        find.text('Edited f0.dart and f1.dart, ran echo', findRichText: true);
    expect(summary, findsOneWidget);
    final text = tester.widget<Text>(find.ancestor(
        of: summary,
        matching: find.byType(Text),
        matchRoot: true));
    expect(text.style?.color, AppColors.fg3);
    expect(text.style?.fontSize, 14);

    // 16px chevron slot + 8px gap puts the summary at x = 24.
    expect(tester.getTopLeft(summary).dx, closeTo(24, 0.5));

    expect(find.text('Show'), findsNothing);
    expect(find.text('Hide'), findsNothing);
    expect(find.byType(DenseToolRow), findsNothing);
    expect(
      find.descendant(
        of: find.byType(CollapsedActivity),
        matching: find.byType(AppIcon),
      ),
      findsOneWidget,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('tapping the summary reveals the rows and tapping again hides '
      'them', (tester) async {
    _usePhone();
    await _pump(tester, CollapsedActivity(_rows()));

    await tester.tap(
        find.text('Edited f0.dart and f1.dart, ran echo', findRichText: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(DenseToolRow), findsNWidgets(8));
    expect(find.text('Show'), findsNothing);
    expect(find.text('Hide'), findsNothing);

    await tester.tap(
        find.text('Edited f0.dart and f1.dart, ran echo', findRichText: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(DenseToolRow), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('work summary shows outcome when collapsed and command '
      'duration when expanded', (tester) async {
    _usePhone();
    await _pump(
      tester,
      CollapsedActivity(const [
        DenseToolRow(
          tool: 'read_file',
          args: {'path': 'lib/a.dart'},
          result: {'status': 'ok'},
        ),
        DenseToolRow(
          tool: 'change_files',
          args: {
            'path': 'lib/a.dart',
            'action': 'replace',
            'find': 'old',
            'with': 'new',
          },
          result: {'status': 'ok'},
        ),
        DenseToolRow(
          tool: 'bash',
          args: {'command': 'flutter test test/work_notes_test.dart'},
          result: {
            'status': 'ok',
            'data': {
              'exit_code': 0,
              'duration_ms': 1400,
              'stdout': '00:01 +7: All tests passed!',
            },
          },
        ),
      ]),
    );

    final summary = find.text(
      'Read a.dart, edited a.dart, ran flutter test passed',
      findRichText: true,
    );
    expect(summary, findsOneWidget);

    await tester.tap(summary);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(DenseToolRow), findsNWidgets(3));
    await tester.tap(find.text('flutter test test/work_notes_test.dart',
        findRichText: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('1.4s'), findsWidgets);
    debugDefaultTargetPlatformOverride = null;
  });
}
