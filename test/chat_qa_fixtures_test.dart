import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/chat/chat_card.dart';
import 'package:snippet/chat/chat_style.dart';
import 'package:snippet/chat/stage_bar.dart';
import 'package:snippet/chat/stage_header.dart';
import 'package:snippet/chat/decided_card.dart';
import 'package:snippet/plan_card.dart';
import 'package:snippet/screens/session_coordination_cards.dart';
import 'package:snippet/screens/lead/lead_state.dart' show WorkerQuestion;
import 'package:snippet/theme.dart';
import 'package:snippet/turn_changes_card.dart';
import 'package:snippet/widgets.dart' show MarkdownBody;
import 'package:snippet/markdown_widgets.dart';

// Fixtures for states the scratch daemon cannot seed: every card is W wide at
// x16, nothing overflows, headers survive 2x with a two line subtitle.
void main() {
  Future<void> pump(
      WidgetTester t, double vw, double scale, Widget body) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = Size(vw, 1600);
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      builder: (c, w) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: w!),
      home: Scaffold(body: SingleChildScrollView(child: body)),
    ));
    await t.pump(const Duration(milliseconds: 100));
  }

  for (final vw in [360.0, 393.0, 430.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('header no overflow, 1:1 and group, $vw x$scale', (t) async {
        await pump(
            t,
            vw,
            scale,
            Column(children: [
              StageBar(
                  framed: false,
                  members: const [StageMember('sashy')],
                  title: 'Sashy',
                  subtitle:
                      'Working, Visual QA: Quiet Build 1 and more words here',
                  onTap: () {},
                  onBack: () {}),
              StageBar(
                  framed: false,
                  members: const [StageMember('sashy'), StageMember('buddy')],
                  title: 'App Redesign review group',
                  subtitle:
                      'Sashy, Buddy, Ada and you are all in this group chat',
                  onTap: () {},
                  onBack: () {}),
            ]));
        expect(t.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      });

      testWidgets('CH-04/05/11/13/14/15 cards at W, $vw x$scale', (t) async {
        await pump(
            t,
            vw,
            scale,
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Column(children: [
                // CH-05 pending, CH-04 pending (amber outline)
                ChatCard(fill: approvalTint, children: const [
                  NeedsYouRow(trailing: 'Sashy - 12:41'),
                  SizedBox(height: 12),
                ]),
                ChatCard(border: const Color(0xFFE9B44C), children: const [
                  ChatCardHeader(title: 'Which density?', subtitle: 'r14'),
                ]),
                // CH-05 resolved and expired, CH-04 answered
                const DecidedCard(
                    kind: DecidedKind.approved,
                    title: 'rm -rf build/',
                    code: true),
                const DecidedCard(
                    kind: DecidedKind.expired, title: 'rm -rf build/'),
                const DecidedCard(
                    kind: DecidedKind.answered,
                    title: 'Which density?',
                    subtitle: 'Option A'),
                ApprovalDecideButtons(
                    onAllowOnce: () {}, onAlways: () {}, onDeny: () {}),
                // CH-13 plan
                PlanProgressCard(steps: [
                  for (var i = 0; i < 7; i++)
                    {
                      'step': 'Step $i',
                      'status': i < 4 ? 'completed' : 'pending'
                    }
                ]),
                // CH-15 changes
                TurnChangesCard(event: const {
                  'total_files': 7,
                  'add': 212,
                  'del': 48,
                  'files': [
                    {'path': 'lib/a.dart', 'add': 1, 'del': 1}
                  ]
                }, onReview: () {}),
                // CH-14 worker question
                WorkerQuestionCard(
                    question: const WorkerQuestion(
                        taskId: 't1',
                        question: 'Which density should the list use?',
                        task: 'Phone chat')),
              ]),
            ));
        for (final type in [
          ChatCard,
          DecidedCard,
          PlanProgressCard,
          TurnChangesCard,
          WorkerQuestionCard
        ]) {
          for (final el in find.byType(type).evaluate()) {
            final r = t.getRect(find.byElementPredicate((e) => e == el));
            expect(r.left, 16, reason: '$type');
            expect(r.width, vw - 32, reason: '$type');
          }
        }
        final deny = t.getSize(find
            .ancestor(of: find.text('Deny'), matching: find.byType(Material))
            .first);
        expect(deny.height, greaterThanOrEqualTo(48));
        expect(t.takeException(), isNull);
        debugDefaultTargetPlatformOverride = null;
      });
    }
  }

  for (final vw in [360.0, 393.0, 430.0]) {
    testWidgets('reading mode bubble is W wide at x16, $vw', (t) async {
      await pump(
          t,
          vw,
          1.0,
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: ChatBubbleRow(
                mine: false,
                fill: true,
                child: ChatBubble(
                    mine: false,
                    reading: true,
                    child: Container(height: 40, color: Colors.red))),
          ));
      final r = t.getRect(find.byType(Container).last);
      expect(r.left, 16);
      expect(r.width, vw - 32);
      debugDefaultTargetPlatformOverride = null;
    });
  }

  testWidgets('reading mode rule', (t) async {
    expect(readingMode('short'), isFalse);
    expect(readingMode('x' * 601), isTrue);
    expect(readingMode('a\n\n| A | B |\n|---|---|\n| 1 | 2 |'), isTrue);
    expect(readingMode('```dart\nx\n```'), isTrue);
  });
}
