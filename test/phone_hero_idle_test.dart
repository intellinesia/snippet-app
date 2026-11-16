import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/ambient_loop.dart';
import 'package:snippet/mochi.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/phone_hero.dart';
import 'package:snippet/theme.dart';

final now = DateTime(2026, 11, 16, 23, 0);
int sec(DateTime d) => d.millisecondsSinceEpoch ~/ 1000;

CoordinationAgent agent(String id, String name) =>
    CoordinationAgent.fromJson({'id': id, 'display_name': name});

SessionInfo session(String id, String agentId, int minutesAgo,
        {DateTime? wake, bool running = false}) =>
    SessionInfo.fromJson({
      'id': id,
      'title': 'Title $id',
      'agent_id': agentId,
      'last_active': sec(now.subtract(Duration(minutes: minutesAgo))),
      if (running) 'status': 'running',
      if (running) 'running': true,
      if (wake != null) 'next_wake_at': sec(wake),
    });

Future<void> pumpHero(WidgetTester t, List<CoordinationAgent> agents,
    List<SessionInfo> sessions,
    {bool reduced = false}) async {
  await t.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: MediaQuery(
      data: MediaQueryData(size: const Size(390, 800), disableAnimations: reduced),
      child: Scaffold(
        body: PhoneHero(
            now: now,
            sessions: sessions,
            agents: agents,
            onOpenSession: (_) {}),
      ),
    ),
  ));
  await t.pump();
}

Future<void> unmount(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  await t.pump(const Duration(seconds: 1));
}

final team = [
  agent('snippet', 'Rook'),
  agent('wren', 'Wren'),
  agent('pip', 'Pip'),
  agent('sol', 'Sol'),
];

void main() {
  setUpAll(() {
    rememberAgentCharacters(
        [('snippet', '01'), ('wren', '05'), ('pip', '11'), ('sol', '22')]);
  });

  group('lead', () {
    testWidgets('is the agent of the most recently active session', (t) async {
      await pumpHero(t, team, [
        session('a', 'snippet', 90),
        session('b', 'pip', 5),
        session('c', 'wren', 30),
      ]);
      expect(find.text('Pip is napping'), findsOneWidget);
      // Others follow by recency: Wren, then Rook; Sol is left off.
      expect(find.text('Wren and Rook too · a message wakes them'),
          findsOneWidget);
      await unmount(t);
    });

    testWidgets('falls back to snippet with no sessions', (t) async {
      await pumpHero(t, [agent('wren', 'Wren'), agent('snippet', 'Rook')], []);
      expect(find.text('Rook is napping'), findsOneWidget);
      await unmount(t);
    });

    testWidgets('falls back to the first agent without snippet', (t) async {
      await pumpHero(t, [agent('wren', 'Wren'), agent('pip', 'Pip')], []);
      expect(find.text('Wren is napping'), findsOneWidget);
      await unmount(t);
    });

    testWidgets('skips sessions of agents not on stage', (t) async {
      await pumpHero(t, [agent('wren', 'Wren'), agent('pip', 'Pip')],
          [session('x', 'ghost', 1), session('y', 'pip', 50)]);
      expect(find.text('Pip is napping'), findsOneWidget);
      await unmount(t);
    });
  });

  group('copy', () {
    testWidgets('three agents', (t) async {
      await pumpHero(t, team.take(3).toList(), []);
      expect(find.text('Rook is napping'), findsOneWidget);
      expect(
          find.text('Wren and Pip too · a message wakes them'), findsOneWidget);
      await unmount(t);
    });

    testWidgets('two agents', (t) async {
      await pumpHero(t, team.take(2).toList(), []);
      expect(find.text('Wren too · a message wakes them'), findsOneWidget);
      await unmount(t);
    });

    testWidgets('one agent', (t) async {
      await pumpHero(t, team.take(1).toList(), []);
      expect(find.text('Rook is napping'), findsOneWidget);
      expect(find.text('A message wakes them'), findsOneWidget);
      await unmount(t);
    });

    testWidgets('a working agent keeps the busy hero', (t) async {
      await pumpHero(t, team, [session('r', 'wren', 1, running: true)]);
      expect(find.byKey(const Key('hero-idle-stage')), findsNothing);
      expect(find.textContaining('is napping'), findsNothing);
      await unmount(t);
    });
  });

  group('next wake', () {
    testWidgets('row shows when a wake is due', (t) async {
      await pumpHero(t, team.take(3).toList(), [
        session('w', 'sol', 120, wake: DateTime(2026, 11, 17, 8, 0)),
      ]);
      expect(find.byKey(const Key('hero-idle-stage')), findsOneWidget);
      expect(find.text('Next: Sol, Title w, 08:00'), findsOneWidget);
      expect(find.text('in 9 h'), findsOneWidget);
      // Below the copy.
      expect(
          t.getTopLeft(find.text('Next: Sol, Title w, 08:00')).dy,
          greaterThan(t
              .getBottomLeft(
                  find.text('Wren and Pip too · a message wakes them'))
              .dy));
      await unmount(t);
    });

    testWidgets('row is absent without a wake', (t) async {
      await pumpHero(t, team.take(3).toList(), [session('a', 'snippet', 10)]);
      expect(find.textContaining('Next:'), findsNothing);
      await unmount(t);
    });

    testWidgets('a past wake does not show', (t) async {
      await pumpHero(t, team.take(3).toList(), [
        session('w', 'sol', 120, wake: now.subtract(const Duration(hours: 1))),
      ]);
      expect(find.textContaining('Next:'), findsNothing);
      await unmount(t);
    });
  });

  group('motion', () {
    testWidgets('no ticker runs when motion is reduced', (t) async {
      await t.runAsync(() => CharacterRoster.load());
      await pumpHero(t, team.take(3).toList(), [], reduced: true);
      await t.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const Key('hero-idle-z')), findsOneWidget);
      expect(AmbientClock.instance.isRunning, isFalse);
      expect(AmbientClock.instance.hasListeners, isFalse);
      expect(t.binding.transientCallbackCount, 0);
      expect(t.binding.hasScheduledFrame, isFalse);
      await unmount(t);
    });

    testWidgets('the clock runs when motion is allowed', (t) async {
      await t.runAsync(() => CharacterRoster.load());
      await pumpHero(t, team.take(3).toList(), []);
      expect(AmbientClock.instance.isRunning, isTrue);
      await unmount(t);
      expect(AmbientClock.instance.isRunning, isFalse);
    });
  });
}
