import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/api.dart';
import 'package:snippet/composer/composer_card.dart';
import 'package:snippet/models.dart';
import 'package:snippet/motion.dart';
import 'package:snippet/screens/lanes.dart';
import 'package:snippet/screens/session.dart';
import 'package:snippet/term.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/tool_activity.dart';
import 'package:snippet/transcript.dart';
import 'package:snippet/widgets.dart';
import 'package:stream_channel/stream_channel.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

class _FakeSocket extends StreamChannelMixin implements WebSocketChannel {
  final _controller = StreamController<dynamic>.broadcast();
  final List<String> sent = [];

  @override
  Stream get stream => _controller.stream;

  @override
  late final WebSocketSink sink = _FakeSink(_controller.sink, sent);

  @override
  int? get closeCode => null;

  @override
  String? get closeReason => null;

  @override
  String? get protocol => null;

  @override
  Future<void> get ready => Future.value();

  void pushJson(Map<String, dynamic> payload) {
    _controller.add(jsonEncode(payload));
  }
}

class _FakeSink implements WebSocketSink {
  _FakeSink(this._sink, this._sent);
  final StreamSink _sink;
  final List<String> _sent;

  @override
  void add(dynamic data) {
    if (data is String) _sent.add(data);
  }

  @override
  void addError(Object error, [StackTrace? stackTrace]) {}

  @override
  Future addStream(Stream stream) => Future.value();

  @override
  Future close([int? closeCode, String? closeReason]) => _sink.close();

  @override
  Future get done => _sink.done;
}

Map<String, dynamic> _editCall(String path) => {
      'kind': 'tool_call',
      'tool_name': 'change_files',
      'arguments': {
        'path': path,
        'action': 'replace',
        'find': 'old',
        'with': 'new',
      },
    };

Map<String, dynamic> _editResult() => {
      'kind': 'tool_result',
      'tool_name': 'change_files',
      'result': {'status': 'ok'},
    };

Map<String, dynamic> _bashCall(String cmd) => {
      'kind': 'tool_call',
      'tool_name': 'bash',
      'arguments': {'command': cmd},
    };

Map<String, dynamic> _bashResult([int code = 0]) => {
      'kind': 'tool_result',
      'tool_name': 'bash',
      'result': {
        'data': {'exit_code': code},
      },
    };

Future<_FakeSocket> _pumpSession(
  WidgetTester tester, {
  required TargetPlatform platform,
  Size size = const Size(1280, 800),
}) async {
  debugDefaultTargetPlatformOverride = platform;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
  final socket = _FakeSocket();
  DaemonClient.wsConnector = (uri, {connectTimeout, pingInterval}) => socket;
  addTearDown(() => DaemonClient.wsConnector = null);
  SharedPreferences.setMockInitialValues({});
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: SessionScreen(
      client: DaemonClient('http://127.0.0.1:9090', 'tok'),
      sessionId: 'sess-1',
      title: 'Test Session',
    ),
  ));
  await tester.pump();
  return socket;
}

Future<void> _disposeSession(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 300));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump();
  debugDefaultTargetPlatformOverride = null;
}

void main() {
  test('activitySummary formats edited files before commands', () {
    expect(activitySummary(const []), '');
    final summary = activitySummary([
      const ToolStep(
        tool: 'change_files',
        args: {
          'changes': [
            {'path': 'a.dart', 'action': 'replace', 'find': 'x', 'with': 'y'},
            {'path': 'b.dart', 'action': 'replace', 'find': 'x', 'with': 'y'},
            {'path': 'c.dart', 'action': 'replace', 'find': 'x', 'with': 'y'},
          ],
        },
        result: {'status': 'ok'},
      ),
      const ToolStep(
        tool: 'bash',
        args: {'command': 'ls'},
        result: {'data': {'exit_code': 0}},
      ),
      const ToolStep(
        tool: 'bash',
        args: {'command': 'pwd'},
        result: {'data': {'exit_code': 0}},
      ),
    ]);
    expect(summary, 'Edited 3 files, ran 2 commands');
  });

  testWidgets('CollapsedActivity collapses consecutive tools and expands in place',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: CollapsedActivity([
          DenseToolRow(
            tool: 'change_files',
            args: const {
              'path': 'lib/a.dart',
              'action': 'replace',
              'find': 'a',
              'with': 'b',
            },
            result: const {'status': 'ok'},
          ),
          DenseToolRow(
            tool: 'bash',
            args: const {'command': 'echo hi'},
            result: const {'data': {'exit_code': 0}},
          ),
        ]),
      ),
    ));
    await tester.pump();

    expect(find.text('Edited 1 file, ran 1 command'), findsOneWidget);
    expect(find.text('Show'), findsOneWidget);
    expect(find.text('Hide'), findsNothing);
    expect(find.byType(DenseToolRow), findsNothing);
    expect(find.byType(WorkingDots), findsNothing);
    expect(
      find.descendant(
        of: find.byType(CollapsedActivity),
        matching: find.byType(AppIcon),
      ),
      findsNothing,
    );

    await tester.tap(find.text('Edited 1 file, ran 1 command'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(DenseToolRow), findsNWidgets(2));
    expect(find.text('Hide'), findsOneWidget);
    expect(find.text('Show'), findsNothing);

    await tester.tap(find.text('Hide'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(DenseToolRow), findsNothing);
    expect(find.text('Show'), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('CollapsedActivity shows a Show line with no icons when running',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: const Scaffold(
        body: CollapsedActivity(
          [
            DenseToolRow(
              tool: 'bash',
              args: {'command': 'flutter test'},
            ),
          ],
          running: true,
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('Running flutter test'), findsOneWidget);
    expect(find.text('Show'), findsOneWidget);
    expect(find.byType(WorkingDots), findsNothing);
    expect(
      find.descendant(
        of: find.byType(CollapsedActivity),
        matching: find.byType(AppIcon),
      ),
      findsNothing,
    );
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('SessionContextBar hides zero counts and opens on tap',
      (tester) async {
    var lanesTapped = 0;
    var termsTapped = 0;

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: SessionContextBar(
          laneCount: 0,
          laneRunning: false,
          onTapLanes: () => lanesTapped++,
          termCount: 0,
          termRunning: false,
          onTapTerms: () => termsTapped++,
        ),
      ),
    ));
    expect(find.textContaining('Lanes'), findsNothing);
    expect(find.textContaining('terminal'), findsNothing);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: SessionContextBar(
          laneCount: 4,
          laneRunning: false,
          onTapLanes: () => lanesTapped++,
          termCount: 2,
          termRunning: true,
          onTapTerms: () => termsTapped++,
        ),
      ),
    ));
    expect(find.text('Lanes 4'), findsOneWidget);
    expect(find.text('2 terminals'), findsOneWidget);

    await tester.tap(find.text('Lanes 4'));
    await tester.tap(find.text('2 terminals'));
    expect(lanesTapped, 1);
    expect(termsTapped, 1);
  });

  testWidgets('SessionContextFooter shows context, cache, and weekly stats',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: SessionContextFooter(
          contextWindow: 200000,
          lastPromptTokens: 160000,
          cacheReadTokens: 42000,
          rateSecondary: RateWindow.fromJson({
            'used_percent': 7,
            'window_minutes': 10080,
          }),
        ),
      ),
    ));
    expect(find.text('80% context'), findsOneWidget);
    expect(find.text('42k cached'), findsOneWidget);
    expect(find.text('7% this week'), findsOneWidget);

    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: const Scaffold(
        body: SessionContextFooter(
          contextWindow: 0,
          lastPromptTokens: 0,
          cacheReadTokens: 0,
        ),
      ),
    ));
    expect(find.textContaining('context'), findsNothing);
    expect(find.textContaining('cached'), findsNothing);
  });

  for (final desktop in [true, false]) {
    testWidgets(
        'SessionScreen renders collapsed activity (${desktop ? 'desktop' : 'phone'})',
        (tester) async {
      final socket = await _pumpSession(
        tester,
        platform: desktop ? TargetPlatform.linux : TargetPlatform.android,
        size: desktop ? const Size(1280, 800) : const Size(390, 844),
      );
      socket.pushJson({
        'wire': 'snapshot',
        'status': 'running',
        'workspace': '/tmp/ws',
        'events': [
          {'kind': 'user_input', 'text': 'fix it'},
          _editCall('a.dart'),
          _editResult(),
          _editCall('b.dart'),
          _editResult(),
          _editCall('c.dart'),
          _editResult(),
          _bashCall('echo 1'),
          _bashResult(),
          _bashCall('echo 2'),
          _bashResult(),
          {'kind': 'assistant_text', 'text': 'Done editing.'},
          _bashCall('flutter analyze'),
        ],
      });
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Edited 3 files, ran 2 commands'), findsOneWidget);
      expect(find.text('Running flutter analyze'), findsOneWidget);
      expect(find.byType(DenseToolRow), findsNothing);
      expect(find.text('Show'), findsNWidgets(2));

      await tester.tap(find.text('Edited 3 files, ran 2 commands'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(DenseToolRow), findsNWidgets(5));

      await _disposeSession(tester);
    });
  }

  testWidgets('Desktop SessionScreen shows ctxbar chips and cfoot under composer',
      (tester) async {
    final socket = await _pumpSession(
      tester,
      platform: TargetPlatform.linux,
      size: const Size(1280, 800),
    );
    socket.pushJson({
      'wire': 'snapshot',
      'status': 'idle',
      'workspace': '/tmp/ws',
      'context_window': 200000,
      'last_prompt_tokens': 160000,
      'cache_read_tokens': 42000,
      'rate_limit': {
        'secondary': {'used_percent': 7, 'window_minutes': 10080},
      },
      'lanes': [
        {
          'id': 'l1',
          'title': 'Worker 1',
          'status': 'running',
          'started_at': '2026-11-12T20:00:00Z',
        },
        {
          'id': 'l2',
          'title': 'Worker 2',
          'status': 'completed',
          'started_at': '2026-11-12T20:00:00Z',
        },
      ],
      'events': [
        {'kind': 'user_input', 'text': 'hello'},
      ],
    });
    socket.pushJson({
      'wire': 'term',
      'op': 'snapshot',
      'id': '0',
      'alive': true,
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    final composerBox = tester.getRect(find.byType(ComposerCard));
    final lanesBox = tester.getRect(find.text('Lanes 2'));
    final termBox = tester.getRect(find.text('1 terminal'));
    final ctxBox = tester.getRect(find.text('80% context'));

    expect(lanesBox.bottom, lessThanOrEqualTo(composerBox.top));
    expect(termBox.bottom, lessThanOrEqualTo(composerBox.top));
    expect(ctxBox.top, greaterThanOrEqualTo(composerBox.bottom));
    expect(find.text('42k cached'), findsOneWidget);
    expect(find.text('7% this week'), findsOneWidget);

    await tester.tap(find.text('1 terminal'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(SessionTermView), findsOneWidget);

    await tester.tap(find.text('Lanes 2'));
    await tester.pumpAndSettle();
    expect(find.byType(LanesScreen), findsOneWidget);

    await _disposeSession(tester);
  });

  testWidgets('Phone SessionScreen hides desktop ctxbar and cfoot',
      (tester) async {
    final socket = await _pumpSession(
      tester,
      platform: TargetPlatform.android,
      size: const Size(390, 844),
    );
    socket.pushJson({
      'wire': 'snapshot',
      'status': 'idle',
      'workspace': '/tmp/ws',
      'context_window': 200000,
      'last_prompt_tokens': 160000,
      'cache_read_tokens': 42000,
      'lanes': [
        {
          'id': 'l1',
          'title': 'Worker 1',
          'status': 'running',
          'started_at': '2026-11-12T20:00:00Z',
        },
      ],
      'events': [],
    });
    socket.pushJson({
      'wire': 'term',
      'op': 'snapshot',
      'id': '0',
      'alive': true,
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(SessionContextBar), findsNothing);
    expect(find.byType(SessionContextFooter), findsNothing);
    expect(find.text('Lanes 1'), findsNothing);
    expect(find.text('1 terminal'), findsNothing);
    expect(find.text('80% context'), findsNothing);

    await _disposeSession(tester);
  });
}
