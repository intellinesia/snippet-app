import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/file_tree_sidebar_panel.dart';
import 'package:snippet/screens/files.dart';
import 'package:snippet/screens/session.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/theme.dart';

class _FakeFileClient extends DaemonClient {
  _FakeFileClient(this.entries) : super('https://daemon.invalid', 'test-token');

  final List<Map<String, dynamic>> entries;

  final DeviceEventHub _hub = DeviceEventHub.local();

  @override
  DeviceEventHub get deviceEvents => _hub;

  @override
  Future<FsListing> fs(String? path) async => FsListing.fromJson({
        'path': path ?? '/repo',
        'parent': '/',
        'entries': entries,
      });
}

void main() {
  test('FsEntry parses size, modified and git_status additively', () {
    final full = FsEntry.fromJson({
      'name': 'main.dart',
      'path': '/repo/main.dart',
      'is_dir': false,
      'git': false,
      'size': 3276,
      'modified': 1700000000,
      'git_status': 'modified',
    });
    expect(full.size, 3276);
    expect(full.modified, 1700000000);
    expect(full.gitStatus, 'modified');

    final legacy = FsEntry.fromJson({
      'name': 'old.dart',
      'path': '/repo/old.dart',
      'is_dir': false,
      'git': false,
    });
    expect(legacy.size, isNull);
    expect(legacy.modified, isNull);
    expect(legacy.gitStatus, isNull);
  });

  test('HarnessState parses and preserves SessionCounts across deltas', () {
    final initial = HarnessState.fromJson({
      'status': 'idle',
      'workspace': '/repo',
      'events': const [],
      'counts': {
        'changed_files': 3,
        'open_prs': 1,
        'processes': 2,
      },
    });
    expect(initial.counts.changedFiles, 3);
    expect(initial.counts.openPrs, 1);
    expect(initial.counts.processes, 2);

    final kept = initial.applyDelta({'status': 'running', 'new_events': const []});
    expect(kept.counts.changedFiles, 3);
    expect(kept.counts.openPrs, 1);
    expect(kept.counts.processes, 2);

    final updated = kept.applyDelta({
      'status': 'idle',
      'new_events': const [],
      'counts': {'changed_files': 5, 'open_prs': 0, 'processes': 1},
    });
    expect(updated.counts.changedFiles, 5);
    expect(updated.counts.openPrs, 0);
    expect(updated.counts.processes, 1);
  });

  testWidgets('FileTreeSidebarPanel renders git status badges with theme tokens',
      (tester) async {
    final client = _FakeFileClient([
      {'name': 'src', 'path': '/repo/src', 'is_dir': true, 'git_status': 'modified'},
      {'name': 'a.dart', 'path': '/repo/a.dart', 'is_dir': false, 'git_status': 'added'},
      {'name': 'u.dart', 'path': '/repo/u.dart', 'is_dir': false, 'git_status': 'untracked'},
      {'name': 'd.dart', 'path': '/repo/d.dart', 'is_dir': false, 'git_status': 'deleted'},
      {'name': 'clean.dart', 'path': '/repo/clean.dart', 'is_dir': false},
    ]);

    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 300,
          height: 400,
          child: FileTreeSidebarPanel(
            client: client,
            workspacePath: '/repo',
            onOpenFile: (_, __) {},
          ),
        ),
      ),
    ));
    await tester.pumpAndSettle();

    final mText = tester.widget<Text>(find.text('M'));
    final aText = tester.widget<Text>(find.text('A'));
    final uText = tester.widget<Text>(find.text('U'));
    final dText = tester.widget<Text>(find.text('D'));
    expect(mText.style?.color, AppColors.run);
    expect(aText.style?.color, AppColors.ok);
    expect(uText.style?.color, AppColors.fg4);
    expect(dText.style?.color, AppColors.danger);
  });

  testWidgets('FileExplorer shows git status and phone size + modified details',
      (tester) async {
    final twoHoursAgo =
        DateTime.now().millisecondsSinceEpoch ~/ 1000 - 2 * 3600;
    final client = _FakeFileClient([
      {
        'name': 'lib',
        'path': '/repo/lib',
        'is_dir': true,
        'modified': twoHoursAgo,
        'git_status': 'modified',
      },
      {
        'name': 'notes.txt',
        'path': '/repo/notes.txt',
        'is_dir': false,
        'size': 3277,
        'modified': twoHoursAgo,
        'git_status': 'untracked',
      },
    ]);

    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.pumpWidget(MaterialApp(
        home: FileExplorer(client: client, title: 'repo', start: '/repo'),
      ));
      await tester.pumpAndSettle();

      expect(find.text('M'), findsOneWidget);
      expect(find.text('U'), findsOneWidget);
      expect(find.text('3.2 KB · 2h'), findsOneWidget);
      // Folders do not show size/modified line.
      expect(find.text('2h'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('SessionShortcutStrip shows count badges above zero only',
      (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: SessionShortcutStrip(
          counts: const SessionCounts(changedFiles: 4, openPrs: 0, processes: 2),
          onGit: () {},
          onFiles: () {},
          onDeliverables: () {},
          onPullRequests: () {},
          onTerm: () {},
          onProcesses: () {},
        ),
      ),
    ));

    expect(find.text('Git'), findsOneWidget);
    expect(find.text('Files'), findsOneWidget);
    expect(find.text('Shared'), findsOneWidget);
    expect(find.text('PRs'), findsOneWidget);
    expect(find.text('Shell'), findsOneWidget);
    expect(find.text('Processes'), findsOneWidget);

    expect(find.text('4'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('0'), findsNothing);
  });
}
