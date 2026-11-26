import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/chat/activity_dock.dart';
import 'package:snippet/chat/tool_call_row.dart';
import 'package:snippet/chat/tool_output_sheet.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/tool_activity.dart';
import 'package:snippet/tool_sheet.dart';
import 'package:snippet/transcript.dart';
import 'package:snippet/turn_changes_card.dart';

Widget wrap(Widget child) => MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: Center(child: SizedBox(width: 393, child: child))),
    );

void usePhone() {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
}

void resetPlatform() {
  debugDefaultTargetPlatformOverride = null;
}

ToolStep bashStep({bool running = false}) => ToolStep(
      tool: 'bash',
      args: const {'command': 'flutter test'},
      result: running
          ? null
          : const {
              'status': 'ok',
              'data': {
                'exit_code': 0,
                'duration_ms': 8200,
                'stdout': 'ok\n'
              }
            },
      startMs: running
          ? DateTime.now().millisecondsSinceEpoch - 2000
          : DateTime.now().millisecondsSinceEpoch - 8200,
      endMs: running ? null : DateTime.now().millisecondsSinceEpoch,
    );

void main() {
  testWidgets('phone collapsed tool row is a 48-high filled card', (tester) async {
    usePhone();
    await tester.pumpWidget(wrap(ToolCallRow(step: bashStep())));
    await tester.pump();

    expect(tester.getSize(find.byType(ToolCallRow)).height, 48);
    expect(find.text('8.2s'), findsOneWidget);
    final box = tester
        .widgetList<DecoratedBox>(find.descendant(
            of: find.byType(ToolCallRow), matching: find.byType(DecoratedBox)))
        .firstWhere((w) => w.decoration is BoxDecoration);
    final deco = box.decoration as BoxDecoration;
    expect(deco.color, AppColors.surface1);
    expect(deco.borderRadius, BorderRadius.circular(6));
    resetPlatform();
  });

  testWidgets('phone terminal card has bash label, neutral footer and copy',
      (tester) async {
    usePhone();
    await tester.pumpWidget(wrap(TerminalBlock(step: bashStep())));
    await tester.pump();

    expect(find.text('bash'), findsOneWidget);
    expect(find.text('exit 0'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    resetPlatform();
  });

  testWidgets('phone turn changes collapse has no review CTA; expanded uses 36-high actions',
      (tester) async {
    usePhone();
    await tester.pumpWidget(wrap(TurnChangesCard(
      event: const {
        'total_files': 2,
        'add': 12,
        'del': 3,
        'files': [
          {'path': 'lib/a.dart', 'add': 10, 'del': 2},
          {'path': 'lib/b.dart', 'add': 2, 'del': 1},
        ],
      },
      onReview: () {},
    )));
    await tester.pump();

    expect(find.text('2 files changed'), findsOneWidget);
    expect(find.text('Review changes'), findsNothing);
    await tester.tap(find.text('2 files changed'));
    await tester.pump();
    expect(find.text('lib/a.dart'), findsOneWidget);
    expect(find.text('Revert all'), findsOneWidget);
    expect(tester.getSize(find.ancestor(
            of: find.text('Revert all'), matching: find.byType(Container)).first).height,
        closeTo(36, 1));
    resetPlatform();
  });

  testWidgets('tool output sheet uses input output error tabs and a 36-high copy button',
      (tester) async {
    usePhone();
    await tester.pumpWidget(wrap(const ToolOutputSheet(
        input: 'cmd', output: 'out', error: 'err')));
    await tester.pump();

    expect(find.text('Input'), findsOneWidget);
    expect(find.text('Output'), findsOneWidget);
    expect(find.text('Error'), findsOneWidget);
    expect(tester.getSize(find.ancestor(
            of: find.text('Copy'), matching: find.byType(Container)).first).height,
        closeTo(36, 1));
    resetPlatform();
  });

  testWidgets('phone activity dock is a 36-high content-sized floating pill',
      (tester) async {
    usePhone();
    final batch = ToolBatch([bashStep(running: true)], running: true);
    await tester.pumpWidget(wrap(Align(
      alignment: Alignment.topCenter,
      child: ActivityDock(
          run: DockRun(batch, DateTime.now().subtract(const Duration(seconds: 4))),
          agentId: 'Sashy',
          onOpen: (_) {}),
    )));
    await tester.pump();

    final size = tester.getSize(find.byType(ActivityDock));
    expect(size.height, 36);
    expect(size.width, lessThanOrEqualTo(236));
    expect(find.textContaining('Sashy running'), findsOneWidget);
    resetPlatform();
  });
}
