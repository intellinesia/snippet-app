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

void _expectLockedNeedsYou(WidgetTester t, Finder within, double fontSize) {
  final label = find.descendant(of: within, matching: find.text('Needs you'));
  expect(label, findsOneWidget);
  final text = t.widget<Text>(label);
  expect(text.style?.color, AppColors.fg2);
  expect(text.style?.fontSize, fontSize);
  expect(text.style?.fontWeight, FontWeight.w500);
  expect(
      find.descendant(
          of: within,
          matching:
              find.byWidgetPredicate((w) => w is AppIcon && w.name == 'hand')),
      findsNothing);
  final dot = find.descendant(
      of: within,
      matching: find.byWidgetPredicate((w) =>
          w is Container &&
          w.decoration is BoxDecoration &&
          (w.decoration as BoxDecoration).color == AppColors.run &&
          (w.decoration as BoxDecoration).shape == BoxShape.circle));
  expect(dot, findsOneWidget);
  expect(t.getSize(dot), const Size(6, 6));
  expect(
      find.descendant(
          of: within,
          matching: find.byWidgetPredicate(
              (w) => w is Text && w.style?.color == AppColors.run)),
      findsNothing);
}

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
      'NT-01 desktop stack: width, anchor, cap, footer and locked needs-you',
      (t) async {
    _seedStack();
    await _pumpHost(t);
    await t.pumpAndSettle();

    final cards = find.byType(NotificationBanner);
    expect(cards, findsNWidgets(3));
    final first = t.getRect(cards.at(0));
    final second = t.getRect(cards.at(1));
    expect(first.width, 360);
    expect(first.left, 1440 - 24 - 360);
    expect(first.top, kShellTabStripHeight + TopZone.gap);
    expect(second.top, closeTo(first.bottom + 8, .01));

    final material = t.widget<Material>(find
        .descendant(of: cards.first, matching: find.byType(Material))
        .first);
    expect(material.color, AppColors.surface2);
    expect(material.borderRadius, BorderRadius.circular(12));
    _expectLockedNeedsYou(t, cards.first, 11.5);

    final infoIcons = find.descendant(
        of: cards.at(1),
        matching: find.byWidgetPredicate(
            (w) => w is AppIcon && w.size == 20 && w.color == AppColors.fg2));
    expect(infoIcons, findsOneWidget);
    expect(
        find.descendant(
            of: cards.at(1),
            matching: find.byWidgetPredicate((w) =>
                (w is AppIcon && w.color == AppColors.run) ||
                (w is Text && w.style?.color == AppColors.run))),
        findsNothing,
        reason: 'information banners are neutral');

    for (final label in ['Show all 5', 'Dismiss all']) {
      expect(find.text(label), findsOneWidget);
      final target = find
          .ancestor(of: find.text(label), matching: find.byType(ConstrainedBox))
          .first;
      expect(t.getSize(target).height, 28);
      final text = t.widget<Text>(find.text(label));
      expect(text.style?.fontSize, 12);
      expect(text.style?.color, AppColors.fg2);
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
    expect(material.borderRadius, BorderRadius.circular(14));
    _expectLockedNeedsYou(t, card, 12);

    final field = find.byKey(const ValueKey('reply-field'));
    expect(t.getSize(field).height, 36);
    final fieldBox = t.widget<Container>(field);
    final decoration = fieldBox.decoration as BoxDecoration;
    expect(decoration.color, AppColors.surface1);
    expect(decoration.borderRadius, BorderRadius.circular(8));

    for (final label in ['Open', 'Approve']) {
      expect(t.getSize(_btn(label)).height, 28);
      final text = t.widget<Text>(find.text(label));
      expect(text.style?.fontSize, 12);
      expect(text.style?.fontWeight, FontWeight.w500);
    }
    final openMaterial = t.widget<Material>(find
        .ancestor(of: find.text('Open'), matching: find.byType(Material))
        .first);
    final approveMaterial = t.widget<Material>(find
        .ancestor(of: find.text('Approve'), matching: find.byType(Material))
        .first);
    expect(openMaterial.color, AppColors.surface3);
    expect(approveMaterial.color, AppColors.fg1);

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
    expect(find.text('Reply'), findsOneWidget);
    expect(find.byTooltip('Send'), findsNothing);
    await t.enterText(find.byType(TextField), 'yes, checking now');
    await t.pump();
    expect(find.byTooltip('Send'), findsOneWidget);
    expect(t.getSize(find.byTooltip('Send')).height, 28);
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
      expect(t.getSize(_btn(label)).height, 28);
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
