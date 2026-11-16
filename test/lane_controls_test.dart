import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/lanes.dart';
import 'package:snippet/screens/session_panels.dart';
import 'package:snippet/transcript.dart';

class _FakeDaemon extends DaemonClient {
  _FakeDaemon() : super('https://daemon.invalid', 'test-token');

  final List<(String, String)> cancelled = [];
  final List<(String, String)> retried = [];

  @override
  Future<void> cancelLane(String session, String lane) async {
    cancelled.add((session, lane));
  }

  @override
  Future<String> retryLane(String session, String lane) async {
    retried.add((session, lane));
    return 'lane-new';
  }
}

LaneInfo _lane({
  String id = 'lane-1',
  String title = 'Audit server',
  String status = 'running',
  List<String> recent = const [],
}) =>
    LaneInfo(
      id: id,
      title: title,
      status: status,
      startedAt: DateTime.now().toUtc().toIso8601String(),
      activity: 'Thinking',
      recent: recent,
    );

void main() {
  test('LaneInfo.fromJson parses recent and tolerates missing field', () {
    final withRecent = LaneInfo.fromJson({
      'id': 'lane-1',
      'title': 'Check',
      'status': 'running',
      'started_at': '2026-01-01T00:00:00Z',
      'recent': ['line 1', 'line 2', 'line 3'],
    });
    expect(withRecent.recent, ['line 1', 'line 2', 'line 3']);

    final old = LaneInfo.fromJson({
      'id': 'lane-2',
      'title': 'Check',
      'status': 'failed',
      'started_at': '2026-01-01T00:00:00Z',
    });
    expect(old.recent, isEmpty);
    expect(old.retryable, isTrue);
  });

  testWidgets('running LaneDetailCard keeps to one activity line, Stop confirms',
      (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      final client = _FakeDaemon();
      final lane = _lane(recent: const ['Read src/lanes.rs', 'cargo test']);
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LaneDetailCard(
            lane: lane,
            client: client,
            sessionId: 'sess-1',
          ),
        ),
      ));
      await t.pump();

      expect(find.text('Read src/lanes.rs'), findsNothing);
      expect(find.text('cargo test'), findsNothing);
      final stopFinder = find.widgetWithText(LaneControlButton, 'Stop');
      expect(stopFinder, findsOneWidget);
      expect(t.getSize(stopFinder).height, 44.0);

      await t.tap(stopFinder);
      await t.pumpAndSettle();
      expect(find.text('Stop this lane?'), findsOneWidget);

      await t.tap(find.text('Cancel'));
      await t.pumpAndSettle();
      expect(client.cancelled, isEmpty);

      await t.tap(stopFinder);
      await t.pumpAndSettle();
      await t.tap(find.widgetWithText(InkWell, 'Stop').last);
      await t.pumpAndSettle();
      expect(client.cancelled, [('sess-1', 'lane-1')]);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('failed and cancelled LaneDetailCard show Retry on desktop',
      (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final client = _FakeDaemon();
      final lanes = [
        _lane(id: 'lane-f', title: 'Failed task', status: 'failed'),
        _lane(id: 'lane-c', title: 'Cancelled task', status: 'cancelled'),
      ];
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView(
            children: laneSections(lanes, client: client, sessionId: 'sess-2'),
          ),
        ),
      ));
      await t.pump();

      final retries = find.widgetWithText(LaneControlButton, 'Retry');
      expect(retries, findsNWidgets(2));
      expect(t.getSize(retries.first).height, 26.0);

      await t.tap(retries.first);
      await t.pumpAndSettle();
      await t.tap(retries.last);
      await t.pumpAndSettle();
      expect(client.retried, [('sess-2', 'lane-f'), ('sess-2', 'lane-c')]);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('LaneNotice keeps one activity line, Stop, Retry, and retryOf label',
      (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final client = _FakeDaemon();
      final running = _lane(
        id: 'lane-r',
        status: 'running',
        recent: const ['grep lane', 'edit file'],
      );
      final cancelled = _lane(id: 'lane-x', status: 'cancelled');

      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              LaneNotice(
                title: running.title,
                live: () => running,
                onOpen: () {},
                client: client,
                sessionId: 'sess-3',
                retryOf: 'lane-0',
              ),
              LaneNotice(
                title: cancelled.title,
                live: () => cancelled,
                onOpen: () {},
                client: client,
                sessionId: 'sess-3',
              ),
            ],
          ),
        ),
      ));
      await t.pump(const Duration(milliseconds: 50));

      expect(find.text('Retry of lane-0'), findsOneWidget);
      expect(find.text('grep lane'), findsNothing);
      expect(find.text('edit file'), findsNothing);
      expect(find.widgetWithText(LaneControlButton, 'Stop'), findsOneWidget);
      expect(find.widgetWithText(LaneControlButton, 'Retry'), findsOneWidget);

      await t.tap(find.widgetWithText(LaneControlButton, 'Retry'));
      await t.pumpAndSettle();
      expect(client.retried, [('sess-3', 'lane-x')]);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('desktop SessionLanesPanel keeps one activity line, Stop/Retry controls',
      (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    try {
      final client = _FakeDaemon();
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SessionLanesPanel(
            client: client,
            sessionId: 'sess-4',
            lanes: [
              _lane(id: 'l-run', status: 'running', recent: const ['tail log']),
              _lane(id: 'l-fail', status: 'failed'),
            ],
          ),
        ),
      ));
      await t.pump();

      expect(find.text('tail log'), findsNothing);
      expect(find.widgetWithText(LaneControlButton, 'Stop'), findsOneWidget);
      expect(find.widgetWithText(LaneControlButton, 'Retry'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
