import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/screens/agent_wake_panel.dart';
import 'package:snippet/screens/wakes_screen.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/wake_models.dart';

import 'support/wake_fakes.dart';

Future<void> _pump(WidgetTester tester, Widget child,
    {bool scroll = true}) async {
  freezeWakeClock();
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 1400);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: scroll
          ? SingleChildScrollView(
              padding: const EdgeInsets.all(12), child: child)
          : child,
    ),
  ));
  await tester.pumpAndSettle();
}

AgentWakePanel _panel(FakeWakeClient c) =>
    AgentWakePanel(client: c, owner: 'scout', name: 'Revenue Scout');

void phone(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      await body(tester);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  phone('shows schedule, next and last run, runs, reason and context',
      (tester) async {
    final c = FakeWakeClient(
      wakeState: WakeSchedule.fromJson(wakeJson()),
      warmState: KeepWarmEntry.fromJson(keepWarmJson(
          enabled: true,
          provider:
              'This provider cannot be warmed; its cache is not exposed')),
      runs: sampleRuns(),
    );
    await _pump(tester, _panel(c));
    expect(find.text('Wakes and reporting'), findsOneWidget);
    expect(find.text('Weekdays at 09:00'), findsOneWidget);
    expect(find.textContaining('in 1h'), findsOneWidget);
    expect(find.text('22:00 to 07:00'), findsOneWidget);
    expect(find.text('Recent runs'), findsOneWidget);
    expect(find.byKey(const ValueKey('run-12')), findsOneWidget);
    expect(find.byKey(const ValueKey('run-11')), findsOneWidget);
    expect(
        find.text('This provider cannot be warmed; its cache is not exposed'),
        findsOneWidget);
    expect(find.text('Context length'), findsNothing);
  });

  phone('no schedule offers to set one', (tester) async {
    final c = FakeWakeClient();
    await _pump(tester, _panel(c));
    expect(find.text('Set schedule'), findsOneWidget);
    expect(find.textContaining('No wake schedule'), findsOneWidget);
    expect(find.text('Context length'), findsNothing);
    expect(
        find.textContaining('Most providers cannot be warmed'), findsOneWidget);
  });

  phone('saving a new schedule sends the wake body', (tester) async {
    final c = FakeWakeClient();
    await _pump(tester, _panel(c));
    await tester.tap(find.text('Set schedule'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'weekdays 09:00');
    await tester.enterText(find.byType(TextField).at(1), 'Check pipeline');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(c.puts, hasLength(1));
    final body = c.puts.single;
    expect(body['schedule'], 'weekdays 09:00');
    expect(body['brief'], 'Check pipeline');
    expect(body['enabled'], isTrue);
    expect(body['report'],
        {'to': 'mission_control', 'task_id': null, 'only_on_change': true});
    expect(find.byKey(const ValueKey('wake-schedule')), findsOneWidget);
  });

  phone('keep-warm toggle calls the daemon', (tester) async {
    final c = FakeWakeClient(wakeState: WakeSchedule.fromJson(wakeJson()));
    await _pump(tester, _panel(c));
    await tester.tap(find.text('Keep prompt cache warm'));
    await tester.pumpAndSettle();
    expect(c.warmPuts.single['enabled'], isTrue);
    expect(find.text('Ping every'), findsOneWidget);
  });

  phone('overview lists wakes with agent names', (tester) async {
    final c = FakeWakeClient(
      wakeState: WakeSchedule.fromJson(wakeJson(lastError: 'Session was busy')),
      warmState: KeepWarmEntry.fromJson(keepWarmJson()),
    );
    await _pump(tester, WakesScreen(client: c, embedded: true), scroll: false);
    expect(find.text('Revenue Scout'), findsNWidgets(2));
    expect(find.byKey(const ValueKey('wake-scout')), findsOneWidget);
    expect(find.byKey(const ValueKey('warm-scout')), findsOneWidget);
    expect(find.textContaining('Session was busy'), findsOneWidget);
  });
}
