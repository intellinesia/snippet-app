import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/models.dart';

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

}
