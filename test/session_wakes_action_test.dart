import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/api.dart';
import 'package:snippet/screens/agent_wake_panel.dart';
import 'package:snippet/screens/session.dart';
import 'package:snippet/theme.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'support/wake_fakes.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets(
      'session actions list contains Wakes and keep warm for a non-Mission-Control session and opens AgentWakePanel',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    DaemonClient.wsConnector =
        (uri, {connectTimeout, pingInterval}) => _Socket();
    addTearDown(() => DaemonClient.wsConnector = null);
    SharedPreferences.setMockInitialValues({});
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(390, 844);
    addTearDown(tester.view.reset);

    final client = FakeWakeClient();
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: SessionScreen(
        client: client,
        sessionId: 'conv-42',
        title: 'Feature session',
        onMenu: () {},
      ),
    ));
    await _pump(tester);

    await tester.tap(find.text('Feature session').first);
    await _pump(tester);
    expect(find.text('Actions'), findsOneWidget);
    expect(find.text('Wakes and keep warm'), findsOneWidget);
    expect(find.text('Scheduled wakes and prompt cache'), findsOneWidget);
    expect(find.text('Automated wakes'), findsNothing);

    await tester.tap(find.text('Wakes and keep warm'));
    await _pump(tester);
    final panel =
        tester.widget<AgentWakePanel>(find.byType(AgentWakePanel));
    expect(panel.owner, 'conv-42');
    expect(panel.name, 'Feature session');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    debugDefaultTargetPlatformOverride = null;
  });
}

class _Socket extends StreamChannelMixin implements WebSocketChannel {
  final _controller = StreamController<dynamic>.broadcast();
  @override
  Stream get stream => _controller.stream;
  @override
  late final WebSocketSink sink = _Sink(_controller.sink);
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
  final StreamSink _sink;
  _Sink(this._sink);
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
