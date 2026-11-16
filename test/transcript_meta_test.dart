import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/chat/signal_row.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/session.dart';
import 'package:snippet/screens/session_coordination_cards.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/tool_activity.dart';
import 'package:snippet/transcript.dart';

ToolStep bash(String command, {int code = 0, String stdout = ''}) => ToolStep(
      tool: 'bash',
      args: {'command': command},
      result: {
        'status': 'ok',
        'data': {'exit_code': code, 'stdout': stdout},
      },
    );

ToolStep edit(String path) => ToolStep(
      tool: 'change_files',
      args: {
        'path': path,
        'action': 'replace',
        'find': 'a',
        'with': 'b',
      },
      result: const {'status': 'ok'},
    );

Widget wrap(Widget child) => MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(body: child),
    );

void main() {
  group('work summary', () {
    test('never contains shell syntax', () {
      final steps = [
        bash('cd ~/code/app && python3 - <<\'EOF\'\n'
            'p="lib/a.dart"\nassert open(p).read()\n'
            'open(p,"w").write("x")\nEOF'),
        bash('export PATH=\$HOME/bin:\$PATH; CPU_SLOT_WAIT=1 cpu-slot flutter test test/a_test.dart'),
        bash('cat > notes.txt <<EOF\nhello\nEOF'),
        bash('python3 -c "assert 1; print(open(\'f\').read())"'),
      ];
      for (final subset in [
        for (final s in steps) [s],
        steps,
      ]) {
        final w = describeWork(subset);
        final line = activitySummary(subset);
        expect(line, isNot(matches(r'[<>|=(){}\\$]')), reason: line);
        for (final bad in ['assert', 'open(', 'EOF', 'cd ', 'export', 'cat >']) {
          expect(line, isNot(contains(bad)), reason: line);
        }
        expect(w.text, isNotEmpty);
      }
    });

    test('describes the work in the agent\'s terms', () {
      expect(
        describeWork([
          edit('lib/screens/phone_hero.dart'),
          bash('flutter test test/a.dart'),
          bash('flutter test test/b.dart'),
          bash('flutter test test/c.dart'),
        ]).text,
        'Edited phone_hero.dart, ran 3 tests',
      );
      expect(describeWork([bash('flutter test')]).text, 'Ran flutter test');
      expect(describeWork([bash('python3 - <<EOF\nprint(1)\nEOF')]).text,
          'Ran a script');
      final reads = describeWork([
        for (var i = 0; i < 4; i++)
          ToolStep(
              tool: 'read_file',
              args: {'path': 'lib/f$i.dart'},
              result: const {'status': 'ok'}),
        for (var i = 0; i < 2; i++)
          ToolStep(
              tool: 'view_image',
              args: {'path': 'shots/$i.png'},
              result: const {'status': 'ok'}),
      ]);
      expect(reads.text, 'Read 4 files, viewed 2 images');
    });

    test('outcome follows the exit code', () {
      expect(describeWork([edit('a.dart'), bash('flutter test')]).outcome,
          'passed');
      final failed =
          describeWork([edit('a.dart'), bash('flutter test', code: 1)]);
      expect(failed.outcome, 'failed');
      expect(failed.failed, isTrue);
      expect(describeWork([bash('ls'), bash('pwd')]).outcome, isNull);
    });

    test('a running step is named, not summarised', () {
      const live = ToolStep(tool: 'bash', args: {'command': 'flutter test'});
      expect(liveStepText(live), 'Running flutter test');
    });

    test('step chips', () {
      expect(stepChip(edit('a.dart'))?.text, '+1 −1');
      expect(stepChip(bash('flutter test', stdout: '00:01 +2: 2 passed'))?.text,
          '2 passed');
      expect(stepChip(bash('flutter test', code: 1))?.tone,
          StepChipTone.danger);
      expect(
          stepChip(const ToolStep(
                  tool: 'view_image',
                  args: {'path': 'a.png'},
                  result: {'status': 'ok'}))
              ?.text,
          'image');
    });
  });

  group('envelopes and names', () {
    const body = '[task_cancelled]\n'
        'task_id: d3bd\n'
        'title: Daily LinkedIn sync\n'
        'reason: Moot: run 3 completed.\n'
        'note: Stop work on it.\n'
        '[/task_cancelled]';

    test('parse key value lines between the tags', () {
      final env = parseCoordinationEnvelope(body)!;
      expect(env.tag, 'task_cancelled');
      expect(env.field('title'), 'Daily LinkedIn sync');
      expect(env.field('reason'), 'Moot: run 3 completed.');
      expect(parseCoordinationEnvelope('plain words'), isNull);
    });

    test('become one sentence naming the sender', () {
      final sig = envelopeSignal(parseCoordinationEnvelope(body)!, 'Mission Control');
      expect(signalPlain(sig.text),
          'Mission Control cancelled Daily LinkedIn sync');
      expect(sig.sub, 'Moot: run 3 completed.');
    });

    test('display names never show raw ids', () {
      expect(agentDisplayName('mission-control'), 'Mission Control');
      expect(agentDisplayName('agent:moss'), 'Moss');
      expect(agentDisplayName('moss', {'moss': 'Moss the Builder'}),
          'Moss the Builder');
      expect(agentDisplayName('human'), 'You');
      expect(prettyProfile('claude-opus'), 'Claude Opus');
      expect(prettyProfile('antigravity'), 'Antigravity');
    });
  });

  group('rows', () {
    testWidgets('watch rows are visible on their own', (t) async {
      await t.pumpWidget(wrap(const Column(children: [
        SystemRow(
            step: 'watch_added',
            reasoning: 'watching "build 7" (/tmp/build.log)'),
        SystemRow(
            step: 'file_watch',
            reasoning: '"build 7" — /tmp/build.log grew: APK ok\n__DONE__ exit=0'),
        SystemRow(step: 'watch_removed', reasoning: 'stopped watching "build 7"'),
      ])));
      expect(find.text('Watching build 7', findRichText: true), findsOneWidget);
      expect(find.text('build 7 finished', findRichText: true), findsOneWidget);
      expect(find.text('Stopped watching build 7', findRichText: true),
          findsOneWidget);
    });

    testWidgets('agent messages show names and the me-to-them label',
        (t) async {
      await t.pumpWidget(wrap(const Column(children: [
        AgentMessageCard(
            agentId: 'moss', body: 'Staging is green.', outbound: false),
        AgentMessageCard(
            agentId: 'moss',
            body: 'Please rebase.',
            outbound: true,
            meId: 'rook',
            meName: 'Rook'),
        AgentMessageCard(
            agentId: 'mission-control',
            body: '[task_cancelled]\ntitle: Sync\nreason: Moot.\n[/task_cancelled]',
            outbound: false),
      ])));
      expect(find.text('Moss'), findsOneWidget);
      expect(find.text('Rook to Moss'), findsOneWidget);
      expect(find.textContaining('moss'), findsNothing);
      expect(find.textContaining('mission-control'), findsNothing);
      expect(find.text('Mission Control cancelled Sync', findRichText: true),
          findsOneWidget);
      expect(find.text('Moot.'), findsOneWidget);
    });

    testWidgets('handoff divider reads takes over from', (t) async {
      await t.pumpWidget(wrap(const HandoffNotice(event: {
        'from': 'rook',
        'to': 'moss',
        'note': 'take the deploy',
        'by': 'human',
        'at': 1765000000,
      })));
      await t.pump(const Duration(milliseconds: 500));
      expect(find.text('Moss takes over from Rook', findRichText: true),
          findsOneWidget);
      expect(find.textContaining('"take the deploy"'), findsOneWidget);
      expect(find.textContaining('you'), findsOneWidget);
    });

    testWidgets('open work line lists steps with result chips', (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      await t.pumpWidget(wrap(CollapsedActivity(
        [
          DenseToolRow(
              tool: 'change_files',
              args: const {
                'path': 'lib/a.dart',
                'action': 'replace',
                'find': 'a',
                'with': 'b'
              },
              result: const {'status': 'ok'}),
          DenseToolRow(
              tool: 'bash',
              args: const {'command': 'flutter test test/a_test.dart'},
              result: const {
                'status': 'ok',
                'data': {'exit_code': 0, 'stdout': '3 passed'}
              }),
        ],
        open: true,
        onOpenChanged: (_) {},
      )));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.text('lib/a.dart'), findsOneWidget);
      expect(find.text('flutter test test/a_test.dart'), findsOneWidget);
      expect(find.text('3 passed'), findsOneWidget);
      debugDefaultTargetPlatformOverride = null;
    });

    test('watch output reads as a verdict', () {
      expect(readWatchPreview('APK rc=0 built\n__DONE__').ok, isTrue);
      expect(readWatchPreview('__DONE__ exit=2').ok, isFalse);
      expect(readWatchPreview('TEST rc=1 native assets').ok, isFalse);
      expect(readWatchPreview('12 passed, 0 errors').ok, isTrue);
      expect(readWatchPreview('compiling foo').ok, isNull);
      expect(readWatchPreview('built ok __DONE__').lines, ['built ok']);
    });
  });
}
