import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/mochi.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/phone_hero.dart';
import 'package:snippet/theme.dart';

final _now = DateTime(2026, 11, 16, 8, 0);
int _sec(DateTime t) => t.millisecondsSinceEpoch ~/ 1000;

CoordinationAgent _agent(String id, String name) =>
    CoordinationAgent.fromJson({'id': id, 'display_name': name});

SessionInfo _session(String id, String agent, Map<String, dynamic> extra) =>
    SessionInfo.fromJson({
      'id': id,
      'title': 'Session $id',
      'agent_id': agent,
      'last_active': _sec(_now.subtract(const Duration(minutes: 2))),
      ...extra,
    });

final _agents = [
  _agent('rook', 'Rook'),
  _agent('moss', 'Moss'),
  _agent('wren', 'Wren'),
  _agent('sol', 'Sol'),
];

SessionInfo _asking() => _session('s1', 'rook', {
      'title': 'Sidebar density',
      'status': 'waiting_for_input',
      'attention': {
        'type': 'approval',
        'tool': 'bash',
        'text': 'git push --force-with-lease origin lane/sidebar-polish',
      },
    });

SessionInfo _running() => _session('s2', 'moss', {
      'title': 'Staging deploy',
      'status': 'running',
      'running': true,
      'running_since': _sec(
          DateTime.now().subtract(const Duration(minutes: 11, seconds: 5))),
      'plan': {'done': 3, 'total': 6, 'current': 'Health checks'},
    });

Widget _host(
  List<SessionInfo> sessions, {
  List<String>? opened,
  List<String>? calls,
}) =>
    MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: SingleChildScrollView(
          child: PhoneHero(
            now: _now,
            sessions: sessions,
            agents: _agents,
            onOpenSession: (s) => opened?.add(s.id),
            onDecide: (s, ok) async =>
                calls?.add('${ok ? 'approve' : 'deny'}:${s.id}'),
            onReviewPr: (s) => calls?.add('review:${s.id}'),
            onMergePr: (s) => calls?.add('merge:${s.id}'),
          ),
        ),
      ),
    );

void main() {
  setUp(() => rememberAgentCharacters(const []));

  testWidgets('with nothing live the hero shows the cast asleep',
      (tester) async {
    await tester.pumpWidget(_host([
      _session('idle', 'rook', {'status': 'idle'}),
    ]));
    expect(find.byType(PhoneHero), findsOneWidget);
    // The cast carries no name labels; the name lives in semantics only.
    expect(find.text('Rook'), findsNothing);
    expect(find.text('Needs you'), findsNothing);
    expect(find.bySemanticsLabel(RegExp('Rook is asleep')), findsOneWidget);
  });

  testWidgets('nobody sleeps while an agent is working', (tester) async {
    await tester.pumpWidget(_host([_running()]));
    expect(find.bySemanticsLabel(RegExp('asleep')), findsNothing);
  });

  testWidgets('stage lists live agents, badge only on the needs-you one',
      (tester) async {
    rememberAgentCharacters(
        const [('rook', '01'), ('moss', '07'), ('wren', '05')]);
    await tester.pumpWidget(_host([_asking(), _running()]));
    expect(find.bySemanticsLabel(RegExp('Rook needs you')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Moss is working')), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('Wren')), findsNothing);
    expect(find.text('Moss'), findsNothing);
    final chars = tester
        .widgetList<AgentCharacter>(find.byType(AgentCharacter))
        .where((c) => c.size != 36 && c.size != 24)
        .toList();
    expect(chars.length, 2);
    final rook = chars.firstWhere((c) => c.characterId == '01');
    expect(rook.badge, '?');
    expect(rook.state, AgentCharacterState.needs);
    final moss = chars.firstWhere((c) => c.characterId == '07');
    expect(moss.badge, isNull);
    expect(moss.state, AgentCharacterState.working);
  });

  testWidgets('approval card shows the ask and Approve / Deny call the API',
      (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(_host([_asking()], calls: calls));
    expect(find.text('Needs you'), findsOneWidget);
    expect(find.text('2 min'), findsOneWidget);
    expect(find.text('Rook · Sidebar density'), findsOneWidget);
    expect(find.text('Run a command'), findsOneWidget);
    expect(find.textContaining('git push --force-with-lease'), findsOneWidget);
    await tester.tap(find.text('Approve'));
    await tester.pump();
    await tester.tap(find.text('Deny'));
    await tester.pump();
    expect(calls, ['approve:s1', 'deny:s1']);
  });

  testWidgets('a question shows its text and Answer opens the session',
      (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(_host([
      _session('q1', 'rook', {
        'title': 'Theme sync',
        'status': 'waiting_for_input',
        'attention': {'type': 'question', 'text': 'Which palette should win?'},
      }),
    ], opened: opened));
    expect(find.text('Which palette should win?'), findsOneWidget);
    expect(find.text('Approve'), findsNothing);
    await tester.tap(find.text('Answer'));
    expect(opened, ['q1']);
  });

  testWidgets('PR line offers Review and Merge for the newest open PR',
      (tester) async {
    final calls = <String>[];
    await tester.pumpWidget(_host([
      _session('old', 'wren', {
        'last_active': _sec(_now.subtract(const Duration(hours: 5))),
        'pr': {'number': 12, 'state': 'open'},
      }),
      _session('new', 'wren', {
        'pr': {'number': 280, 'state': 'open', 'title': 'Notch idle CPU'},
      }),
      _session('merged', 'wren', {
        'pr': {'number': 300, 'state': 'merged'},
      }),
    ], calls: calls));
    expect(find.text('PR #280 ready'), findsOneWidget);
    expect(find.text('PR #12 ready'), findsNothing);
    await tester.tap(find.text('Review'));
    await tester.tap(find.text('Merge'));
    expect(calls, ['review:new', 'merge:new']);
  });

  testWidgets('running step and next wake lines', (tester) async {
    final opened = <String>[];
    await tester.pumpWidget(_host([
      _running(),
      _session('w1', 'sol', {
        'title': 'X check-in',
        'status': 'idle',
        'next_wake_at': _sec(DateTime(2026, 11, 16, 17, 0)),
      }),
      _session('w2', 'sol', {
        'title': 'Later',
        'next_wake_at': _sec(DateTime(2026, 11, 17, 9, 0)),
      }),
    ], opened: opened));
    expect(find.text('Moss · Staging deploy, plan 4/6'), findsOneWidget);
    expect(find.text('11m'), findsOneWidget);
    expect(find.text('Next: Sol, X check-in, 17:00'), findsOneWidget);
    expect(find.text('in 9 h'), findsOneWidget);
    await tester.tap(find.text('Next: Sol, X check-in, 17:00'));
    expect(opened, ['w1']);
  });

  testWidgets('lines without data are omitted', (tester) async {
    await tester.pumpWidget(_host([_asking()]));
    expect(find.textContaining('ready'), findsNothing);
    expect(find.textContaining('step'), findsNothing);
    expect(find.textContaining('Next:'), findsNothing);
    expect(find.text('Approve'), findsOneWidget);
  });

  testWidgets('stage shows at most five agents', (tester) async {
    final many = [for (var i = 0; i < 7; i++) _agent('a$i', 'Agent$i')];
    rememberAgentCharacters([for (var i = 0; i < 7; i++) ('a$i', '0${i + 1}')]);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: PhoneHero(
          now: _now,
          agents: many,
          sessions: [
            for (var i = 0; i < 7; i++)
              _session('r$i', 'a$i', {'status': 'running', 'running': true}),
          ],
          onOpenSession: (_) {},
        ),
      ),
    ));
    expect(find.bySemanticsLabel(RegExp(r'^Agent\d is working$')),
        findsNWidgets(5));
  });
}
