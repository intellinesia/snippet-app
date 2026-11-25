import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/canvas/canvas_screen.dart';
import 'package:snippet/notification_banner.dart';
import 'package:snippet/top_zone.dart';
import 'package:snippet/notification_popovers.dart';
import 'package:snippet/notification_sync.dart';
import 'package:snippet/theme.dart';

import 'canvas_layout_test.dart' show EmptyCanvasClient;

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('canvas notices use the top band at ${scale}x', (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(393, 852);
      addTearDown(tester.view.reset);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final sem = tester.ensureSemantics();
      foregroundNotifications.drain();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async => null);
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null));
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c)
                .copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: NotificationPopovers(
            child: Scaffold(
                body: CanvasScreen(
                    client: EmptyCanvasClient(),
                    title: 'Board',
                    onClose: () {}))),
      ));
      await tester.pump(const Duration(milliseconds: 100));
      await tester.tap(find.bySemanticsLabel('Share').first);
      await tester.pump(const Duration(milliseconds: 100));
      await tester.pump(const Duration(milliseconds: 600));
      expect(find.byType(SnackBar), findsNothing);
      // NT-01: notices are floating banners under the top bars, x16 wide.
      final toast = tester.getRect(find.byType(NotificationBanner));
      expect(toast.left, 16);
      expect(toast.width, 393 - 32);
      expect(toast.top, TopZone.floatTop(tester.element(find.byType(Scaffold).first)));
      // Auto-dismiss kept.
      await tester.pump(const Duration(seconds: 6));
      await tester.pumpAndSettle();
      expect(find.byType(NotificationBanner), findsNothing);
      sem.dispose();
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
