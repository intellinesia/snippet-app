import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/lanes.dart';

class _FakeDaemon extends DaemonClient {
  _FakeDaemon() : super('https://daemon.invalid', 'test-token');
  final retried = <String>[];

  @override
  Future<String> retryLane(String session, String lane) async {
    retried.add(lane);
    return 'lane-new';
  }
}

LaneInfo _lane(String id, String title, String status,
        {String? summary, String? error, String? activity, Duration? age}) =>
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
  _lane('e', 'Transcript meta (first try)', 'cancelled'),
];

Future<_FakeDaemon> _pump(WidgetTester tester, List<LaneInfo> lanes) async {
  final client = _FakeDaemon();
  await tester.pumpWidget(MaterialApp(
    home: LanesScreen(
        liveLanes: () => lanes, client: client, sessionId: 'sess-1'),
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
  _phone('summary line counts done and the oldest running lane',
      (tester) async {
    await _pump(tester, _all);
    expect(find.text('2 of 5 done'), findsOneWidget);
    expect(find.text('1 running · 6m'), findsOneWidget);
  });

  _phone('sections lead with failures, then live work', (tester) async {
    await _pump(tester, _all);
    final needs = tester.getTopLeft(find.text('Needs you')).dy;
    final working = tester.getTopLeft(find.text('Working')).dy;
    expect(needs, lessThan(working));
    expect(find.text('Build failed on macOS.'), findsOneWidget);
    expect(find.text('cargo test session_stats · 6m'), findsOneWidget);
    expect(find.text('Retry'), findsOneWidget);
    expect(find.text('Stop'), findsOneWidget);
    expect(find.text('View details'), findsNothing);
  });

  _phone('empty sections are omitted', (tester) async {
    await _pump(tester, [_all[0], _all[2]]);
    expect(find.text('Needs you'), findsNothing);
    expect(find.text('Working'), findsOneWidget);
    expect(find.text('Retry'), findsNothing);
    expect(find.text('1 finished'), findsOneWidget);
  });

  _phone('finished lanes fold into one row that expands',
      (tester) async {
    await _pump(tester, _all);
    expect(find.text('2 finished, 1 cancelled'), findsOneWidget);
    expect(find.text('Transcript meta redesign'), findsNothing);
    await tester.tap(find.text('2 finished, 1 cancelled'));
    await tester.pump();
    expect(find.text('Transcript meta redesign'), findsOneWidget);
    expect(find.text('Redesign landed.'), findsOneWidget);
    expect(find.text('Transcript meta (first try)'), findsOneWidget);
    await tester.tap(find.text('2 finished, 1 cancelled'));
    await tester.pump();
    expect(find.text('Transcript meta redesign'), findsNothing);
  });

  _phone('Retry uses the lane retry path', (tester) async {
    final client = await _pump(tester, _all);
    await tester.tap(find.text('Retry'));
    await tester.pump();
    expect(client.retried, ['d']);
  });

  _phone('phone rows meet the 44px target', (tester) async {
    await _pump(tester, _all);
    final row = find.byKey(const ValueKey('lane-row-d'));
    expect(tester.getSize(row).height, greaterThanOrEqualTo(44));
  });

  _phone('a row opens the lane detail', (tester) async {
    await _pump(tester, _all);
    await tester.tap(find.text('Notch HUD'));
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(LaneDetailScreen), findsOneWidget);
  });
}
