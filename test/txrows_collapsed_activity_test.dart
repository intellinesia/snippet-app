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
        find.text('Ran 6 commands · edited 2 files', findRichText: true);
    expect(summary, findsOneWidget);
    final text = tester.widget<Text>(find.ancestor(
        of: summary,
        matching: find.byType(Text),
        matchRoot: true));
    expect(text.style?.color, AppColors.fg3);
    expect(text.style?.fontSize, 14);

    // 14px chevron slot + 8px gap puts the summary at x = 22.
    expect(tester.getTopLeft(summary).dx, closeTo(22, 0.5));

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
        find.text('Ran 6 commands · edited 2 files', findRichText: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(DenseToolRow), findsNWidgets(8));
    expect(find.text('Show'), findsNothing);
    expect(find.text('Hide'), findsNothing);

    await tester.tap(
        find.text('Ran 6 commands · edited 2 files', findRichText: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(DenseToolRow), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
