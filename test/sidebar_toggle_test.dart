import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/api.dart';
import 'package:snippet/screens/agent_rail.dart';
import 'package:snippet/screens/agents_sidebar_panel.dart';
import 'package:snippet/screens/desktop_shell.dart';
import 'package:snippet/screens/shell_split_view.dart';
import 'package:snippet/screens/sidebar.dart';
import 'package:snippet/screens/sidebar_mode.dart';
import 'package:snippet/theme.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

Future<void> _pump(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

void main() {
  testWidgets('toggling the sidebar keeps the open panes mounted',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    DaemonClient.wsConnector =
        (uri, {connectTimeout, pingInterval}) => _Socket();
    SharedPreferences.setMockInitialValues({
      'instances':
          '[{"name":"Local","url":"http://127.0.0.1:9090","token":"tok"}]',
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        MaterialApp(theme: buildAppTheme(), home: const DesktopShell()));
    await _pump(tester);

    final before = tester.state(find.byType(ShellSplitView));
    expect(find.byType(Sidebar), findsOneWidget);
    expect(find.byType(AgentRail), findsOneWidget);

    await tester.tap(find.byTooltip('Hide sidebar (Ctrl+B)'));
    await _pump(tester);
    expect(find.byType(Sidebar), findsNothing);
    expect(find.byType(AgentRail), findsNothing);
    expect(tester.state(find.byType(ShellSplitView)), same(before));

    await tester.tap(find.byTooltip('Show sidebar (Ctrl+B)'));
    await _pump(tester);
    expect(find.byType(Sidebar), findsOneWidget);
    expect(find.byType(AgentRail), findsOneWidget);
    expect(tester.state(find.byType(ShellSplitView)), same(before));

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    DaemonClient.wsConnector = null;
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('the header switch puts agents first and keeps the footer tools',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    DaemonClient.wsConnector =
        (uri, {connectTimeout, pingInterval}) => _Socket();
    SharedPreferences.setMockInitialValues({
      'instances':
          '[{"name":"Local","url":"http://127.0.0.1:9090","token":"tok"}]',
    });
    sidebarAgentsFirst.value = false;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
        MaterialApp(theme: buildAppTheme(), home: const DesktopShell()));
    await _pump(tester);

    final before = tester.state(find.byType(ShellSplitView));
    expect(find.byTooltip('Back'), findsNothing);
    double railWidth() => tester
        .getSize(find
            .ancestor(
                of: find.byType(AgentRail),
                matching: find.byType(AnimatedContainer))
            .first)
        .width;
    expect(railWidth(), kAgentRailWidth);
    expect(find.byType(AgentsSidebarPanel), findsNothing);

    await tester.tap(find.byKey(const ValueKey('sidebar-mode-agents')));
    await _pump(tester);
    expect(sidebarAgentsFirst.value, isTrue);
    expect(railWidth(), 0);
    expect(find.byType(AgentsSidebarPanel), findsOneWidget);
    for (final tip in ['Usage', 'Settings', 'Tasks']) {
      expect(
          find.descendant(
              of: find.byType(Sidebar), matching: find.byTooltip(tip)),
          findsWidgets,
          reason: tip);
    }
    expect(tester.state(find.byType(ShellSplitView)), same(before));
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool('desktop_sidebar_agents_first'), isTrue);

    await tester.tap(find.byKey(const ValueKey('sidebar-mode-sessions')));
    await _pump(tester);
    expect(railWidth(), kAgentRailWidth);
    expect(find.byType(AgentsSidebarPanel), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    sidebarAgentsFirst.value = false;
    DaemonClient.wsConnector = null;
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
