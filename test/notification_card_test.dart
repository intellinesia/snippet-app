import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide testWidgets;
import 'package:flutter_test/flutter_test.dart' as ft show testWidgets;
import 'package:snippet/notification_card.dart';
import 'package:snippet/session_quick_send.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/widgets.dart' show AppIcon;

void testWidgets(String name, Future<void> Function(WidgetTester) body) =>
    ft.testWidgets(name, (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await body(t);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

const _sizes = [Size(360, 780), Size(393, 852), Size(430, 932)];
const _scales = [1.0, 1.35, 2.0];

final _approval = <String, dynamic>{
  'kind': 'waiting',
  'title': 'Lead',
  'body': 'Run flutter build apk for snippet-mobile',
  'session': 's',
  'url': 'u',
  'attention': {'type': 'approval', 'tool': 'bash', 'text': 'flutter build apk'},
};
final _message = <String, dynamic>{
  'kind': 'message',
  'title': 'Sashy',
  'body': 'Short note. ' * 40,
  'session': 's',
  'url': 'u',
};
final _decision = <String, dynamic>{
  'kind': 'waiting',
  'title': 'Lead',
  'body': 'Which branch?',
  'session': 's',
  'url': 'u',
  'attention': {
    'type': 'question',
    'text': 'Which branch?',
    'choices': [
      {'label': 'main'},
      {'label': 'release'}
    ],
  },
};

Future<void> _pump(WidgetTester t, Size size, double scale, Map<String, dynamic> p,
    {Future<bool> Function(Map<String, dynamic>, QuickAction)? send,
    double keyboard = 0}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  t.view.viewInsets = FakeViewPadding(bottom: keyboard);
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    builder: (c, child) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: child!),
    home: Scaffold(
      body: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 104, 16, 16),
        child: NotificationMessageCard(
          payload: p,
          onOpen: () {},
          onDismiss: () {},
          onHold: (_) {},
          onSent: () {},
          send: send ?? (_, __) async => true,
        ),
      ),
    ),
  ));
  await t.pump(const Duration(milliseconds: 50));
}

Finder _btn(String label) => find.ancestor(
    of: find.text(label), matching: find.byType(InkWell)).first;

void main() {
  for (final size in _sizes) {
    for (final scale in _scales) {
      testWidgets('NT-02 ${size.width.toInt()} x$scale', (t) async {
        await _pump(t, size, scale, _approval);
        final card = find.byType(NotificationMessageCard);
        expect(t.getRect(card).left, 16);
        expect(t.getRect(card).width, size.width - 32);
        expect(t.getSize(find.byKey(const ValueKey('reply-field'))).height, 44);
        for (final l in ['Open', 'Approve']) {
          final s = t.getSize(_btn(l));
          expect(s.height, greaterThanOrEqualTo(36), reason: l);
          if (scale < 1.75) expect(s.width, greaterThanOrEqualTo(120), reason: l);
        }
        if (scale >= 1.75) {
          expect(t.getTopLeft(_btn('Approve')).dy,
              lessThan(t.getTopLeft(_btn('Open')).dy),
              reason: 'stacked, Approve on top');
        } else {
          final inner = size.width - 32 - 24;
          expect(t.getSize(_btn('Open')).width, closeTo((inner - 8) / 2, .5));
        }
        expect(find.text('Needs you'), findsOneWidget);
        expect(
            find.descendant(
                of: card,
                matching: find.byWidgetPredicate(
                    (w) => w is AppIcon && w.name == 'hand')),
            findsNothing);
        expect(t.takeException(), isNull);

        await _pump(t, size, scale, _message);
        expect(find.text('Approve'), findsNothing);
        expect(find.text('Reply'), findsOneWidget);
        expect(find.text('Needs you'), findsNothing);
        expect(find.text('More'), findsOneWidget);
        expect(t.getSize(find.ancestor(of: find.text('More'), matching: find.byType(ConstrainedBox)).first).height,
            greaterThanOrEqualTo(48));
        expect(t.takeException(), isNull);

        await _pump(t, size, scale, _decision);
        expect(find.text('Approve'), findsNothing);
        for (final l in ['main', 'release']) {
          final s = t.getSize(_btn(l));
          expect(s.height, greaterThanOrEqualTo(36));
          expect(s.width, size.width - 32 - 24);
        }
        expect(t.takeException(), isNull);
      });
    }
  }

  testWidgets('NT-02 keyboard at 360 x 640 clamps body to 2 lines, keeps buttons',
      (t) async {
    await _pump(t, const Size(360, 640), 1, _message, keyboard: 260);
    final body = t.widget<Text>(find.textContaining('Short note').first);
    expect(body.maxLines, 2);
    expect(find.text('Reply'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
  });

  testWidgets('NT-02 send icon only with text; failure line; no red',
      (t) async {
    await _pump(t, _sizes[1], 1, _message, send: (_, __) async => false);
    expect(find.byTooltip('Send'), findsNothing);
    await t.enterText(find.byType(TextField), 'hi');
    await t.pump();
    expect(find.byTooltip('Send'), findsOneWidget);
    expect(t.getSize(find.byTooltip('Send')).height, 48);
    expect(t.getSize(find.byKey(const ValueKey('reply-field'))).height, 44);
    await t.testTextInput.receiveAction(TextInputAction.send);
    await t.pump();
    await t.pump();
    expect(find.text('Could not send. Try again.'), findsOneWidget);
    expect(t.takeException(), isNull);
  });

  testWidgets('NT-02 approve shows Approving... disabled', (t) async {
    final done = Completer<bool>();
    await _pump(t, _sizes[1], 1, _approval, send: (_, __) => done.future);
    await t.tap(find.text('Approve'));
    await t.pump();
    expect(find.text('Approving...'), findsOneWidget);
    done.complete(false);
    await t.pump();
    await t.pump();
    expect(find.text('Approve'), findsOneWidget);
  });
}

