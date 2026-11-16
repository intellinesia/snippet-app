import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/api.dart';
import 'package:snippet/screens/session.dart';
import 'package:snippet/theme.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  testWidgets(
      'decision events render as quiet notice lines while pending bars remain',
      (tester) async {
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
        sessionId: 'sess-dec',
        title: 'Decision test',
        embedded: true,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 200));

    final ts = DateTime(2026, 11, 16, 9, 52).millisecondsSinceEpoch ~/ 1000;
    final attach = sockets.lastWhere((s) => s.uri.path.contains('attach'));
    attach.controller.add(jsonEncode({
      'wire': 'snapshot',
      'session_id': 'sess-dec',
      'status': 'waiting_for_input',
      'events': [
        {
          'kind': 'approval_request',
          'tool_name': 'bash',
          'summary': 'git push --force-with-lease',
          'index': 1,
          'total': 2,
        },
        {
          'kind': 'decision',
          'request': 'approval',
          'request_id': '0:2026-11-16T09:52:00Z',
          'outcome': 'approved',
          'answer': null,
          'tool_name': 'bash',
          'summary': 'git push --force-with-lease',
          'by': 'human',
          'via': 'app',
          'at': ts,
        },
        {
          'kind': 'decision',
          'request': 'approval',
          'request_id': '1:2026-11-16T09:52:00Z',
          'outcome': 'denied',
          'answer': null,
          'tool_name': 'bash',
          'summary': 'rm -rf build',
          'by': 'mission-control',
          'via': 'agent',
          'at': ts,
        },
        {
          'kind': 'decision',
          'request': 'question',
          'request_id': '2:2026-11-16T09:52:00Z',
          'outcome': 'answered',
          'answer': 'Blue',
          'tool_name': null,
          'summary': null,
          'by': 'human',
          'via': 'desk',
          'at': ts,
        },
        {
          'kind': 'decision',
          'request': 'question',
          'request_id': '3:2026-11-16T09:52:00Z',
          'outcome': 'skipped',
          'answer': null,
          'tool_name': null,
          'summary': null,
          'by': 'human',
          'via': 'app',
          'at': ts,
        },
        {
          'kind': 'approval_request',
          'tool_name': 'bash',
          'summary': 'cargo test',
          'index': 2,
          'total': 2,
        },
      ],
    }));

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('You approved · git push --force-with-lease · 9:52'),
        findsOneWidget);
    expect(find.text('Mission Control denied · rm -rf build · 9:52'),
        findsOneWidget);
    expect(find.text('You answered: Blue · 9:52'), findsOneWidget);
    expect(find.text('You skipped the question · 9:52'), findsOneWidget);
    expect(find.byType(ApprovalBar), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    debugDefaultTargetPlatformOverride = null;
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
  @override
  void add(dynamic data) {}
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future addStream(Stream stream) async {}
  @override
  Future close([int? closeCode, String? closeReason]) async {}
  @override
  Future get done => Future.value();
}
