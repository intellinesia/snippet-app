import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:snippet/mochi.dart';
import 'package:snippet/screens/mobile_chrome.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/widgets.dart';

void main() {
  testWidgets('setMobileAgentsList persists preference cleanly', (tester) async {
    SharedPreferences.setMockInitialValues({});
    mobileAgentsList.value = false;
    setMobileAgentsList(true);
    await tester.pump();
    expect(mobileAgentsList.value, isTrue);
    expect(
        (await SharedPreferences.getInstance())
            .getBool('mobile_home_agents_list'),
        isTrue);
    setMobileAgentsList(false);
    await tester.pump();
    expect(mobileAgentsList.value, isFalse);
  });

  testWidgets(
      'MobileHomeHeader renders compact 44px bar, MC badge, 17px strong title, listening pill, trailing action, and settings back mode',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      var mcTaps = 0;
    var moreTaps = 0;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: MobileHomeHeader(
          title: 'Sessions',
          mcBadgeCount: 3,
          onMc: () => mcTaps++,
          listening: true,
          trailing: [
            RoundBtn(
              icon: 'more-horizontal',
              tooltip: 'More',
              onTap: () => moreTaps++,
            ),
          ],
        ),
      ),
    ));
    await tester.pump();

    expect(find.byType(MochiIcon), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(find.byType(ListeningPill), findsOneWidget);
    expect(find.byTooltip('More'), findsOneWidget);

    final badgeBox = tester.widget<Container>(find
        .ancestor(of: find.text('3'), matching: find.byType(Container))
        .first);
    expect((badgeBox.decoration as BoxDecoration).color, AppColors.accentFill);
    final badgeText = tester.widget<Text>(find.text('3'));
    expect(badgeText.style?.color, AppColors.accentFg);

    final headerRect = tester.getRect(find.byType(MobileHomeHeader));
    expect(headerRect.height, 56);

    final title = tester.widget<Text>(find.text('Sessions'));
    expect(title.style?.fontSize, 17);
    expect(title.style?.fontWeight, FontWeight.w500);
    expect(title.maxLines, 1);
    expect(title.overflow, TextOverflow.ellipsis);
    expect(
      tester.getCenter(find.text('Sessions')).dx,
      closeTo(headerRect.center.dx, 1.0),
    );

    await tester.tap(find.byTooltip('Mission Control'));
    await tester.tap(find.byTooltip('More'));
    expect(mcTaps, 1);
    expect(moreTaps, 1);

    var backTaps = 0;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: MobileHomeHeader(
          title: 'Settings',
          onBack: () => backTaps++,
        ),
      ),
    ));
    await tester.pump();
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.byTooltip('Mission Control'), findsNothing);
    expect(find.byType(ListeningPill), findsNothing);
    final settingsTitle = tester.widget<Text>(find.text('Settings'));
    expect(settingsTitle.style?.fontSize, 17);
    expect(settingsTitle.style?.fontWeight, FontWeight.w500);
      await tester.tap(find.byTooltip('Back'));
      expect(backTaps, 1);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets(
      'MobileMissionBar renders back, Mission Control pill, tasks button with badge, and handles taps',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    try {
      var backTaps = 0;
    var actionTaps = 0;
    var tasksTaps = 0;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: MobileMissionBar(
          onBack: () => backTaps++,
          onActions: () => actionTaps++,
          onTasks: () => tasksTaps++,
          tasksBadgeCount: 2,
        ),
      ),
    ));
    await tester.pump();

    expect(find.text('Mission Control'), findsOneWidget);
    expect(find.byType(MochiIcon), findsOneWidget);
    expect(find.byTooltip('Back'), findsOneWidget);
    expect(find.byTooltip('Tasks'), findsOneWidget);
    expect(find.text('2'), findsOneWidget);

    final tasksIcon = tester.widget<AppIcon>(find
        .descendant(
            of: find.byTooltip('Tasks'), matching: find.byType(AppIcon))
        .first);
    expect(tasksIcon.name, 'task');

    await tester.tap(find.byTooltip('Back'));
    await tester.tap(find.text('Mission Control'));
    await tester.tap(find.byTooltip('Tasks'));
      expect(backTaps, 1);
      expect(actionTaps, 1);
      expect(tasksTaps, 1);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });
}
