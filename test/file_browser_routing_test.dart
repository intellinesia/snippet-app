import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/api.dart';
import 'package:snippet/swr.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/files.dart';

/// The session's file browser is opened from `session.dart` with an
/// `onOpenFile` callback that creates a shell TAB. That is a desktop concept:
/// the phone shell renders `_activeTab`, and a file tab is auxiliary, so
/// `_activeTab` skips it and the mobile shell never draws it.
///
/// Honouring that callback on a phone therefore closed the explorer and pushed a
/// surface the phone does not render — tapping a file appeared to do nothing.
/// These tests pin the split: phones get the viewer route, desktop keeps tabs.
class _FakeFilesClient extends DaemonClient {
  _FakeFilesClient() : super('https://daemon.invalid', 'test-token');

  @override
  late final DeviceEventHub deviceEvents = DeviceEventHub.local();

  @override
  Future<FsListing> fs(String? path) async {
    if (path == '/root/lib') {
      return FsListing.fromJson({
        'path': '/root/lib',
        'parent': '/root',
        'entries': [
          {'name': 'main.dart', 'path': '/root/lib/main.dart', 'is_dir': false},
        ],
      });
    }
    return FsListing.fromJson({
      'path': path ?? '/root',
      'parent': null,
      'entries': [
        {'name': 'clip.mp4', 'path': '/root/clip.mp4', 'is_dir': false},
        {'name': 'song.mp3', 'path': '/root/song.mp3', 'is_dir': false},
        {'name': 'notes.pdf', 'path': '/root/notes.pdf', 'is_dir': false},
        {'name': 'notes.txt', 'path': '/root/notes.txt', 'is_dir': false},
        {'name': 'lib', 'path': '/root/lib', 'is_dir': true},
      ],
    });
  }

  @override
  Future<FileContent> readFile(String path) async => FileContent.fromJson({
        'path': path,
        'content': 'hello\n',
        'size': 6,
        'binary': false,
        'hash': 'x',
      });
}

void main() {
  /// Run [body] as a PHONE or as desktop. Cleared in a `finally` inside the
  /// body: the framework asserts no foundation debug variable survives the body,
  /// which runs before any tearDown.
  Future<void> asPlatform(TargetPlatform platform,
      Future<void> Function() body) async {
    debugDefaultTargetPlatformOverride = platform;
    try {
      await body();
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  }

  /// Pump the explorer and return a sink for the `onOpenFile` callback, so a
  /// test can assert whether the desktop tab path was taken.
  Future<List<String>> pumpExplorer(WidgetTester tester, {double width = 420}) async {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final opened = <String>[];
    await tester.pumpWidget(MaterialApp(
      home: FileExplorer(
        client: _FakeFilesClient(),
        title: 'Files',
        start: '/root',
        onOpenFile: (path, name) => opened.add(path),
      ),
    ));
    await tester.pumpAndSettle();
    return opened;
  }

  testWidgets('on a phone, tapping a file opens the viewer, not a shell tab',
      (tester) async {
    await asPlatform(TargetPlatform.android, () async {
      final opened = await pumpExplorer(tester);

      await tester.tap(find.text('notes.txt'));
      await tester.pumpAndSettle();

      // The regression: the tab callback fired and the viewer never opened.
      expect(opened, isEmpty,
          reason: 'a phone must not route a file into a desktop shell tab');
      expect(find.byType(FileViewer), findsOneWidget,
          reason: 'the file should open in a viewer route');
    });
  });

  testWidgets('on desktop, tapping a file still opens a shell tab',
      (tester) async {
    await asPlatform(TargetPlatform.macOS, () async {
      final opened = await pumpExplorer(tester, width: 1400);

      await tester.tap(find.text('notes.txt'));
      await tester.pumpAndSettle();

      expect(opened, ['/root/notes.txt'],
          reason: 'desktop keeps the tab behaviour the mobile fix must not break');
    });
  });

  testWidgets('openFileForViewing routes the viewer on a phone',
      (tester) async {
    // The ONE seam both call sites use. It was fixed twice — first for the file
    // browser, then again for the agent's `present_file` card, which had been
    // calling the tab callback directly and stayed inert. Asserting the seam
    // itself is what stops a third call site repeating it.
    //
    // Two separate tests, not two phases in one: `pumpWidget` with the same
    // widget TYPE updates the tree instead of replacing it, so the Navigator
    // kept the route pushed in the first phase and it leaked into the second.
    await asPlatform(TargetPlatform.android, () async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        }),
      ));

      final handled = openFileForViewing(ctx,
          client: _FakeFilesClient(), path: '/root/notes.txt', name: 'notes.txt');
      // Settle, not a single pump: the push runs a route transition, and the
      // viewer is only built once that transition starts.
      await tester.pumpAndSettle();

      expect(handled, isTrue,
          reason: 'a phone must be handled here, not by the caller');
      expect(find.byType(FileViewer), findsOneWidget);
    });
  });

  testWidgets('openFileForViewing defers to the caller on desktop',
      (tester) async {
    await asPlatform(TargetPlatform.macOS, () async {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        home: Builder(builder: (c) {
          ctx = c;
          return const SizedBox();
        }),
      ));

      final handled = openFileForViewing(ctx,
          client: _FakeFilesClient(), path: '/root/notes.txt', name: 'notes.txt');
      await tester.pumpAndSettle();

      expect(handled, isFalse,
          reason: 'desktop must fall through to its own tab/panel path');
      expect(find.byType(FileViewer), findsNothing);
    });
  });

  testWidgets('mobile standalone FileExplorer provides New chat here action and climbs back cleanly',
      (tester) async {
    await asPlatform(TargetPlatform.android, () async {
      tester.view.physicalSize = const Size(420, 900);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      String? newChatFolder;
      var closed = false;

      await tester.pumpWidget(MaterialApp(
        home: FileExplorer(
          client: _FakeFilesClient(),
          title: 'Files',
          start: '/root',
          onClose: () => closed = true,
          onNewChat: (folder) => newChatFolder = folder,
        ),
      ));
      await tester.pumpAndSettle();

      // 1. The phone action tiles offer 'New chat' when onNewChat is set
      expect(find.text('New chat'), findsOneWidget);
      await tester.tap(find.text('New chat'));
      await tester.pumpAndSettle();
      expect(newChatFolder, equals('/root'));

      // 2. Navigate into subfolder 'lib'
      await tester.tap(find.text('lib'));
      await tester.pumpAndSettle();

      expect(find.text('main.dart'), findsOneWidget);
      // Title plus the bold last breadcrumb.
      expect(find.text('lib'), findsNWidgets(3));
      expect(find.text('root'), findsOneWidget);

      // In subfolder, the 'New chat' tile targets '/root/lib'
      await tester.tap(find.text('New chat'));
      await tester.pumpAndSettle();
      expect(newChatFolder, equals('/root/lib'));

      // 3. Tapping back in SnAppBar climbs to parent folder (/root)
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(find.text('root'), findsNWidgets(3));
      expect(find.text('notes.txt'), findsOneWidget);
      expect(closed, isFalse);

      // 4. Tapping back at root calls onClose without opening any session
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      expect(closed, isTrue);
    });
  });
}

