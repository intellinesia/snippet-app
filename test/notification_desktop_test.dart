import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide testWidgets;
import 'package:flutter_test/flutter_test.dart' as ft show testWidgets;
import 'package:snippet/notification_banner.dart';
import 'package:snippet/notification_card.dart';
import 'package:snippet/notification_popovers.dart';
import 'package:snippet/notification_sync.dart';
import 'package:snippet/screens/shell_frame.dart';
import 'package:snippet/session_quick_send.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/top_zone.dart';
import 'package:snippet/widgets.dart' show AppIcon;

void testWidgets(String name, Future<void> Function(WidgetTester) body) =>
    ft.testWidgets(name, (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      try {
        await body(t);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

Future<void> _pumpHost(WidgetTester t,
    {Size size = const Size(1440, 900)}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: const NotificationPopovers(child: Scaffold(body: SizedBox.expand())),
  ));
  await t.pump();
}

void _seedStack() {
  foregroundNotifications.drain();
  for (final i in [1, 2, 3, 4]) {
    foregroundNotifications.add({
      'kind': 'done',
      'title': i == 1 ? 'PR #$i merged' : 'Task $i done',
      'body': 'snippet-mobile - Sashy',
      'session': 's$i',
      'url': 'u',
    });
  }
  foregroundNotifications.add({
    'kind': 'waiting',
    'title': 'Lead',
    'body': 'Approve merge of canvas-app-final?',
    'session': 'sw',
    'url': 'u',
    'attention': {'type': 'approval', 'text': 'Approve merge'},
  });
}

Finder _btn(String label) =>
    find.ancestor(of: find.text(label), matching: find.byType(InkWell)).first;

Finder _badge(Finder within, Color color) => find.descendant(
    of: within,
    matching: find.byWidgetPredicate((w) =>
        w is Container &&
        w.decoration is BoxDecoration &&
        (w.decoration as BoxDecoration).color == color &&
        (w.decoration as BoxDecoration).border != null &&
        (w.decoration as BoxDecoration).shape == BoxShape.circle));

Future<void> _pumpCard(WidgetTester t, Map<String, dynamic> payload,
    {Future<bool> Function(Map<String, dynamic>, QuickAction)? send}) async {
  t.view.physicalSize = const Size(1440, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.only(top: 44, right: 24),
          child: SizedBox(
            width: 360,
            child: NotificationMessageCard(
              payload: payload,
              onOpen: () {},
              onDismiss: () {},
              onHold: (_) {},
              onSent: () {},
              send: send ?? (_, __) async => true,
            ),
          ),
        ),
      ),
    ),
  ));
  await t.pump(const Duration(milliseconds: 50));
}

void main() {
  setUp(() {
    TopZone.reset();
    foregroundNotifications.drain();
  });
  tearDown(() {
    TopZone.reset();
    foregroundNotifications.drain();
  });

  test('information titles carry done and failed in words', () {
    expect(
        informationTitle({'kind': 'done', 'title': 'Deploy'}), 'Done: Deploy');
    expect(
        informationTitle({'kind': 'done', 'title': 'PR merged'}), 'PR merged');
    expect(informationTitle({'kind': 'error', 'title': 'Deploy'}),
        'Failed: Deploy');
  });

  testWidgets(
      'NT-01 desktop slim toasts: width, anchor, cap, quiet footer, auto-open',
      (t) async {
    _seedStack();
    await _pumpHost(t);
    await t.pumpAndSettle();

    // The newest actionable needs-you item opens with its actions.
    final open = find.byType(NotificationMessageCard);
    expect(open, findsOneWidget);
    expect(find.text('Approve'), findsOneWidget);
    expect(find.text('Deny'), findsOneWidget);
    expect(find.text('Needs you'), findsOneWidget);
    expect(_badge(open, AppColors.run), findsOneWidget);

    final pills = find.byType(NotificationBanner);
    expect(pills, findsNWidgets(2));
    final top = t.getRect(open);
    final pill = t.getRect(pills.at(0));
    expect(top.width, 360);
    expect(top.left, 1440 - 24 - 360);
    expect(top.top, kShellTabStripHeight + TopZone.gap);
    expect(pill.height, 40);
    expect(pill.top, closeTo(top.bottom + 6, .01));

    final material = t.widget<Material>(find
        .descendant(of: pills.first, matching: find.byType(Material))
        .first);
    expect(material.color, AppColors.surface2);
    expect((material.shape as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(20));
    expect(
        find.descendant(
            of: pills.first,
            matching: find.byWidgetPredicate((w) =>
                (w is AppIcon && w.color == AppColors.run) ||
                (w is Text && w.style?.color == AppColors.run))),
        findsNothing,
        reason: 'information toasts are neutral');

    for (final label in ['+2', 'Clear']) {
      expect(find.text(label), findsOneWidget);
      final text = t.widget<Text>(find.text(label));
      expect(text.style?.fontSize, 11.5);
      expect(text.style?.color, AppColors.fg4);
    }
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('NT-01 desktop anchor follows a lower registered top bar',
      (t) async {
    TopZone.register('attention', kShellTabStripHeight + 32);
    foregroundNotifications.add({
      'kind': 'done',
      'title': 'PR merged',
      'body': 'snippet-mobile - Sashy',
      'session': 's',
      'url': 'u',
    });
    await _pumpHost(t);
    await t.pumpAndSettle();
    expect(t.getRect(find.byType(NotificationBanner)).top,
        kShellTabStripHeight + 32 + TopZone.gap);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets(
      'NT-01 desktop lifetimes: information 6s, needs-you folds after 30s',
      (t) async {
    foregroundNotifications
        .add({'kind': 'done', 'title': 'Info', 'session': 'a', 'url': 'u'});
    foregroundNotifications.add({
      'kind': 'waiting',
      'title': 'Ask',
      'session': 'b',
      'url': 'u',
      'attention': {'type': 'approval', 'text': 'Approve'},
    });
    await _pumpHost(t);
    await t.pump(const Duration(seconds: 5));
    expect(find.text('Done: Info'), findsOneWidget);
    await t.pump(const Duration(seconds: 2));
    await t.pumpAndSettle();
    expect(find.text('Done: Info'), findsNothing);
    expect(find.text('Ask'), findsOneWidget);
    await t.pump(const Duration(seconds: 24));
    await t.pumpAndSettle();
    expect(find.text('Ask'), findsNothing);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('NT-02 desktop approval card geometry and quick approve',
      (t) async {
    final sent = <QuickAction>[];
    final payload = <String, dynamic>{
      'kind': 'waiting',
      'title': 'Lead',
      'body': 'Approve merge of canvas-app-final? Checks are green.',
      'session': 's',
      'url': 'u',
      'attention': {'type': 'approval', 'text': 'Approve merge'},
    };
    await _pumpCard(t, payload, send: (_, action) {
      sent.add(action);
      return Completer<bool>().future;
    });

    final card = find.byType(NotificationMessageCard);
    final material = t.widget<Material>(
        find.descendant(of: card, matching: find.byType(Material)).first);
    expect(material.color, AppColors.surface2);
    expect((material.shape as RoundedRectangleBorder).borderRadius,
        BorderRadius.circular(12));
    expect(find.text('Needs you'), findsOneWidget);
    expect(find.byKey(const ValueKey('reply-field')), findsNothing);

    for (final label in ['Open', 'Approve', 'Deny']) {
      expect(t.getSize(_btn(label)).height, 26);
      final text = t.widget<Text>(find.text(label));
      expect(text.style?.fontSize, 12);
      expect(text.style?.fontWeight, FontWeight.w500);
    }
    Color fill(String label) => t
        .widget<Material>(find
            .ancestor(of: find.text(label), matching: find.byType(Material))
            .first)
        .color!;
    expect(fill('Approve'), AppColors.fg1);
    expect(fill('Deny'), AppColors.surface3);
    expect(fill('Open'), Colors.transparent);
    // Approve and Deny lead; Open trails on the right.
    expect(t.getRect(_btn('Deny')).left,
        greaterThan(t.getRect(_btn('Approve')).right));
    expect(
        t.getRect(_btn('Open')).right, closeTo(t.getRect(card).right - 10, 1));

    await t.tap(find.text('Approve'));
    await t.pump();
    expect(sent.single, isA<QuickApprove>());
    expect(t.takeException(), isNull);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('NT-02 desktop reply card sends quick reply', (t) async {
    final sent = <QuickAction>[];
    await _pumpCard(t, <String, dynamic>{
      'kind': 'message',
      'title': 'Sashy',
      'body': 'Can you look at the notification stack?',
      'session': 's',
      'url': 'u',
    }, send: (_, action) {
      sent.add(action);
      return Completer<bool>().future;
    });
    expect(find.text('Approve'), findsNothing);
    expect(find.byKey(const ValueKey('reply-field')), findsOneWidget);
    expect(find.byTooltip('Send'), findsNothing);
    await t.enterText(find.byType(TextField), 'yes, checking now');
    await t.pump();
    expect(find.byTooltip('Send'), findsOneWidget);
    expect(t.getSize(find.byTooltip('Send')).height, 26);
    await t.tap(find.byTooltip('Send'));
    await t.pump();
    final reply = sent.single as QuickReply;
    expect(reply.text, 'yes, checking now');
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('NT-02 desktop question choices use compact quick actions',
      (t) async {
    final sent = <QuickAction>[];
    await _pumpCard(t, <String, dynamic>{
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
    }, send: (_, action) {
      sent.add(action);
      return Completer<bool>().future;
    });
    for (final label in ['main', 'release']) {
      expect(t.getSize(_btn(label)).height, 26);
    }
    await t.tap(find.text('main'));
    await t.pump();
    expect(sent.single, isA<QuickAnswer>());
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('NT-02 bare waiting payload opens only when ask data is missing',
      (t) async {
    await _pumpCard(t, <String, dynamic>{
      'kind': 'waiting',
      'title': 'Lead',
      'body': 'Input needed',
      'session': 's',
      'url': 'u',
    });
    expect(
        cardActionFor({
          'kind': 'waiting',
          'session': 's',
        }),
        CardAction.none);
    expect(find.text('Open'), findsOneWidget);
    expect(find.text('Approve'), findsNothing);
    expect(find.text('Reply'), findsNothing);
    expect(find.byKey(const ValueKey('reply-field')), findsNothing);
    await t.pumpWidget(const SizedBox());
  });
}
