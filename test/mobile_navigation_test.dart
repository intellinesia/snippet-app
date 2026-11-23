import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/screens/mobile_home/quiet_home.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/screens/mobile_home/mobile_home_screen.dart';
import 'package:snippet/api.dart';
import 'package:snippet/notifications.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/lead/coordination_agent_detail.dart';
import 'package:snippet/screens/desktop_shell.dart';
import 'package:snippet/screens/mobile_chrome.dart';
import 'package:snippet/theme.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

const _chats = 'Add a machine to begin.';
const _tasks = 'Add a machine to see its tasks.';
const _agents = 'Add a machine to see its agents.';
const _settings = 'Add a machine to configure it.';

Finder _visible(Finder f) => f.hitTestable();

Future<void> _pumpShell(WidgetTester tester) async {
  tester.view.devicePixelRatio = 2.0;
  tester.view.physicalSize = const Size(390, 844) * 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: buildAppTheme(),
    home: const DesktopShell(),
  ));
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('with no machine the phone shows only the connect welcome',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      SharedPreferences.setMockInitialValues({});
      await _pumpShell(tester);
      expect(find.text('Connect to your computer'), findsOneWidget);
      expect(_visible(find.text('Scan QR code')), findsOneWidget);
      expect(find.byType(MobileHomeHeader), findsNothing);
      expect(find.byType(MobileMissionBar), findsNothing);
      for (final text in [_chats, _tasks, _agents, _settings]) {
        expect(find.text(text), findsNothing);
      }

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('notification session replaces chat history and reuses its tab',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    DaemonClient.wsConnector = (uri, {connectTimeout, pingInterval}) =>
        _FakeWebSocketChannel();
    addTearDown(() => DaemonClient.wsConnector = null);
    try {
      SharedPreferences.setMockInitialValues({
        'instances':
            '[{"name":"Local","url":"http://127.0.0.1:9090","token":"tok"},{"name":"Other","url":"http://127.0.0.1:9091","token":"other"}]',
      });
      await _pumpShell(tester);
      Future<void> pump() async {
        await tester.pump(const Duration(milliseconds: 400));
        await tester.pump(const Duration(milliseconds: 400));
      }

      final sidebar = tester.widget<Sidebar>(find.byType(Sidebar));
      sidebar.onOpenSession('old', 'Old session', null);
      await pump();
      sidebar.onOpenSession('target', 'Target session', null);
      await pump();
      final before = tester.widget<MobileShell>(find.byType(MobileShell));
      final targetBody = before.activeTabBody;
      sidebar.onOpenSession('old', 'Old session', null);
      await pump();

      void notify(String url) => onNotifTap!({
            'url': url,
            'session': 'target',
            'title': 'Target session',
          });
      notify('http://127.0.0.1:9090');
      await pump();
      expect(tester.widget<MobileShell>(find.byType(MobileShell)).activeTabBody?.key,
          targetBody?.key);
      notify('http://127.0.0.1:9090');
      await pump();
      await tester.binding.handlePopRoute();
      await pump();
      var shell = tester.widget<MobileShell>(find.byType(MobileShell));
      expect(shell.chatsOpen, isTrue);
      expect(shell.mobileHome, MobileHome.home);
      expect(shell.canPopRoute, isFalse);

      notify('http://127.0.0.1:9091');
      await pump();
      shell = tester.widget<MobileShell>(find.byType(MobileShell));
      expect(shell.chatsOpen, isFalse);
      expect(shell.activeTabBody?.key, isNot(targetBody?.key));
      await tester.binding.handlePopRoute();
      await pump();
      expect(tester.widget<MobileShell>(find.byType(MobileShell)).chatsOpen, isTrue);
      expect(tester.widget<MobileShell>(find.byType(MobileShell)).canPopRoute, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('an edge swipe that is also a system back navigates once',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    DaemonClient.wsConnector = (uri, {connectTimeout, pingInterval}) =>
        _FakeWebSocketChannel();
    addTearDown(() => DaemonClient.wsConnector = null);
    var closed = false;
    tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'SystemNavigator.pop') closed = true;
      return null;
    });
    addTearDown(() => tester.binding.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null));
    try {
      SharedPreferences.setMockInitialValues({
        'instances':
            '[{"name":"Local","url":"http://127.0.0.1:9090","token":"tok"}]',
      });
      await _pumpShell(tester);
      final sidebar = tester.widget<Sidebar>(find.byType(Sidebar));
      sidebar.onOpenSession('s1', 'A session', null);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.widget<MobileShell>(find.byType(MobileShell)).chatsOpen,
          isFalse);

      await tester.timedDragFrom(const Offset(4, 400), const Offset(300, 0),
          const Duration(milliseconds: 150));
      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));

      final shell = tester.widget<MobileShell>(find.byType(MobileShell));
      expect(shell.chatsOpen, isTrue);
      expect(shell.mobileHome, MobileHome.home);
      expect(closed, isFalse);
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('an agent opens over the home and back returns to it',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    DaemonClient.wsConnector = (uri, {connectTimeout, pingInterval}) =>
        _FakeWebSocketChannel();
    addTearDown(() => DaemonClient.wsConnector = null);
    try {
      SharedPreferences.setMockInitialValues({
        'instances':
            '[{"name":"Local","url":"http://127.0.0.1:9090","token":"tok"}]',
      });
      await _pumpShell(tester);

      expect(find.byType(QuietHomeScreen), findsOneWidget);

      final sidebar = tester.widget<Sidebar>(find.byType(Sidebar));
      sidebar.onAgent(CoordinationAgent.fromJson(
          {'id': 'scout', 'display_name': 'Scout', 'handle': 'scout'}));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      var shell = tester.widget<MobileShell>(find.byType(MobileShell));
      expect(shell.mobileHome, MobileHome.agents);
      expect(find.byType(CoordinationAgentDetail), findsOneWidget);

      await tester.binding.handlePopRoute();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 400));
      shell = tester.widget<MobileShell>(find.byType(MobileShell));
      expect(shell.mobileHome, MobileHome.home);
      expect(find.byType(CoordinationAgentDetail), findsNothing);
      expect(find.byType(QuietHomeScreen), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
      await tester.pump();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

class _FakeWebSocketChannel extends StreamChannelMixin
    implements WebSocketChannel {
  final _controller = StreamController<dynamic>.broadcast();
  @override
  Stream get stream => _controller.stream;
  @override
  late final WebSocketSink sink = _FakeWebSocketSink(_controller.sink);
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
  @override
  String? get protocol => null;
  @override
  Future<void> get ready => Future.value();
}

class _FakeWebSocketSink implements WebSocketSink {
  final StreamSink _sink;
  _FakeWebSocketSink(this._sink);
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
