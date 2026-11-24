import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide testWidgets;
import 'package:flutter_test/flutter_test.dart' as flutter_test
    show testWidgets;
import 'package:snippet/api.dart';
import 'package:snippet/ink.dart';
import 'package:snippet/mochi.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/mobile_home/agents_group.dart';
import 'package:snippet/screens/mobile_home/everyone_sheet.dart';
import 'package:snippet/screens/mobile_home/home_data.dart';
import 'package:snippet/screens/mobile_home/home_style.dart';
import 'package:snippet/screens/mobile_home/mobile_home_screen.dart';
import 'package:snippet/screens/mobile_home/one_thing_ask.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/theme.dart';

class _Client extends DaemonClient {
  _Client({this.mockGroups = const []}) : super('http://127.0.0.1:1', 'test');
  final List<GroupSummary> mockGroups;
  final _events = DeviceEventHub.local();

  @override
  DeviceEventHub get deviceEvents => _events;

  @override
  Future<List<GroupSummary>> groups() async => mockGroups;
}

GroupSummary _group(
  String id,
  String title, {
  List<String> agentIds = const ['snippet', 'mobile'],
  String? lastEventAt,
  String? createdAt,
  int unread = 0,
  String? previewBody,
  String previewFrom = 'snippet',
  List<String> replying = const [],
}) =>
    GroupSummary.fromJson({
      'id': id,
      'title': title,
      'members': [
        {'kind': 'human', 'id': 'human'},
        for (final a in agentIds) {'kind': 'agent', 'id': a},
      ],
      if (lastEventAt != null) 'last_event_at': lastEventAt,
      'created_at': createdAt ?? '2026-11-22T10:00:00Z',
      'unread': unread,
      if (previewBody != null)
        'last_message': {
          'from_kind': previewFrom == 'human' ? 'human' : 'agent',
          'from_id': previewFrom,
          'body': previewBody,
        },
      'replying': replying,
    });

final _now = DateTime.now();
int _ago(int minutes) =>
    _now.subtract(Duration(minutes: minutes)).millisecondsSinceEpoch ~/ 1000;

SessionInfo _s(String id, {Map<String, dynamic> extra = const {}}) =>
    SessionInfo.fromJson({
      'id': id,
      'title': 'Session $id',
      'folder': '/work/$id',
      'status': 'idle',
      'last_active': _ago(30),
      ...extra,
    });

SessionInfo _approval(String id, int minutes,
        {String? agent, bool managed = false, String? label}) =>
    _s(id, extra: {
      'status': 'waiting_for_input',
      'last_active': _ago(minutes),
      'worker_agent_id': agent ?? 'rust',
      if (managed) 'managed_by': 'agent',
      'attention': {
        'type': 'approval',
        'tool': 'bash',
        'label': label ?? 'Push fix/$id to origin?',
        'text': 'git push origin fix/$id',
      },
    });

SessionInfo _question(String id, int minutes, {String agent = 'rust'}) =>
    _s(id, extra: {
      'status': 'waiting_for_input',
      'last_active': _ago(minutes),
      'worker_agent_id': agent,
      'attention': {'type': 'question', 'text': 'Which branch?'},
    });

SessionInfo _handoff(String id, int minutes, {String agent = 'rust'}) =>
    _s(id, extra: {
      'status': 'waiting_for_input',
      'last_active': _ago(minutes),
      'worker_agent_id': agent,
      'attention': {'type': 'handoff', 'text': 'Take over the review'},
    });

SessionInfo _managed(String id, String owner,
        {bool worker = true, bool settled = false, String status = 'idle'}) =>
    _s(id, extra: {
      'managed_by': 'agent',
      if (worker) 'worker_agent_id': owner else 'owner_agent_id': owner,
      'status': status,
      'running': status == 'running',
      'settled': settled,
    });

CoordinationAgent _agent(String id, String name) =>
    CoordinationAgent.fromJson({'id': id, 'display_name': name});

void main() {
  setUp(() => rememberAgentCharacters(const []));

  group('data rules', () {
    test('managed_by parses and defaults to human', () {
      expect(_s('a').managedBy, 'human');
      expect(_s('a').agentManaged, isFalse);
      expect(_managed('b', 'snippet').agentManaged, isTrue);
    });

    test('sheet settles on a quarter of the travel or a gentle fling', () {
      bool go(double p, double up, bool open) =>
          sheetSettlesOpen(progress: p, up: up, wasOpen: open);
      expect(go(0.3, 0, false), isTrue);
      expect(go(0.2, 0, false), isFalse);
      expect(go(0.1, 400, false), isTrue);
      expect(go(0.7, 0, true), isFalse);
      expect(go(0.8, 0, true), isTrue);
      expect(go(0.9, -400, true), isFalse);
    });

    test('agent rows run latest activity first, name breaks ties', () {
      final rows = agentRows(
        [_agent('a', 'Alpha'), _agent('b', 'Bravo'), _agent('c', 'Charlie')],
        [
          _s('x', extra: {'worker_agent_id': 'c', 'last_active': _ago(5)}),
          _s('y', extra: {'worker_agent_id': 'a', 'last_active': _ago(500)}),
        ],
      );
      expect([for (final r in rows.asleep) r.agent.id], ['c', 'a', 'b']);
    });

    test('managed sessions group on worker then owner and skip settled', () {
      final by = managedByAgent([
        _managed('a', 'snippet'),
        _managed('b', 'snippet'),
        _managed('c', 'mobile', worker: false),
        _managed('d', 'snippet', settled: true),
        _s('human', extra: {'worker_agent_id': 'snippet'}),
      ]);
      expect(by.keys.toSet(), {'snippet', 'mobile'});
      expect(by['snippet']!.length, 2);
      expect(by['mobile']!.single.id, 'c');
    });

    test('the Sessions list holds only human sessions not shown as asks', () {
      final r = humanSessions([
        _s('h1'),
        _s('h2', extra: {'settled': true}),
        _managed('m', 'snippet'),
        _approval('ask', 3),
      ]);
      expect([for (final s in r.main) s.id], ['h1']);
      expect([for (final s in r.settled) s.id], ['h2']);
    });

    test('Needs you runs approvals, questions, handoffs, newest first', () {
      final items = needsYouItems([
        _handoff('h', 1),
        _question('q-old', 20),
        _approval('a-old', 30),
        _question('q-new', 5),
        _approval('a-managed', 2, managed: true),
        _s('quiet'),
      ]);
      expect([for (final i in items) i.id],
          ['a-managed', 'a-old', 'q-new', 'q-old', 'h']);
      expect(items.first.session.agentManaged, isTrue);
    });

    test('askHeadlineSpans italicises branch names and code tokens', () {
      const base = TextStyle(fontFamily: 'Literata', fontSize: 30);
      final spans = askHeadlineSpans('Push fix/handoff-sweep to origin?', base);
      final texts = [for (final s in spans.cast<TextSpan>()) s.text];
      final styles = [
        for (final s in spans.cast<TextSpan>()) s.style?.fontStyle
      ];
      expect(texts, ['Push ', 'fix/handoff-sweep', ' to origin?']);
      expect(styles, [null, FontStyle.italic, null]);
    });
  });

  group('ink', () {
    test('picks whichever of dark and white contrasts more', () {
      const teal = Color(0xFF1FB6B6);
      expect(inkOn(teal), const Color(0xFF14141A));
      expect(inkContrast(teal), greaterThan(7));
      expect(inkOn(const Color(0xFF1B2A8C)), Colors.white);
    });

    test('every roster colour keeps high-contrast ink readable', () {
      final j =
          jsonDecode(File('assets/avatars/roster.json').readAsStringSync())
              as Map<String, dynamic>;
      final colours = [
        for (final c in j['characters'] as List)
          CharacterSpec.fromJson(c as Map<String, dynamic>).color,
      ];
      expect(colours, isNotEmpty);
      for (final c in colours) {
        expect(inkContrast(c), greaterThanOrEqualTo(4.3), reason: '$c');
      }
    });

    test(
        'sortedGroups orders most recent activity first and breaks ties by title',
        () {
      final groups = sortedGroups([
        _group('b', 'Bravo',
            lastEventAt: '2026-11-22T12:00:00Z',
            createdAt: '2026-11-22T08:00:00Z'),
        _group('a', 'alpha',
            lastEventAt: '2026-11-22T12:00:00Z',
            createdAt: '2026-11-22T08:00:00Z'),
        _group('c', 'Newest',
            lastEventAt: '2026-11-22T14:00:00Z',
            createdAt: '2026-11-22T09:00:00Z'),
        _group('d', 'Created only', createdAt: '2026-11-22T13:00:00Z'),
      ]);
      expect([for (final g in groups) g.id], ['c', 'd', 'a', 'b']);
    });

    test('groupMatchesQuery matches title, preview, and member names or ids',
        () {
      final gc = _group(
        'g1',
        'scrapper bois',
        agentIds: const ['crawler', 'rust'],
        previewBody: 'Proxy rotation landed',
      );
      const names = {'crawler': 'Scraper Bot', 'rust': 'Rust PR Reviewer'};
      expect(groupMatchesQuery(gc, '', agentNames: names), isTrue);
      expect(groupMatchesQuery(gc, 'SCRAPPER', agentNames: names), isTrue);
      expect(
          groupMatchesQuery(gc, 'proxy rotation', agentNames: names), isTrue);
      expect(groupMatchesQuery(gc, 'crawler', agentNames: names), isTrue);
      expect(groupMatchesQuery(gc, 'PR Reviewer', agentNames: names), isTrue);
      expect(groupMatchesQuery(gc, 'unrelated', agentNames: names), isFalse);
    });
  });

  group('One thing screen', () {
    late List<String> decided;
    late List<String> opened;

    Future<void> pumpHome(
      WidgetTester tester,
      List<SessionInfo> sessions, {
      List<CoordinationAgent>? agents,
      List<GroupSummary> groups = const [],
      double textScale = 1,
    }) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(393, 852) * 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c)
              .copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: MobileHomeScreen(
            client: _Client(mockGroups: groups),
            sessions: sessions,
            agents: agents ??
                [
                  _agent('snippet', 'Snippet'),
                  _agent('mobile', 'Mobile Design'),
                  _agent('rust', 'Rust PR Reviewer'),
                ],
            onOpenSession: (s) => opened.add(s.id),
            onOpenAgent: (a) => opened.add('agent:${a.id}'),
            onOpenLead: () => opened.add('lead'),
            onSettings: () {},
            onPlus: (_) {},
            onDecide: (s, ok) async {
              decided.add('${ok ? 'approve' : 'deny'}:${s.id}');
              return true;
            },
          ),
        ),
      ));
      await tester.pump(const Duration(milliseconds: 300));
    }

    setUp(() {
      decided = [];
      opened = [];
    });

    void testWidgets(String name, Future<void> Function(WidgetTester) body) =>
        flutter_test.testWidgets(name, (tester) async {
          debugDefaultTargetPlatformOverride = TargetPlatform.android;
          try {
            await body(tester);
          } finally {
            debugDefaultTargetPlatformOverride = null;
          }
        });

    final base = [
      _approval('p1', 2, managed: true),
      _question('p2', 10),
      _handoff('p3', 12),
      for (var i = 0; i < 4; i++)
        _managed('m$i', 'snippet', status: i < 2 ? 'running' : 'idle'),
      _managed('mm', 'mobile', status: 'running'),
      for (var i = 0; i < 6; i++) _s('h$i'),
    ];

    testWidgets(
        'quiet state rests cleanly with bare top bar and Everyone handle',
        (tester) async {
      await pumpHome(tester, [_s('h0')]);
      expect(find.text('Snippet'), findsOneWidget);
      expect(find.text('All quiet'), findsOneWidget);
      expect(find.byType(OneThingAsk), findsNothing);
      expect(find.text('Session h0'), findsNothing);
      expect(find.byKey(const ValueKey('everyone-handle')), findsOneWidget);
      expect(find.text('Everyone'), findsOneWidget);
    });

    testWidgets(
        'busy state centres the top ask (even managed), Approve advances and 2 more cycles',
        (tester) async {
      await pumpHome(tester, base);
      // The header status and the strip under the ask both say it.
      expect(find.text('2 working'), findsNWidgets(2));
      expect(find.text('Rust PR Reviewer asks'), findsOneWidget);
      expect(find.text('Push fix/p1 to origin?', findRichText: true),
          findsOneWidget);
      // No kind pills or command boxes on the resting home.
      expect(find.text('Approval'), findsNothing);
      expect(find.byKey(const ValueKey('ask-command')), findsNothing);
      // Sessions and agents stay tucked in Everyone.
      expect(find.text('Session h0'), findsNothing);
      expect(find.text('2 more'), findsOneWidget);

      // Tapping "2 more" cycles to the next ask (question).
      await tester.tap(find.text('2 more'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Which branch?', findRichText: true), findsOneWidget);
      expect(find.text('Answer'), findsOneWidget);

      // Swipe right returns to the approval ask.
      await tester.fling(find.byType(OneThingAsk), const Offset(200, 0), 800);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.text('Approve'), findsOneWidget);

      // Approving removes it and updates the remaining count to "1 more".
      await tester.tap(find.text('Approve'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(decided, ['approve:p1']);
      expect(find.text('1 more'), findsOneWidget);
      expect(find.text('Which branch?', findRichText: true), findsOneWidget);
    });

    testWidgets('denying the last ask settles cleanly into Quiet state',
        (tester) async {
      await pumpHome(tester, [_approval('p1', 2), _s('h0')]);
      expect(find.text('1 more'), findsNothing);
      await tester.tap(find.text('Deny'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(decided, ['deny:p1']);
      expect(find.byType(OneThingAsk), findsOneWidget);
      expect(find.text('Approve'), findsNothing);
      expect(find.text('Deny'), findsNothing);
    });

    test('folds default: Asleep open, Settled closed, search opens Settled',
        () {
      expect(asleepOpenFor(null), isTrue);
      expect(asleepOpenFor(false), isFalse);
      expect(settledOpenFor(null), isFalse);
      expect(settledOpenFor(true), isTrue);
      expect(settledOpenFor(null, searching: true), isTrue);
    });

    testWidgets('with only settled sessions, Settled stays a collapsed fold',
        (tester) async {
      await pumpHome(tester, [
        for (var i = 0; i < 6; i++) _s('old$i', extra: {'settled': true}),
      ]);
      await tester.tap(find.byKey(const ValueKey('everyone-handle')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const ValueKey('settled-fold')), findsOneWidget);
      expect(find.byKey(const ValueKey('session-row-old0')), findsNothing);
      final asleep =
          tester.getTopLeft(find.byKey(const ValueKey('asleep-fold'))).dy;
      final settled =
          tester.getTopLeft(find.byKey(const ValueKey('settled-fold'))).dy;
      expect(asleep, lessThan(settled));
      await tester.tap(find.byKey(const ValueKey('settled-fold')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byKey(const ValueKey('session-row-old0')), findsOneWidget);
    });

    testWidgets('Back closes the Everyone sheet before anything else',
        (tester) async {
      await pumpHome(tester, base);
      await tester.tap(find.byKey(const ValueKey('everyone-handle')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(EveryoneSheet), findsOneWidget);

      final nav = Navigator.of(tester.element(find.byType(EveryoneSheet)));
      expect(await nav.maybePop(), isTrue);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 900));
      expect(find.byType(EveryoneSheet), findsNothing);
    });

    testWidgets('working state fits a 360 dp phone at large text',
        (tester) async {
      await pumpHome(
          tester,
          [
            _s('w1', extra: {
              'status': 'running',
              'running': true,
              'worker_agent_id': 'snippet',
              'plan': {
                'done': 1,
                'total': 4,
                'current': 'Design merged Wakes page (phone + desktop)'
              },
            }),
            _managed('m1', 'snippet', status: 'running'),
          ],
          textScale: 1.3);
      tester.view.physicalSize = const Size(360, 740) * 3;
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.textContaining('is working'), findsOneWidget);
      expect(find.text('1 of 4 done'), findsOneWidget);
      expect(find.text('Last result'), findsNothing);
      expect(tester.takeException(), isNull);
      final top = tester.getTopLeft(find.textContaining('is working')).dy;
      final bar =
          tester.getBottomLeft(find.byKey(const ValueKey('home-stage-bar'))).dy;
      expect(top, greaterThan(bar + 24));
    });

    testWidgets(
        'Everyone pull-up sheet shows Working with managed pills, Your sessions, Asleep, and opens ManagedView',
        (tester) async {
      await pumpHome(tester, base);
      await tester.tap(find.byKey(const ValueKey('everyone-handle')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(find.byType(EveryoneSheet), findsOneWidget);
      expect(find.text('Working'), findsOneWidget);
      expect(find.text('Your sessions'), findsOneWidget);
      expect(find.text('Session h0'), findsOneWidget);
      // Agent-managed sessions never appear as rows under Your sessions (count = 6 human).
      expect(find.text('6'), findsOneWidget);
      expect(find.text('Session m1'), findsNothing);
      expect(find.text('4 managed'), findsOneWidget);
      expect(find.text('1 managed'), findsNWidgets(2));
      expect(
          find.bySemanticsLabel('Snippet, 4 managed sessions'), findsOneWidget);
      // Composer stays on top of the Everyone sheet.
      expect(find.byKey(const ValueKey('home-open-lead')), findsOneWidget);

      // Tapping the managed pill opens ManagedView with Running and Idle.
      await tester.tap(find.text('4 managed'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.text('4 managed sessions'), findsOneWidget);
      expect(find.text('Running'), findsOneWidget);
      expect(find.text('Idle'), findsOneWidget);
      expect(find.text('Session m0'), findsOneWidget);
      expect(find.text('Session mm'), findsNothing);
      expect(find.text('Message Snippet'), findsOneWidget);
    });

    testWidgets('agent with no managed sessions shows no pill in Everyone',
        (tester) async {
      await pumpHome(tester, [_s('h0')]);
      await tester.tap(find.byKey(const ValueKey('everyone-handle')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('asleep-fold')));
      await tester.pumpAndSettle();
      expect(find.byType(ManagedPill), findsNothing);
      expect(find.textContaining('0 managed'), findsNothing);
    });

    testWidgets(
        'Lead button sits inside composer left edge and opens Lead chat directly',
        (tester) async {
      await pumpHome(tester, [_s('h0')]);
      final btn = find.byKey(const ValueKey('home-open-lead'));
      expect(btn, findsOneWidget);
      final rect = tester.getRect(btn);
      expect(rect.width, inInclusiveRange(44, 52));
      expect(rect.height, inInclusiveRange(44, 52));
      expect(find.bySemanticsLabel('Lead, open chat'), findsOneWidget);
      await tester.tap(btn);
      await tester.pump();
      expect(opened, ['lead']);
    });

    testWidgets(
        'controls are 44 to 52 high, at least 44 wide, and never overlap',
        (tester) async {
      await pumpHome(tester, base);
      Rect rectOf(Finder f) => tester.getRect(f.first);
      Finder hit(String tooltip) => find.ancestor(
          of: find.byTooltip(tooltip), matching: find.byType(Hit44));
      final boxes = <String, Rect>{
        'search': rectOf(hit('Search')),
        'settings': rectOf(hit('Settings')),
        'deny': rectOf(find.ancestor(
            of: find.text('Deny'), matching: find.byType(InkWell))),
        'approve': rectOf(find.ancestor(
            of: find.text('Approve'), matching: find.byType(InkWell))),
        'more': rectOf(find.ancestor(
            of: find.text('2 more'), matching: find.byType(InkWell))),
        'everyone': rectOf(find.byKey(const ValueKey('everyone-handle'))),
        'mc': rectOf(find.byKey(const ValueKey('home-open-lead'))),
      };
      for (final e in boxes.entries) {
        expect(e.value.width, greaterThanOrEqualTo(44), reason: e.key);
        // The Everyone handle is a deliberately taller 64 pt pull zone.
        expect(
            e.value.height, inInclusiveRange(44, e.key == 'everyone' ? 64 : 52),
            reason: e.key);
      }
      final keys = boxes.keys.toList();
      for (var i = 0; i < keys.length; i++) {
        for (var j = i + 1; j < keys.length; j++) {
          expect(boxes[keys[i]]!.overlaps(boxes[keys[j]]!), isFalse,
              reason: '${keys[i]} overlaps ${keys[j]}');
        }
      }

      // Check managed pill hit box inside Everyone sheet too.
      await tester.tap(find.byKey(const ValueKey('everyone-handle')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      final pill = rectOf(find.descendant(
          of: find.byType(ManagedPill).first, matching: find.byType(Hit44)));
      expect(pill.width, greaterThanOrEqualTo(44));
      expect(pill.height, inInclusiveRange(44, 52));
      final row =
          tester.getRect(find.byKey(const ValueKey('agent-row-snippet')));
      expect(pill.left, greaterThanOrEqualTo(row.left));
      final tap = find.descendant(
          of: find.byKey(const ValueKey('agent-row-snippet')),
          matching: find.byType(InkWell));
      expect(
          tester.getRect(tap.first).right, lessThanOrEqualTo(pill.left + 0.5));
    });

    testWidgets('at 1.3x text scale ask and Everyone sheet render cleanly',
        (tester) async {
      await pumpHome(tester, base, textScale: 1.3);
      expect(find.text('Approve'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.tap(find.byKey(const ValueKey('everyone-handle')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('4 managed'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('reduced motion keeps ask removal and Everyone sheet calm',
        (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await pumpHome(tester, [_approval('p1', 2), _s('h0')]);
      await tester.tap(find.text('Approve'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.text('Approve'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('everyone-handle')));
      await tester.pump();
      expect(find.byType(EveryoneSheet), findsOneWidget);
    });

    testWidgets('search swaps to pinned pill bar with clear and close',
        (tester) async {
      await pumpHome(tester, base);
      await tester.tap(find.byTooltip('Search'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byKey(const ValueKey('home-search-bar')), findsOneWidget);
      expect(find.byTooltip('Clear search'), findsNothing);
      await tester.enterText(find.byType(TextField).first, 'Snippet');
      await tester.pump();
      expect(find.byTooltip('Clear search'), findsOneWidget);
      await tester.tap(find.byTooltip('Clear search'));
      await tester.pump();
      expect(find.byTooltip('Clear search'), findsNothing);
      await tester.tap(find.byTooltip('Close search'));
      await tester.pump(const Duration(milliseconds: 250));
      expect(find.byKey(const ValueKey('home-stage-bar')), findsOneWidget);
    });

    testWidgets('tone pills keep cream characters warm', (tester) async {
      expect(pillTone(const Color(0xFFD9D4C8)), const Color(0xFFD9C9A0));
      expect(pillTone(const Color(0xFF1FB6B6)), const Color(0xFF1FB6B6));
    });

    testWidgets('Everyone sheet is non-empty when only groups exist',
        (tester) async {
      await pumpHome(
        tester,
        const [],
        agents: const [],
        groups: [
          _group(
            'gc-1',
            'scrapper bois',
            agentIds: const ['snippet', 'rust'],
            lastEventAt:
                _now.subtract(const Duration(minutes: 4)).toIso8601String(),
            unread: 3,
            previewBody: 'Found 42 fresh leads',
          ),
        ],
      );
      await tester.tap(find.byKey(const ValueKey('everyone-handle')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('No sessions yet'), findsNothing);
      expect(find.text('Groups'), findsOneWidget);
      expect(find.text('scrapper bois'), findsOneWidget);
      expect(find.byKey(const ValueKey('group-unread-gc-1')), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const ValueKey('group-unread-gc-1')),
              matching: find.text('3')),
          findsOneWidget);
    });

    testWidgets(
        'Everyone sheet places Groups between Agents and Settled, and search matches groups',
        (tester) async {
      final groups = [
        _group(
          'gc-1',
          'scrapper bois',
          agentIds: const ['snippet', 'rust'],
          lastEventAt:
              _now.subtract(const Duration(minutes: 2)).toIso8601String(),
          unread: 2,
          previewBody: 'Batch crawl finished',
        ),
        _group(
          'gc-2',
          'release crew',
          agentIds: const ['mobile', 'rust'],
          lastEventAt:
              _now.subtract(const Duration(minutes: 9)).toIso8601String(),
          replying: const ['mobile'],
        ),
      ];
      await pumpHome(
        tester,
        [
          _s('old1', extra: {
            'settled': true,
            'settled_at': _ago(180),
          }),
        ],
        groups: groups,
      );
      await tester.tap(find.byKey(const ValueKey('everyone-handle')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      expect(find.text('Groups'), findsOneWidget);
      expect(find.text('scrapper bois'), findsOneWidget);
      expect(find.text('release crew'), findsOneWidget);
      expect(
          find.textContaining('Mobile Design is replying', findRichText: true),
          findsOneWidget);

      final asleepY =
          tester.getTopLeft(find.byKey(const ValueKey('asleep-fold'))).dy;
      final groupsY = tester.getTopLeft(find.text('Groups')).dy;
      final settledY =
          tester.getTopLeft(find.byKey(const ValueKey('settled-fold'))).dy;
      expect(groupsY, greaterThan(asleepY));
      expect(settledY, greaterThan(groupsY));

      // Search finds groups by title and by member name.
      await tester.tap(find.byKey(const ValueKey('everyone-sheet-handle')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));
      await tester.tap(find.byTooltip('Search'));
      await tester.pump(const Duration(milliseconds: 250));
      await tester.enterText(find.byType(TextField).first, 'scrapper');
      await tester.pump();
      expect(find.text('Groups'), findsOneWidget);
      expect(find.text('scrapper bois'), findsOneWidget);
      expect(find.text('release crew'), findsNothing);
    });
  });
}
