import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/api.dart';
import 'package:snippet/chat/message_enter.dart';
import 'package:snippet/screens/session.dart';
import 'package:snippet/theme.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

Map<String, dynamic> _text(String t) => {'kind': 'assistant_text', 'text': t};

void main() {
  for (final desktop in [true, false]) {
    testWidgets(
        'a new event keeps earlier rows mounted '
        '(${desktop ? 'desktop' : 'phone'})', (tester) async {
      debugDefaultTargetPlatformOverride =
          desktop ? TargetPlatform.linux : TargetPlatform.android;
      addTearDown(() => debugDefaultTargetPlatformOverride = null);
      final socket = _Socket();
      DaemonClient.wsConnector =
          (uri, {connectTimeout, pingInterval}) => socket;
      addTearDown(() => DaemonClient.wsConnector = null);
      SharedPreferences.setMockInitialValues({});
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize =
          desktop ? const Size(1440, 900) : const Size(390, 844);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: SessionScreen(
          client: DaemonClient('http://127.0.0.1:9090', 'tok'),
          sessionId: 'worker',
          title: 'Worker',
          onMenu: () {},
        ),
      ));
      await tester.pump(const Duration(milliseconds: 400));

      void send(Map<String, dynamic> frame) =>
          socket.controller.add(jsonEncode(frame));
      send({
        'wire': 'snapshot',
        'status': 'idle',
        'workspace': '/tmp/w',
        'event_offset': 0,
        'events': [
          {'kind': 'user_input', 'text': 'go'},
          _text('first reply'),
        ],
      });
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 400));
      }
      State rowOf(String text) => tester.state(find
          .ancestor(
              of: find.textContaining(text, findRichText: true).first,
              matching: find.byType(MessageEnter))
          .first);
      final before = rowOf('first reply');

      send({
        'wire': 'delta',
        'status': 'idle',
        'workspace': '/tmp/w',
        'new_events': [_text('second reply')],
        'event_count': 3,
        'total_events': 3,
      });
      for (var i = 0; i < 3; i++) {
        await tester.pump(const Duration(milliseconds: 400));
      }
      expect(find.textContaining('second reply', findRichText: true),
          findsWidgets);
      expect(identical(rowOf('first reply'), before), isTrue,
          reason: 'the earlier row was remounted');
      debugDefaultTargetPlatformOverride = null;
    });
  }
}

class _Socket extends StreamChannelMixin implements WebSocketChannel {
  final controller = StreamController<dynamic>.broadcast();
  @override
  Stream get stream => controller.stream;
  @override
  late final WebSocketSink sink = _Sink(controller.sink);
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
