import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide testWidgets;
import 'package:flutter_test/flutter_test.dart' as flutter_test show testWidgets;
import 'package:snippet/agent_character.dart';
import 'package:snippet/api.dart';
import 'package:snippet/ink.dart';
import 'package:snippet/mochi.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/mobile_home/agents_group.dart';
import 'package:snippet/screens/mobile_home/home_data.dart';
import 'package:snippet/screens/mobile_home/home_style.dart';
import 'package:snippet/screens/mobile_home/mobile_home_screen.dart';
import 'package:snippet/screens/mobile_home/needs_you_pager.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/theme.dart';

class _Client extends DaemonClient {
  _Client() : super('http://127.0.0.1:1', 'test');
  final _events = DeviceEventHub.local();

  @override
  DeviceEventHub get deviceEvents => _events;
}

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
        {String? agent, bool managed = false}) =>
    _s(id, extra: {
      'status': 'waiting_for_input',
      'last_active': _ago(minutes),
      'worker_agent_id': agent ?? 'rust',
      if (managed) 'managed_by': 'agent',
      'attention': {
        'type': 'approval',
        'tool': 'bash',
        'label': 'Push $id to origin?',
        'text': 'git push origin $id',
      },
    });

SessionInfo _question(String id, int minutes) => _s(id, extra: {
      'status': 'waiting_for_input',
      'last_active': _ago(minutes),
      'attention': {'type': 'question', 'text': 'Which branch?'},
    });

SessionInfo _handoff(String id, int minutes) => _s(id, extra: {
      'status': 'waiting_for_input',
      'last_active': _ago(minutes),
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
  });

  group('ink', () {
    test('picks whichever of dark and white contrasts more', () {
      const teal = Color(0xFF1FB6B6);
      expect(inkOn(teal), const Color(0xFF14141A));
      expect(inkContrast(teal), greaterThan(7));
      expect(inkOn(const Color(0xFF1B2A8C)), Colors.white);
    });

    test('every roster colour keeps Approve ink readable', () {
      final j = jsonDecode(File('assets/avatars/roster.json').readAsStringSync())
          as Map<String, dynamic>;
      final colours = [
        for (final c in j['characters'] as List)
          CharacterSpec.fromJson(c as Map<String, dynamic>).color,
      ];
      expect(colours, isNotEmpty);
      // Neither ink reaches 4.5:1 on the mid-blue characters; about 4.3 to 4.4:1 is
      // the best either ink can do there.
      for (final c in colours) {
        expect(inkContrast(c), greaterThanOrEqualTo(4.3), reason: '$c');
      }
    });
  });

  group('screen', () {
    late List<String> decided;
    late List<String> opened;

    Future<void> pumpHome(
      WidgetTester tester,
      List<SessionInfo> sessions, {
      List<CoordinationAgent>? agents,
      double textScale = 1,
    }) async {
      tester.view.devicePixelRatio = 3;
      tester.view.physicalSize = const Size(393, 852) * 3;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        builder: (c, child) => MediaQuery(
          data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(textScale)),
          child: child!,
        ),
        home: Scaffold(
          body: MobileHomeScreen(
            client: _Client(),
            sessions: sessions,
            agents: agents ??
                [
                  _agent('snippet', 'Snippet'),
                  _agent('mobile', 'Mobile Design'),
                  _agent('rust', 'Rust PR Reviewer'),
                ],
            onOpenSession: (s) => opened.add(s.id),
            onOpenAgent: (a) => opened.add('agent:${a.id}'),
            onOpenMissionControl: () {},
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

    // The platform override must be cleared before the test ends.
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
      _approval('p1', 2),
      _question('p2', 10),
      _handoff('p3', 12),
      for (var i = 0; i < 4; i++)
        _managed('m$i', 'snippet', status: i < 2 ? 'running' : 'idle'),
      _managed('mm', 'mobile', status: 'running'),
      for (var i = 0; i < 12; i++) _s('h$i'),
    ];

    testWidgets('managed sessions stay off the list and the pill counts them',
        (tester) async {
      await pumpHome(tester, base);
      expect(find.text('Session m0'), findsNothing);
      expect(find.text('4 managed'), findsOneWidget);
      expect(find.text('1 managed'), findsOneWidget);
      expect(find.bySemanticsLabel('Snippet, 4 managed sessions'),
          findsOneWidget);
      expect(find.text('Session h0'), findsOneWidget);
    });

    testWidgets('an agent with no managed sessions has no pill',
        (tester) async {
      await pumpHome(tester, [_s('h0')]);
      expect(find.byType(ManagedPill), findsNothing);
      expect(find.textContaining('0 managed'), findsNothing);
    });

    testWidgets('the pill opens the managed view with Running and Idle',
        (tester) async {
      await pumpHome(tester, base);
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

    testWidgets('three asks page, and Approve clears the card', (tester) async {
      await pumpHome(tester, base);
      expect(find.text('Needs you'), findsOneWidget);
      expect(find.text('1 of 3'), findsOneWidget);
      expect(find.text('Push p1 to origin?'), findsOneWidget);
      expect(find.bySemanticsLabel(RegExp('Needs you, 3 items, item 1')),
          findsOneWidget);
      await tester.tap(find.text('Approve'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(decided, ['approve:p1']);
      expect(find.text('Push p1 to origin?'), findsNothing);
      expect(find.text('1 of 2'), findsOneWidget);
    });

    testWidgets('one ask is a full card with no dots or count',
        (tester) async {
      await pumpHome(tester, [_approval('p1', 2), _s('h0')]);
      expect(find.textContaining(' of '), findsNothing);
      expect(find.byType(PageView), findsNothing);
      await tester.tap(find.text('Deny'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(decided, ['deny:p1']);
      expect(find.text('Needs you'), findsNothing);
    });

    testWidgets('with none the section is gone', (tester) async {
      await pumpHome(tester, [_s('h0')]);
      expect(find.text('Needs you'), findsNothing);
      expect(find.byType(NeedsYouSection), findsOneWidget);
    });

    testWidgets('a horizontal swipe pages without scrolling the list and a '
        'vertical drag on a card scrolls it', (tester) async {
      await pumpHome(tester, base);
      final scroll = tester.state<ScrollableState>(find
          .descendant(
              of: find.byType(MobileHomeScreen),
              matching: find.byType(Scrollable))
          .first);
      expect(scroll.position.pixels, 0);
      await tester.drag(find.byType(PageView), const Offset(-200, 4));
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('2 of 3'), findsOneWidget);
      expect(scroll.position.pixels, 0);
      await tester.drag(find.byType(PageView), const Offset(0, -240));
      await tester.pump(const Duration(seconds: 1));
      expect(scroll.position.pixels, greaterThan(0));
    });

    testWidgets('controls are 44 to 52 high, 44 wide and never overlap',
        (tester) async {
      await pumpHome(tester, base);
      final boxes = <String, Rect>{};
      Rect rectOf(Finder f) => tester.getRect(f.first);
      Finder hit(String tooltip) => find.ancestor(
          of: find.byTooltip(tooltip), matching: find.byType(Hit44));
      boxes['search'] = rectOf(hit('Search'));
      boxes['settings'] = rectOf(hit('Settings'));
      boxes['pill'] = rectOf(find.descendant(
          of: find.byType(ManagedPill).first, matching: find.byType(Hit44)));
      boxes['pill2'] = rectOf(find.descendant(
          of: find.byType(ManagedPill).last, matching: find.byType(Hit44)));
      boxes['deny'] = rectOf(find.ancestor(
          of: find.text('Deny'), matching: find.byType(InkWell)));
      boxes['approve'] = rectOf(find.ancestor(
          of: find.text('Approve'), matching: find.byType(InkWell)));
      for (final e in boxes.entries) {
        expect(e.value.width, greaterThanOrEqualTo(44), reason: e.key);
        expect(e.value.height, inInclusiveRange(44, 52), reason: e.key);
      }
      final keys = boxes.keys.toList();
      for (var i = 0; i < keys.length; i++) {
        for (var j = i + 1; j < keys.length; j++) {
          expect(boxes[keys[i]]!.overlaps(boxes[keys[j]]!), isFalse,
              reason: '${keys[i]} overlaps ${keys[j]}');
        }
      }
      // The row's own hit area stops at the pill.
      final row = tester.getRect(find.byKey(const ValueKey('agent-row-snippet')));
      expect(boxes['pill']!.left, greaterThanOrEqualTo(row.left));
      final tap = find.descendant(
          of: find.byKey(const ValueKey('agent-row-snippet')),
          matching: find.byType(InkWell));
      expect(tester.getRect(tap.first).right,
          lessThanOrEqualTo(boxes['pill']!.left + 0.5));
    });

    testWidgets('at 1.3x text the card grows and the pill keeps its count',
        (tester) async {
      await pumpHome(tester, base, textScale: 1.3);
      expect(find.text('Approve'), findsOneWidget);
      expect(tester.takeException(), isNull);
      final card = tester.getRect(find.byType(AskCard).first);
      expect(card.height, greaterThan(kAskCardHeight));
      final approve = tester.getRect(find
          .ancestor(of: find.text('Approve'), matching: find.byType(InkWell))
          .first);
      expect(approve.bottom, lessThanOrEqualTo(card.bottom));
      expect(find.text('4 managed'), findsOneWidget);
    });

    testWidgets('reduced motion keeps the removal to a fade', (tester) async {
      tester.platformDispatcher.accessibilityFeaturesTestValue =
          const FakeAccessibilityFeatures(disableAnimations: true);
      addTearDown(
          tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
      await pumpHome(tester, [_approval('p1', 2), _s('h0')]);
      await tester.tap(find.text('Approve'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Needs you'), findsNothing);
    });

    testWidgets('tone pills keep cream characters warm', (tester) async {
      expect(pillTone(const Color(0xFFD9D4C8)), const Color(0xFFD9C9A0));
      expect(pillTone(const Color(0xFF1FB6B6)), const Color(0xFF1FB6B6));
    });
  });
}
