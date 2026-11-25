import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/session_actions_page.dart';
import 'package:snippet/screens/spec_bar.dart';
import 'package:snippet/theme.dart';

Widget _wrap(double scale, Widget body, {String? subtitle}) => MaterialApp(
      theme: buildAppTheme(),
      builder: (c, ch) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
          child: ch!),
      home: Scaffold(
          body: Column(children: [
        SpecBar(title: 'Goal', subtitle: subtitle ?? 'Running - feat/x'),
        Expanded(child: SingleChildScrollView(child: body)),
      ])),
    );

GoalInfo _goal() =>
    GoalInfo.fromJson({'text': 'Ship the wake', 'status': 'active'});

void main() {
  for (final w in [360.0, 393.0, 430.0]) {
    for (final s in [1.0, 1.35, 2.0]) {
      testWidgets('goal page w=$w s=$s', (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = Size(w, 852);
        addTearDown(t.view.reset);
        await t.pumpWidget(_wrap(
            s,
            SessionGoalPage(
              goal: _goal(),
              onSet: (_) {},
              onCancel: () {},
              onResume: () {},
              onDone: () {},
              criteria: const [GoalCriterion('Tests pass', true), GoalCriterion('Docs', false)],
              onToggleCriterion: (_) {},
              onAddCriterion: (_) {},
            )));
        await t.pump();
        expect(t.takeException(), isNull);
        final back = t.getRect(find.bySemanticsLabel('Back'));
        expect(back.size, const Size(48, 48));
        expect(back.left, 0);
        if (s == 1.0) expect(t.getTopLeft(find.text('Goal').first).dx, 56);
        final box = t.getRect(find.text('Ship the wake').hitTestable().first);
        expect(box.left, 28);
        final boxRect = t.getRect(find.ancestor(
            of: find.text('Ship the wake'), matching: find.byType(DecoratedBox)).first);
        expect(boxRect.left, 16);
        expect(boxRect.width, w - 32);
        expect(boxRect.height, greaterThanOrEqualTo(92));
        expect(find.text('Success criteria'), findsOneWidget);
        for (final l in ['Tests pass, done', 'Docs, open', 'Add criterion']) {
          expect(t.getRect(find.bySemanticsLabel(l)).height, greaterThanOrEqualTo(48));
        }
      });
    }
  }

  testWidgets('goal page without a goal record hides criteria', (t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(393, 852);
    addTearDown(t.view.reset);
    await t.pumpWidget(_wrap(
        1,
        SessionGoalPage(
            goal: null,
            onSet: (_) {},
            onCancel: () {},
            onResume: () {},
            onDone: () {})));
    expect(find.text('Success criteria'), findsNothing);
    expect(find.text('Goal'), findsWidgets);
  });

  for (final s in [1.0, 2.0]) {
    testWidgets('behaviour effort chips s=$s', (t) async {
      t.view.devicePixelRatio = 1;
      t.view.physicalSize = const Size(393, 852);
      addTearDown(t.view.reset);
      await t.pumpWidget(_wrap(
          s,
          SessionBehaviourPage(
              auto: null,
              resume: null,
              onAuto: null,
              onResume: null,
              effort: 'medium',
              onEffort: (_) {})));
      expect(t.takeException(), isNull);
      for (final l in ['Low', 'Medium', 'High', 'Max']) {
        expect(t.getRect(find.bySemanticsLabel(l)).height, 44);
      }
      expect(find.text('Approvals'), findsNothing);
    });
  }
}
