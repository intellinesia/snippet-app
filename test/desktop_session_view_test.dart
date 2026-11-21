import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/chat/activity_dock.dart';
import 'package:snippet/chat/ledger_line.dart';
import 'package:snippet/api.dart';
import 'package:snippet/motion.dart';
import 'package:snippet/screens/session.dart';
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
  String sessionId = 'sess-1',
  VoidCallback? onTogglePanel,
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
      sessionId: sessionId,
      title: 'Test Session',
      onTogglePanel: onTogglePanel,
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

List<Widget> _activityRows() => [
      for (var i = 0; i < 2; i++)
        DenseToolRow(
          tool: 'change_files',
          args: {
            'path': 'lib/f$i.dart',
            'action': 'replace',
            'find': 'a',
            'with': 'b',
          },
          result: const {'status': 'ok'},
        ),
      for (var i = 0; i < 6; i++)
        DenseToolRow(
          tool: 'bash',
          args: {'command': 'echo $i'},
          result: const {
            'data': {'exit_code': 0}
          },
        ),
    ];

void _usePhoneView() {
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  addTearDown(() => debugDefaultTargetPlatformOverride = null);
}

Future<void> _pumpRows(WidgetTester tester, Widget child) async {
  tester.view.devicePixelRatio = 1;
  tester.view.physicalSize = const Size(390, 844);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(body: child),
  ));
  await tester.pump();
}

void main() {
  test('activitySummary joins parts with dots in reading order', () {
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
        result: {
          'data': {'exit_code': 0}
        },
      ),
      const ToolStep(
        tool: 'bash',
        args: {'command': 'pwd'},
        result: {
          'data': {'exit_code': 0}
        },
      ),
    ]);
    expect(summary, 'Edited 3 files, searched 1 time, ran pwd');
  });

  testWidgets(
      'CollapsedActivity collapses consecutive tools and expands in place',
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
            result: const {
              'data': {'exit_code': 0}
            },
          ),
        ]),
      ),
    ));
    await tester.pump();

    // Without timings the fold names the work instead of counting steps.
    // Desktop folds a finished run into one ledger sentence.
    expect(find.byType(LedgerLine), findsOneWidget);
    expect(find.text('Show'), findsNothing);
    expect(find.text('Hide'), findsNothing);
    expect(find.byType(DenseToolRow), findsNothing);
    expect(find.byType(WorkingDots), findsNothing);
    // The leading status icon toggles every step.
    final summary = find
        .descendant(of: find.byType(LedgerLine), matching: find.byType(AppIcon))
        .first;
    await tester.tap(summary);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.byType(DenseToolRow), findsNWidgets(2));

    await tester.tap(summary);
    await tester.pumpAndSettle();
    expect(find.byType(DenseToolRow), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('CollapsedActivity shows a pulsing chevron when running',
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

    // A running run shows its live row, with the command's terminal open.
    expect(find.byType(LedgerStrip), findsOneWidget);
    expect(find.text('Running tests'), findsOneWidget);
    expect(find.text('flutter test'), findsOneWidget);
    expect(find.text('Show'), findsNothing);
    expect(find.byType(WorkingDots), findsNothing);
    // Peek with its Space key; Stop only appears when the session can stop.
    expect(find.text('Peek'), findsOneWidget);
    expect(find.text('Space'), findsOneWidget);
    expect(find.text('Stop'), findsNothing);
    expect(find.byType(RunSpinner), findsOneWidget);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('phone keeps the dock between tool calls while the model thinks',
      (tester) async {
    final socket = await _pumpSession(tester,
        platform: TargetPlatform.android, size: const Size(390, 844));
    socket.pushJson({
      'wire': 'snapshot',
      'status': 'running',
      'workspace': '/tmp/ws',
      'events': [
        {'kind': 'user_input', 'text': 'fix it'},
        _bashCall('echo 1'),
        _bashResult(),
      ],
    });
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(ActivityDock), findsOneWidget);
    expect(find.byType(ActivityPill), findsNothing);
    await _disposeSession(tester);
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

      if (desktop) {
        expect(find.byType(LedgerLine), findsOneWidget);
        expect(find.byType(LedgerStrip), findsOneWidget);
        expect(find.text('flutter analyze'), findsOneWidget);
        expect(find.byType(DenseToolRow), findsNothing);

        await tester.tap(find.text('Peek'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 300));
        expect(find.text('Steps so far'), findsOneWidget);
        expect(find.text('1 command'), findsOneWidget);
      } else {
        // Phone: the finished run is one pill, the live run is the dock.
        expect(find.byType(WorkLine), findsNothing);
        expect(find.byType(DenseToolRow), findsNothing);
        expect(find.byType(ActivityPill), findsOneWidget);
        expect(find.byType(ActivityDock), findsOneWidget);
        expect(
            find.textContaining('Running flutter analyze', findRichText: true),
            findsOneWidget);

        await tester.tap(find.byType(ActivityPill));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        expect(find.text('Activity'), findsOneWidget);
        expect(find.text('Edited 3 files'), findsOneWidget);
      }

      await _disposeSession(tester);
    });
  }

  testWidgets(
      'tapping the summary reveals the rows and tapping again hides '
      'them', (tester) async {
    _usePhoneView();
    await _pumpRows(tester, CollapsedActivity(_activityRows()));

    await tester.tap(find.byType(WorkLine));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(DenseToolRow), findsNWidgets(8));
    expect(find.text('Show'), findsNothing);
    expect(find.text('Hide'), findsNothing);

    await tester.tap(find.byType(WorkLine));
    await tester.pumpAndSettle();

    expect(find.byType(DenseToolRow), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets(
      'work summary shows outcome when collapsed and command '
      'duration when expanded', (tester) async {
    _usePhoneView();
    await _pumpRows(
      tester,
      CollapsedActivity(const [
        DenseToolRow(
          tool: 'read_file',
          args: {'path': 'lib/a.dart'},
          result: {'status': 'ok'},
        ),
        DenseToolRow(
          tool: 'change_files',
          args: {
            'path': 'lib/a.dart',
            'action': 'replace',
            'find': 'old',
            'with': 'new',
          },
          result: {'status': 'ok'},
        ),
        DenseToolRow(
          tool: 'bash',
          args: {'command': 'flutter test test/work_notes_test.dart'},
          result: {
            'status': 'ok',
            'data': {
              'exit_code': 0,
              'duration_ms': 1400,
              'stdout': '00:01 +7: All tests passed!',
            },
          },
        ),
      ]),
    );

    final summary = find.textContaining('Worked for 1.4s', findRichText: true);
    expect(summary, findsOneWidget);

    await tester.tap(summary);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byType(DenseToolRow), findsNWidgets(3));
    await tester.tap(find.textContaining(
        'flutter test test/work_notes_test.dart',
        findRichText: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.text('1.4s'), findsWidgets);
    debugDefaultTargetPlatformOverride = null;
  });
}
