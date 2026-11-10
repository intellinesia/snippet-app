import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/screens/mobile_chrome.dart';

void main() {
  testWidgets('tapping the active Sessions segment flips to Agents and back',
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
      expect(find.text('Agents'), findsOneWidget);
      expect(mobileAgentsList.value, isTrue);
      expect((await SharedPreferences.getInstance()).getBool('mobile_home_agents_list'), isTrue);

      await tester.tap(find.byKey(const ValueKey('home-list-segment')));
      await tester.pumpAndSettle();
      expect(find.text('Sessions'), findsOneWidget);
      expect(sessionsTaps, 0);
    } finally {
      mobileAgentsList.value = false;
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
