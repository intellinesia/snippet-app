import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/app_dialog.dart';
import 'package:snippet/dialog_widgets.dart';
import 'package:snippet/theme.dart';

Future<void> _host(WidgetTester t, double w, double h, double scale) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = Size(w, h);
  debugDefaultTargetPlatformOverride = TargetPlatform.android;
  await t.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    builder: (c, ch) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: ch!),
    home: Builder(
        builder: (c) => Scaffold(
                body: Column(children: [
              TextButton(
                  key: const Key('plain'),
                  onPressed: () => confirmAction(c,
                      title: 'Leave group',
                      body: 'You will stop getting messages.',
                      confirmLabel: 'Leave group'),
                  child: const Text('p')),
              TextButton(
                  key: const Key('typed'),
                  onPressed: () => confirmAction(c,
                      title: 'Delete group',
                      body: 'Removes chats and artifacts.',
                      typedName: 'App Redesign'),
                  child: const Text('t')),
              TextButton(
                  key: const Key('prompt'),
                  onPressed: () => promptText(c,
                      title: 'Rename session',
                      initial: 'Old',
                      saveLabel: 'Rename'),
                  child: const Text('r')),
            ]))),
  ));
}

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
      _spec('confirm dialogs $w x $s', (t) async {
        await _host(t, w, 852, s);
        await t.tap(find.byKey(const Key('plain')));
        await t.pumpAndSettle();
        expect(t.takeException(), isNull);
        expect(find.byType(BackdropFilter), findsNothing);
        final card = t.getRect(find.byType(AppDialogCard));
        expect(card.width, w - 48);
        for (final b in ['Cancel', 'Leave group']) {
          final r = t.getRect(find
              .ancestor(of: find.text(b), matching: find.byType(InkWell))
              .first);
          expect(r.height, greaterThanOrEqualTo(48));
          if (s == 1.0) expect(r.width, greaterThanOrEqualTo(130));
        }
        await t.tap(find.text('Cancel'));
        await t.pumpAndSettle();

        await t.tap(find.byKey(const Key('typed')));
        await t.pumpAndSettle();
        expect(find.text('Type App Redesign to confirm'), findsOneWidget);
        InkWell confirm() => t.widget<InkWell>(find
            .ancestor(of: find.text('Delete'), matching: find.byType(InkWell))
            .first);
        expect(confirm().onTap, isNull);
        await t.enterText(find.byType(TextField), 'app redesign');
        await t.pump();
        expect(confirm().onTap, isNull);
        await t.enterText(find.byType(TextField), '  App Redesign ');
        await t.pump();
        expect(confirm().onTap, isNotNull);
        expect(t.takeException(), isNull);
        await t.tap(find.text('Cancel'));
        await t.pumpAndSettle();

        await t.tap(find.byKey(const Key('prompt')));
        await t.pumpAndSettle();
        expect(find.text('Old'), findsOneWidget);
        InkWell verb() => t.widget<InkWell>(find
            .ancestor(of: find.text('Rename'), matching: find.byType(InkWell))
            .first);
        expect(verb().onTap, isNull);
        expect(t.takeException(), isNull);
      });
    }
  }

  _spec('keyboard open at 360x640 keeps field and buttons visible', (t) async {
    await _host(t, 360, 640, 1);
    t.view.viewInsets = const FakeViewPadding(bottom: 300);
    await t.tap(find.byKey(const Key('typed')));
    await t.pumpAndSettle();
    for (final f in [
      find.byType(TextField),
      find.text('Cancel'),
      find.text('Delete')
    ]) {
      expect(t.getRect(f).bottom, lessThanOrEqualTo(340));
      expect(t.getRect(f).top, greaterThanOrEqualTo(0));
    }
    expect(t.takeException(), isNull);
    t.view.resetViewInsets();
  });
}
