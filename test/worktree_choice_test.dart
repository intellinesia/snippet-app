import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/api.dart';
import 'package:snippet/desktop_pick.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/new_session_picker.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/theme.dart';

class _FakeDaemon extends DaemonClient {
  _FakeDaemon({
    required this.repo,
    this.sessionList = const [],
    this.profiles = const [],
    this.activeProfile,
  }) : super('https://daemon.invalid', 't');

  @override
  late final DeviceEventHub deviceEvents = DeviceEventHub.local();

  final bool repo;
  final List<SessionInfo> sessionList;
  final List<Map<String, dynamic>> profiles;
  final String? activeProfile;
  final List<String> worktreeQueries = [];

  @override
  Future<FsListing> fs(String? path) async {
    if (path == '/code/app/lib') {
      return FsListing.fromJson({
        'path': '/code/app/lib',
        'parent': '/code/app',
        'entries': [],
      });
    }
    return FsListing.fromJson({
      'path': '/code/app',
      'parent': '/code',
      'entries': [
        {'name': 'lib', 'path': '/code/app/lib', 'is_dir': true},
      ],
    });
  }

  @override
  Future<RepoWorktrees> worktrees(String folder) async {
    worktreeQueries.add(folder);
    return RepoWorktrees.fromJson(
      repo
          ? {
              'repo': folder,
              'worktrees': [
                {'path': folder, 'branch': 'main'},
                {'path': '/wt/app/ab12', 'branch': 'snippet/ab12'},
              ],
            }
          : {'repo': null, 'worktrees': []},
    );
  }

  @override
  Future<List<SessionInfo>> sessions({String? folder, int? limit}) async =>
      sessionList;

  @override
  Future<ServerConfig> getConfig({bool force = false}) async =>
      ServerConfig.fromJson({
        'profiles': profiles,
        if (activeProfile != null) 'active': activeProfile,
      });
}

SessionInfo _session(String id, String folder, int lastActive) =>
    SessionInfo.fromJson({
      'id': id,
      'folder': folder,
      'title': id,
      'status': 'idle',
      'last_active': lastActive,
    });

Future<
    ({
      List<(String, WorkspaceMode)> opened,
      List<(String, WorkspaceMode, String?, String, List<PickedLocalFile>)>
          started,
    })> _pump(
  WidgetTester tester,
  _FakeDaemon client, {
  bool withOnStart = false,
  VoidCallback? onClose,
}) async {
  final opened = <(String, WorkspaceMode)>[];
  final started =
      <(String, WorkspaceMode, String?, String, List<PickedLocalFile>)>[];
  tester.view.devicePixelRatio = 2.0;
  tester.view.physicalSize = const Size(390, 844) * 2.0;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: NewSessionPicker(
        client: client,
        machineLabel: 'mac',
        onClose: onClose,
        onOpenFolder: (folder, mode) async => opened.add((folder, mode)),
        onStart: withOnStart
            ? (folder, mode, profile, text, attachments) async =>
                started.add((folder, mode, profile, text, attachments))
            : null,
      ),
    ),
  ));
  await tester.pumpAndSettle();
  return (opened: opened, started: started);
}

void main() {
  Future<void> sendPrompt(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump();
    await tester.tap(find.byTooltip('Start'));
    await tester.pump(const Duration(milliseconds: 100));
  }

  testWidgets('in a repo a new chat defaults to a new worktree',
      (tester) async {
    final res = await _pump(tester, _FakeDaemon(repo: true));
    expect(find.text('What are we making?'), findsOneWidget);
    expect(find.text('Worktree'), findsOneWidget);
    expect(find.text('main'), findsOneWidget);
    await sendPrompt(tester, 'Build it');
    expect(res.opened.single, ('/code/app', WorkspaceMode.worktree));
  });

  testWidgets('the folder itself can be chosen via Worktree toggle',
      (tester) async {
    final res = await _pump(tester, _FakeDaemon(repo: true));
    await tester.tap(find.text('Worktree'));
    await tester.pumpAndSettle();
    await sendPrompt(tester, 'Work in folder');
    expect(res.opened.single, ('/code/app', WorkspaceMode.folder));
  });

  testWidgets('an existing worktree can be chosen from the folder sheet',
      (tester) async {
    final res = await _pump(tester, _FakeDaemon(repo: true));
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Works in'), findsOneWidget);
    await tester.tap(find.text('Existing (2)'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('snippet/ab12').last);
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use snippet/ab12'));
    await tester.pumpAndSettle();
    expect(find.text('snippet/ab12'), findsOneWidget);
    await sendPrompt(tester, 'Continue here');
    expect(res.opened.single, ('/wt/app/ab12', WorkspaceMode.folder));
  });

  testWidgets('outside a repo there is nothing to choose', (tester) async {
    final res = await _pump(tester, _FakeDaemon(repo: false));
    expect(find.text('Worktree'), findsNothing);
    expect(find.text('main'), findsNothing);
    await sendPrompt(tester, 'Hello');
    expect(res.opened.single, ('/code/app', WorkspaceMode.folder));
  });

  testWidgets('recent row shows at most 3 deduplicated session folders',
      (tester) async {
    final client = _FakeDaemon(
      repo: true,
      sessionList: [
        _session('mission-control', '/home/mc', 100),
        _session('s1', '/code/snippet-service', 90),
        _session('s2', '/code/snippet-service', 85),
        _session('s3', '/code/technoxi', 80),
        _session('s4', '/code/snippet-mobile-wave2', 70),
        _session('s5', '/code/fourth-repo', 60),
      ],
    );
    await _pump(tester, client);
    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('snippet-service'), findsOneWidget);
    expect(find.text('technoxi'), findsOneWidget);
    expect(find.text('snippet-mobile-wave2'), findsOneWidget);
    expect(find.text('fourth-repo'), findsNothing);
    expect(find.text('mc'), findsNothing);

    await tester.tap(find.text('technoxi'));
    await tester.pumpAndSettle();
    expect(client.worktreeQueries, contains('/code/technoxi'));
  });

  testWidgets('onStart receives folder, mode, profile, and first message',
      (tester) async {
    final client = _FakeDaemon(
      repo: true,
      profiles: [
        {'name': 'opus', 'provider': 'anthropic', 'model': 'claude-opus'},
        {'name': 'gemini-pro', 'provider': 'gemini', 'model': 'gemini'},
      ],
      activeProfile: 'opus',
    );
    final res = await _pump(tester, client, withOnStart: true);
    expect(find.text('opus'), findsOneWidget);

    await tester.tap(find.text('opus'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('gemini-pro').last);
    await tester.pumpAndSettle();

    await sendPrompt(tester, 'Ship the fix');
    expect(res.opened, isEmpty);
    expect(res.started.single.$1, '/code/app');
    expect(res.started.single.$2, WorkspaceMode.worktree);
    expect(res.started.single.$3, 'gemini-pro');
    expect(res.started.single.$4, 'Ship the fix');
    expect(res.started.single.$5, isEmpty);
  });

  testWidgets('folder sheet navigates into subfolder and applies it',
      (tester) async {
    final res = await _pump(tester, _FakeDaemon(repo: true));
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('lib'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Use lib in new worktree'));
    await tester.pumpAndSettle();
    expect(find.text('lib'), findsOneWidget);
    await sendPrompt(tester, 'Check lib');
    expect(res.opened.single, ('/code/app/lib', WorkspaceMode.worktree));
  });

  test('a worktree session is known by its project folder', () {
    final s = SessionInfo.fromJson({
      'id': 'x',
      'folder': '/wt/app/ab12',
      'origin_folder': '/code/app',
      'branch': 'snippet/ab12',
    });
    expect(s.projectFolder, '/code/app');
    expect(s.inWorktree, isTrue);
    final plain = SessionInfo.fromJson({'id': 'y', 'folder': '/code/app'});
    expect(plain.projectFolder, '/code/app');
    expect(plain.inWorktree, isFalse);
  });
}
