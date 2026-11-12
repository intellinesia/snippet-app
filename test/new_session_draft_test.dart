import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/new_session_draft.dart';
import 'package:snippet/theme.dart';

class _FakeDaemon extends DaemonClient {
  _FakeDaemon() : super('https://daemon.invalid', 'test-token');

  List<SessionInfo> sessionList = const [];
  int sessionsCalls = 0;

  @override
  Future<ServerConfig> getConfig({bool force = false}) async =>
      ServerConfig.fromJson({
        'profiles': [
          {'name': 'opus', 'provider': 'anthropic', 'model': 'claude'},
          {'name': 'gemini-pro', 'provider': 'gemini', 'model': 'gemini'},
        ],
        'active': 'opus',
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
  Future<List<SessionInfo>> sessions({String? folder, int? limit}) async {
    sessionsCalls++;
    return sessionList;
  }
}

SessionInfo _session(
  String id,
  String title, {
  int lastActive = 0,
  String? profile,
  String folder = '/repo',
  String? originFolder,
  String? branch,
  String? agentId,
}) =>
    SessionInfo.fromJson({
      'id': id,
      'folder': folder,
      'title': title,
      'status': 'idle',
      'last_active': lastActive,
      'profile': profile,
      'origin_folder': originFolder,
      'branch': branch,
      'agent_id': agentId,
    });

Future<void> _pump(
  WidgetTester tester,
  _FakeDaemon client, {
  SessionInfo? source,
  List<SessionInfo>? recents,
  ValueChanged<String>? onOpen,
  String? folder = '/repo',
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(800, 900);
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: NewSessionDraft(
        client: client,
        machineLabel: 'test',
        folder: folder,
        source: source,
        recentSessions: recents,
        onOpenSession: onOpen,
        onStart: (_, __, ___, ____) async {},
      ),
    ),
  ));
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('recent row shows up to four folder sessions and opens one',
      (tester) async {
    final client = _FakeDaemon();
    final opened = <String>[];
    final recents = [
      _session('s5', 'Elsewhere', folder: '/other', lastActive: 50),
      _session('s4', 'Fourth', lastActive: 40),
      _session('s3', 'Third', lastActive: 30, profile: 'opus'),
      _session('s2', 'Second', lastActive: 20, agentId: 'reviewer'),
      _session('s1', 'First', lastActive: 10),
      _session('s0', 'Worktree one',
          folder: '/repo-wt', originFolder: '/repo', lastActive: 5),
    ];
    await _pump(tester, client,
        recents: recents, onOpen: opened.add);

    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('First'), findsOneWidget);
    expect(find.text('Fourth'), findsOneWidget);
    expect(find.text('Third'), findsOneWidget);
    expect(find.text('Second'), findsOneWidget);
    // Fifth-newest and the other folder's session stay off the row.
    expect(find.text('Elsewhere'), findsNothing);
    expect(find.text('Worktree one'), findsNothing);

    await tester.tap(find.text('Third'));
    await tester.pumpAndSettle();
    expect(opened, ['s3']);
  });

  testWidgets('recent row is hidden without an open callback', (tester) async {
    final client = _FakeDaemon()
      ..sessionList = [_session('s1', 'First', lastActive: 10)];
    await _pump(tester, client, recents: client.sessionList);

    expect(find.text('Recent'), findsNothing);
    expect(client.sessionsCalls, 0);
  });

  testWidgets('recents are fetched from the daemon when no pool is passed',
      (tester) async {
    final client = _FakeDaemon()
      ..sessionList = [
        _session('s1', 'Fetched', lastActive: 10),
        _session('s2', 'Other folder', folder: '/elsewhere', lastActive: 20),
      ];
    await _pump(tester, client, onOpen: (_) {});

    expect(client.sessionsCalls, 1);
    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('Fetched'), findsOneWidget);
    expect(find.text('Other folder'), findsNothing);
  });

  testWidgets('source session prefills folder, branch and profile',
      (tester) async {
    final client = _FakeDaemon();
    final source = _session(
      'src',
      'Source session',
      folder: '/src-project',
      profile: 'gemini-pro',
      branch: 'feature-x',
    );
    await _pump(tester, client, source: source, folder: null);

    expect(find.text('src-project'), findsOneWidget);
    expect(find.text('feature-x'), findsOneWidget);
    expect(find.text('gemini-pro'), findsOneWidget);
  });
}
