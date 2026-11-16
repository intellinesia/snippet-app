import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/session.dart';
import 'package:snippet/screens/session_coordination_cards.dart';
import 'package:snippet/theme.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _Client extends DaemonClient {
  _Client() : super('http://127.0.0.1:9090', 'tok');
  @override
  Future<List<SessionInfo>> sessions({String? folder, int? limit}) async => [
        SessionInfo.fromJson({
          'id': 's1',
          'title': 'Parity',
          'status': 'running',
          'agent_id': 'rook'
        }),
      ];
  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => [
        CoordinationAgent.fromJson(
            {'id': 'rook', 'display_name': 'Rook', 'handle': 'rook'}),
      ];
}

Map<String, dynamic> _msg(String lane, String body,
        {bool out = false, required int ago}) =>
    {
      'kind': 'agent_message',
      'agent_id': 'lane $lane',
      'body': body,
      'outbound': out,
      'at': DateTime.now().millisecondsSinceEpoch ~/ 1000 - ago,
    };

Map<String, dynamic> _lane(String id, String title, String status) => {
      'id': id,
      'title': title,
      'status': status,
      'started_at': '2026-11-16T15:07:27+00:00',
    };

Future<void> _mount(WidgetTester t, List<Map<String, dynamic>> events,
    List<Map<String, dynamic>> lanes) async {
  final onError = FlutterError.onError;
  // SessionScreen opens audio players that have no test plugin.
  FlutterError.onError = (d) {
    if (d.exceptionAsString().contains('audioplayers')) return;
    onError?.call(d);
  };
  _restore = onError;
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  SharedPreferences.setMockInitialValues({});
  final sockets = <_Socket>[];
  DaemonClient.wsConnector = (uri, {connectTimeout, pingInterval}) {
    final s = _Socket(uri);
    sockets.add(s);
    return s;
  };
  t.view.devicePixelRatio = 2;
  t.view.physicalSize = const Size(390, 2400) * 2;
  await t.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: SessionScreen(
          client: _Client(), sessionId: 's1', title: 'Parity', onMenu: () {})));
  await t.pump(const Duration(milliseconds: 200));
  final attach = sockets.lastWhere((s) => s.uri.path.contains('attach'));
  attach.controller.add(jsonEncode({
    'wire': 'snapshot',
    'session_id': 's1',
    'workspace': '/tmp/w',
    'status': 'running',
    'events': events,
    'lanes': lanes,
  }));
  for (var i = 0; i < 6; i++) {
    await t.runAsync(() => Future.delayed(const Duration(milliseconds: 50)));
    await t.pump(const Duration(milliseconds: 200));
  }
}

Future<void> _unmount(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  DaemonClient.wsConnector = null;
  debugDefaultTargetPlatformOverride = null;
  t.view.resetPhysicalSize();
  t.view.resetDevicePixelRatio();
  FlutterError.onError = _restore;
}

FlutterExceptionHandler? _restore;

Finder _card(String text) => find.ancestor(
    of: find.textContaining(text, findRichText: true),
    matching: find.byType(LaneMessageCard));

void main() {

  testWidgets('groups a lane run and places the parent reply inside',
      (t) async {
    await _mount(t, [
      {'kind': 'user_input', 'text': 'Check every page.'},
      _msg('a', 'Settings: should Approvals open a sheet?', ago: 900),
      _msg('a', 'Round 5 wins.', out: true, ago: 850),
      _msg('b', 'Agents page captured.', ago: 700),
      _msg('b', 'Files page captured.', ago: 600),
      _msg('b', 'Terminals rendered directly.', ago: 500),
      _msg('a', 'Also check desktop.', out: true, ago: 300),
    ], [
      _lane('a', 'Parity: settings pages', 'running'),
      _lane('b', 'Parity: tools pages', 'running'),
    ]);

    expect(find.byType(LaneMessageCard), findsNWidgets(3));
    // The tools lane's three notes are one card, showing the newest.
    expect(find.text('3 notes'), findsOneWidget);
    expect(find.text('2 earlier'), findsOneWidget);
    expect(find.text('Terminals rendered directly.'), findsOneWidget);
    expect(find.text('Agents page captured.'), findsNothing);
    await t.tap(find.text('2 earlier'));
    await t.pump();
    expect(find.text('Agents page captured.'), findsOneWidget);
    expect(_card('Agents page captured.'), findsOneWidget);
    expect(_card('Terminals rendered directly.').evaluate().single,
        _card('Agents page captured.').evaluate().single);

    // The reply sits in the asking lane's card, which now reads 'asked'.
    expect(find.text('asked'), findsOneWidget);
    expect(_card('Round 5 wins.').evaluate().single,
        _card('should Approvals open a sheet?').evaluate().single);
    expect(find.textContaining('Rook', findRichText: true), findsWidgets);

    // A later note to the lane with no lane message before it stands alone.
    expect(find.text('Told'), findsOneWidget);
    expect(_card('Also check desktop.'), findsOneWidget);
    expect(find.text('Open lane'), findsNothing);
    await _unmount(t);
  });

  testWidgets('an unanswered ask from a running lane is waiting', (t) async {
    await _mount(t, [
      _msg('a', 'Should the desktop row change too?', ago: 130),
    ], [
      _lane('a', 'Parity: settings pages', 'running'),
    ]);
    expect(find.text('asks · waiting 2 min'), findsOneWidget);
    expect(find.text('Open lane'), findsOneWidget);
    await _unmount(t);
  });

  testWidgets('a finished lane is not waiting', (t) async {
    await _mount(t, [
      _msg('a', 'Should the desktop row change too?', ago: 130),
    ], [
      _lane('a', 'Parity: settings pages', 'completed'),
    ]);
    expect(find.text('asks'), findsOneWidget);
    expect(find.textContaining('waiting'), findsNothing);
    expect(find.text('Open lane'), findsNothing);
    await _unmount(t);
  });

  test('status words', () {
    const ask = LaneNote(body: 'Which one?');
    const note = LaneNote(body: 'Done.');
    expect(laneStatusWord(notes: [note]), 'note');
    expect(laneStatusWord(notes: [note, note]), '2 notes');
    expect(laneStatusWord(notes: [note, ask]), 'asks');
    expect(laneStatusWord(notes: [ask], answered: true), 'asked');
    expect(laneStatusWord(notes: [note], answered: true), 'note');
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
