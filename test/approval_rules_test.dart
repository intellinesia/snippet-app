import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/api.dart';
import 'package:snippet/approval_code.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/agent_thread_cards.dart';
import 'package:snippet/screens/session.dart';
import 'package:snippet/session_quick_send.dart';
import 'package:snippet/theme.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

final _ts = DateTime(2026, 11, 16, 9, 52).millisecondsSinceEpoch ~/ 1000;

Map<String, dynamic> _request({
  String? title,
  String? reason,
  Map<String, dynamic>? rule,
  int total = 1,
}) =>
    {
      'kind': 'approval_request',
      'tool_name': 'bash',
      'summary': 'git push --force-with-lease origin lane/sidebar-polish',
      'index': 1,
      'total': total,
      if (title != null) 'title': title,
      if (reason != null) 'reason': reason,
      if (rule != null) 'rule': rule,
    };

/// Pumps a phone SessionScreen fed one snapshot; returns the attach socket.
Future<_Socket> _pumpSession(WidgetTester tester,
    {required List<Map<String, dynamic>> events,
    String sessionId = 'sess-rules'}) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  SharedPreferences.setMockInitialValues({});
  final sockets = <_Socket>[];
  DaemonClient.wsConnector = (uri, {connectTimeout, pingInterval}) {
    final s = _Socket(uri);
    sockets.add(s);
    return s;
  };
  addTearDown(() => DaemonClient.wsConnector = null);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.reset);

  final client = DaemonClient('http://127.0.0.1:9090', 'tok');
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: SessionScreen(
      client: client,
      sessionId: sessionId,
      title: 'Rules test',
      embedded: true,
    ),
  ));
  await tester.pump(const Duration(milliseconds: 200));
  final attach = sockets.lastWhere((s) => s.uri.path.contains('attach'));
  attach.controller.add(jsonEncode({
    'wire': 'snapshot',
    'session_id': sessionId,
    'status': 'waiting_for_input',
    'events': events,
  }));
  await tester.pump(const Duration(milliseconds: 200));
  await tester.pump(const Duration(milliseconds: 200));
  return attach;
}

Future<void> _unmount(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 16));
  debugDefaultTargetPlatformOverride = null;
}

List<Map> _sentKinds(_Socket s) => [
      for (final f in (s.sink as _Sink).sent)
        if (f is String) jsonDecode(f) as Map
    ];

void main() {
  group('approvalTitle', () {
    test('adds a question mark unless the title already ends in ? . or !', () {
      expect(approvalTitle('Push the rebased branch'),
          'Push the rebased branch?');
      expect(approvalTitle('Push it?'), 'Push it?');
      expect(approvalTitle('Push it.'), 'Push it.');
      expect(approvalTitle('Push it!'), 'Push it!');
      expect(approvalTitle('  '), isNull);
      expect(approvalTitle(null), isNull);
    });
  });

  test('QuickApproveRule sends approve_rule with optional via', () {
    expect(const QuickApproveRule(via: 'desk').frame('n1'),
        {'kind': 'approve_rule', 'nonce': 'n1', 'via': 'desk'});
    expect(const QuickApproveRule().frame('n2'),
        {'kind': 'approve_rule', 'nonce': 'n2'});
  });

  testWidgets('pinned card shows title, reason and the rule link',
      (tester) async {
    final attach = await _pumpSession(tester, events: [
      _request(
        title: 'Push the rebased branch',
        reason: 'Rewrites lane/sidebar-polish on origin.',
        rule: {'id': 'bash:git push', 'label': 'pushes'},
      ),
    ]);

    expect(find.text('Push the rebased branch?'), findsOneWidget);
    expect(find.text('Run this command?'), findsNothing);
    expect(find.text('Rewrites lane/sidebar-polish on origin.'),
        findsOneWidget);
    expect(find.text('Always allow pushes in this session'), findsOneWidget);
    expect(find.text('Always allow'), findsNothing);

    await tester.tap(find.text('Always allow pushes in this session'));
    await tester.pump(const Duration(milliseconds: 100));
    final sent = _sentKinds(attach).where((m) => m['kind'] != null).toList();
    expect(sent.last['kind'], 'approve_rule');
    expect(sent.last['via'], 'app');
    expect(sent.last['nonce'], isNotNull);
    await _unmount(tester);
  });

  testWidgets('without new fields the card keeps today\'s look and approve_all',
      (tester) async {
    final attach = await _pumpSession(tester, events: [_request(total: 2)]);

    expect(find.text('Run this command?'), findsOneWidget);
    expect(find.textContaining('in this session'), findsNothing);
    expect(find.text('Always allow'), findsOneWidget);

    await tester.tap(find.text('Always allow'));
    await tester.pump(const Duration(milliseconds: 100));
    final sent = _sentKinds(attach).where((m) => m['kind'] != null).toList();
    expect(sent.last['kind'], 'approve_all');
    await _unmount(tester);
  });

  testWidgets('Lead session pins the same card with the new fields',
      (tester) async {
    await _pumpSession(tester, sessionId: 'lead', events: [
      _request(
        title: 'Push the rebased branch',
        reason: 'Rewrites lane/sidebar-polish on origin.',
        rule: {'id': 'bash:git push', 'label': 'pushes'},
      ),
    ]);

    expect(find.byType(ApprovalBar), findsOneWidget);
    expect(find.text('Push the rebased branch?'), findsOneWidget);
    expect(find.text('Rewrites lane/sidebar-polish on origin.'),
        findsOneWidget);
    expect(find.text('Always allow pushes in this session'), findsOneWidget);
    await _unmount(tester);
  });

  testWidgets('decided lines for a rule auto-approval and an always-approve',
      (tester) async {
    await _pumpSession(tester, events: [
      {
        'kind': 'decision',
        'request': 'approval',
        'request_id': '',
        'outcome': 'approved',
        'tool_name': 'bash',
        'summary': 'git push origin main',
        'by': 'rule',
        'via': 'rule',
        'rule': 'pushes',
        'at': _ts,
      },
      {
        'kind': 'decision',
        'request': 'approval',
        'request_id': '1:2026-11-16T09:52:00Z',
        'outcome': 'approved',
        'tool_name': 'bash',
        'summary': 'git push --force-with-lease',
        'by': 'human',
        'via': 'app',
        'rule': 'pushes',
        'at': _ts,
      },
      _request(),
    ]);

    expect(find.text('Allowed by rule · git push origin main · 9:52'),
        findsOneWidget);
    expect(
        find.text(
            'You approved · always for pushes · git push --force-with-lease · 9:52'),
        findsOneWidget);
    await _unmount(tester);
  });

  group('mirrored DeskApprovalCard', () {
    CoordinationEvent ev({bool withRule = true}) => CoordinationEvent.fromJson({
          'event_id': 'e-rule',
          'thread_id': 'group:g1',
          'sequence': 1,
          'actor_kind': 'agent',
          'actor_id': 'snippet',
          'idempotency_key': 'k-e-rule',
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'payload': {
            'body': 'waiting on an approval',
            'approval': {
              'session': 's1',
              'session_title': 'Sidebar density',
              'task_id': 't1',
              'task_title': 'Sidebar polish',
              'tool': 'bash',
              'summary': 'git push --force-with-lease origin lane/sidebar-polish',
              'approval_id': '3:2026-11-16',
              if (withRule) ...{
                'title': 'Push the rebased branch',
                'reason': 'Rewrites lane/sidebar-polish on origin.',
                'rule': {'id': 'bash:git push', 'label': 'pushes'},
              },
            },
          },
        });

    Future<_Socket> pump(WidgetTester t, CoordinationEvent e) async {
      final ch = _Socket(Uri.parse('ws://x/attach'));
      DaemonClient.wsConnector = (uri, {connectTimeout, pingInterval}) {
        Timer(const Duration(milliseconds: 10),
            () => ch.controller.add('{"wire":"snapshot"}'));
        return ch;
      };
      addTearDown(() => DaemonClient.wsConnector = null);
      await t.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: DeskApprovalCard(
            event: e,
            approval: e.payload['approval'] as Map,
            client: DaemonClient('http://127.0.0.1:9090', 'tok'),
            agentId: 'snippet',
          ),
        ),
      ));
      await t.pump();
      return ch;
    }

    testWidgets('shows headline, reason and link; the link sends approve_rule',
        (t) async {
      final ch = await pump(t, ev());
      expect(find.text('Push the rebased branch?'), findsOneWidget);
      expect(
          find.text('Rewrites lane/sidebar-polish on origin.'), findsOneWidget);
      expect(find.text('Always allow pushes in this session'), findsOneWidget);

      await t.tap(find.text('Always allow pushes in this session'));
      await t.pump(const Duration(milliseconds: 50));
      await t.pump(const Duration(milliseconds: 50));

      final sent = _sentKinds(ch).single;
      expect(sent['kind'], 'approve_rule');
      expect(sent['via'], 'desk');
      expect(find.textContaining('Approved'), findsOneWidget);
      expect(find.text('Approve'), findsNothing);
    });

    testWidgets('without the new fields it has no link or headline',
        (t) async {
      await pump(t, ev(withRule: false));
      expect(find.textContaining('Always allow'), findsNothing);
      expect(find.text('Push the rebased branch?'), findsNothing);
      expect(find.text('Approve'), findsOneWidget);
    });

    testWidgets('an approved_rule outcome reads as approved', (t) async {
      final e = ev();
      (e.payload['approval'] as Map)['outcome'] = {'state': 'approved_rule'};
      await pump(t, e);
      expect(find.textContaining('Approved'), findsOneWidget);
      expect(find.text('Approve'), findsNothing);
    });
  });
}

class _Socket extends StreamChannelMixin implements WebSocketChannel {
  _Socket(this.uri);
  final Uri uri;
  final controller = StreamController<dynamic>.broadcast();
  @override
  Stream get stream => controller.stream;
  @override
  late final WebSocketSink sink = _Sink();
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
  final sent = <dynamic>[];
  @override
  void add(dynamic data) => sent.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future addStream(Stream stream) async {}
  @override
  Future close([int? closeCode, String? closeReason]) async {}
  @override
  Future get done => Future.value();
}
