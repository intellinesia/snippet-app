import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/api.dart';
import 'package:snippet/composer/composer_card.dart';
import 'package:snippet/screens/session.dart';
import 'package:snippet/theme.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import 'support/wake_fakes.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _open(WidgetTester tester, String sessionId) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  DaemonClient.wsConnector = (uri, {connectTimeout, pingInterval}) => _Socket();
  addTearDown(() => DaemonClient.wsConnector = null);
  SharedPreferences.setMockInitialValues({});
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: SessionScreen(
      client: FakeWakeClient(),
      sessionId: sessionId,
      title: 'Session',
      onMenu: () {},
    ),
  ));
  await _pump(tester);
}

Iterable<ComposerChip> _modelChips(WidgetTester tester) => tester
    .widgetList<ComposerChip>(find.byType(ComposerChip))
    .where((c) => c.icon == 'cpu' || c.icon.startsWith('provider:'));

Future<void> _close(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  debugDefaultTargetPlatformOverride = null;
}

void main() {
  testWidgets('a work session composer shows the model picker', (tester) async {
    await _open(tester, 'conv-42');
    expect(_modelChips(tester), isNotEmpty);
    await _close(tester);
  });

  testWidgets('a desk session composer hides the model picker', (tester) async {
    await _open(tester, 'inbox-snippet');
    expect(_modelChips(tester), isEmpty);
    await _close(tester);
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
