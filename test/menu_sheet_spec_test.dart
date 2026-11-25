import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/menu_widgets.dart';
import 'package:snippet/theme.dart';

void _spec(String name, Future<void> Function(WidgetTester) body) {
  testWidgets(name, (t) async {
    addTearDown(t.view.reset);
    try {
      await body(t);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void main() {
  for (final w in [360.0, 393.0, 430.0]) {
    for (final s in [1.0, 1.35, 2.0]) {
      _spec('menu sheet $w x $s', (t) async {
        t.view.devicePixelRatio = 1;
        t.view.physicalSize = Size(w, 852);
        debugDefaultTargetPlatformOverride = TargetPlatform.android;
        late BuildContext ctx;
        await t.pumpWidget(MaterialApp(
          theme: buildAppTheme(),
          builder: (c, ch) => MediaQuery(
              data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(s)),
              child: ch!),
          home: Scaffold(body: Builder(builder: (c) {
            ctx = c;
            return const SizedBox.expand();
          })),
        ));
        showAppMenu<String>(ctx, items: [
          appMenuHeading('Session'),
          appMenuItem(value: 'a', label: 'Rename', icon: 'pencil'),
          appMenuItem(value: 'b', label: 'Fork session', icon: 'git-fork'),
          appMenuItem(
              value: 'c',
              label: 'Export transcript',
              icon: 'download',
              enabled: false,
              detail: 'Needs a running session'),
          const PopupMenuDivider(),
          appMenuItem(value: 'd', label: 'Stop session', icon: 'stop'),
          appMenuItem(value: 'e', label: 'Delete', icon: 'trash', danger: true),
        ]);
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.byType(BackdropFilter), findsNothing);
        expect(t.getRect(find.byType(AppSheetSurface)).width, w);
        expect(t.getRect(find.byType(AppSheetSurface)).bottom, 852);
        for (final l in ['Rename', 'Fork session', 'Stop session', 'Delete']) {
          final row = t.getRect(find
              .ancestor(of: find.text(l), matching: find.byType(InkWell))
              .first);
          expect(row.width, w);
          expect(row.height, greaterThanOrEqualTo(56));
          expect(t.getTopLeft(find.text(l)).dx, 64);
        }
        expect(find.text('Needs a running session'), findsOneWidget);
        expect(t.getRect(find.byType(AppSheetSurface)).height,
            lessThanOrEqualTo(852 * 0.85 + 40));
        // Delete is the last row.
        expect(t.getTopLeft(find.text('Delete')).dy,
            greaterThan(t.getTopLeft(find.text('Stop session')).dy));
      });
    }
  }
}
