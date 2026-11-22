import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/chat/signal_row.dart';
import 'package:snippet/panel.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/widgets.dart';

void main() {
  testWidgets(
      'showSignalDetails opens an anchored desktop popover with Copy and Close, not a modal dialog or bottom sheet',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.reset);

    try {
      late BuildContext ctx;
      await tester.pumpWidget(MaterialApp(
        theme: buildAppTheme(),
        home: Scaffold(
          body: Builder(builder: (c) {
            ctx = c;
            return const SizedBox.expand();
          }),
        ),
      ));

      // Anchor near the bottom of the window to verify it opens above the click cleanly.
      showSignalDetails(
        ctx,
        title: 'Model error',
        body: 'Snippet restarted mid-turn; the next message picks it up.',
        point: const Offset(620, 760),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 250));

      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.text('Model error'), findsOneWidget);
      expect(find.byTooltip('Copy'), findsOneWidget);
      expect(find.byTooltip('Close'), findsOneWidget);

      final popover = find
          .ancestor(of: find.text('Model error'), matching: find.byType(Material))
          .first;
      final rect = tester.getRect(popover);
      expect(rect.width, closeTo(460, 2));
      // Anchored right above the click point at y=760.
      expect(rect.bottom, closeTo(750, 4));
      expect(rect.top, greaterThan(0));

      await tester.tap(find.byTooltip('Close'));
      await tester.pumpAndSettle();
      expect(find.text('Model error'), findsNothing);
    } finally {
      debugDefaultTargetPlatformOverride = null;
    }
  });

  testWidgets('showAppSheet uses desktop width and displays subtitle',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1440, 900);
    addTearDown(tester.view.reset);

    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Builder(builder: (c) {
          ctx = c;
          return const SizedBox.expand();
        }),
      ),
    ));

    showAppSheet<void>(
      ctx,
      title: 'Watch details',
      subtitle: 'Polls every 5 minutes',
      child: const SizedBox(width: 600, height: 120),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    expect(find.text('Watch details'), findsOneWidget);
    expect(find.text('Polls every 5 minutes'), findsOneWidget);
    final card = find
        .descendant(
            of: find.byType(Dialog), matching: find.byType(Container))
        .first;
    final rect = tester.getRect(card);
    expect(rect.width, closeTo(460, 2));
    debugDefaultTargetPlatformOverride = null;
  });

  testWidgets('desktop right drawer scales comfortably on wide windows',
      (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.macOS;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1600, 900);
    addTearDown(tester.view.reset);

    late BuildContext ctx;
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Builder(builder: (c) {
          ctx = c;
          return const SizedBox.expand();
        }),
      ),
    ));

    presentScreen<void>(
      ctx,
      style: PanelStyle.drawer,
      maxWidth: 640,
      builder: (_, __) => const SizedBox.expand(
        key: ValueKey('drawer-body'),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 250));

    final rect = tester.getRect(find.byKey(const ValueKey('drawer-body')));
    // 36% of 1600 = 576px (wider than phone-sized 460px, capped at 640px).
    expect(rect.width, inInclusiveRange(560, 640));
    expect(rect.right, closeTo(1600, 1));
    debugDefaultTargetPlatformOverride = null;
  });
}
