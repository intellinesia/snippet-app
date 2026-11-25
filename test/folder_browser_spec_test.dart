import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/menu_widgets.dart';
import 'package:snippet/models.dart';
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
    return FsListing.fromJson({
      'path': '/home/me/code/snippet-mobile-all',
      'parent': '/home/me/code',
      'entries': [
        if (!empty)
          for (final n in ['android', 'lib', 'test'])
            {'name': n, 'path': '/x/$n', 'is_dir': true},
        if (!empty) {'name': 'README.md', 'path': '/x/r', 'is_dir': false},
      ],
    });
  }

  @override
  Future<RepoWorktrees> worktrees(String folder) async =>
      throw Exception('none');
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
}
