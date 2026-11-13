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
  testWidgets('collapsed line is centred fg3 text with a fg1 Show action',
      (tester) async {
    _usePhone();
    await _pump(tester, CollapsedActivity(_rows()));

    final summary = tester.widget<Text>(
        find.text('Edited 2 files, ran 6 commands'));
    expect(summary.style?.color, AppColors.fg3);
    expect(summary.style?.fontSize, isNot(TS.caption().fontSize));

    final show = tester.widget<Text>(find.text('Show'));
    expect(show.style?.color, AppColors.fg1);
    expect(show.style?.fontWeight, FontWeight.w500);

    expect(find.text('Hide'), findsNothing);
    expect(find.byType(DenseToolRow), findsNothing);
    expect(
      find.descendant(
        of: find.byType(CollapsedActivity),
        matching: find.byType(AppIcon),
      ),
      findsNothing,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('Show expands rows and Hide collapses them', (tester) async {
    _usePhone();
    await _pump(tester, CollapsedActivity(_rows()));

    await tester.tap(find.text('Show'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(DenseToolRow), findsNWidgets(8));
    expect(find.text('Hide'), findsOneWidget);
    expect(find.text('Show'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(CollapsedActivity),
        matching: find.byType(AppIcon),
      ),
      findsNothing,
    );

    await tester.tap(find.text('Hide'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(DenseToolRow), findsNothing);
    expect(find.text('Show'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });
}
