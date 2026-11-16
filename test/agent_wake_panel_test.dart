import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/models.dart';
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
    expect(find.textContaining(RegExp(r'^(today|tomorrow) \d\d:\d\d$')),
        findsOneWidget);
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

  phone('named wakes switch, save and clear by name', (tester) async {
    final c = FakeWakeClient(wakeState: WakeSchedule.fromJson(wakeJson()));
    c.named['linkedin-sync'] = WakeSchedule.fromJson({
      ...wakeJson(name: 'linkedin-sync'),
      'schedule': 'daily 21:00',
      'schedule_text': 'Daily at 21:00',
      'report': {
        'to': 'group',
        'group': 'group:abc',
        'task_id': null,
        'only_on_change': false
      },
    });
    await _pump(tester, _panel(c));
    expect(find.byKey(const ValueKey('wake-switcher')), findsOneWidget);
    expect(find.text('Default'), findsOneWidget);
    expect(find.text('New wake'), findsOneWidget);
    expect(find.text('Weekdays at 09:00'), findsOneWidget);

    await tester.tap(find.text('linkedin-sync'));
    await tester.pumpAndSettle();
    expect(find.text('Daily at 21:00'), findsOneWidget);
    // The Reports to line and the checked Report to row.
    expect(find.text('Group'), findsNWidgets(2));

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(c.puts.last['name'], 'linkedin-sync');
    expect((c.puts.last['report'] as Map)['group'], 'group:abc');
    expect(find.text('daily 21:00'), findsOneWidget);

    await tester.tap(find.text('Edit'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove'));
    await tester.pumpAndSettle();
    expect(c.clearedNames, ['linkedin-sync']);
    expect(find.text('Weekdays at 09:00'), findsOneWidget);
  });

  test('wake names slug like the daemon', () {
    expect(wakeNameSlug('  LinkedIn Sync! '), 'linkedin-sync');
    expect(wakeNameSlug('--'), '');
  });

  phone('overview lists wakes with agent names', (tester) async {
    final c = FakeWakeClient(
      wakeState: WakeSchedule.fromJson(wakeJson(lastError: 'Session was busy')),
      warmState: KeepWarmEntry.fromJson(keepWarmJson()),
    );
    await _pump(tester, WakesScreen(client: c, embedded: true), scroll: false);
    expect(find.text('Revenue Scout'), findsOneWidget);
    expect(find.byKey(const ValueKey('wake-scout')), findsOneWidget);
    // Keep warm is its own page now.
    expect(find.byKey(const ValueKey('warm-scout')), findsNothing);
    expect(find.textContaining('Session was busy'), findsOneWidget);
  });

  phone('keep warm page lists only warm sessions', (tester) async {
    final c = FakeWakeClient(
      wakeState: WakeSchedule.fromJson(wakeJson()),
      warmState: KeepWarmEntry.fromJson(keepWarmJson()),
    );
    await _pump(tester, WakesScreen(client: c, embedded: true, keepWarm: true),
        scroll: false);
    expect(find.byKey(const ValueKey('warm-scout')), findsOneWidget);
    expect(find.byKey(const ValueKey('wake-scout')), findsNothing);
  });

  phone('a conversation kept warm shows its title and a readable reason',
      (tester) async {
    const id = 'snippet-mobile-8f8d/conversations/abc';
    final c = FakeWakeClient(
      warmState: KeepWarmEntry.fromJson(keepWarmJson(
          owner: id,
          ownerKind: 'session',
          sessionId: id,
          skipped: 'quiet hours')),
    )..sessionList = [
        SessionInfo.fromJson({'id': id, 'title': 'Wave 2 merge'})
      ];
    await _pump(tester, WakesScreen(client: c, embedded: true, keepWarm: true),
        scroll: false);
    expect(find.text('Wave 2 merge'), findsOneWidget);
    expect(find.text('Paused for quiet hours'), findsOneWidget);
    expect(find.textContaining('snippet-mobile-8f8d'), findsNothing);
    expect(find.text('0 warms'), findsNothing);
    expect(find.text('No wakes yet'), findsNothing);

    await tester.tap(find.text('Wave 2 merge'));
    await tester.pumpAndSettle();
    // The row action and the menu entry both read Open conversation.
    expect(find.text('Open conversation'), findsNWidgets(2));
    await tester.tap(find.text('Stop keeping warm'));
    await tester.pumpAndSettle();
    expect(c.warmPuts.single['enabled'], isFalse);
  });

  phone('with no schedules the empty state shows',
      (tester) async {
    final c = FakeWakeClient();
    await _pump(tester, WakesScreen(client: c, embedded: true), scroll: false);
    expect(find.text('No wakes yet'), findsOneWidget);
  });
}
