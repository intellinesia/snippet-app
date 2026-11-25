import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/app_dialog.dart';
import 'package:snippet/dialog_widgets.dart';
import 'package:snippet/widgets.dart';
import 'package:snippet/menu_widgets.dart';
import 'package:snippet/morph_sheet.dart';
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

Future<BuildContext> _host(WidgetTester t, double w, double h, double s) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = Size(w, h);
  t.view.padding = const FakeViewPadding(top: 44, bottom: 20);
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
  return ctx;
}

void main() {
  for (final w in [360.0, 393.0, 430.0]) {
    for (final s in [1.0, 1.35, 2.0]) {
      _spec('sheet sizes $w x $s', (t) async {
        final ctx = await _host(t, w, 852, s);
        for (final size in [
          SheetSize.medium,
          SheetSize.large,
          SheetSize.small
        ]) {
          showAppSheet<void>(ctx,
              title: 'Choose folder',
              size: size,
              pinned: size == SheetSize.small
                  ? null
                  : AppDialogButton('Select', primary: true, onTap: () {}),
              child: Column(children: [
                for (var i = 0; i < 30; i++)
                  SizedBox(height: 52, child: Text('row $i'))
              ]));
          await t.pumpAndSettle();
          expect(t.takeException(), isNull);
          expect(find.byType(BackdropFilter), findsNothing);
          final r = t.getRect(find.byType(AppSheetSurface));
          expect(r.width, w);
          expect(r.bottom, 852);
          if (size == SheetSize.medium) expect(r.height, closeTo(852 * 0.6, 1));
          if (size == SheetSize.large) expect(r.top, closeTo(60, 1));
          if (size == SheetSize.small)
            expect(r.height, lessThanOrEqualTo(852 * 0.4 + 1));
          if (size != SheetSize.small) {
            final close = t.getRect(find
                .ancestor(
                    of: find.byType(AppIcon).first,
                    matching: find.byType(SizedBox))
                .first);
            expect(close.width, 48);
            expect(close.height, 48);
            final btn = t.getRect(find.byType(AppDialogButton));
            expect(btn.height, greaterThanOrEqualTo(48));
            expect(btn.bottom, closeTo(852 - 20 - 16, 1));
            expect(btn.left, 16);
            expect(btn.width, w - 32);
          }
          Navigator.of(ctx).pop();
          await t.pumpAndSettle();
        }
      });
    }
  }

  _spec('sheet with keyboard at 360x640 keeps pinned button visible',
      (t) async {
    final ctx = await _host(t, 360, 640, 1);
    t.view.viewInsets = const FakeViewPadding(bottom: 300);
    showAppSheet<void>(ctx,
        title: 'New task',
        size: SheetSize.medium,
        pinned: AppDialogButton('Create', primary: true, onTap: () {}),
        child: const TextField());
    await t.pumpAndSettle();
    final b = t.getRect(find.text('Create'));
    expect(b.bottom, lessThanOrEqualTo(340));
    expect(b.top, greaterThanOrEqualTo(0));
    expect(t.takeException(), isNull);
    t.view.resetViewInsets();
  });
}
