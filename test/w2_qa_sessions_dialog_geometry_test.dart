import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/api.dart';
import 'package:snippet/app_dialog.dart';
import 'package:snippet/chat/stage_bar.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/mobile_home/sessions_list_phone.dart';
import 'package:snippet/screens/new_session_draft.dart';
import 'package:snippet/screens/session.dart';
import 'package:snippet/screens/session_handoff.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/widgets.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _FakeClient extends DaemonClient {
  _FakeClient({this.settled = false}) : super('http://127.0.0.1:1', 'tok');
  final bool settled;

  @override
  Future<List<SessionInfo>> sessions({String? folder, int? limit}) async => [
        SessionInfo.fromJson({
          'id': 'sess-w2',
          'title': 'Wire the wake',
          'status': settled ? 'idle' : 'running',
          'settled': settled,
          'branch': 'feat/redesign-all',
          'folder': '/Users/x/snippet-mobile-all',
          'agent_id': 'snippet',
        }),
      ];

  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => [
        CoordinationAgent.fromJson({
          'id': 'sashy',
          'display_name': 'Sashy',
          'status': 'active',
          'kind': 'agent',
        }),
        CoordinationAgent.fromJson({
          'id': 'rook',
          'display_name': 'Rook',
          'status': 'active',
          'kind': 'agent',
        }),
      ];

  @override
  Future<Map<String, dynamic>> handOffSession(String session, String toAgent,
          {String? note}) async =>
      {'pending': false};
}

class _FakeSocket extends StreamChannelMixin implements WebSocketChannel {
  _FakeSocket(this.uri);
  final Uri uri;
  final controller = StreamController<dynamic>.broadcast();
  @override
  Stream get stream => controller.stream;
  @override
  late final WebSocketSink sink = _FakeSink();
  @override
  int? get closeCode => null;
  @override
  String? get closeReason => null;
  @override
  String? get protocol => null;
  @override
  Future<void> get ready => Future.value();
}

class _FakeSink implements WebSocketSink {
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

Widget _app(double scale, Widget home) => MaterialApp(
      theme: buildAppTheme(),
      builder: (c, ch) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: ch!,
      ),
      home: home,
    );

void _phoneTest(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (t) async {
    SharedPreferences.setMockInitialValues({});
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    addTearDown(t.view.reset);
    try {
      await body(t);
    } finally {
      debugDefaultTargetPlatformOverride = null;
      DaemonClient.wsConnector = null;
    }
  });
}

void main() {
  for (final w in [360.0, 393.0, 430.0]) {
    for (final s in [1.0, 2.0]) {
      _phoneTest('SE-03 header and Wake button w=$w s=$s', (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = Size(w, 852);
        addTearDown(t.view.reset);

        final sockets = <_FakeSocket>[];
        DaemonClient.wsConnector = (uri, {connectTimeout, pingInterval}) {
          final sock = _FakeSocket(uri);
          sockets.add(sock);
          return sock;
        };

        await t.pumpWidget(_app(
          s,
          SessionScreen(
            client: _FakeClient(settled: true),
            sessionId: 'sess-w2',
            title: 'Wire the wake',
            onMenu: () {},
          ),
        ));
        await t.pump(const Duration(milliseconds: 200));
        final attach = sockets.lastWhere((e) => e.uri.path.contains('attach'));
        attach.controller.add(jsonEncode({
          'wire': 'snapshot',
          'session_id': 'sess-w2',
          'workspace': '/Users/x/snippet-mobile-all',
          'status': 'idle',
          'events': [],
        }));
        for (var i = 0; i < 4; i++) {
          await t.pump(const Duration(milliseconds: 200));
        }
        expect(t.takeException(), isNull);

        final header = find.byType(StageBar);
        final headerCard = t.getRect(find
            .descendant(of: header, matching: find.byType(Container))
            .first);
        final backIcon = find.descendant(
            of: header,
            matching: find.byWidgetPredicate(
                (x) => x is AppIcon && x.name == 'chevron-left'));
        final moreIcon = find.descendant(
            of: header,
            matching: find.byWidgetPredicate(
                (x) => x is AppIcon && x.name == 'more-horizontal'));
        final wake = t.getRect(find
            .ancestor(of: find.text('Wake'), matching: find.byType(InkWell))
            .first);

        debugPrint(
            'MEASURE SE-03 w=${w.toInt()} s=${s}x: header=${headerCard.left.toStringAsFixed(1)},${headerCard.width.toStringAsFixed(1)}x${headerCard.height.toStringAsFixed(1)} '
            'wake=${wake.width.toStringAsFixed(1)}x${wake.height.toStringAsFixed(1)}');

        // v19 XO-03 supersedes the old plain bar: the phone chat header is a
        // surface card inset x16 with one trailing icon. Wake keeps its existing
        // settled-bar target because the written delta does not supersede it.
        expect(headerCard.left, 16);
        expect(headerCard.width, w - 32);
        if (s == 1.0) expect(headerCard.height, 58);
        expect(headerCard.height, greaterThanOrEqualTo(58));
        expect(backIcon, findsOneWidget);
        expect(moreIcon, findsOneWidget);
        expect(wake.height, greaterThanOrEqualTo(44));

        await t.pumpWidget(const SizedBox.shrink());
        await t.pump();
      });

      _phoneTest('SE-06 hand-off page w=$w s=$s', (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = Size(w, 852);
        addTearDown(t.view.reset);

        final client = _FakeClient();
        await t.pumpWidget(_app(
          s,
          Builder(
            builder: (ctx) => Scaffold(
              body: TextButton(
                key: const Key('open'),
                onPressed: () => showHandOffSheet(
                  ctx,
                  client: client,
                  sessionId: 'sess-w2',
                  sessionTitle: 'Wire the wake',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ));
        await t.tap(find.byKey(const Key('open')));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.text('Hand off session'), findsOneWidget);

        final row = t.getRect(find.bySemanticsLabel('Sashy'));
        await t.tap(find.text('Sashy'));
        await t.pump();
        expect(find.text('Selected'), findsOneWidget);

        final noteBox = t.getRect(find
            .ancestor(
                of: find.byType(TextField), matching: find.byType(DecoratedBox))
            .first);
        final btn = t.getRect(find.bySemanticsLabel('Hand off to Sashy'));

        debugPrint(
            'MEASURE SE-06 w=${w.toInt()} s=${s}x: row=${row.width.toStringAsFixed(1)}x${row.height.toStringAsFixed(1)} '
            'note=${noteBox.width.toStringAsFixed(1)}x${noteBox.height.toStringAsFixed(1)} '
            'btn=${btn.width.toStringAsFixed(1)}x${btn.height.toStringAsFixed(1)}');

        expect(row.width, w - 16);
        expect(row.height, greaterThanOrEqualTo(56));
        expect(noteBox.width, w - 32);
        expect(noteBox.height, greaterThanOrEqualTo(92));
        expect(btn.width, w - 32);
        expect(btn.height, greaterThanOrEqualTo(48));
      });

      _phoneTest('SE-05 new session attach button w=$w s=$s', (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = Size(w, 852);
        addTearDown(t.view.reset);

        await t.pumpWidget(_app(
          s,
          NewSessionDraft(
            client: _FakeClient(),
            machineLabel: 'Mac mini',
            folder: '/Users/x/snippet-mobile-all',
            layout: NewSessionLayout.phone,
            onStart: (_, __, ___, ____) async {},
          ),
        ));
        await t.pump();
        expect(t.takeException(), isNull);

        final card = t.getRect(find
            .ancestor(
                of: find.text('What should it do?'),
                matching: find.byType(Container))
            .last);
        final attach = t.getRect(find.bySemanticsLabel('Add context'));
        final start = t.getRect(find.bySemanticsLabel('Start'));

        debugPrint(
            'MEASURE SE-05 w=${w.toInt()} s=${s}x: card=${card.left.toStringAsFixed(1)},${card.width.toStringAsFixed(1)}x${card.height.toStringAsFixed(1)} '
            'attach=${attach.left.toStringAsFixed(1)},${attach.width.toStringAsFixed(1)}x${attach.height.toStringAsFixed(1)} '
            'start=${start.width.toStringAsFixed(1)}x${start.height.toStringAsFixed(1)}');

        expect(card.left, 16);
        expect(card.width, w - 32);
        // Attach sits inside the prompt box; Start is in the top bar.
        expect(attach.size, const Size(48, 48));
        expect(attach.left, 32);
        expect(start.height, 48);
      });

      _phoneTest('SE-02 zero Needs you chip hidden w=$w s=$s', (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = Size(w, 852);
        addTearDown(t.view.reset);

        final idleOnly = [
          SessionInfo.fromJson({
            'id': 'i1',
            'title': 'Idle one',
            'status': 'idle',
            'folder': '/Users/x/snippet-mobile-all',
            'last_active': DateTime.now().millisecondsSinceEpoch ~/ 1000 - 120,
          }),
        ];
        await t.pumpWidget(_app(
          s,
          Scaffold(
            body: QuietSessionsScreen(
              sessions: idleOnly,
              agents: const [],
              onOpenSession: (_) {},
            ),
          ),
        ));
        await t.pump();
        expect(t.takeException(), isNull);
        expect(find.textContaining('Needs you'), findsNothing);
        final allChip = t.getRect(find.bySemanticsLabel('All, 1'));
        final doneChip = t.getRect(find.bySemanticsLabel('Done, 1'));

        debugPrint(
            'MEASURE SE-02 w=${w.toInt()} s=${s}x: needsHidden=true all=${allChip.width.toStringAsFixed(1)}x${allChip.height.toStringAsFixed(1)} '
            'done=${doneChip.width.toStringAsFixed(1)}x${doneChip.height.toStringAsFixed(1)}');

        expect(allChip.height, 44);
        expect(doneChip.height, 44);
      });

      _phoneTest('DL-01 confirm Cancel button visible edge w=$w s=$s',
          (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = Size(w, 852);
        addTearDown(t.view.reset);

        await t.pumpWidget(_app(
          s,
          Builder(
            builder: (ctx) => Scaffold(
              body: TextButton(
                key: const Key('open'),
                onPressed: () => confirmAction(
                  ctx,
                  title: 'Leave this group?',
                  body: 'You will stop seeing its messages.',
                  confirmLabel: 'Leave group',
                ),
                child: const Text('open'),
              ),
            ),
          ),
        ));
        await t.tap(find.byKey(const Key('open')));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);

        final cardRect = t.getRect(find.byType(AppDialogCard));
        final cardMat = t.widget<Material>(find
            .descendant(
                of: find.byType(AppDialogCard), matching: find.byType(Material))
            .first);
        final cancelMat = t.widget<Material>(find
            .ancestor(of: find.text('Cancel'), matching: find.byType(Material))
            .first);
        final cancelContainer = t.widget<Container>(find
            .ancestor(of: find.text('Cancel'), matching: find.byType(Container))
            .first);
        final cancelRect = t.getRect(find
            .ancestor(of: find.text('Cancel'), matching: find.byType(InkWell))
            .first);
        final confirmRect = t.getRect(find
            .ancestor(
                of: find.text('Leave group'), matching: find.byType(InkWell))
            .first);

        final dec = cancelContainer.decoration as BoxDecoration?;
        final border = dec?.border as Border?;

        debugPrint(
            'MEASURE DL-01 w=${w.toInt()} s=${s}x: card=${cardRect.width.toStringAsFixed(1)}x${cardRect.height.toStringAsFixed(1)} '
            'cardBg=${cardMat.color} cancelBg=${cancelMat.color} border=${border?.top.color} '
            'cancel=${cancelRect.width.toStringAsFixed(1)}x${cancelRect.height.toStringAsFixed(1)} '
            'confirm=${confirmRect.width.toStringAsFixed(1)}x${confirmRect.height.toStringAsFixed(1)}');

        expect(cardRect.width, w - 48);
        expect(cardMat.color, AppColors.surface1);
        expect(cancelMat.color, AppColors.surface2);
        expect(cardMat.color, isNot(cancelMat.color));
        expect(border?.top.color, AppColors.line);
        expect(cancelRect.height, greaterThanOrEqualTo(48));
        expect(confirmRect.height, greaterThanOrEqualTo(48));
      });
    }
  }
}
