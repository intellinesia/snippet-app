import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/menu_widgets.dart';
import 'package:snippet/models.dart';
import 'package:snippet/screens/new_session_draft.dart';
import 'package:snippet/screens/new_session_picker.dart';
import 'package:snippet/theme.dart';

class _Daemon extends DaemonClient {
  _Daemon({this.fail = false, this.empty = false})
      : super('http://127.0.0.1:9', 'tok');
  final bool fail;
  final bool empty;
  @override
  Future<FsListing> fs(String? path) async {
    if (fail) throw Exception('denied');
    final dir = (path == null || path.isEmpty)
        ? '/home/me/code/snippet-mobile-all'
        : path;
    final parent = dir.contains('/')
        ? dir.substring(0, dir.lastIndexOf('/'))
        : '/';
    return FsListing.fromJson({
      'path': dir,
      'parent': parent.isEmpty ? '/' : parent,
      'entries': [
        if (!empty)
          for (final n in ['android', 'lib', 'test'])
            {'name': n, 'path': '$dir/$n', 'is_dir': true},
        if (!empty) {'name': 'README.md', 'path': '$dir/README.md', 'is_dir': false},
      ],
    });
  }

  @override
  Future<RepoWorktrees> worktrees(String folder) async =>
      throw Exception('none');

  @override
  Future<ServerConfig> getConfig({bool force = false}) async =>
      ServerConfig.fromJson({
        'profiles': [
          {'name': 'opus', 'provider': 'anthropic', 'model': 'claude'},
        ],
        'active': 'opus',
      });

  @override
  Future<List<SessionInfo>> sessions({String? folder, int? limit}) async =>
      const [];
}

Future<void> _open(WidgetTester t, double w, double s, _Daemon d) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = Size(w, 852);
  t.view.padding = const FakeViewPadding(top: 44, bottom: 20);
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  await t.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    builder: (c, ch) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(s)),
        child: ch!),
    home: NewSessionPicker(
        client: d, machineLabel: 'Local', onOpenFolder: (_, __) async {}),
  ));
  await t.pump(const Duration(milliseconds: 300));
  final row = find.text('Choose folder').last;
  await t.ensureVisible(row);
  await t.pump();
  await t.tap(row);
  await t.pumpAndSettle();
}

void main() {
  for (final w in [360.0, 393.0, 430.0]) {
    for (final s in [1.0, 1.35, 2.0]) {
      testWidgets('folder browser $w x $s', (t) async {
        addTearDown(t.view.reset);
        try {
          await _open(t, w, s, _Daemon());
          expect(t.takeException(), isNull);
          expect(find.text('home / me / code / snippet-mobile-all'),
              findsOneWidget);
          expect(find.text('README.md'), findsNothing);
          for (final n in ['..', 'android', 'lib', 'test']) {
            final r = t.getRect(find
                .ancestor(of: find.text(n), matching: find.byType(InkWell))
                .first);
            expect(r.width, w);
            expect(r.height, greaterThanOrEqualTo(52));
            expect(t.getTopLeft(find.text(n)).dx, 44);
          }
          final sheet = t.getRect(find.byType(AppSheetSurface));
          expect(sheet.width, w);
          expect(sheet.top, 60);
          expect(sheet.height, 792);
          final row0 = t.getRect(find
              .ancestor(of: find.text('..'), matching: find.byType(InkWell))
              .first);
          final btn = t.getRect(find
              .ancestor(
                  of: find.text('Select snippet-mobile-all'),
                  matching: find.byType(InkWell))
              .first);
          expect(btn.left, 16);
          expect(btn.width, w - 32);
          expect(btn.height, 48);
          expect(btn.bottom, closeTo(852 - 20 - 16, 1));
          expect(
              t
                  .getRect(find.descendant(
                      of: find.byType(AppSheetSurface),
                      matching: find.text('Choose folder')))
                  .left,
              20);
          debugPrint(
              'MEASURE dl05_browser w=${w.toInt()} scale=$s sheet=${sheet.width.toStringAsFixed(1)}x${sheet.height.toStringAsFixed(1)}@y${sheet.top.toStringAsFixed(0)} rowH=${row0.height.toStringAsFixed(1)} btn=x${btn.left.toStringAsFixed(0)},${btn.width.toStringAsFixed(1)}x${btn.height.toStringAsFixed(1)}');
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }

  testWidgets('folder browser error and empty states', (t) async {
    addTearDown(t.view.reset);
    try {
      await _open(t, 393, 1, _Daemon(fail: true));
      expect(find.text("Can't open this folder"), findsOneWidget);
      expect(t.getRect(find.text('Retry')).height, greaterThanOrEqualTo(14));
      await t.pumpWidget(const SizedBox());
      await _open(t, 393, 1, _Daemon(empty: true));
      expect(find.text('No folders here'), findsOneWidget);
      expect(find.text('Select snippet-mobile-all'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  for (final w in [360.0, 393.0, 430.0]) {
    for (final s in [1.0, 2.0]) {
      testWidgets('new session phone folder chip opens large sheet $w x $s',
          (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = Size(w, 852);
        t.view.padding = const FakeViewPadding(top: 44, bottom: 20);
        addTearDown(t.view.reset);
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        try {
          final d = _Daemon();
          final recents = [
            SessionInfo.fromJson({
              'id': 's1',
              'folder': '/home/me/code/design-kit',
              'title': 'Design kit',
              'status': 'idle',
              'last_active': 200,
            }),
            SessionInfo.fromJson({
              'id': 's2',
              'folder': '/home/me/code/snippet-daemon',
              'title': 'Daemon',
              'status': 'idle',
              'last_active': 100,
            }),
          ];
          await t.pumpWidget(MaterialApp(
            theme: buildAppTheme(),
            builder: (c, ch) => MediaQuery(
                data:
                    MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(s)),
                child: ch!),
            home: NewSessionDraft(
              client: d,
              machineLabel: 'Mac mini',
              folder: '/home/me/code/snippet-mobile-all',
              recentSessions: recents,
              layout: NewSessionLayout.phone,
              onStart: (_, __, ___, ____) async {},
            ),
          ));
          await t.pumpAndSettle();
          await t.tap(find.bySemanticsLabel('snippet-mobile-all'));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);

          // Large sheet (top at safeTop+16 = 60, height 792), not popover.
          final sheet = t.getRect(find.byType(AppSheetSurface));
          expect(sheet.width, w);
          expect(sheet.top, 60);
          expect(sheet.height, 792);
          expect(find.text('Find a folder'), findsNothing);

          // Recent folder chips >= 44 high.
          final chip = t.getRect(find
              .ancestor(
                  of: find.text('design-kit'), matching: find.byType(InkWell))
              .first);
          expect(chip.height, greaterThanOrEqualTo(44));

          // Rows >= 56 high per DL-02 and full viewport wide.
          final rowHeights = <double>[];
          for (final n in ['..', 'android', 'lib', 'test']) {
            final r = t.getRect(find
                .ancestor(of: find.text(n), matching: find.byType(InkWell))
                .first);
            expect(r.width, w);
            expect(r.height, greaterThanOrEqualTo(56));
            expect(t.getTopLeft(find.text(n)).dx, 44);
            rowHeights.add(r.height);
          }

          // Pinned Select button: x16, w-32 x 48, 16 above safe area.
          final btn = t.getRect(find
              .ancestor(
                  of: find.text('Select snippet-mobile-all'),
                  matching: find.byType(InkWell))
              .first);
          expect(btn.left, 16);
          expect(btn.width, w - 32);
          expect(btn.height, 48);
          expect(btn.bottom, closeTo(852 - 20 - 16, 1));

          debugPrint(
              'MEASURE draft_folder w=${w.toInt()} scale=$s sheet=${sheet.width.toStringAsFixed(1)}x${sheet.height.toStringAsFixed(1)}@y${sheet.top.toStringAsFixed(0)} chipH=${chip.height.toStringAsFixed(1)} rowH=${rowHeights.first.toStringAsFixed(1)} btn=x${btn.left.toStringAsFixed(0)},${btn.width.toStringAsFixed(1)}x${btn.height.toStringAsFixed(1)}');

          // Navigate into subfolder and select it.
          await t.tap(find.text('lib'));
          await t.pumpAndSettle();
          expect(find.text('Select lib'), findsOneWidget);
          await t.tap(find.text('Select lib'));
          await t.pumpAndSettle();
          expect(find.byType(AppSheetSurface), findsNothing);
          expect(find.bySemanticsLabel('lib'), findsOneWidget);
        } finally {
          debugDefaultTargetPlatformOverride = null;
        }
      });
    }
  }

  testWidgets('new session desktop folder chip keeps popover', (t) async {
    t.view.devicePixelRatio = 1;
    t.view.physicalSize = const Size(1200, 852);
    addTearDown(t.view.reset);
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    try {
      await t.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: NewSessionDraft(
            client: _Daemon(),
            machineLabel: 'Mac mini',
            folder: '/home/me/code/snippet-mobile-all',
            layout: NewSessionLayout.sheet,
            onStart: (_, __, ___, ____) async {},
          ),
        ),
      ));
      await t.pumpAndSettle();
      await t.tap(find.text('snippet-mobile-all'));
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(find.byType(AppSheetSurface), findsNothing);
      expect(find.text('Find a folder'), findsOneWidget);
      expect(find.text('Choose folder…'), findsOneWidget);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
