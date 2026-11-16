import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/models.dart';
import 'package:snippet/screens/desk_memory.dart';
import 'package:snippet/screens/memory_entries.dart';
import 'package:snippet/screens/memory_screen.dart';
import 'package:snippet/theme.dart';

import 'support/wake_fakes.dart';

const _index = '''
# Memory
- [[build]] — Signing, split APKs, systemd-run builds, goldens, CI-on-main, R8 JNI keep rules and Linux daemon memory.
- [[renderer]] — Scene renderer paths per platform, 20 fps pacing and ambient-tick kicks.
- Never commit render or golden images. [added: 2026-11-12]
- Keep replies short. [added: 2026-11-10]
''';

const _topic = '''
# Build and Release
- Android release signing reads SNIPPET_KEYSTORE. Without those env vars, release falls back to debug signing.
- Always release with --split-per-abi and ship the arm64 split.
''';

class _Client extends FakeWakeClient {
  final edits = <String>[];
  final nowS = DateTime.now().millisecondsSinceEpoch ~/ 1000;

  List<MemoryScope> get _all => [
        for (final j in [
          {'key': 'global', 'kind': 'global', 'label': 'You', 'entries': 11,
            'last_consolidated': nowS - 2 * 86400},
          {'key': 'project:snippet-mobile', 'kind': 'project',
            'label': 'snippet-mobile', 'entries': 12, 'files': 9,
            'consolidating': true},
          {'key': 'project:snippet-service', 'kind': 'project',
            'label': 'snippet-service', 'entries': 18,
            'last_consolidated': nowS - 18 * 3600},
          {'key': 'agent:rook', 'kind': 'agent', 'label': 'Rook', 'entries': 6,
            'last_consolidated': nowS - 86400},
          {'key': 'agent:moss', 'kind': 'agent', 'label': 'Moss', 'entries': 3},
          {'key': 'session:a/conversations/b', 'kind': 'session',
            'label': 'snippet-mobile-0123456789ab/conversations/b',
            'entries': 4, 'last_commit': {'date': nowS - 7200, 'subject': 'x'}},
        ])
          MemoryScope.fromJson(j)
      ];

  @override
  List<MemoryScope>? cachedMemoryScopes() => null;

  @override
  Future<List<MemoryScope>> memoryScopes() async => _all;

  @override
  Future<({String content, List<String> files})> memoryFile(String key,
          {String path = 'MEMORY.md'}) async =>
      (
        content: path == 'MEMORY.md' ? _index : _topic,
        files: ['MEMORY.md', 'build.md', 'renderer.md']
      );

  @override
  Future<List<MemoryCommit>> memoryHistory(String key, {int limit = 50}) async =>
      const [];

  @override
  Future<void> editMemoryEntry(String key, String matching,
      {String? entry, String? file}) async {
    edits.add('$key|$matching|${entry ?? ''}');
  }
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

Widget _app(Widget child) => RepaintBoundary(
      key: const ValueKey('shot'),
      child: MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(backgroundColor: AppColors.paneBg, body: child),
      ),
    );

void _view(WidgetTester t, TargetPlatform p, Size size) {
  debugDefaultTargetPlatformOverride = p;
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = size;
  addTearDown(t.view.reset);
}

void main() {
  test('parseMemoryEntries reads topics and notes', () {
    final e = parseMemoryEntries(_index);
    expect(e.length, 4);
    expect(e[0].file, 'build');
    expect(e[0].match, '[[build]]');
    expect(e[2].added, '2026-11-12');
    expect(memoryEntryMatches(e[1], 'RENDERER'), isTrue);
    expect(memoryEntryMatches(e[1], 'zzz'), isFalse);
  });

  testWidgets('phone: scopes page, scope search, topic and forget',
      (t) async {
    _view(t, TargetPlatform.android, const Size(390, 844));
    final c = _Client();
    await t.pumpWidget(_app(MemoryScreen(client: c, embedded: true, onBack: () {})));
    await t.pumpAndSettle();
    expect(find.text('11 entries · consolidated 2 days ago'), findsOneWidget);
    expect(find.text('12 entries · consolidating now'), findsOneWidget);
    expect(find.text('3 entries · not consolidated yet'), findsOneWidget);
    await _shot(t, 'memory-phone');

    await t.tap(find.text('snippet-mobile').first);
    await t.pumpAndSettle();
    expect(find.text('build.md'), findsOneWidget);
    await _shot(t, 'memory-scope');
    await t.enterText(find.byType(TextField), 'golden');
    await t.pumpAndSettle();
    expect(find.text('build.md'), findsOneWidget);
    expect(find.text('renderer.md'), findsNothing);
    await t.enterText(find.byType(TextField), '');
    await t.pumpAndSettle();

    await t.tap(find.text('build.md'));
    await t.pumpAndSettle();
    expect(find.textContaining('SNIPPET_KEYSTORE'), findsOneWidget);
    await _shot(t, 'memory-topic');
    await t.tap(find.text('Forget'));
    await t.pumpAndSettle();
    await t.tap(find.text('Forget').last);
    await t.pumpAndSettle();
    expect(c.edits, ['project:snippet-mobile|[[build]]|']);
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('desktop: drawer at 760 shows two panes', (t) async {
    _view(t, TargetPlatform.macOS, const Size(1280, 800));
    final c = _Client();
    await t.pumpWidget(_app(Align(
        alignment: Alignment.centerRight,
        child: ColoredBox(
            color: AppColors.bg,
            child: SizedBox(
            width: 760, child: DeskMemoryView(client: c, sessionId: 's'))))));
    await t.pumpAndSettle();
    await t.tap(find.text('build.md').first);
    await t.pumpAndSettle();
    expect(find.textContaining('SNIPPET_KEYSTORE'), findsWidgets);
    await _shot(t, 'memory-desktop');
    debugDefaultTargetPlatformOverride = null;
  });
}
