import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/chat/chat_info.dart' show DockedInfoNav;
import 'package:snippet/models.dart';
import 'package:snippet/screens/agent_wake_panel.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/widgets.dart';

import 'support/wake_fakes.dart';

Map<String, dynamic> _watchJson({
  String id = 'w-1',
  String owner = 'scout',
  String name = 'inbox',
  String mode = 'poll',
  int intervalMinutes = 5,
  bool enabled = true,
  String status = 'running',
  String? lastError,
  String? lastFiredAt,
  String? lastRunAt,
}) =>
    {
      'id': id,
      'owner': owner,
      'name': name,
      'mode': mode,
      'interval_minutes': intervalMinutes,
      'filter': 'URGENT',
      'max_wakes_per_day': 48,
      'quiet_start': '22:00',
      'quiet_end': '07:00',
      'enabled': enabled,
      'status': status,
      'last_error': lastError,
      'last_run_at': lastRunAt ?? '2026-10-31T09:58:00Z',
      'last_fired_at': lastFiredAt ?? '2026-10-31T09:55:00Z',
      'fires_last_day': 3,
      'script_path': '/home/snippet/.snippet/agents/scout/watches/$name.sh',
      'created_at': '2026-10-30T08:00:00Z',
      'updated_at': '2026-10-31T09:00:00Z',
    };

class _FakeWatchClient extends FakeWakeClient {
  _FakeWatchClient({
    List<AgentWatch> watches = const [],
    this.eventsByWatch = const {},
    this.scriptsByWatch = const {},
  }) {
    watchList = List<AgentWatch>.from(watches);
  }

  final Map<String, List<AgentWatchEvent>> eventsByWatch;
  final Map<String, String> scriptsByWatch;
  final toggled = <(String agentId, String watchId, bool enabled)>[];
  final deleted = <(String agentId, String watchId)>[];

  @override
  Future<AgentWatch> setAgentWatchEnabled(
      String agentId, String watchId, bool enabled) async {
    toggled.add((agentId, watchId, enabled));
    final idx = watchList.indexWhere((w) => w.id == watchId);
    final current = watchList[idx];
    final updated = AgentWatch.fromJson({
      'id': current.id,
      'owner': current.owner,
      'name': current.name,
      'mode': current.mode,
      'interval_minutes': current.intervalMinutes,
      'filter': current.filter,
      'max_wakes_per_day': current.maxWakesPerDay,
      'quiet_start': current.quietStart,
      'quiet_end': current.quietEnd,
      'enabled': enabled,
      'status': enabled ? 'running' : 'paused',
      'last_error': current.lastError,
      'last_run_at': current.lastRunAt,
      'last_fired_at': current.lastFiredAt,
      'fires_last_day': current.firesLastDay,
      'script_path': current.scriptPath,
    });
    watchList[idx] = updated;
    return updated;
  }

  @override
  Future<void> deleteAgentWatch(String agentId, String watchId) async {
    deleted.add((agentId, watchId));
    watchList.removeWhere((w) => w.id == watchId);
  }

  @override
  Future<List<AgentWatchEvent>> agentWatchEvents(
          String agentId, String watchId,
          {int limit = 20}) async =>
      eventsByWatch[watchId] ?? const [];

  @override
  Future<String> agentWatchScript(String agentId, String watchId) async =>
      scriptsByWatch[watchId] ?? '';
}

Future<void> _pumpPanel(WidgetTester tester, _FakeWatchClient client) async {
  freezeWakeClock();
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 1400);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(12),
        child: AgentWakePanel(
          client: client,
          owner: 'scout',
          name: 'Revenue Scout',
        ),
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  test('AgentWatch.fromJson parses view fields and tolerates missing keys', () {
    final full = AgentWatch.fromJson(_watchJson());
    expect(full.id, 'w-1');
    expect(full.owner, 'scout');
    expect(full.name, 'inbox');
    expect(full.mode, 'poll');
    expect(full.intervalMinutes, 5);
    expect(full.modeLabel, 'poll every 5m');
    expect(full.filter, 'URGENT');
    expect(full.maxWakesPerDay, 48);
    expect(full.quietStart, '22:00');
    expect(full.quietEnd, '07:00');
    expect(full.enabled, isTrue);
    expect(full.status, 'running');
    expect(full.firesLastDay, 3);
    expect(full.lastFiredAt, isNotNull);

    final sparse = AgentWatch.fromJson({'id': 'w-2', 'name': 'minimal'});
    expect(sparse.id, 'w-2');
    expect(sparse.name, 'minimal');
    expect(sparse.mode, 'poll');
    expect(sparse.intervalMinutes, 5);
    expect(sparse.enabled, isTrue);
    expect(sparse.status, 'idle');
    expect(sparse.lastError, isNull);
    expect(sparse.lastFiredAt, isNull);
  });

  group('DaemonClient watch routes', () {
    late HttpServer server;
    late DaemonClient client;
    final seen = <String>[];
    final bodies = <String>[];

    setUp(() async {
      HttpOverrides.global = null;
      seen.clear();
      bodies.clear();
      server = await HttpServer.bind('127.0.0.1', 0);
      server.listen((req) async {
        seen.add('${req.method} ${req.uri.path}?${req.uri.query}');
        bodies.add(await utf8.decoder.bind(req).join());
        final p = req.uri.path;
        Object body = {};
        if (p == '/agents/scout/watches') {
          body = {
            'watches': [_watchJson()]
          };
        } else if (p == '/agents/scout/watches/w-1' && req.method == 'POST') {
          body = _watchJson(enabled: false, status: 'paused');
        } else if (p == '/agents/scout/watches/w-1' && req.method == 'DELETE') {
          body = {'removed': true};
        } else if (p == '/agents/scout/watches/w-1/events') {
          body = {
            'events': [
              {
                'kind': 'fired',
                'at': '2026-10-31T09:55:00Z',
                'excerpt': 'line 1'
              }
            ]
          };
        } else if (p == '/agents/scout/watches/w-1/script') {
          body = {'script': '#!/usr/bin/env bash\necho ok\n'};
        }
        req.response.statusCode = 200;
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(body));
        await req.response.close();
      });
      client = DaemonClient('http://127.0.0.1:${server.port}', 'tok');
    });

    tearDown(() => server.close(force: true));

    test('calls documented endpoints and payloads', () async {
      final list = await client.agentWatches('scout');
      expect(list.single.name, 'inbox');
      final updated = await client.setAgentWatchEnabled('scout', 'w-1', false);
      expect(updated.enabled, isFalse);
      final events = await client.agentWatchEvents('scout', 'w-1');
      expect(events.single.excerpt, 'line 1');
      final script = await client.agentWatchScript('scout', 'w-1');
      expect(script, contains('echo ok'));
      await client.deleteAgentWatch('scout', 'w-1');

      expect(seen, contains('GET /agents/scout/watches?token=tok'));
      expect(seen, contains('POST /agents/scout/watches/w-1?token=tok'));
      expect(
          seen, contains('GET /agents/scout/watches/w-1/events?token=tok&limit=20'));
      expect(seen, contains('GET /agents/scout/watches/w-1/script?token=tok'));
      expect(seen, contains('DELETE /agents/scout/watches/w-1?token=tok'));
      expect(
          jsonDecode(bodies[seen.indexOf('POST /agents/scout/watches/w-1?token=tok')]),
          {'enabled': false});
    });
  });

  void withPlatform(TargetPlatform platform, String name,
      Future<void> Function(WidgetTester) body) {
    testWidgets(name, (tester) async {
      debugDefaultTargetPlatformOverride = platform;
      try {
        await body(tester);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });
  }

  withPlatform(
      TargetPlatform.android, 'hides Watches section when agent has no watches',
      (tester) async {
    final client = _FakeWatchClient();
    await _pumpPanel(tester, client);
    expect(find.text('Watches'), findsNothing);
  });

  withPlatform(TargetPlatform.android,
      'renders two watch rows with mode text, status, and fired time',
      (tester) async {
    final watches = [
      AgentWatch.fromJson(_watchJson(
        id: 'w-1',
        name: 'inbox',
        mode: 'poll',
        intervalMinutes: 5,
        status: 'running',
        lastFiredAt: DateTime(2026, 10, 31, 9, 55).toIso8601String(),
      )),
      AgentWatch.fromJson(_watchJson(
        id: 'w-2',
        name: 'whatsapp',
        mode: 'stream',
        status: 'error',
        lastError: 'exit 1: auth expired',
        lastFiredAt: DateTime(2026, 10, 31, 9, 0).toIso8601String(),
      )),
    ];
    final client = _FakeWatchClient(watches: watches);
    await _pumpPanel(tester, client);

    expect(find.text('Watches'), findsOneWidget);
    expect(find.text('inbox'), findsOneWidget);
    expect(find.text('whatsapp'), findsOneWidget);
    expect(find.text('poll every 5m · running · fired 5m ago'), findsOneWidget);
    expect(find.text('stream · error · fired 1h ago'), findsOneWidget);

    expect(wakeStatusColor('running'), AppColors.ok);
    expect(wakeStatusColor('error'), AppColors.danger);
    expect(wakeStatusColor('paused'), AppColors.fg4);
  });

  withPlatform(TargetPlatform.android,
      'toggling a watch switch calls setAgentWatchEnabled with right ids',
      (tester) async {
    final client = _FakeWatchClient(watches: [
      AgentWatch.fromJson(_watchJson(id: 'w-1', name: 'inbox', enabled: true)),
      AgentWatch.fromJson(_watchJson(
          id: 'w-2',
          name: 'feed',
          mode: 'stream',
          enabled: false,
          status: 'paused')),
    ]);
    await _pumpPanel(tester, client);

    final secondSwitch = find.descendant(
      of: find.byKey(const ValueKey('watch-w-2')),
      matching: find.byType(AppSwitch),
    );
    await tester.tap(secondSwitch);
    await tester.pumpAndSettle();

    expect(client.toggled, [('scout', 'w-2', true)]);
    expect(tester.widget<AppSwitch>(secondSwitch).on, isTrue);
  });

  withPlatform(TargetPlatform.android,
      'tapping a watch row opens detail with script, events, error and delete',
      (tester) async {
    const scriptBody = '#!/usr/bin/env bash\ncurl -s https://example.test/feed';
    final client = _FakeWatchClient(
      watches: [
        AgentWatch.fromJson(_watchJson(
          id: 'w-1',
          name: 'inbox',
          status: 'error',
          lastError: 'exit 22: timeout',
        )),
      ],
      eventsByWatch: {
        'w-1': [
          AgentWatchEvent.fromJson({
            'kind': 'error',
            'at': DateTime(2026, 10, 31, 9, 55).toIso8601String(),
            'excerpt': 'curl: (22) 504 Gateway Timeout',
          }),
        ],
      },
      scriptsByWatch: {'w-1': scriptBody},
    );
    await _pumpPanel(tester, client);

    await tester.tap(find.byKey(const ValueKey('watch-w-1')));
    await tester.pumpAndSettle();

    expect(find.text('exit 22: timeout'), findsOneWidget);
    expect(find.text('curl: (22) 504 Gateway Timeout'), findsOneWidget);
    expect(find.text(scriptBody), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);

    await tester.tap(find.text('Delete'));
    await tester.pumpAndSettle();
    expect(find.text('Delete inbox?'), findsOneWidget);

    await tester.tap(find.text('Delete').last);
    await tester.pumpAndSettle();

    expect(client.deleted, [('scout', 'w-1')]);
    expect(find.text('Watches'), findsNothing);
  });

  withPlatform(TargetPlatform.macOS,
      'tapping a watch row pushes through DockedInfoNav when present',
      (tester) async {
    const scriptBody = '#!/usr/bin/env bash\necho docked';
    final pushed = <String>[];
    final client = _FakeWatchClient(
      watches: [
        AgentWatch.fromJson(_watchJson(id: 'w-1', name: 'inbox')),
      ],
      scriptsByWatch: {'w-1': scriptBody},
    );
    freezeWakeClock();
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(500, 900);
    addTearDown(tester.view.reset);

    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: DockedInfoNav(
          push: (title, builder) {
            pushed.add(title);
            navKey.currentState?.push(MaterialPageRoute<void>(
                builder: (ctx) => Scaffold(body: builder(ctx))));
          },
          pop: () => navKey.currentState?.maybePop(),
          child: Navigator(
            key: navKey,
            onGenerateRoute: (_) => MaterialPageRoute<void>(
              builder: (_) => SingleChildScrollView(
                child: AgentWakePanel(
                  client: client,
                  owner: 'scout',
                  name: 'Revenue Scout',
                ),
              ),
            ),
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const ValueKey('watch-w-1')));
    await tester.pumpAndSettle();

    expect(pushed, ['inbox']);
    expect(find.text(scriptBody), findsOneWidget);
  });
}
