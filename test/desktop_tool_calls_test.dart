import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/chat/tool_call_row.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/tool_activity.dart';
import 'package:snippet/tool_views.dart';
import 'package:snippet/turn_changes_card.dart';

Widget wrap(Widget child) => MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Center(child: SizedBox(width: 640, child: child)),
      ),
    );

void useDesktop() {
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
}

Finder richTextContaining(String text, {required Finder within}) =>
    find.descendant(
      of: within,
      matching: find.byWidgetPredicate(
          (w) => w is RichText && w.text.toPlainText().contains(text)),
    );

ToolStep bash(String command,
        {Map<String, dynamic>? result, Map<String, dynamic>? extraArgs}) =>
    ToolStep(
      tool: 'bash',
      args: {'command': command, ...?extraArgs},
      result: result,
    );

void main() {
  group('desktop tool call rows', () {
    testWidgets('a running row is 28pt, s1-filled and reads in words',
        (tester) async {
      useDesktop();
      final step = bash('npm run build');
      await tester.pumpWidget(wrap(ToolCallRow(step: step)));
      await tester.pump();

      expect(tester.getSize(find.byType(ToolCallRow)).height, 28);
      expect(
        richTextContaining('Running npm run build',
            within: find.byType(ToolCallRow)),
        findsOneWidget,
      );
      final filled = tester
          .widgetList<DecoratedBox>(find.descendant(
              of: find.byType(ToolCallRow),
              matching: find.byType(DecoratedBox)))
          .any((w) =>
              w.decoration is BoxDecoration &&
              (w.decoration as BoxDecoration).color == AppColors.surface1);
      expect(filled, isTrue);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('a failed shell row carries exit and duration metadata once',
        (tester) async {
      useDesktop();
      final step = bash('flutter test', result: {
        'status': 'error',
        'data': {'exit_code': 1, 'duration_ms': 1200, 'stdout': 'boom'},
      });
      await tester.pumpWidget(wrap(ToolCallRow(step: step)));
      await tester.pump();

      expect(
        richTextContaining('Ran flutter test',
            within: find.byType(ToolCallRow)),
        findsOneWidget,
      );
      expect(find.text('exit 1 · 1.2s'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('desktop tool detail bodies', () {
    testWidgets('terminal details show mono command and ANSI-free output',
        (tester) async {
      useDesktop();
      await tester.pumpWidget(wrap(Builder(
        builder: (context) => toolDetailView(
          context,
          tool: 'bash',
          args: const {'command': 'npm test'},
          result: const {
            'status': 'ok',
            'data': {
              'exit_code': 0,
              'stdout': '\u001b[32mall good\u001b[0m\nError-free exit',
            },
          },
        ),
      )));
      await tester.pump();

      final body = find.byType(Scaffold);
      expect(richTextContaining(r'$ npm test', within: body), findsOneWidget);
      expect(richTextContaining('all good', within: body), findsOneWidget);
      expect(richTextContaining('\u001b[', within: body), findsNothing);
      debugDefaultTargetPlatformOverride = null;
    });

    testWidgets('change details use neutral mono diff lines', (tester) async {
      useDesktop();
      await tester.pumpWidget(wrap(Builder(
        builder: (context) => toolDetailView(
          context,
          tool: 'change_files',
          args: const {
            'path': 'lib/a.dart',
            'action': 'replace',
            'find': 'old',
            'with': 'new',
          },
          result: const {'status': 'ok'},
        ),
      )));
      await tester.pump();

      expect(find.text('lib/a.dart'), findsOneWidget);
      expect(find.text('old'), findsOneWidget);
      expect(find.text('new'), findsOneWidget);
      expect(find.text('−'), findsOneWidget);
      expect(find.text('+'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('desktop turn changes', () {
    testWidgets('collapsed card expands to dense rows and a 28pt review action',
        (tester) async {
      useDesktop();
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
      expect(find.text('Review changes'), findsOneWidget);
      final review = tester.getRect(find
          .ancestor(
              of: find.text('Review changes'), matching: find.byType(Container))
          .first);
      expect(review.height, closeTo(28, 1));
      debugDefaultTargetPlatformOverride = null;
    });
  });
}
