import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:snippet/api.dart';
import 'package:snippet/composer/composer_card.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/agent_messaging.dart';
import 'package:snippet/swr.dart';

CoordinationEvent _ev(String id, int seq, String kind, String body,
        {String key = ''}) =>
    CoordinationEvent.fromJson({
      'event_id': id,
      'thread_id': 'thread',
      'sequence': seq,
      'actor_kind': kind,
      'actor_id': kind == 'human' ? 'local' : 'growth',
      'idempotency_key': key.isEmpty ? 'k-$id' : key,
      'created_at': DateTime.utc(2026, 11, 12, 10, 0, seq).toIso8601String(),
      'payload': {'body': body},
    });

class _Client extends DaemonClient {
  _Client() : super('https://daemon.invalid', 'test-token');

  DirectThreadPage page = DirectThreadPage(
      events: [_ev('a1', 1, 'agent', 'earlier message')], deliveries: const {});
  final _hub = DeviceEventHub.local();

  @override
  DeviceEventHub get deviceEvents => _hub;

  @override
  Future<DirectThreadPage> agentThreadPage({
    required String peerId,
    String actorKind = 'human',
    String actorId = 'local',
    int afterSequence = 0,
    int? beforeSequence,
    bool latest = false,
    int limit = 100,
  }) async =>
      page;

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => const [];

  @override
  Future<List<InboxEntry>> agentInbox(String agentId,
          {String? contains,
          String? kind,
          int? before,
          int limit = 50}) async =>
      const [];

  @override
  Future<void> markAgentThreadRead(
      {required String peerId,
      String actorKind = 'human',
      String actorId = 'local'}) async {}

  // The server answers with its own event id and a different idempotency key.
  @override
  Future<CoordinationEvent> sendAgentMessage({
    required String toAgentId,
    required String body,
    String fromKind = 'human',
    String fromId = 'local',
    String? idempotencyKey,
    String? originSession,
    String? replyTo,
    String? reaction,
    bool remove = false,
  }) async {
    final ev = _ev('srv-1', 2, 'human', body, key: 'server-chose-this');
    page = DirectThreadPage(events: [...page.events, ev], deliveries: const {});
    return ev;
  }
}

// The local bubble and the server's copy must be one widget, or the send looks
// like the thread reloaded.
void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  testWidgets('a sent message keeps its row when the server confirms it',
      (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    t.view.physicalSize = const Size(390, 844) * 3;
    t.view.devicePixelRatio = 3;
    addTearDown(t.view.reset);
    final client = _Client();
    await t.pumpWidget(MaterialApp(
      home: AgentThreadScreen(
          client: client, agentId: 'growth', agentName: 'Growth'),
    ));
    for (var i = 0; i < 12; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    await t.enterText(find.byType(TextField), 'hello there');
    await t.pump();
    await t.tap(find.byType(ComposerMorphButton));
    await t.pump(const Duration(milliseconds: 50));
    final bubble = find.text('hello there', findRichText: true);
    expect(bubble, findsOneWidget);
    final before = t.element(bubble);
    for (var i = 0; i < 15; i++) {
      await t.pump(const Duration(milliseconds: 100));
    }
    expect(bubble, findsOneWidget);
    final same = identical(before, t.element(bubble));
    debugDefaultTargetPlatformOverride = null;
    expect(same, isTrue,
        reason: 'the bubble was rebuilt from scratch when confirmed');
  });
}
