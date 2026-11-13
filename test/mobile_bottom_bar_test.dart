import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/screens/mobile_bottom_bar.dart';
import 'package:snippet/screens/shell_models.dart';
import 'package:snippet/theme.dart';

void main() {
  Widget harness({
    MobileHome home = MobileHome.chats,
    int working = 0,
    VoidCallback? onSearch,
    ValueChanged<MobileHome>? onHome,
    VoidCallback? onNewSession,
    void Function(BuildContext)? onNewAgentOrGroup,
  }) {
    return MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Align(
            alignment: Alignment.bottomCenter,
            child: MobileBottomBar(
              home: home,
              onHome: onHome ?? (_) {},
              onNewSession: onNewSession ?? () {},
              onNewAgentOrGroup: onNewAgentOrGroup ?? (_) {},
              workingCount: working,
              onSearch: onSearch,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('the three tabs render and tapping Agents reports the home', (
    tester,
  ) async {
    MobileHome? picked;
    await tester.pumpWidget(
      harness(onSearch: () {}, onHome: (h) => picked = h),
    );
    await tester.pumpAndSettle();

    for (final label in ['Sessions', 'Agents', 'Settings']) {
      expect(find.text(label), findsOneWidget, reason: label);
    }
    expect(find.text('Tasks'), findsNothing);
    expect(find.byTooltip('New session'), findsOneWidget);
    expect(find.byTooltip('Search'), findsOneWidget);

    await tester.tap(find.text('Agents'));
    await tester.pumpAndSettle();
    expect(picked, MobileHome.agents);
  });

  testWidgets('Tasks and Settings show only the tab capsule', (tester) async {
    await tester.pumpWidget(harness(home: MobileHome.tasks));
    await tester.pumpAndSettle();
    expect(find.text('Sessions'), findsOneWidget);
    expect(find.text('Tasks'), findsNothing);
    expect(find.byTooltip('New session'), findsNothing);
    expect(find.byTooltip('Search'), findsNothing);

    await tester.pumpWidget(harness(home: MobileHome.settings));
    await tester.pumpAndSettle();
    expect(find.byTooltip('New session'), findsNothing);
    expect(find.byTooltip('Search'), findsNothing);
  });

  testWidgets('the search circle reports onSearch and keeps the tabs', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(harness(onSearch: () => opened++));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    expect(opened, 1);
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Sessions'), findsOneWidget);
    expect(find.byTooltip('Search'), findsOneWidget);
  });

  testWidgets('the pill shows the working count and calls onNewSession', (
    tester,
  ) async {
    var called = 0;
    await tester.pumpWidget(harness(working: 3, onNewSession: () => called++));
    await tester.pumpAndSettle();

    expect(find.text('3 working'), findsOneWidget);
    await tester.tap(find.byTooltip('New session'));
    await tester.pumpAndSettle();
    expect(called, 1);
  });

  testWidgets('no working sessions means no count on the pill', (tester) async {
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    expect(find.textContaining('working'), findsNothing);
  });

  testWidgets('Agents hides the primary pill and keeps tabs and search',
      (tester) async {
    await tester.pumpWidget(
      harness(
        home: MobileHome.agents,
        onSearch: () {},
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('New agent or group'), findsNothing);
    expect(find.byTooltip('New session'), findsNothing);
    expect(find.byTooltip('Search'), findsOneWidget);
    expect(find.text('Agents'), findsOneWidget);
  });
}
