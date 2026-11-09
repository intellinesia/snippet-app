import 'dart:async';

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
  final client = DaemonClient('http://127.0.0.1:9090', 'tok');
  late List<_Socket> sockets;

  Future<void> show(WidgetTester tester, {required bool acceptDrops, bool? live}) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: SessionScreen(
        client: client,
        sessionId: 'live-test',
        title: 'Live test',
        embedded: true,
        acceptDrops: acceptDrops,
        live: live,
      ),
    ));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

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

  bool attachOpen() => sockets.any((s) => s.uri.path.contains('attach') && !s.closed);

  testWidgets('a visible chat in an unfocused pane keeps its socket', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await show(tester, acceptDrops: true);
    expect(attachOpen(), isTrue);
    await show(tester, acceptDrops: false, live: true);
    expect(attachOpen(), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('a hidden chat still parks its socket', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    await show(tester, acceptDrops: true);
    expect(attachOpen(), isTrue);
    await show(tester, acceptDrops: false, live: false);
    expect(attachOpen(), isFalse);
    await show(tester, acceptDrops: false, live: true);
    expect(attachOpen(), isTrue);
    await tester.pumpWidget(const SizedBox.shrink());
    debugDefaultTargetPlatformOverride = null;
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
