import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:snippet/screens/tasks/task_phone.dart';
import 'package:snippet/screens/tasks/task_phone_board.dart';
import 'package:snippet/screens/tasks/tasks_panel.dart';

import 'tasks_phone_test.dart' show FakeTasks, task, wrap;

void main() {
  final rows = [
    task('t1', 'todo', priority: 0),
    task('p1', 'in_progress'),
    task('p2', 'in_progress', priority: 1),
    task('r1', 'in_review'),
    task('b1', 'blocked'),
    task('d1', 'done'),
    task('c1', 'cancelled'),
  ];
  for (final w in [360.0, 393.0, 430.0]) {
    for (final scale in [1.0, 1.35, 2.0]) {
      testWidgets('board w=$w s=$scale', (tester) async {
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          SharedPreferences.setMockInitialValues({});
          tester.view.devicePixelRatio = 1;
          tester.view.physicalSize = Size(w, 852);
          addTearDown(tester.view.reset);
          await tester.pumpWidget(
              wrap(scale, Scaffold(body: TasksPanel(client: FakeTasks(rows)))));
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          // Board view lives in the New task split button's menu.
          await tester.tap(find.bySemanticsLabel('Task options'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          await tester.tap(find.bySemanticsLabel('Board view'));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 400));
          final plus = tester.getRect(find.bySemanticsLabel('New task'));
          final tg = tester.getRect(find.bySemanticsLabel('List view'));
          expect(plus.right, w - 4);
          expect(tg.right, plus.left);
          expect(tg.width, 48);
          expect(tester.takeException(), isNull);
          expect(find.text('7 cards'), findsOneWidget);
          Finder chip(BoardColumn c) =>
              find.bySemanticsLabel(RegExp('^${c.label}, '));
          final chips = [
            for (final c in BoardColumn.values) tester.getRect(chip(c))
          ];
          for (final c in chips) {
            expect(c.height, 44);
          }
          expect(chips[0].left, 16);
          for (var i = 1; i < chips.length; i++) {
            expect(chips[i].left - chips[i - 1].right, 4);
          }
          // Todo column first
          final card = tester.getRect(find.byKey(const ValueKey('board-card-t1')));
          expect(card.left, 16);
          expect(card.width, w - 32);
          expect(card.height, greaterThanOrEqualTo(80));
          // no drag: no draggable widgets
          expect(find.byType(LongPressDraggable<Object>), findsNothing);
          expect(find.byType(Draggable<Object>), findsNothing);
          expect(find.textContaining('Long-press'), findsNothing);
          // Review column holds needs-you cards with the amber hand
          await tester.tap(chip(BoardColumn.review));
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 300));
          expect(find.text('Needs you'), findsNWidgets(2));
          final rc = tester.getRect(find.byKey(const ValueKey('board-card-r1')));
          // ignore: avoid_print
          print('w=$w s=$scale chips=$chips todoCard=$card reviewCard=$rc toggle=$tg');
          expect(rc.width, w - 32);
          // swipe left goes to Done
          await tester.fling(find.byKey(const ValueKey('board-pages')),
              const Offset(-300, 0), 1500);
          await tester.pumpAndSettle();
          expect(find.byKey(const ValueKey('board-card-d1')), findsOneWidget);
          expect(find.text('Needs you'), findsNothing);
          expect(find.byIcon(Icons.drag_handle), findsNothing);
          // back to the list
          await tester.tap(find.bySemanticsLabel('List view'));
          await tester.pump();
          expect(find.bySemanticsLabel(RegExp('^All, ')), findsOneWidget);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }
}
