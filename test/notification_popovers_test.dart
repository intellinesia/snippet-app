import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:snippet/notification_inbox.dart';
import 'package:flutter_test/flutter_test.dart' hide testWidgets;
import 'package:flutter_test/flutter_test.dart' as ft show testWidgets;
import 'package:snippet/desktop_notifications.dart';
import 'package:snippet/notification_popovers.dart';
import 'package:snippet/widgets.dart' show AppIcon;
import 'package:snippet/notification_sync.dart';
import 'package:snippet/notifications.dart';

void _platform(TargetPlatform p) => debugDefaultTargetPlatformOverride = p;

void testWidgets(String name, Future<void> Function(WidgetTester) body) =>
    ft.testWidgets(name, (t) async {
      try {
        await body(t);
      } finally {
        debugDefaultTargetPlatformOverride = null;
      }
    });

void main() {
  test('desktop foreground state controls visible-chat suppression', () {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    reportForeground(true);
    reportVisibleNotificationSession('u', 's');
    expect(notificationAppForeground, isTrue);
    expect(suppressVisibleNotification({'url': 'u', 'session': 's'}), isTrue);
    expect(
        suppressVisibleNotification({'url': 'u', 'session': 'other'}), isFalse);
    reportForeground(false);
    expect(notificationAppForeground, isFalse);
    expect(visibleNotificationSession.value, isNull);
    reportVisibleNotificationSession('u', 's');
    expect(visibleNotificationSession.value, isNull);
    reportForeground(true);
    expect(notificationAppForeground, isTrue);
    expect(suppressVisibleNotification({'url': 'u', 'session': 's'}), isFalse);
  });

  final haptics = <String>[];
  setUp(() {
    foregroundNotifications.drain();
    visibleNotificationSession.value = null;
    notificationAppForeground = true;
    haptics.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'HapticFeedback.vibrate') {
        haptics.add(call.arguments as String);
      }
      return null;
    });
  });
  tearDown(() {
    onNotifTap = null;
    foregroundNotifications.drain();
    visibleNotificationSession.value = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  test('destination preserves brief context', () {
    final payload = notificationDestination('url', {
      'kind': 'waiting',
      'message': 'Approve command',
      'destination': {'type': 'session', 'id': 's'},
    });
    expect(payload['kind'], 'waiting');
    expect(payload['body'], 'Approve command');
    expect(payload['session'], 's');
  });

  testWidgets('each item expires on its own deadline without haptics',
      (tester) async {
    foregroundNotifications.add({'title': 'First'});
    await tester.pumpWidget(
        const MaterialApp(home: NotificationPopovers(child: Scaffold())));
    await tester.pump(const Duration(seconds: 3));
    foregroundNotifications.add({'title': 'Second'});
    await tester.pump();
    expect(find.text('Second'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('First'), findsNothing);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsNothing);
    expect(haptics, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
    expect(tester.takeException(), isNull);
  });

  testWidgets('phone banners dismiss with a swipe up, not sideways',
      (tester) async {
    _platform(TargetPlatform.android);
    foregroundNotifications.add({'title': 'Up'});
    await tester.pumpWidget(
        const MaterialApp(home: NotificationPopovers(child: Scaffold())));
    await tester.pumpAndSettle();
    await tester.drag(find.byType(Dismissible), const Offset(500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Up'), findsOneWidget);
    await tester.drag(find.byType(Dismissible), const Offset(-500, 0));
    await tester.pumpAndSettle();
    expect(find.text('Up'), findsOneWidget);
    await tester.drag(find.byType(Dismissible), const Offset(0, 200));
    await tester.pumpAndSettle();
    expect(find.text('Up'), findsOneWidget);
    await tester.fling(find.byType(Dismissible), const Offset(0, -80), 1500);
    await tester.pumpAndSettle();
    expect(find.text('Up'), findsNothing);
    expect(haptics, ['HapticFeedbackType.lightImpact']);
  });

  testWidgets('gesture pauses expiry; reduced motion and suppression clean up',
      (tester) async {
    foregroundNotifications.add({'title': 'Next', 'kind': 'waiting'});
    foregroundNotifications.add({'title': 'Held', 'url': 'u', 'session': 's'});
    await tester.pumpWidget(const MaterialApp(
        home: MediaQuery(
      data: MediaQueryData(disableAnimations: true),
      child: NotificationPopovers(child: Scaffold()),
    )));
    expect(
        tester
            .widget<AnimatedSwitcher>(find.byType(AnimatedSwitcher).first)
            .duration,
        Duration.zero);
    final gesture = await tester.startGesture(
        tester.getTopLeft(find.byType(Dismissible)) + const Offset(1, 1));
    await tester.pump(const Duration(seconds: 16));
    expect(find.text('Next'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    expect(find.text('Collapse'), findsOneWidget, reason: 'a hold expands');
    await gesture.cancel();
    expect(notificationAppForeground, isTrue);
    expect(suppressVisibleNotification({'url': 'u', 'session': 's'}), isFalse);
    visibleNotificationSession.value = notificationSessionKey('u', 's');
    expect(suppressVisibleNotification({'url': 'u', 'session': 's'}), isTrue);
    await tester.pumpAndSettle();
    expect(find.text('Held'), findsNothing);
    expect(find.text('needs you'), findsNothing);
    await tester.pump(const Duration(seconds: 11));
    expect(find.text('Next'), findsOneWidget);
    await tester.pump(const Duration(seconds: 1));
    await tester.pump();
    expect(find.text('Next'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    foregroundNotifications.add({'title': 'After dispose'});
    expect(foregroundNotifications.drain().single['title'], 'After dispose');
    await tester.pump(const Duration(seconds: 10));
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop toast shows one item, closes to the next and opens chat',
      (tester) async {
    _platform(TargetPlatform.linux);
    final opened = <Map<String, dynamic>>[];
    onNotifTap = opened.add;
    foregroundNotifications.add({'title': 'First', 'kind': 'done', 'session': 's1'});
    foregroundNotifications.add({'title': 'Second', 'kind': 'done', 'session': 's2'});
    await tester.pumpWidget(const MaterialApp(
        home: NotificationPopovers(child: Scaffold(body: Text('Home')))));
    await tester.pumpAndSettle();
    expect(find.byType(DesktopToast), findsOneWidget);
    expect(find.text('+1 more'), findsOneWidget);
    final first = find.text('First').evaluate().isNotEmpty ? 'First' : 'Second';
    final next = first == 'First' ? 'Second' : 'First';
    await tester.tap(find.descendant(
        of: find.byType(DesktopToast), matching: find.byType(AppIcon)).last);
    await tester.pumpAndSettle();
    expect(find.text(first), findsNothing);
    expect(find.text(next), findsOneWidget);
    await tester.tap(find.text('Open chat'));
    await tester.pumpAndSettle();
    expect(opened.single['title'], next);
    expect(find.byType(DesktopToast), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });
}
