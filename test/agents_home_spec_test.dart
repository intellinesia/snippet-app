import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/mobile_home/agents_home.dart';
import 'package:snippet/screens/mobile_home/all_agents_phone.dart';
import 'package:snippet/screens/mobile_home/quiet_home.dart';
import 'package:snippet/screens/phone_agent_page.dart';
import 'package:snippet/theme.dart';

class _Client extends DaemonClient {
  _Client() : super('http://127.0.0.1:9', 'tok');
}

CoordinationAgent _agent(String id, {bool lead = false}) =>
    CoordinationAgent.fromJson({
      'id': id,
      'display_name': 'Agent $id with a long name',
      'handle': id,
      'status': 'active',
      if (lead) 'kind': 'lead',
    });

SessionInfo _session(String id, String agent, String status,
        {Map<String, dynamic>? attention}) =>
    SessionInfo.fromJson({
      'id': id,
      'agent_id': agent,
      'title': 'Task for $agent',
      'status': status,
      'running': status == 'running',
      'last_active': DateTime.now().millisecondsSinceEpoch ~/ 1000 - 300,
      if (attention != null) 'attention': attention,
    });

final _agents = [
  _agent('lead', lead: true),
  for (var i = 1; i <= 9; i++) _agent('a$i'),
];
final _sessions = [
  for (var i = 1; i <= 5; i++) _session('s$i', 'a$i', 'running'),
  _session('q1', 'a6', 'waiting_for_input',
      attention: {'type': 'question', 'text': 'Should I ship the build?'}),
  _session('q2', 'a7', 'waiting_for_input',
      attention: {'type': 'question', 'text': 'Which branch do you want?'}),
];
final _groups = [
  GroupSummary.fromJson({
    'id': 'g1',
    'title': 'Canvas review',
    'members': [
      {'agent_id': 'a1'},
      {'agent_id': 'a2'}
    ],
  }),
];

Future<void> _pump(WidgetTester t, Widget child, double w, double scale) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = Size(w, 2400);
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  await t.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    builder: (c, ch) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: ch!),
    home: Scaffold(body: SafeArea(child: child)),
  ));
  await t.pump(const Duration(milliseconds: 100));
}

void _spec(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (t) async {
    try {
      await body(t);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  final report = <String>[];
  tearDownAll(() {
    // ignore: avoid_print
    for (final l in report) print(l);
  });

  for (final w in [360.0, 393.0, 430.0]) {
    for (final scale in [1.0, 1.35, 2.0]) {
      _spec('Home at $w x $scale', (t) async {
        addTearDown(t.view.reset);
        final sem = t.ensureSemantics();
        await _pump(
            t,
            QuietHomeScreen(
              sessions: _sessions,
              agents: _agents,
              groups: _groups,
              onOpenSession: (_) {},
              onOpenSessions: () {},
              onSettings: () {},
              onSearch: () {},
              onAllAgents: () {},
            ),
            w,
            scale);
        expect(t.takeException(), isNull);
        final content = w - 32;
        final cards = find.byType(AgentCard);
        expect(cards, findsNWidgets(4));
        final c0 = t.getSize(cards.first);
        final big = scale >= 1.35;
        expect(c0.width, closeTo(big ? content : (content - 10) / 2, 0.6));
        expect(c0.height, greaterThanOrEqualTo(138));
        for (final c in cards.evaluate()) {
          expect(t.getSize(find.byWidget(c.widget)).height,
              greaterThanOrEqualTo(138));
        }
        for (final chip in find.byType(StateChip).evaluate()) {
          expect(t.getSize(find.byWidget(chip.widget)).height, 44);
        }
        expect(find.byType(StateChip), findsNWidgets(4));
        expect(find.byKey(const ValueKey('chip-amber-dot')), findsOneWidget);
        final ask = t.getSize(find.byKey(const ValueKey('ask-card')).first);
        expect(ask.width, closeTo(content, 0.6));
        expect(ask.height, greaterThanOrEqualTo(82));
        expect(find.text('1 of 2'), findsOneWidget);
        final foot = t.getSize(find.byKey(const ValueKey('home-footer')));
        expect(foot.width, closeTo(content, 0.6));
        expect(foot.height, greaterThanOrEqualTo(50));
        final search = t.getSize(find.bySemanticsLabel('Search'));
        final settings = t.getSize(find.bySemanticsLabel('Settings'));
        expect(search, const Size(48, 48));
        expect(settings, const Size(48, 48));
        for (final r in find.byType(MarkRow).evaluate()) {
          expect(t.getSize(find.byWidget(r.widget)).height,
              greaterThanOrEqualTo(56));
          expect(t.getSize(find.byWidget(r.widget)).width, w);
        }
        expect(find.byType(MarkRow).evaluate().length, lessThanOrEqualTo(4));
        final sizes = [
          for (final e in find.text('Agents').evaluate())
            (e.widget as Text).style!.fontSize
        ];
        expect(sizes, contains(28));
        report.add(
            'HOME w=$w s=$scale card=$c0 ask=$ask footer=$foot search=$search');
        sem.dispose();
      });

      _spec('All agents at $w x $scale', (t) async {
        addTearDown(t.view.reset);
        final sem = t.ensureSemantics();
        await _pump(
            t,
            QuietAgentsScreen(
              client: _Client(),
              agents: _agents,
              sessions: _sessions,
              groups: _groups,
              onOpenAgent: (_) {},
              onOpenLead: () {},
            ),
            w,
            scale);
        expect(t.takeException(), isNull);
        expect(t.getSize(find.bySemanticsLabel('Back')), const Size(48, 48));
        expect(t.getSize(find.bySemanticsLabel('Search')), const Size(48, 48));
        expect(find.text('All 10'), findsOneWidget);
        expect(find.text('Working 5'), findsOneWidget);
        expect(find.text('Idle 3'), findsOneWidget);
        expect(find.text('Asking 2'), findsOneWidget);
        expect(find.text('10 agents, 1 group'), findsOneWidget);
        for (final chip in find.byType(StateChip).evaluate()) {
          expect(t.getSize(find.byWidget(chip.widget)).height, 44);
        }
        for (final r in find.byType(MarkRow).evaluate()) {
          final s = t.getSize(find.byWidget(r.widget));
          expect(s.height, greaterThanOrEqualTo(56));
          expect(s.width, w);
        }
        // 8 rows then a fold of 2.
        expect(find.byType(MarkRow), findsNWidgets(8));
        expect(find.text('Show 2 more'), findsOneWidget);
        await t.tap(find.text('Show 2 more'));
        await t.pump();
        expect(find.byType(MarkRow), findsNWidgets(10));
        await t.tap(find.text('Working 5'));
        await t.pump();
        expect(find.byType(MarkRow), findsNWidgets(5));
        await t.tap(find.text('Idle 3'));
        await t.pump();
        expect(find.byType(MarkRow), findsNWidgets(3));
        await t.tap(find.text('Groups'));
        await t.pump();
        expect(find.text('Groups 1'), findsOneWidget);
        final g = t.getSize(find.byType(MarkRow).first);
        expect(g.height, greaterThanOrEqualTo(68));
        report.add('ALL w=$w s=$scale row=$g');
        sem.dispose();
      });
    }
  }

  _spec('Empty Home shows one line and one 48 high button', (t) async {
    addTearDown(t.view.reset);
    await _pump(
        t,
        QuietHomeScreen(
          sessions: const [],
          agents: const [],
          onOpenSession: (_) {},
          onOpenSessions: () {},
          onSettings: () {},
          onSearch: () {},
        ),
        393,
        1);
    expect(find.text('No agents yet'), findsOneWidget);
    final b = t.getSize(find.byKey(const ValueKey('empty-new-agent')));
    expect(b, const Size(361, 48));
    expect(find.byType(StateChip), findsNothing);
  });

  for (final w in [360.0, 393.0, 430.0]) {
    for (final scale in [1.0, 2.0]) {
      _spec('Profile tiles and rows at $w x $scale', (t) async {
        addTearDown(t.view.reset);
        await _pump(
            t,
            Column(children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(children: [
                  Expanded(child: ProfileTile('chat', 'Chat', onTap: () {})),
                  const SizedBox(width: 8),
                  Expanded(child: ProfileTile('task', 'Tasks', onTap: () {})),
                  const SizedBox(width: 8),
                  Expanded(child: ProfileTile('clock', 'Wake', onTap: () {})),
                ]),
              ),
              ProfileRow('Profile', 'Quiet reviewer, 200k context and a long tail',
                  onTap: () {}),
            ]),
            w,
            scale);
        expect(t.takeException(), isNull);
        final tile = t.getSize(find.byType(ProfileTile).first);
        expect(tile.width, closeTo((w - 32 - 16) / 3, 0.6));
        expect(tile.height, greaterThanOrEqualTo(56));
        expect(t.getSize(find.byType(ProfileRow)).height,
            greaterThanOrEqualTo(48));
        report.add('PROFILE w=$w s=$scale tile=$tile');
      });
    }
  }
}
