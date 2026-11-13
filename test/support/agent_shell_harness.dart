import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/api.dart';
import 'package:snippet/screens/desktop_shell.dart';
import 'package:snippet/theme.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

Map<String, dynamic> agentJson(String id, String name, String role,
        {String? profile}) =>
    {
      'id': id,
      'display_name': name,
      'handle': id,
      'kind': 'agent',
      'status': 'active',
      'role': role,
      if (profile != null) 'profile': profile,
      'capabilities': ['code', 'review'],
      'assigned_sessions': [],
    };

/// A real loopback daemon: the shell builds its own `DaemonClient` from the
/// saved instance, so the only seam is the network.
class FakeDaemon {
  FakeDaemon._(this.server);
  final HttpServer server;
  final requests = <String>[];

  static Future<FakeDaemon> start({Object? Function(String path)? extra}) async {
    final server = await HttpServer.bind('127.0.0.1', 0);
    final d = FakeDaemon._(server);
    server.listen((req) async {
      // Keep-alive would leave the shared client's idle timer pending in fake time.
      req.response.persistentConnection = false;
      d.requests.add('${req.method} ${req.uri.path}');
      final path = req.uri.path;
      Object? body = extra?.call(path);
      if (body != null) {
      } else if (path == '/agents') {
        body = [
          agentJson('snippet', 'Snippet', 'Implementer', profile: 'opus'),
          agentJson('reviewer', 'Rust PR Reviewer', 'Code reviewer'),
        ];
      } else if (path == '/coordination/direct/messages') {
        body = {
         'events': [
          for (final (i, (who, text)) in [
            ('human', 'Can you take the desktop sidebar polish next?'),
            ('agent', 'On it. I will start with the row density, then send you screenshots.'),
            ('human', 'Also check the 320px layout.'),
            ('agent', 'Done with the first pass. Want me to open a PR?'),
          ].indexed)
            {
              'event_id': 'e$i',
              'thread_id': 'direct:human:local:agent:snippet',
              'partition_key': 'snippet',
              'sequence': i + 1,
              'event_type': 'direct_message',
              'actor_kind': who,
              'actor_id': who == 'human' ? 'local' : 'snippet',
              'payload_version': 1,
              'payload': {'body': text},
              'idempotency_key': 'e$i',
              'created_at': '2026-11-08T09:0$i:00Z',
            },
         ],
        };
      } else if (path == '/memory/scopes') {
        body = [
          {
            'key': 'agent:snippet',
            'kind': 'agent',
            'label': 'Snippet',
            'path': '/mem/agent',
            'entries': 14,
            'files': 5,
            'last_commit': {'date': 1762600000, 'subject': 'Remember desktop layout rules'},
            'pending': 0,
          },
        ];
      } else if (path == '/config') {
        body = {
          'profiles': [
            {'name': 'opus', 'provider': 'anthropic', 'model': 'claude-opus'},
            {'name': 'sonnet', 'provider': 'anthropic', 'model': 'claude-sonnet'},
          ],
        };
      } else if (path.endsWith('/inbox') ||
          path.endsWith('/board') ||
          path == '/sessions' ||
          path.startsWith('/memory')) {
        body = [];
      }
      req.response.headers.contentType = ContentType.json;
      if (body == null) {
        req.response.statusCode = 404;
        req.response.write('{}');
      } else {
        req.response.write(jsonEncode(body));
      }
      await req.response.close();
    });
    return d;
  }

  String get url => 'http://127.0.0.1:${server.port}';
}

Future<void> settle(WidgetTester tester, [int rounds = 6]) async {
  for (var i = 0; i < rounds; i++) {
    await tester.runAsync(() => Future.delayed(const Duration(milliseconds: 60)));
    await tester.pump(const Duration(milliseconds: 250));
  }
}

/// Mounts the desktop shell at 1440x900 against [daemon] and opens the agent
/// tab for [agentId] from the agent rail.
Future<void> openAgentTab(
    WidgetTester tester, FakeDaemon daemon, String agentId) async {
  HttpOverrides.global = null;
  final onError = FlutterError.onError;
  FlutterError.onError = (d) {
    if (d.exceptionAsString().contains('audioplayers')) return;
    onError?.call(d);
  };
  _restoreOnError = onError;
  debugDefaultTargetPlatformOverride = TargetPlatform.linux;
  DaemonClient.wsConnector = (uri, {connectTimeout, pingInterval}) => _Socket();
  addTearDown(() => DaemonClient.wsConnector = null);
  SharedPreferences.setMockInitialValues({
    'instances':
        '[{"name":"Local","url":"${daemon.url}","token":"tok"}]',
  });
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(1440, 900);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(),
      home: const DesktopShell()));
  await settle(tester);
  await tester.tap(find.byKey(const ValueKey('sidebar-mode-agents')));
  await settle(tester);
  await tester.tap(find.byKey(ValueKey('agent-card-$agentId')));
  await settle(tester);
}

class _Socket extends StreamChannelMixin implements WebSocketChannel {
  final _c = StreamController<dynamic>.broadcast();
  @override
  Stream get stream => _c.stream;
  @override
  late final WebSocketSink sink = _Sink(_c.sink);
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
  _Sink(this._sink);
  final StreamSink _sink;
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

FlutterExceptionHandler? _restoreOnError;

Future<void> closeShell(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 1));
  DaemonClient.wsConnector = null;
  debugDefaultTargetPlatformOverride = null;
  FlutterError.onError = _restoreOnError;
}
