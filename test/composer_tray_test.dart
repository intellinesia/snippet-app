import 'package:flutter/rendering.dart';
import 'dart:ui' as ui;
import 'dart:io';
import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/api.dart';
import 'package:snippet/composer/composer_card.dart';
import 'package:snippet/composer/composer_tray.dart';
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
          'title': 'Tray test',
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

Future<void> _pumpSession(WidgetTester tester, Map<String, dynamic> snap) async {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  SharedPreferences.setMockInitialValues({});
  final sockets = <_Socket>[];
  DaemonClient.wsConnector = (uri, {connectTimeout, pingInterval}) {
    final s = _Socket(uri);
    sockets.add(s);
    return s;
  };
  addTearDown(() => DaemonClient.wsConnector = null);
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    builder: (_, child) =>
        RepaintBoundary(key: const ValueKey('shot'), child: child!),
    home: SessionScreen(
      client: FakeClient(),
      sessionId: 'sess-t',
      title: 'Tray test',
      onMenu: () {},
    ),
  ));
  await tester.pump(const Duration(milliseconds: 200));
  final attach = sockets.lastWhere((s) => s.uri.path.contains('attach'));
  attach.controller.add(jsonEncode({
    'wire': 'snapshot',
    'session_id': 'sess-t',
    'workspace': '/tmp/proj',
    ...snap,
  }));
  for (var i = 0; i < 4; i++) {
    await tester.pump(const Duration(milliseconds: 200));
  }
}

final _plus = find.byWidgetPredicate(
    (w) => w is ComposerIconButton && w.tooltip == 'Actions');

Future<void> _settle(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _done(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(minutes: 1));
  debugDefaultTargetPlatformOverride = null;
}

void main() {
  testWidgets('+ opens the tray; no Lanes row without lanes; second + closes',
      (tester) async {
    await _pumpSession(tester, {'status': 'idle', 'events': []});
    expect(find.text('Hand off'), findsNothing);
    expect(find.text('Fork from here'), findsNothing);

    await tester.tap(_plus);
    await _settle(tester);
    expect(find.text('Photo or file'), findsOneWidget);
    expect(find.text('Hand off'), findsOneWidget);
    expect(find.text('To another agent, after this turn'), findsOneWidget);
    expect(find.text('Fork from here'), findsOneWidget);
    expect(find.text('Lanes'), findsNothing);
    expect(find.text('Interrupt'), findsNothing);
    final turn = tester.widget<AnimatedRotation>(find.ancestor(
        of: _plus, matching: find.byType(AnimatedRotation)));
    expect(turn.turns, closeTo(0.125, 0.001));

    await tester.tap(_plus);
    await _settle(tester);
    expect(find.text('Hand off'), findsNothing);
    expect(find.text('Photo or file'), findsNothing);
    await _done(tester);
  });

  testWidgets('swiping the tray down puts it away; a short drag springs back',
      (tester) async {
    await _pumpSession(tester, {'status': 'idle', 'events': []});
    await tester.tap(_plus);
    await _settle(tester);
    expect(find.text('Hand off'), findsOneWidget);

    await tester.timedDrag(find.text('Fork from here'), const Offset(0, 30),
        const Duration(milliseconds: 600));
    await _settle(tester);
    await _settle(tester);
    expect(find.text('Hand off'), findsOneWidget);

    await tester.fling(find.text('Fork from here'), const Offset(0, 200), 1200);
    await _settle(tester);
    await _settle(tester);
    expect(find.text('Hand off'), findsNothing);
    await _done(tester);
  });

  testWidgets('running with lanes: Interrupt only with a draft, Lanes counts',
      (tester) async {
    await _pumpSession(tester, {
      'status': 'running',
      'events': [],
      'lanes': [
        {'id': 'l1', 'title': 'Goldens', 'status': 'running', 'started_at': ''},
        {'id': 'l2', 'title': 'Note', 'status': 'completed', 'started_at': ''},
      ],
    });
    await tester.tap(_plus);
    await _settle(tester);
    expect(find.text('Lanes'), findsOneWidget);
    expect(find.text('1 running'), findsOneWidget);
    // Empty draft: the send button already stops the turn.
    expect(find.text('Interrupt'), findsNothing);
    await tester.enterText(find.byType(TextField).last, 'also check 360');
    await tester.pump();
    expect(find.text('Interrupt'), findsOneWidget);
    await _shot(tester, 'tray_phone');
    tester.view.viewInsets = const FakeViewPadding(bottom: 330);
    await _settle(tester);
    await _shot(tester, 'tray_phone_keyboard');
    tester.view.resetViewInsets();
    await _settle(tester);
    // Interrupt sits at the top of the list.
    expect(tester.getTopLeft(find.text('Interrupt')).dy,
        lessThan(tester.getTopLeft(find.text('Photo or file')).dy));
    await _done(tester);
  });

  testWidgets('Hand off swaps the tray to the picker inline, back returns',
      (tester) async {
    await _pumpSession(tester, {'status': 'idle', 'events': []});
    await tester.tap(_plus);
    await _settle(tester);
    await tester.tap(find.text('Hand off'));
    await _settle(tester);
    expect(find.text('Hand off to'), findsOneWidget);
    expect(find.text('Photo or file'), findsNothing);
    // No sheet: the picker lives in the tray, not a new route.
    expect(find.byType(BottomSheet), findsNothing);
    expect(find.text('Moss'), findsOneWidget);
    await tester.tap(find.text('Moss'));
    await tester.pump();
    expect(find.text('Hand to Moss'), findsOneWidget);
    expect(find.text('Note for Moss (optional)'), findsOneWidget);

    await tester.tap(find.descendant(
        of: find.byType(ComposerTrayHeader),
        matching: find.byType(InkWell)));
    await _settle(tester);
    expect(find.text('Hand off to'), findsNothing);
    expect(find.text('Photo or file'), findsOneWidget);
    await _done(tester);
  });

  testWidgets('Fork swaps to the two choices; tapping outside closes',
      (tester) async {
    await _pumpSession(tester, {'status': 'idle', 'events': []});
    await tester.tap(_plus);
    await _settle(tester);
    await tester.tap(find.text('Fork from here'));
    await _settle(tester);
    expect(find.text('Fork this conversation'), findsOneWidget);
    expect(find.text('From this message'), findsOneWidget);
    expect(find.text('Full history'), findsOneWidget);

    await tester.tapAt(const Offset(195, 300));
    await _settle(tester);
    expect(find.text('Fork this conversation'), findsNothing);
    await _done(tester);
  });
}

class _Socket extends StreamChannelMixin implements WebSocketChannel {
  _Socket(this.uri);
  final Uri uri;
  final controller = StreamController<dynamic>.broadcast();
  @override
  Stream get stream => controller.stream;
  @override
  late final WebSocketSink sink = _Sink();
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
  @override
  void add(dynamic data) {}
  @override
  void addError(Object error, [StackTrace? stackTrace]) {}
  @override
  Future addStream(Stream stream) => Future.value();
  @override
  Future close([int? closeCode, String? closeReason]) => Future.value();
  @override
  Future get done => Future.value();
}

Future<void> _shot(WidgetTester t, String name) async {
  const dir = String.fromEnvironment('SHOT_DIR');
  if (dir.isEmpty) return;
  await t.runAsync(() async {
    final b = t.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('shot')));
    final img = await b.toImage(pixelRatio: 2);
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}
