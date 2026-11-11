import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/screens/mobile_chrome.dart';

void main() {
  testWidgets('the active segment opens a picker for sessions or agents',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      SharedPreferences.setMockInitialValues({});
      mobileAgentsList.value = false;
      var sessionsTaps = 0;
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: MobileTopBar(
                  mission: false,
                  onMission: () {},
                  onSessions: () => sessionsTaps++,
                  onMenu: () {},
                  onSettings: () {}))));
      expect(find.text('Sessions'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('home-list-segment')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('list-pick-sessions')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('list-pick-agents')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('list-pick-agents')), findsNothing);
      expect(find.text('Agents'), findsOneWidget);
      expect(mobileAgentsList.value, isTrue);
      expect((await SharedPreferences.getInstance()).getBool('mobile_home_agents_list'), isTrue);

      await tester.tap(find.byKey(const ValueKey('home-list-segment')));
      await tester.pumpAndSettle();
      await tester.tapAt(const Offset(200, 500));
      await tester.pumpAndSettle();
      expect(mobileAgentsList.value, isTrue);
      await tester.tap(find.byKey(const ValueKey('home-list-segment')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('list-pick-sessions')));
      await tester.pumpAndSettle();
      expect(find.text('Sessions'), findsOneWidget);
      expect(sessionsTaps, 0);
    } finally {
      mobileAgentsList.value = false;
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('the picker keeps a fixed max width and stays on screen',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      SharedPreferences.setMockInitialValues({});
      for (final w in [320.0, 390.0, 800.0]) {
        await _openAt(tester, w);
        final card = tester.getRect(find
            .ancestor(
                of: find.byKey(const ValueKey('list-pick-sessions')),
                matching: find.byType(Material))
            .first);
        expect(card.width, lessThanOrEqualTo(220), reason: 'width at $w');
        expect(card.left, greaterThanOrEqualTo(16), reason: 'left at $w');
        expect(card.right, lessThanOrEqualTo(w - 16), reason: 'right at $w');
        Navigator.of(tester.element(find.byKey(const ValueKey('list-pick-sessions')))).pop();
        await tester.pumpAndSettle();
      }
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}

void _noop() {}

Future<void> _openAt(WidgetTester tester, double width) async {
  tester.view.physicalSize = Size(width, 800);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
          body: MobileTopBar(
              mission: false,
              onMission: _noop,
              onSessions: _noop,
              onMenu: _noop,
              onSettings: _noop))));
  await tester.tap(find.byKey(const ValueKey('home-list-segment')));
  await tester.pumpAndSettle();
}
