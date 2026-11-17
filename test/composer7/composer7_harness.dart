import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/session.dart';
import 'package:snippet/theme.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class FakeClient extends DaemonClient {
  FakeClient() : super('http://127.0.0.1:9090', 'tok');

  @override
  Future<List<SessionInfo>> sessions({String? folder, int? limit}) async => [
        SessionInfo.fromJson({
          'id': 'sess-t',
          'title': 'Sidebar density',
          'status': 'idle',
          'agent_id': 'rook',
        }),
      ];

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => [
        CoordinationAgent.fromJson({
          'id': 'rook',
          'display_name': 'Rook',
          'handle': 'rook',
          'status': 'active'
        }),
        CoordinationAgent.fromJson({
          'id': 'moss',
          'display_name': 'Moss',
          'handle': 'moss',
          'status': 'active'
        }),
      ];
}

const chatEvents = [
  {
    'kind': 'user_input',
    'text': 'Tighten the sidebar rows to the 44pt grid and rerun the goldens.'
  },
  {
    'kind': 'assistant_text',
    'text': 'Rows rebuilt on the 44pt grid. Tests pass and the branch is rebased.'
  },
];

const queueTexts = [
  'Also check 360 before you open the PR.',
  'Use the stone theme for the screenshots.',
  'Then hand the release note to Moss.',
];

List<Map<String, String>> queued(int n) => [
      for (var i = 0; i < n; i++) {'id': 'q$i', 'text': queueTexts[i]}
    ];

int _seq = 0;

class Harness {
  Harness() : id = 'sess-${_seq++}';
  final String id;
  final sockets = <FakeSocket>[];
  final key = GlobalKey();

  /// Every JSON frame the screen sent on the attach socket.
  List<Map<String, dynamic>> get sent => [
        for (final s in sockets)
          if (s.uri.path.contains('attach'))
            for (final f in (s.sink as FakeSink).frames)
              if (f is String) (jsonDecode(f) as Map).cast<String, dynamic>()
      ];

  Future<void> pump(WidgetTester tester, Map<String, dynamic> snap,
      {bool desktop = false}) async {
    debugDefaultTargetPlatformOverride =
        desktop ? TargetPlatform.macOS : TargetPlatform.android;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    SharedPreferences.setMockInitialValues({});
    await ThemeManager.instance.setName('stone');
    DaemonClient.wsConnector = (uri, {connectTimeout, pingInterval}) {
      final s = FakeSocket(uri);
      sockets.add(s);
      return s;
    };
    addTearDown(() => DaemonClient.wsConnector = null);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize =
        desktop ? const Size(1280, 800) : const Size(390, 844);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(RepaintBoundary(
      key: key,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: SessionScreen(
          client: FakeClient(),
          sessionId: id,
          title: 'Sidebar density',
          onMenu: () {},
        ),
      ),
    ));
    await tester.pump(const Duration(milliseconds: 200));
    final attach = sockets.lastWhere((s) => s.uri.path.contains('attach'));
    attach.controller.add(jsonEncode({
      'wire': 'snapshot',
      'session_id': id,
      'workspace': '/tmp/proj',
      'agent_id': 'rook',
      ...snap,
    }));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  Future<void> settle(WidgetTester tester) async {
    await tester.pump();
    for (var i = 0; i < 8; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> shoot(WidgetTester tester, String name) async {
    final dir = Platform.environment['R7_SHOTS'];
    if (dir == null || dir.isEmpty) return;
    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  Future<void> done(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(minutes: 1));
    debugDefaultTargetPlatformOverride = null;
  }
}

class FakeSocket extends StreamChannelMixin implements WebSocketChannel {
  FakeSocket(this.uri);
  final Uri uri;
  final controller = StreamController<dynamic>.broadcast();
  @override
  Stream get stream => controller.stream;
  @override
  late final WebSocketSink sink = FakeSink();
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
  @override
  String? get protocol => null;
  @override
  Future<void> get ready => Future.value();
}

class FakeSink implements WebSocketSink {
  final frames = <dynamic>[];
  @override
  void add(dynamic data) => frames.add(data);
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future addStream(Stream stream) => Future.value();
  @override
  Future close([int? closeCode, String? closeReason]) => Future.value();
  @override
  Future get done => Future.value();
}
