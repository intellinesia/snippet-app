import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/agent_wake_panel.dart';
import 'package:snippet/screens/session.dart';
import 'package:snippet/screens/wakes_screen.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/wake_models.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';
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

Future<void> _pumpMs(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

class _Socket extends StreamChannelMixin implements WebSocketChannel {
  final _controller = StreamController<dynamic>.broadcast();
  @override
  Stream get stream => _controller.stream;
  @override
  late final WebSocketSink sink = _Sink(_controller.sink);
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
  @override
  String? get protocol => null;
  @override
  Future<void> get ready => Future.value();
}

class _Sink implements WebSocketSink {
  final StreamSink _sink;
  _Sink(this._sink);
  @override
  void add(dynamic data) {}
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future addStream(Stream stream) => Future.value();
  @override
  Future close([int? closeCode, String? closeReason]) => _sink.close();
  @override
  Future get done => _sink.done;
}

void main() {
  group('wake panel', () {
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
      expect(find.textContaining('Most providers cannot be warmed'),
          findsOneWidget);
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
          {'to': 'lead', 'task_id': null, 'only_on_change': true});
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
        wakeState:
            WakeSchedule.fromJson(wakeJson(lastError: 'Session was busy')),
        warmState: KeepWarmEntry.fromJson(keepWarmJson()),
      );
      await _pump(tester, WakesScreen(client: c, embedded: true),
          scroll: false);
      expect(find.text('Revenue Scout'), findsOneWidget);
      expect(find.byKey(const ValueKey('wake-wake-scout')), findsOneWidget);
      // Keep warm is managed on its own page; Wakes only summarises it.
      expect(find.byKey(const ValueKey('warm-scout')), findsNothing);
      expect(find.byKey(const Key('keep-warm-summary')), findsOneWidget);
      expect(find.textContaining('Session was busy'), findsOneWidget);
    });

    phone('keep warm page lists only warm sessions', (tester) async {
      final c = FakeWakeClient(
        wakeState: WakeSchedule.fromJson(wakeJson()),
        warmState: KeepWarmEntry.fromJson(keepWarmJson()),
      );
      await _pump(
          tester, WakesScreen(client: c, embedded: true, keepWarm: true),
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
      await _pump(
          tester, WakesScreen(client: c, embedded: true, keepWarm: true),
          scroll: false);
      expect(find.text('Wave 2 merge'), findsOneWidget);
      expect(find.text('Paused for quiet hours'), findsOneWidget);
      expect(find.textContaining('snippet-mobile-8f8d'), findsNothing);
      expect(find.text('0 warms'), findsNothing);
      expect(find.text('Nothing wakes on its own yet'), findsNothing);

      await tester.tap(find.text('Wave 2 merge'));
      await tester.pumpAndSettle();
      // The row action and the menu entry both read Open conversation.
      expect(find.text('Open conversation'), findsNWidgets(2));
      await tester.tap(find.text('Stop keeping warm'));
      await tester.pumpAndSettle();
      expect(c.warmPuts.single['enabled'], isFalse);
    });

    phone('with no schedules the empty state shows', (tester) async {
      final c = FakeWakeClient();
      await _pump(tester, WakesScreen(client: c, embedded: true),
          scroll: false);
      expect(find.text('Nothing wakes on its own yet'), findsOneWidget);
    });
  });

  group('session wakes action', () {
    testWidgets(
        'session actions list contains Wakes and keep warm for a non-Lead session and opens AgentWakePanel',
        (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      DaemonClient.wsConnector =
          (uri, {connectTimeout, pingInterval}) => _Socket();
      addTearDown(() => DaemonClient.wsConnector = null);
      SharedPreferences.setMockInitialValues({});
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(390, 844);
      addTearDown(tester.view.reset);

      final client = FakeWakeClient();
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: SessionScreen(
          client: client,
          sessionId: 'conv-42',
          title: 'Feature session',
          onMenu: () {},
        ),
      ));
      await _pumpMs(tester);

      await tester.tap(find.text('Feature session').first);
      await _pumpMs(tester);
      expect(find.text('Wakes and schedule'), findsOneWidget);
      expect(
          find.text('Wake times, keep warm, recurring jobs'), findsOneWidget);
      expect(find.text('Automated wakes'), findsNothing);

      await tester.tap(find.text('Wakes and schedule'));
      await _pumpMs(tester);
      final panel = tester.widget<AgentWakePanel>(find.byType(AgentWakePanel));
      expect(panel.owner, 'conv-42');
      expect(panel.name, 'Feature session');

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
      debugDefaultTargetPlatformOverride = null;
    });
  });

  group('wake models', () {
    test('wake schedule view parses every field', () {
      final w = WakeSchedule.fromJson(wakeJson());
      expect(w.owner, 'scout');
      expect(w.scheduleText, 'Weekdays at 09:00');
      expect(w.editableSchedule, 'weekdays 09:00');
      expect(w.quietHours?.label, '22:00 to 07:00');
      expect(w.report.to, 'lead');
      expect(w.report.onlyOnChange, isTrue);
      expect(w.maxRunsPerDay, 24);
      expect(w.lastStatus, 'ok');
      expect(w.lastError, isNull);
      expect(w.utcOffsetMinutes, 60);
    });

    test('a sparse wake view falls back to defaults', () {
      final w = WakeSchedule.fromJson({'owner': 'x', 'quiet_hours': null});
      expect(w.quietHours, isNull);
      expect(w.report.to, 'lead');
      expect(w.enabled, isTrue);
      expect(w.nextRunAt, 0);
      expect(w.lastRunAt, isNull);
    });

    test('wake list reads limits and tolerates junk', () {
      final l = WakeList.fromJson({
        'wakes': [wakeJson(), 'junk'],
        'limits': {
          'min_interval_secs': {'user': 900, 'agent': 1800},
          'default_max_runs_per_day': 12,
          'max_runs_per_day': {'user': 96, 'agent': 12},
        },
      });
      expect(l.wakes, hasLength(1));
      expect(l.limits.minAgentIntervalSecs, 1800);
      expect(l.limits.maxRunsPerDayUser, 96);
      expect(l.limits.defaultMaxRunsPerDay, 12);
    });

    test('keep-warm list sums the seven day spend and keeps reasons', () {
      final l = KeepWarmList.fromJson({
        'entries': [
          keepWarmJson(
              skipped: 'session is not open',
              provider: 'This provider does not support caching'),
        ],
        'limits': {'min_interval_minutes': 2, 'max_interval_minutes': 30},
        'spend_7d': [
          {'calls': 3, 'cache_read_tokens': 1000},
          {'calls': 2, 'cache_read_tokens': 500},
        ],
      });
      expect(l.entries.single.reason, 'This provider does not support caching');
      expect(l.entries.single.skippedReason, 'session is not open');
      expect(l.limits.minIntervalMinutes, 2);
      expect(l.limits.maxIntervalMinutes, 30);
      expect(l.calls7d, 5);
      expect(l.cacheReadTokens7d, 1500);
    });

    test('token text round trips', () {
      expect(parseTokens('128k'), 128000);
      expect(parseTokens('200,000'), 200000);
      expect(parseTokens('1.5m'), 1500000);
      expect(parseTokens('lots'), isNull);
      expect(tokensLabel(128000), '128k');
      expect(tokensLabel(1000000), '1M');
    });

    test('agent reads max_context_tokens, zero and null mean unset', () {
      expect(
          CoordinationAgent.fromJson({'id': 'a', 'max_context_tokens': 64000})
              .maxContextTokens,
          64000);
      expect(
          CoordinationAgent.fromJson({'id': 'a', 'max_context_tokens': 0})
              .maxContextTokens,
          isNull);
      expect(CoordinationAgent.fromJson({'id': 'a'}).maxContextTokens, isNull);
    });

    test('recurring parser tolerates weekly schedules', () {
      RecurringJob job(Map<String, dynamic> schedule) => RecurringJob.fromJson(
          {'id': 'j', 'schedule': schedule, 'session_id': 's'});
      expect(
          job({'kind': 'weekly', 'days': 0x1F, 'hour': 9, 'minute': 0})
              .scheduleLabel,
          'weekdays 09:00');
      final w = job({'kind': 'weekly', 'days': 0x09, 'hour': 18, 'minute': 5});
      expect(w.scheduleKind, 'weekly');
      expect(w.scheduleLabel, 'mon,thu 18:05');
      expect(job({'kind': 'weekly'}).scheduleLabel, 'weekly 00:00');
      expect(job({'kind': 'mystery'}).scheduleLabel, 'mystery');
    });
  });
}
