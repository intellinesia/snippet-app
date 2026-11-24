import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/notification_card.dart';
import 'package:snippet/notification_popovers.dart';
import 'package:snippet/notification_sync.dart';
import 'package:snippet/platform.dart';
import 'package:snippet/screens/mobile_home/quiet_home.dart';
import 'package:snippet/theme.dart';

void main() {
  for (final scale in [1.0, 2.0]) {
    testWidgets('lead toast stays clear of search and settings at ${scale}x',
        (tester) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(393, 852);
      addTearDown(tester.view.reset);
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      final sem = tester.ensureSemantics();
      foregroundNotifications.drain();
      foregroundNotifications.add({
        'title': 'Lead',
        'kind': 'idle',
        'body': 'Finished and standing by after a very long status line',
      });
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        builder: (c, child) => MediaQuery(
            data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
            child: child!),
        home: NotificationPopovers(
            child: Scaffold(
                body: QuietPlaceHeader(
                    title: 'Agents', onSearch: () {}, onSettings: () {}))),
      ));
      await tester.pump(const Duration(milliseconds: 600));
      final pill = tester.getRect(find.byType(NotificationMessageCard));
      final search = tester.getRect(find.bySemanticsLabel('Search'));
      final gear = tester.getRect(find.bySemanticsLabel('Settings'));
      // ignore: avoid_print
      print('TOAST ${scale}x pill=$pill search=$search gear=$gear');
      expect(pill.overlaps(search), isFalse);
      expect(pill.overlaps(gear), isFalse);
      expect(search.overlaps(gear), isFalse);
      expect(search.width, greaterThanOrEqualTo(kPhoneTarget));
      expect(search.height, greaterThanOrEqualTo(kPhoneTarget));
      expect(gear.width, greaterThanOrEqualTo(kPhoneTarget));
      expect(gear.height, greaterThanOrEqualTo(kPhoneTarget));
      expect(tester.takeException(), isNull);
      sem.dispose();
      debugDefaultTargetPlatformOverride = null;
      foregroundNotifications.drain();
    });
  }
}
