import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/api.dart';
import 'package:snippet/command_palette.dart';
import 'package:snippet/glass.dart';
import 'package:snippet/goal_models.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/files.dart';
import 'package:snippet/screens/mission_board_panel.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/theme.dart';

const _readme = '''# snippet app

The Android, macOS, Linux and Windows client for [snippet](https://x).

The app connects to a `snippet serve` daemon running on your own machine. The code, the shell and the model keys stay on that machine; the app only attaches to its sessions over an authenticated WebSocket.

## What you can do

- Watch a session live and steer it: streamed replies, tool calls, diffs and approvals.
- Resume, rename and rewind sessions from any device.
- Run delegated lanes, each in its own git worktree, and follow their progress.
- Browse the file tree, review changes, stage files and open terminals.
- Talk to Mission Control by voice, with spoken replies (optional, set up in Settings).
- Switch between several machines.
''';
final _now = DateTime.now().millisecondsSinceEpoch ~/ 1000;

class C extends DaemonClient {
  C() : super('https://daemon.invalid', 't');
  final _h = DeviceEventHub.local();
  @override
  DeviceEventHub get deviceEvents => _h;
  @override
  Future<FsListing> fs(String? path) async {
    final p = path ?? '/home/u/code/snippet-mobile/lib';
    return FsListing.fromJson({'path': p, 'parent': '/home/u/code/snippet-mobile', 'entries': [
      for (final d in ['ambient', 'chat', 'composer', 'coordination', 'screens']) {'name': d, 'path': '$p/$d', 'is_dir': true, 'git': false},
      for (final f in ['api.dart', 'main.dart', 'models.dart', 'theme.dart', 'widgets.dart']) {'name': f, 'path': '$p/$f', 'is_dir': false, 'size': 32000, 'modified': _now - 3600},
    ]});
  }
  @override
  Future<FileContent> readFile(String path) async => FileContent.fromJson({'path': path, 'content': path.endsWith('.md') ? _readme : List.generate(40, (i) => i % 5 == 0 ? '  /// Touch geometry. These are hit areas, not type.' : '  static const gutter$i = 12.0;').join('\n'), 'size': 3200, 'hash': 'h'});
  @override
  Future<List<ArtifactInfo>> artifacts(String session) async => [ArtifactInfo.fromJson({'id': 'a1', 'title': 'Release note for #272', 'kind': 'markdown', 'caption': '', 'versions': [for (var n = 1; n <= 3; n++) {'n': n, 'created_at': _now - 600, 'entry': 'note.md', 'source': 'x', 'url': '/a/$n/note.md'}]})];
  @override
  Future<String> artifactText(String signedPath) async => _readme;
  @override
  Future<ServerConfig> getConfig({bool force = false}) async => ServerConfig.fromJson({'profiles': [{'name': 'opus', 'provider': 'anthropic', 'model': 'Claude Opus 4.6'}], 'active': 'opus'});
  @override
  Future<RepoWorktrees> worktrees(String folder) async => RepoWorktrees.fromJson({'repo': folder, 'worktrees': [{'path': folder, 'branch': 'main'}]});
  @override
  Future<List<SessionInfo>> sessions({String? folder, int? limit}) async => [
    for (final f in ['snippet-mobile', 'snippet-service']) SessionInfo.fromJson({'id': f, 'folder': '/home/u/code/$f', 'title': f, 'status': 'idle', 'last_active': _now - 100}),
  ];
  @override
  Future<List<CoordinationAgent>> coordinationAgents() async => [
    for (final a in [['snippet','Rook'],['moss','Moss'],['pip','Pip']])
      CoordinationAgent.fromJson({'id': a[0], 'display_name': a[1], 'handle': a[0], 'status': 'active'}),
  ];
  @override
  Future<MissionControlOverview> mcOverview() async => MissionControlOverview.fromJson({'recent_tasks': [
    {'id': 'T-244', 'title': 'Staging probe startup grace', 'status': 'in_review', 'updated_at': _now - 300, 'session_id': 's1'},
    {'id': 'T-248', 'title': 'Theme sync across daemon & client', 'status': 'in_progress', 'updated_at': _now - 840, 'session_id': 's2', 'current_step': 'Run tests and goldens', 'plan_done': 2, 'plan_total': 4},
    {'id': 'T-247', 'title': 'Sidebar 44pt row density pass', 'status': 'in_progress', 'updated_at': _now - 1320, 'session_id': 's3', 'plan_done': 3, 'plan_total': 5},
    {'id': 'T-250', 'title': 'Q3 churn brief with letter footnote', 'status': 'done', 'updated_at': _now - 60, 'session_id': 's4'},
  ]});
  @override
  Future<List<RecurringJob>> recurringJobs() async => const [];
  @override
  Future<List<Goal>> goals({String status = 'open'}) async => const [];
}


Future<void> _pump(WidgetTester t, Widget w, {bool phone = true}) async {
  debugDefaultTargetPlatformOverride =
      phone ? TargetPlatform.android : TargetPlatform.linux;
  Glass.enabled = false;
  SharedPreferences.setMockInitialValues({});
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = phone ? const Size(390, 844) : const Size(1280, 800);
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
      theme: buildAppTheme(), home: Scaffold(body: w)));
  await t.pumpAndSettle();
}

void main() {
  testWidgets('board: task cards, sections and filter', (t) async {
    final opened = <String>[];
    await _pump(
        t,
        MissionBoardPanel(
            client: C(), onOpenSession: (id, _) => opened.add(id)),
        phone: false);
    expect(find.text('Needs review'), findsWidgets);
    expect(find.text('In flight'), findsOneWidget);
    expect(find.text('Done today'), findsOneWidget);
    expect(find.text('Step 2 of 4'), findsOneWidget);
    expect(find.text('3 active'), findsOneWidget);
    await t.tap(find.text('Review'));
    expect(opened, ['s1']);
    await t.tap(find.byKey(const ValueKey('board-filter-review')));
    await t.pumpAndSettle();
    expect(find.text('In flight'), findsNothing);
    expect(find.byKey(const ValueKey('board-card-T-244')), findsOneWidget);
    expect(find.byKey(const ValueKey('board-card-T-250')), findsNothing);
    await t.tap(find.byKey(const ValueKey('board-filter-done')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('board-card-T-250')), findsOneWidget);
    expect(find.byKey(const ValueKey('board-card-T-248')), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('files on phone: crumbs, filter, tiles, grouped lists',
      (t) async {
    final chats = <String>[];
    await _pump(
        t,
        FileExplorer(
            client: C(),
            title: 'lib',
            start: '/home/u/code/snippet-mobile/lib',
            onNewChat: chats.add));
    expect(find.text('Folders'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('~'), findsOneWidget);
    for (final l in ['New chat', 'Git', 'Upload', 'New folder']) {
      expect(find.text(l), findsOneWidget);
    }
    await t.tap(find.text('New chat'));
    expect(chats, ['/home/u/code/snippet-mobile/lib']);
    await t.enterText(find.byType(TextField), 'scr');
    await t.pumpAndSettle();
    expect(find.text('screens'), findsOneWidget);
    expect(find.text('chat'), findsNothing);
    expect(find.text('Files'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('palette: empty query shows a taste of each kind', (t) async {
    PaletteItem i(PaletteKind k, String title) =>
        PaletteItem(id: title, kind: k, icon: 'file', title: title, run: () {});
    await _pump(
        t,
        Builder(
            builder: (c) => TextButton(
                onPressed: () => showCommandPalette(c, items: [
                      i(PaletteKind.chat, 'Staging deploy'),
                      i(PaletteKind.setting, 'Routing'),
                      i(PaletteKind.setting, 'Voice'),
                      i(PaletteKind.setting, 'Wakes'),
                    ], sources: [
                      PaletteSource(PaletteKind.pr,
                          () async => [i(PaletteKind.pr, '#280 Notch HUD')]),
                    ]),
                child: const Text('go'))));
    await t.tap(find.text('go'));
    await t.pumpAndSettle();
    expect(find.text('Pull requests'), findsOneWidget);
    expect(find.text('#280 Notch HUD'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);
    expect(find.text('Routing'), findsOneWidget);
    expect(find.text('Wakes'), findsNothing);
    debugDefaultTargetPlatformOverride = null;
  });
}
