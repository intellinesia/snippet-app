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
  testWidgets('source session prefills folder and profile',
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
    expect(find.text('gemini-pro'), findsOneWidget);
  });
}
