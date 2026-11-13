import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/screens/mobile_bottom_bar.dart';
import 'package:snippet/screens/shell_models.dart';
import 'package:snippet/theme.dart';

void main() {
  MobileBarSearch search({ValueChanged<String>? onChanged}) {
    return MobileBarSearch(
      controller: TextEditingController(),
      focusNode: FocusNode(),
      hint: 'Search sessions',
      onChanged: onChanged ?? (_) {},
    );
  }

  Widget harness({
    MobileHome home = MobileHome.chats,
    int working = 0,
    MobileBarSearch? search,
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
              search: search,
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
      harness(search: search(), onHome: (h) => picked = h),
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

  testWidgets('the search circle reveals the field and x restores the tabs', (
    tester,
  ) async {
    var cleared = false;
    final s = search(onChanged: (_) => cleared = true);
    await tester.pumpWidget(harness(search: s));
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsOneWidget);
    expect(find.text('Sessions'), findsNothing);
    expect(find.byTooltip('New session'), findsNothing);

    await tester.enterText(find.byType(TextField), 'abc');
    await tester.tap(find.byTooltip('Close search'));
    await tester.pumpAndSettle();
    expect(find.byType(TextField), findsNothing);
    expect(find.text('Sessions'), findsOneWidget);
    expect(find.byTooltip('Search'), findsOneWidget);
    expect(s.controller.text, isEmpty);
    expect(cleared, isTrue);
    expect(s.focusNode.hasFocus, isFalse);
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
        search: search(),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byTooltip('New agent or group'), findsNothing);
    expect(find.byTooltip('New session'), findsNothing);
    expect(find.byTooltip('Search'), findsOneWidget);
    expect(find.text('Agents'), findsOneWidget);
  });
}
