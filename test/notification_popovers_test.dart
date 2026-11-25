import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:snippet/notification_inbox.dart';
import 'package:flutter_test/flutter_test.dart' hide testWidgets;
import 'package:flutter_test/flutter_test.dart' as ft show testWidgets;
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
    await tester.pump(const Duration(seconds: 4));
    foregroundNotifications.add({'title': 'Second'});
    await tester.pump();
    expect(find.text('Second'), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsOneWidget);
    expect(find.text('First'), findsNothing);
    await tester.pump(const Duration(seconds: 4));
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsNothing);
    expect(haptics, isEmpty);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
    expect(tester.takeException(), isNull);
  });

  testWidgets('a held banner does not expire; suppression removes it',
      (tester) async {
    foregroundNotifications.add({'title': 'Held', 'url': 'u', 'session': 's'});
    await tester.pumpWidget(const MaterialApp(
        home: MediaQuery(
      data: MediaQueryData(disableAnimations: true),
      child: NotificationPopovers(child: Scaffold()),
    )));
    final gesture = await tester.startGesture(
        tester.getTopLeft(find.text('Held')) + const Offset(1, 1));
    await tester.pump(const Duration(seconds: 20));
    expect(find.text('Held'), findsOneWidget);
    await gesture.cancel();
    visibleNotificationSession.value = notificationSessionKey('u', 's');
    await tester.pumpAndSettle();
    expect(find.text('Held'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
    expect(tester.takeException(), isNull);
  });

  testWidgets('desktop shows no toast; asks live on the composer',
      (tester) async {
    _platform(TargetPlatform.linux);
    foregroundNotifications.add({'title': 'First', 'kind': 'done', 'session': 's1'});
    foregroundNotifications.add({'title': 'Ask', 'kind': 'waiting', 'session': 's2'});
    await tester.pumpWidget(const MaterialApp(
        home: NotificationPopovers(child: Scaffold(body: Text('Home')))));
    await tester.pumpAndSettle();
    expect(find.text('First'), findsNothing);
    expect(find.text('Ask'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 10));
  });
}
