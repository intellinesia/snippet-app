import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/lanes.dart';

class _FakeDaemon extends DaemonClient {
  _FakeDaemon() : super('https://daemon.invalid', 'test-token');
  final retried = <String>[];
  final cancelled = <String>[];

  @override
  Future<ServerConfig> getConfig({bool force = false}) async =>
      ServerConfig.fromJson({
        'profiles': [
          {'name': 'sonnet', 'provider': 'anthropic', 'model': 'claude-sonnet'},
        ],
      });

  @override
  Future<String> retryLane(String session, String lane) async {
    retried.add(lane);
    return 'lane-new';
  }

  @override
  Future<void> cancelLane(String session, String lane) async {
    cancelled.add(lane);
  }
}

LaneInfo _lane(String id, String title, String status,
        {String? summary,
        String? error,
        String? activity,
        String? agent,
        String? profile,
        Duration? age}) =>
    LaneInfo(
      id: id,
      title: title,
      status: status,
      startedAt: DateTime.now()
          .toUtc()
          .subtract(age ?? Duration.zero)
          .toIso8601String(),
      summary: summary,
      error: error,
      activity: activity,
      agent: agent,
      profile: profile,
    );

final _all = [
  _lane('a', 'Transcript meta redesign', 'completed',
      summary: 'Redesign landed. Tests pass.'),
  _lane('b', 'Toasts and action sheets', 'completed',
      summary: 'Toasts above the composer.'),
  _lane('c', 'Daemon: goal in list', 'running',
      activity: 'cargo test session_stats', age: const Duration(minutes: 6)),
  _lane('d', 'Notch HUD', 'failed',
      error: 'Build failed on macOS. Signing identity missing.'),
  _lane('e', 'Transcript meta (first try)', 'cancelled',
      summary: 'Stopped by Rook.'),
  _lane('f', 'Release note draft', 'running',
      activity: 'Writing CHANGELOG.md',
      agent: 'moss',
      profile: 'sonnet',
      age: const Duration(minutes: 3)),
];

Future<_FakeDaemon> _pump(WidgetTester tester, List<LaneInfo> lanes) async {
  final client = _FakeDaemon();
  await tester.pumpWidget(MaterialApp(
    home: LanesScreen(
      liveLanes: () => lanes,
      client: client,
      sessionId: 'sess-1',
      sessionTitle: 'Sidebar density',
      sessionAgentId: 'snippet',
      sessionAgentName: 'Rook',
    ),
  ));
  await tester.pump();
  return client;
}

void _phone(String name, WidgetTesterCallback body) =>
    testWidgets(name, (tester) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await body(tester);
        await tester.pumpWidget(const SizedBox());
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

void main() {
  testWidgets('desktop uses the same grouped layout with a Stop control',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      final client = await _pump(tester, _all);
      expect(find.text('Delegated lanes'), findsOneWidget);
      expect(find.text('Rook · 1 needs you'), findsOneWidget);
      expect(find.text('Moss · 1 working'), findsOneWidget);
      expect(find.textContaining('Click a lane'), findsOneWidget);
      expect(find.text('Stop'), findsNWidgets(2));
      await tester.tap(find.text('Retry'));
      await tester.pump();
      expect(client.retried, ['d']);
      await tester.pumpWidget(const SizedBox());
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  _phone('header names the session; groups lead with its own agent',
      (tester) async {
    await _pump(tester, _all);
    expect(find.text('Lanes'), findsOneWidget);
    expect(find.text('Sidebar density'), findsOneWidget);
    final own = tester.getTopLeft(find.text('Rook · 1 needs you')).dy;
    final other = tester.getTopLeft(find.text('Moss · 1 working')).dy;
    expect(own, lessThan(other));
  });

  _phone('rows show activity and elapsed; failures lead their group',
      (tester) async {
    await _pump(tester, _all);
    expect(find.text('cargo test session_stats'), findsOneWidget);
    expect(find.text('6 min'), findsOneWidget);
    expect(find.text('3 min'), findsOneWidget);
    final failed = tester.getTopLeft(find.text('Notch HUD')).dy;
    final running = tester.getTopLeft(find.text('Daemon: goal in list')).dy;
    expect(failed, lessThan(running));
    expect(find.textContaining('Build failed on macOS.', findRichText: true),
        findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
  });

  _phone('the footnote names the hand-off and is omitted for one agent',
      (tester) async {
    await _pump(tester, _all);
    expect(
        find.textContaining(
            'Rook split this work and handed Release note draft to Moss.'),
        findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await _pump(tester, _all.sublist(0, 5));
    expect(find.textContaining('split this work'), findsNothing);
  });

  _phone('a finished-only group counts done and cancelled', (tester) async {
    await _pump(tester, [_all[0], _all[1], _all[4]]);
    expect(find.text('Rook · 2 done, 1 cancelled'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    expect(find.textContaining('Cancelled · Stopped by Rook.', findRichText: true),
        findsOneWidget);
  });

  _phone('Retry uses the lane retry path', (tester) async {
    final client = await _pump(tester, _all);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(client.retried, ['d']);
  });

  _phone('long-pressing a working row stops it after a confirmation',
      (tester) async {
    final client = await _pump(tester, _all);
    await tester.longPress(find.text('Release note draft'));
    await tester.pumpAndSettle();
    expect(find.text('Stop this lane?'), findsOneWidget);
    await tester.tap(find.text('Stop'));
    await tester.pumpAndSettle();
    expect(client.cancelled, ['f']);
  });

  _phone('phone rows meet the 64px target', (tester) async {
    await _pump(tester, _all);
    final row = find.byKey(const ValueKey('lane-row-d'));
    expect(tester.getSize(row).height, greaterThanOrEqualTo(64));
  });

  _phone('a lane with a known profile shows its provider icon with a tooltip',
      (tester) async {
    await _pump(tester, _all);
    await tester.pump();
    expect(find.byTooltip('sonnet \u00b7 claude-sonnet'), findsOneWidget);
    expect(find.text('sonnet'), findsNothing);
    expect(find.textContaining('Writing CHANGELOG.md', findRichText: true),
        findsOneWidget);
  });

  _phone('a row opens the lane detail', (tester) async {
    await _pump(tester, _all);
    await tester.tap(find.text('Notch HUD'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(LaneDetailScreen), findsOneWidget);
  });
}
