import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/api.dart';
import 'package:snippet/screens/session.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/transcript.dart' show QuietAside;
import 'package:snippet/widgets.dart' show ThinkingMarkdown;
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  final client = DaemonClient('http://127.0.0.1:9090', 'tok');
  late List<_Socket> sockets;

  setUp(() {
    sockets = [];
    DaemonClient.wsConnector = (uri, {connectTimeout, pingInterval}) {
      final s = _Socket(uri);
      sockets.add(s);
      return s;
    };
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() => DaemonClient.wsConnector = null);

  Future<_Socket> open(WidgetTester tester, List<Map<String, dynamic>> events) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: SessionScreen(
          client: client, sessionId: 'v', title: 'V', embedded: true),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    final s = sockets.lastWhere((s) => s.uri.path.contains('attach'));
    s._controller.add(jsonEncode({
      'wire': 'snapshot',
      'session_id': 'v',
      'status': 'running',
      'events': events,
    }));
    await tester.pump(const Duration(milliseconds: 400));
    return s;
  }

  Future<void> stream(WidgetTester tester, _Socket s, Map<String, dynamic> f) async {
    s._controller.add(jsonEncode({'wire': 'stream', 'text': 'partial words', ...f}));
    await tester.pump(const Duration(milliseconds: 120));
  }

  testWidgets('voice stream text renders as thinking, not an answer bubble',
      (tester) async {
    final s = await open(tester, []);
    await stream(tester, s, {'voice': true});
    expect(find.byType(ThinkingMarkdown), findsOneWidget);
    expect(find.byKey(const ValueKey('live-text')), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('stream without voice flag stays an answer bubble', (tester) async {
    final s = await open(tester, []);
    await stream(tester, s, {'text_visible': true});
    expect(find.byKey(const ValueKey('live-text')), findsOneWidget);
    expect(find.byType(ThinkingMarkdown), findsNothing);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('quiet assistant_text renders dimmed', (tester) async {
    await open(tester, [
      {'kind': 'user_input', 'text': 'hi'},
      {'kind': 'assistant_text', 'text': 'nothing to say', 'quiet': true},
    ]);
    expect(find.byType(QuietAside), findsOneWidget);
    expect(find.byType(ThinkingMarkdown), findsOneWidget);
    await tester.pumpWidget(const SizedBox.shrink());
  });
}

class _Socket extends StreamChannelMixin implements WebSocketChannel {
  _Socket(this.uri);
  final Uri uri;
  bool closed = false;
  final _controller = StreamController<dynamic>.broadcast();
  @override
  Stream get stream => _controller.stream;
  @override
  late final WebSocketSink sink = _Sink(this);
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
  _Sink(this._socket);
  final _Socket _socket;
  @override
  void add(dynamic data) {}
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future addStream(Stream stream) => Future.value();
  @override
  Future close([int? closeCode, String? closeReason]) {
    _socket.closed = true;
    return _socket._controller.close();
  }

  @override
  Future get done => _socket._controller.done;
}
