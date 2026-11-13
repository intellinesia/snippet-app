import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/api.dart';
import 'package:snippet/screens/desktop_shell.dart';
import 'package:snippet/screens/shell_rail.dart';
import 'package:snippet/theme.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> mountShell(
    WidgetTester tester, {
    Map<String, Object> prefs = const {},
  }) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    DaemonClient.wsConnector =
        (uri, {connectTimeout, pingInterval}) => _Socket();
    SharedPreferences.setMockInitialValues({
      'instances':
          '[{"name":"Local","url":"http://127.0.0.1:9090","token":"tok"}]',
      ...prefs,
    });
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    await tester.pumpWidget(
        MaterialApp(theme: buildAppTheme(), home: const DesktopShell()));
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump(const Duration(milliseconds: 400));
  }

  Future<void> unmountShell(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 1));
    tester.view.reset();
    DaemonClient.wsConnector = null;
    debugDefaultTargetPlatformOverride = null;
  }

  testWidgets('reads persisted sidebar_width at startup and clamps it',
      (tester) async {
    await mountShell(tester, prefs: {'sidebar_width': 350.0});
    final split = tester.widget<ShellSplitView>(find.byType(ShellSplitView));
    expect(split.sidebarWidth, 350.0);
    expect(tester.getSize(find.byType(Sidebar)).width, 350.0);
    await unmountShell(tester);

    await mountShell(tester, prefs: {'sidebar_width': 120.0});
    expect(
      tester.widget<ShellSplitView>(find.byType(ShellSplitView)).sidebarWidth,
      kSidebarMinWidth,
    );
    await unmountShell(tester);
  });

  testWidgets(
      'sidebar resize handle hovers, drags within 220..380, persists, and resets on double-click',
      (tester) async {
    await mountShell(tester);

    final handleFinder = find.byKey(const ValueKey('sidebar-resize-handle'));
    expect(handleFinder, findsOneWidget);
    expect(tester.getSize(handleFinder).width, 6.0);

    final mouseRegion = tester.widget<MouseRegion>(find.descendant(
      of: handleFinder,
      matching: find.byType(MouseRegion),
    ));
    expect(mouseRegion.cursor, SystemMouseCursors.resizeColumn);

    ColoredBox dividerBox() => tester.widget<ColoredBox>(find.descendant(
          of: handleFinder,
          matching: find.byType(ColoredBox),
        ));

    expect(dividerBox().color, AppColors.line);

    final center = tester.getCenter(handleFinder);
    final hoverGesture =
        await tester.createGesture(kind: PointerDeviceKind.mouse);
    await hoverGesture.addPointer(location: center);
    addTearDown(hoverGesture.removePointer);
    await tester.pump();
    expect(dividerBox().color, AppColors.border2);
    await hoverGesture.moveTo(Offset.zero);
    await tester.pump();
    expect(dividerBox().color, AppColors.line);

    // Drag right past max (380) and verify clamp + persistence.
    await tester.drag(handleFinder, const Offset(150, 0));
    await tester.pump();
    expect(
      tester.widget<ShellSplitView>(find.byType(ShellSplitView)).sidebarWidth,
      kSidebarMaxWidth,
    );
    await tester.runAsync(() async {
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble(kSidebarWidthPref), kSidebarMaxWidth);
    });

    // Drag left past min (220) and verify clamp + persistence.
    await tester.drag(handleFinder, const Offset(-300, 0));
    await tester.pump();
    expect(
      tester.widget<ShellSplitView>(find.byType(ShellSplitView)).sidebarWidth,
      kSidebarMinWidth,
    );
    await tester.runAsync(() async {
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble(kSidebarWidthPref), kSidebarMinWidth);
    });

    // Double-click resets to default (kSidebarWidth = 304) and persists.
    final handleCenter = tester.getCenter(handleFinder);
    await tester.tapAt(handleCenter);
    await tester.pump(const Duration(milliseconds: 50));
    await tester.tapAt(handleCenter);
    await tester.pump(const Duration(milliseconds: 300));
    expect(
      tester.widget<ShellSplitView>(find.byType(ShellSplitView)).sidebarWidth,
      kSidebarWidth,
    );
    await tester.runAsync(() async {
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble(kSidebarWidthPref), kSidebarWidth);
    });

    await unmountShell(tester);
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
