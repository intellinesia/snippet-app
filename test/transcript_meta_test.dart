import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/chat/signal_row.dart';
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

ToolStep _read(String path) => ToolStep(
      tool: 'read_file',
      args: {'path': path},
      result: const {'status': 'ok'},
    );

ToolStep _edit(String path) => ToolStep(
      tool: 'change_files',
      args: {
        'path': path,
        'action': 'replace',
        'find': 'a',
        'with': 'b',
      },
      result: const {'status': 'ok'},
    );

ToolStep _create(String path) => ToolStep(
      tool: 'change_files',
      args: {
        'path': path,
        'action': 'create',
        'content': 'hello',
      },
      result: const {'status': 'ok'},
    );

ToolStep _bash(
  String command, {
  String stdout = '',
  String stderr = '',
  int exitCode = 0,
  bool running = false,
}) =>
    ToolStep(
      tool: 'bash',
      args: {'command': command},
      result: running
          ? null
          : {
              'status': exitCode == 0 ? 'ok' : 'error',
              'data': {
                'exit_code': exitCode,
                if (stdout.isNotEmpty) 'stdout': stdout,
                if (stderr.isNotEmpty) 'stderr': stderr,
              },
            },
    );

void main() {
  group('work summary', () {
    test('never contains shell syntax', () {
      final steps = [
        bash('cd ~/code/app && python3 - <<\'EOF\'\n'
            'p="lib/a.dart"\nassert open(p).read()\n'
            'open(p,"w").write("x")\nEOF'),
        bash(
            'export PATH=\$HOME/bin:\$PATH; CPU_SLOT_WAIT=1 cpu-slot flutter test test/a_test.dart'),
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
        for (final bad in [
          'assert',
          'open(',
          'EOF',
          'cd ',
          'export',
          'cat >'
        ]) {
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
      expect(
          stepChip(bash('flutter test', code: 1))?.tone, StepChipTone.danger);
      expect(
          stepChip(const ToolStep(
              tool: 'view_image',
              args: {'path': 'a.png'},
              result: {'status': 'ok'}))?.text,
          'image');
    });
  });

  group('envelopes and names', () {
    const body = '<task_cancelled task_id="d3bd" title="Daily LinkedIn sync">\n'
        '<reason>Moot: run 3 completed.</reason>\n'
        '<note>Stop work on it.</note>\n'
        '</task_cancelled>';

    test('parse attributes and children', () {
      final env = parseCoordinationEnvelope(body)!;
      expect(env.tag, 'task_cancelled');
      expect(env.field('title'), 'Daily LinkedIn sync');
      expect(env.field('reason'), 'Moot: run 3 completed.');
      expect(parseCoordinationEnvelope('plain words'), isNull);
    });

    test('become one sentence naming the sender', () {
      final sig =
          envelopeSignal(parseCoordinationEnvelope(body)!, 'Lead');
      expect(signalPlain(sig.text),
          'Lead cancelled Daily LinkedIn sync');
      expect(sig.sub, 'Moot: run 3 completed.');
    });

    test('display names never show raw ids', () {
      expect(agentDisplayName('lead'), 'Lead');
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
            reasoning:
                '"build 7" — /tmp/build.log grew: APK ok\n__DONE__ exit=0'),
        SystemRow(
            step: 'watch_removed', reasoning: 'stopped watching "build 7"'),
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
            agentId: 'lead',
            body:
                '<task_cancelled title="Sync">\n<reason>Moot.</reason>\n</task_cancelled>',
            outbound: false),
      ])));
      expect(find.text('Moss'), findsOneWidget);
      expect(find.text('Rook to Moss'), findsOneWidget);
      expect(find.textContaining('moss'), findsNothing);
      expect(find.textContaining('lead'), findsNothing);
      expect(find.text('Lead cancelled Sync', findRichText: true),
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
          DenseToolRow(tool: 'change_files', args: const {
            'path': 'lib/a.dart',
            'action': 'replace',
            'find': 'a',
            'with': 'b'
          }, result: const {
            'status': 'ok'
          }),
          DenseToolRow(tool: 'bash', args: const {
            'command': 'flutter test test/a_test.dart'
          }, result: const {
            'status': 'ok',
            'data': {'exit_code': 0, 'stdout': '3 passed'}
          }),
        ],
        open: true,
        onOpenChanged: (_) {},
      )));
      await t.pump(const Duration(milliseconds: 300));
      // Phone: the run folds into one summary line; open, the rows show.
      expect(find.byType(PhoneFoldLine), findsOneWidget);
      expect(
          find.descendant(
              of: find.byType(DenseToolRow),
              matching:
                  find.textContaining('Edited a.dart', findRichText: true)),
          findsOneWidget);
      expect(
          find.textContaining('flutter test test/a_test.dart',
              findRichText: true),
          findsOneWidget);
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

  test('workSummary returns empty string for no steps', () {
    expect(workSummary(const []), '');
  });

  test('workSummary formats reads with names for <= 2 and count for >= 3', () {
    expect(workSummary([_read('lib/session.dart')]), 'Read session.dart');
    expect(
      workSummary([_read('lib/session.dart'), _read('lib/models.dart')]),
      'Read session.dart and models.dart',
    );
    expect(
      workSummary([
        _read('lib/session.dart'),
        _read('lib/session.dart'),
        _read('lib/models.dart'),
      ]),
      'Read session.dart and models.dart',
    );
    expect(
      workSummary([_read('lib/a/mod.dart'), _read('lib/b/mod.dart')]),
      'Read a/mod.dart and b/mod.dart',
    );
    expect(
      workSummary([
        _read('lib/a.dart'),
        _read('lib/b.dart'),
        _read('lib/c.dart'),
      ]),
      'Read 3 files',
    );
    expect(
      workSummary(const [
        ToolStep(
          tool: 'view_file',
          args: {'AbsolutePath': '/repo/lib/main.dart'},
          result: {'status': 'ok'},
        ),
        ToolStep(
          tool: 'view_image',
          args: {'path': '/tmp/screen.png'},
          result: {'status': 'ok'},
        ),
      ]),
      'Read main.dart and screen.png',
    );
  });

  test('workSummary formats edited, created, deleted and moved files', () {
    expect(
      workSummary([
        _edit('lib/agent_card.dart'),
        _edit('lib/sidebar.dart'),
      ]),
      'Edited agent_card.dart and sidebar.dart',
    );
    expect(
      workSummary([
        _create('lib/work_notes.dart'),
        _edit('lib/work_notes.dart'),
        _edit('lib/session_transcript.dart'),
      ]),
      'Edited session_transcript.dart, created work_notes.dart',
    );
    expect(
      workSummary([
        _edit('lib/a.dart'),
        _edit('lib/b.dart'),
        _edit('lib/c.dart'),
        _edit('lib/d.dart'),
        _edit('lib/e.dart'),
      ]),
      'Edited a.dart, b.dart, c.dart and 2 more',
    );
    expect(
      workSummary(const [
        ToolStep(
          tool: 'change_files',
          args: {
            'path': 'lib/a.dart',
            'action': 'replace',
            'find': 'x',
            'with': 'y'
          },
          result: {'status': 'error'},
        ),
      ]),
      'Attempted 1 edit',
    );
  });

  test('workSummary extracts and deduplicates command names', () {
    expect(
      workSummary([
        _bash('cd /home/snippet/code/app && flutter analyze lib/a.dart'),
        _bash(
            'CPU_SLOT_WAIT=3600 cpu-slot cargo test --lib work_notes | tail -n 20'),
        _bash('cargo test --lib other_filter'),
        _bash('rg -n CollapsedActivity lib/'),
        _bash('ls -la lib/'),
      ]),
      'Ran flutter analyze, cargo test, rg, ls',
    );
    expect(
      workSummary([
        _bash('flutter analyze && flutter test test/work_notes_test.dart'),
      ]),
      'Ran flutter analyze, flutter test',
    );
  });

  test('workSummary summarizes searches', () {
    expect(
      workSummary(const [
        ToolStep(
          tool: 'search_content',
          args: {'query': 'CollapsedActivity', 'path': 'lib/'},
          result: {'status': 'ok'},
        ),
      ]),
      'Searched for CollapsedActivity',
    );
    expect(
      workSummary(const [
        ToolStep(
            tool: 'search_content',
            args: {'query': 'a'},
            result: {'status': 'ok'}),
        ToolStep(
            tool: 'web_search', args: {'query': 'b'}, result: {'status': 'ok'}),
      ]),
      'Searched 2 times',
    );
  });

  test('workSummary extracts test and build excerpts only from last command',
      () {
    expect(
      workSummary([
        _read('lib/a.dart'),
        _read('lib/b.dart'),
        _read('lib/c.dart'),
        _edit('lib/agent_card.dart'),
        _edit('lib/sidebar.dart'),
        _bash('flutter analyze', stdout: 'No issues found! (ran in 1.1s)'),
        _bash(
          'cargo test --lib',
          stdout:
              'test result: ok. 212 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out\n'
              'Doc-tests app\n'
              'test result: ok. 0 passed; 0 failed; 0 ignored; 0 measured; 0 filtered out\n',
        ),
      ]),
      'Read 3 files, edited agent_card.dart and sidebar.dart · ran flutter analyze, cargo test · 212 passed',
    );

    expect(
      workSummary([
        _bash(
          'cargo test',
          exitCode: 1,
          stdout: 'test result: FAILED. 210 passed; 2 failed; 0 ignored',
        ),
      ]),
      'Ran cargo test · 210 passed, 2 failed',
    );

    expect(
      workSummary([
        _bash(
          'cargo build',
          exitCode: 101,
          stderr:
              '\x1B[1;31merror[E0425]\x1B[0m: cannot find value `x` in this scope',
        ),
      ]),
      'Ran cargo build · error[E0425]',
    );

    expect(
      workSummary([
        _bash('flutter test', stdout: '00:04 +48: All tests passed!'),
      ]),
      'Ran flutter test · All tests passed!',
    );

    expect(
      workSummary([
        _bash('flutter analyze',
            stdout: 'Analyzing snippet...\n\n3 issues found. (ran in 2.1s)'),
      ]),
      'Ran flutter analyze · 3 issues found',
    );

    expect(
      workSummary([
        _bash('flutter test', stdout: '00:04 +48: All tests passed!'),
        _bash('git status -sb', stdout: '## feat/work-notes\n M lib/a.dart'),
      ]),
      'Ran flutter test, git status',
    );

    expect(
      workSummary([
        _bash('flutter test', stdout: '00:04 +48: All tests passed!'),
        _bash('flutter analyze', running: true),
      ]),
      'Ran flutter test, flutter analyze',
    );
  });

  test('workSummary handles mcp prefixes and other steps', () {
    expect(
      workSummary(const [
        ToolStep(
          tool: 'mcp__snippet_snippet__read_file',
          args: {'path': 'lib/api.dart'},
          result: {'status': 'ok'},
        ),
        ToolStep(
          tool: 'present_file',
          args: {'path': 'out.png'},
          result: {'status': 'ok'},
        ),
      ]),
      'Read api.dart · 1 other step',
    );
  });

  test('workSummary ignores heredoc bodies', () {
    final s = workSummary([
      ToolStep(
          tool: 'bash',
          args: {
            'command': "python3 - <<'E'\nassert old in s\nopen(p).read()\nE\ngrep -n foo bar"
          },
          result: 'ok'),
    ]);
    expect(s, contains('python3'));
    expect(s, contains('grep'));
    expect(s, isNot(contains('assert')));
  });
}
