import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:snippet/agent_character.dart';
import 'package:snippet/api.dart';
import 'package:snippet/chat/signal_row.dart' show agentNames;
import 'package:snippet/models.dart';
import 'package:snippet/screens/new_session_picker.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/theme.dart';

class _Daemon extends DaemonClient {
  _Daemon() : super('https://daemon.invalid', 't');

  @override
  late final DeviceEventHub deviceEvents = DeviceEventHub.local();

  @override
  Future<FsListing> fs(String? path) async => FsListing.fromJson({
        'path':
            path == null || path.isEmpty ? '/home/u' : path,
        'parent': '/home/u',
        'entries': [
          for (final n in [
            'snippet-desktop',
            'snippet-mobile',
            'snippet-service',
            'snippet-site',
            'technoxi'
          ])
            {'name': n, 'path': '/home/u/code/$n', 'is_dir': true},
        ],
      });

  @override
  Future<RepoWorktrees> worktrees(String folder) async =>
      RepoWorktrees.fromJson({
        'repo': folder,
        'worktrees': [
          {'path': folder, 'branch': 'main'},
        ],
      });

  @override
  Future<List<SessionInfo>> sessions({String? folder, int? limit}) async => [
        for (final (i, n)
            in ['snippet-mobile', 'snippet-service', 'technoxi'].indexed)
          SessionInfo.fromJson({
            'id': 's$i',
            'folder': '/home/u/code/$n',
            'title': n,
            'status': 'idle',
            'last_active': 100 - i,
          }),
      ];

  @override
  Future<ServerConfig> getConfig({bool force = false}) async =>
      ServerConfig.fromJson({
        'active': 'claude-opus',
        'profiles': [
          {'name': 'claude-opus', 'provider': 'anthropic', 'model': 'opus'},
        ],
      });
}

Future<void> _shot(WidgetTester t, String name) async {
  const dir = String.fromEnvironment('SHOT_DIR');
  if (dir.isEmpty) return;
  await t.runAsync(() async {
    final b = t.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('shot')));
    final img = await b.toImage();
    final bytes = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$dir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t
        .runAsync(() => Future<void>.delayed(const Duration(milliseconds: 40)));
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));
  tearDown(() => ThemeManager.instance.resetForTest());
  setUpAll(() => agentNames.value = {'snippet': 'Rook'});

  Future<void> pump(
      WidgetTester t, List<(String, WorkspaceMode, String?, String)> started,
      {Size size = const Size(390, 844)}) async {
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.runAsync(() async {
      await CharacterRoster.load();
      await ThemeManager.instance.setName('stone');
    });
    await t.pumpWidget(RepaintBoundary(
      key: const ValueKey('shot'),
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: buildAppTheme(),
        home: NewSessionPicker(
          client: _Daemon(),
          machineLabel: 'mac',
          onOpenFolder: (f, m) async {},
          onStart: (f, m, p, text, a) async => started.add((f, m, p, text)),
        ),
      ),
    ));
    await _settle(t);
  }

  testWidgets('prompt first: empty, typed, folder sheet', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final started = <(String, WorkspaceMode, String?, String)>[];
    await pump(t, started);
    expect(find.text('What are we making?'), findsOneWidget);
    expect(find.text('Rook starts a new session'), findsOneWidget);
    expect(find.text('Recent folders'), findsOneWidget);
    expect(find.text('Choose folder'), findsOneWidget);
    expect(find.text('Model'), findsOneWidget);
    expect(find.text('New worktree'), findsOneWidget);
    await _shot(t, 'ns-b-empty');

    await t.tap(find.byTooltip('Start'));
    await t.pump();
    expect(started, isEmpty);

    await t.enterText(find.byType(TextField),
        'Tighten the sidebar rows to the 44pt grid and rerun the goldens');
    await t.pump();
    await _shot(t, 'ns-b-text');

    await t.ensureVisible(find.text('Choose folder'));
    await t.pump();
    await t.tap(find.text('Choose folder'));
    await _settle(t);
    expect(find.text('Works in'), findsOneWidget);
    expect(find.textContaining('keeps this session off main'), findsOneWidget);
    await _shot(t, 'ns-b-folders');

    await t.tap(find.textContaining('Use '));
    await _settle(t);
    await t.tap(find.byTooltip('Start'));
    await t.pump(const Duration(milliseconds: 100));
    expect(started.single.$1, '/home/u');
    expect(started.single.$2, WorkspaceMode.worktree);
    expect(started.single.$4, startsWith('Tighten'));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('desktop: same structure at dialog size', (t) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    final started = <(String, WorkspaceMode, String?, String)>[];
    await pump(t, started, size: const Size(720, 640));
    expect(find.text('What are we making?'), findsOneWidget);
    expect(find.text('Recent folders'), findsOneWidget);
    await t.enterText(find.byType(TextField), 'Fix the flaky golden');
    await t.pump();
    await _shot(t, 'ns-b-desktop');
    await t.ensureVisible(find.text('Choose folder'));
    await t.pump();
    await t.tap(find.text('Choose folder'));
    await _settle(t);
    await _shot(t, 'ns-b-desktop-folders');
    await t.tap(find.textContaining('Use '));
    await _settle(t);
    await t.tap(find.byTooltip('Start'));
    await t.pump(const Duration(milliseconds: 100));
    expect(started.single.$4, 'Fix the flaky golden');
    debugDefaultTargetPlatformOverride = null;
  });
}
