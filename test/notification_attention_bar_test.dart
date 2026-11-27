import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart' hide testWidgets;
import 'package:flutter_test/flutter_test.dart' as ft show testWidgets;
import 'package:snippet/attention_state.dart';
import 'package:snippet/menu_widgets.dart';
import 'package:snippet/models.dart';
import 'package:snippet/notification_popovers.dart';
import 'package:snippet/quiet.dart';
import 'package:snippet/screens/mobile_chrome.dart';
import 'package:snippet/screens/mobile_home/collapsing_root.dart';
import 'package:snippet/screens/mobile_home/quiet_home.dart';
import 'package:snippet/theme.dart';
import 'package:snippet/toast.dart' show resetToastsForTest;
import 'package:snippet/top_zone.dart';
import 'package:snippet/widgets.dart' show AppIcon;

void testWidgets(String name, Future<void> Function(WidgetTester) body) =>
    ft.testWidgets(name, (t) async {
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      try {
        await body(t);
      } finally {
        debugDefaultTargetPlatformOverride = null;
        phoneNeedsYou.value = 0;
        resetToastsForTest();
        TopZone.reset();
      }
    });

late BuildContext _ctx;

Future<void> _pumpRoot(
  WidgetTester t,
  double w,
  double scale,
  int count, {
  Widget? page,
}) async {
  t.view.devicePixelRatio = 1;
  t.view.physicalSize = Size(w, 852);
  addTearDown(t.view.reset);
  TopZone.reset();
  phoneNeedsYou.value = count;
  await t.pumpWidget(MaterialApp(
    theme: buildAppTheme(),
    builder: (c, child) => MediaQuery(
      data: MediaQuery.of(c).copyWith(
          textScaler: TextScaler.linear(scale),
          padding: const EdgeInsets.only(top: 44)),
      child: NotificationPopovers(child: child!),
    ),
    home: Scaffold(
      body: SafeArea(
        child: page ??
            CollapsingRoot(
              title: 'Sessions',
              child: Builder(builder: (c) {
                _ctx = c;
                return ListView(children: const [
                  LargeTitle('Sessions'),
                  SizedBox(height: 44, child: Text('Chip row')),
                  SizedBox(height: 56, child: Text('First row')),
                ]);
              }),
            ),
      ),
    ),
  ));
  await t.pumpAndSettle();
}

void main() {
  final report = <String>[];
  tearDownAll(() {
    for (final line in report) {
      // ignore: avoid_print
      print(line);
    }
  });

  for (final w in [360.0, 393.0, 430.0]) {
    for (final scale in [1.0, 2.0]) {
      testWidgets('NT-03 + D1 geometry ${w.toInt()} x$scale', (t) async {
        // First measure LargeTitle top without the bar.
        await _pumpRoot(t, w, scale, 0);
        final titleNoBar = t.getRect(find.byType(LargeTitle));
        expect(find.byKey(const ValueKey('bar')), findsNothing);

        // Now show the bar and verify it pushes content down with no overlap.
        phoneNeedsYou.value = 2;
        await t.pumpAndSettle();

        final bar = find.byKey(const ValueKey('bar'));
        expect(bar, findsOneWidget);
        final r = t.getRect(bar);
        final titleWithBar = t.getRect(find.byType(LargeTitle));
        final firstRow = t.getRect(find.text('First row'));

        expect(r.left, 0);
        expect(r.width, w);
        expect(r.top, closeTo(100, 0.5));
        if (scale == 1) expect(r.height, 48);
        expect(r.height, greaterThanOrEqualTo(48));

        // D1: content starts at bar bottom and shifts down by bar height.
        expect(titleWithBar.top, closeTo(r.bottom, 0.5));
        expect(titleWithBar.top - titleNoBar.top, closeTo(r.height, 0.5));
        expect(firstRow.top, greaterThan(titleWithBar.bottom));

        // NT-03 Review alignment: right aligned at W-16 inside a 48 target ending at W-4.
        final reviewTarget =
            t.getRect(find.byKey(const ValueKey('attention-review-target')));
        final reviewText = t.getRect(find.text('Review'));
        expect(reviewTarget.width, greaterThanOrEqualTo(48));
        expect(reviewTarget.height, greaterThanOrEqualTo(48));
        expect(reviewTarget.right, closeTo(w - 4, 0.5));
        expect(reviewText.right, closeTo(w - 16, 0.5));

        expect(t.widget<Text>(find.text('2 need you')).style?.color,
            AppColors.run);
        expect(
            t.widget<AppIcon>(find.byType(AppIcon).first).color, AppColors.run);

        // A toast sits 8 below the bar, the lowest registered top bar.
        toast(_ctx, 'Approved');
        await t.pump(const Duration(milliseconds: 300));
        expect(TopZone.floatTop(_ctx), closeTo(r.bottom + 8, 0.5));
        final toastTop = t.getTopLeft(find.text('Approved')).dy;
        expect(toastTop, greaterThanOrEqualTo(r.bottom + 7));
        expect(t.takeException(), isNull);

        report.add(
          'NT03 w=${w.toInt()} s=${scale}x bar=(${r.left.toStringAsFixed(1)},${r.top.toStringAsFixed(1)},${r.width.toStringAsFixed(1)}x${r.height.toStringAsFixed(1)}) '
          'titleTop=${titleNoBar.top.toStringAsFixed(1)}->${titleWithBar.top.toStringAsFixed(1)} '
          'reviewTarget=${reviewTarget.width.toStringAsFixed(1)}x${reviewTarget.height.toStringAsFixed(1)}@R${reviewTarget.right.toStringAsFixed(1)} '
          'reviewTextR=${reviewText.right.toStringAsFixed(1)} (W-16=${(w - 16).toStringAsFixed(1)}) '
          'toastTop=${toastTop.toStringAsFixed(1)}',
        );
      });
    }
  }

  testWidgets('D2: bar sits under dialog and bottom sheet scrims', (t) async {
    var tapped = 0;
    onReviewNeedsYou = () => tapped++;
    addTearDown(() => onReviewNeedsYou = null);

    await _pumpRoot(t, 393, 1, 2);
    final barCenter = t.getCenter(find.byKey(const ValueKey('bar')));

    // Dialog scrim intercepts taps over the bar and dismisses the dialog.
    showDialog<void>(
      context: _ctx,
      builder: (_) => const AlertDialog(content: Text('Confirm')),
    );
    await t.pumpAndSettle();
    expect(find.text('Confirm'), findsOneWidget);
    await t.tapAt(barCenter);
    await t.pumpAndSettle();
    expect(find.text('Confirm'), findsNothing);
    expect(tapped, 0);

    // Bottom sheet scrim also sits above the bar.
    showModalBottomSheet<void>(
      context: _ctx,
      builder: (_) => const SizedBox(height: 200, child: Text('Sheet')),
    );
    await t.pumpAndSettle();
    expect(find.text('Sheet'), findsOneWidget);
    await t.tapAt(barCenter);
    await t.pumpAndSettle();
    expect(find.text('Sheet'), findsNothing);
    expect(tapped, 0);
  });

  testWidgets('NT-03 hidden on session/pushed pages and AttentionBarHidden',
      (t) async {
    var opened = 0;
    onReviewNeedsYou = () => opened++;
    addTearDown(() => onReviewNeedsYou = null);

    await _pumpRoot(t, 393, 1, 3);
    await t.tap(find.text('Review'));
    expect(opened, 1);
    await t.tap(find.text('3 need you'));
    expect(opened, 2);

    // Pushed session page has no attention bar and clears TopZone bar bottom.
    Navigator.of(_ctx).push(MaterialPageRoute<void>(
      builder: (_) => const Scaffold(
        body: SafeArea(
          child: Column(children: [
            MobileBackBar(title: 'Session'),
            Expanded(child: Center(child: Text('Chat body'))),
          ]),
        ),
      ),
    ));
    await t.pumpAndSettle();
    expect(find.text('Chat body'), findsOneWidget);
    expect(find.byKey(const ValueKey('bar')), findsNothing);
    expect(TopZone.lowestBar.value, lessThan(140));

    // AttentionBarHidden also suppresses the bar on a root.
    await _pumpRoot(
      t,
      393,
      1,
      2,
      page: const AttentionBarHidden(
        child: CollapsingRoot(
          title: 'Sessions',
          child: SizedBox.expand(),
        ),
      ),
    );
    expect(find.byKey(const ValueKey('bar')), findsNothing);
  });

  testWidgets('NT-03 counts: 1 needs you, 0 collapses', (t) async {
    await _pumpRoot(t, 393, 1, 1);
    expect(find.text('1 needs you'), findsOneWidget);
    phoneNeedsYou.value = 0;
    await t.pump();
    await t.pump(const Duration(milliseconds: 250));
    expect(find.byKey(const ValueKey('bar')), findsNothing);
    expect(TopZone.lowestBar.value, closeTo(100, 0.5));
  });

  testWidgets(
      'Agents root carries at most 2 amber elements (bar + card dot)',
      (t) async {
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    final agents = [
      CoordinationAgent.fromJson({
        'id': 'atlas',
        'display_name': 'Atlas',
        'handle': 'atlas',
        'status': 'active',
        'needs_you': 1,
      }),
    ];
    final sessions = [
      SessionInfo.fromJson({
        'id': 's1',
        'agent_id': 'atlas',
        'title': 'Review PR',
        'status': 'waiting_for_input',
        'running': false,
        'last_active': now,
        'attention': {'type': 'question', 'text': 'Approve the migration?'},
      }),
    ];

    await _pumpRoot(
      t,
      393,
      1,
      1,
      page: QuietHomeScreen(
        agents: agents,
        sessions: sessions,
        groups: const [],
        onOpenAgent: (_) {},
        onOpenSession: (_) {},
        onOpenGroup: (_) {},
        onOpenSessions: () {},
        onSettings: () {},
        onSearch: () {},
        onNew: () {},
        onAllAgents: () {},
      ),
    );

    // 1. Attention bar is present and pushes the Agents LargeTitle down.
    final barRect = t.getRect(find.byKey(const ValueKey('bar')));
    final titleRect = t.getRect(find.byType(LargeTitle));
    expect(titleRect.top, closeTo(barRect.bottom, 0.5));

    // 2. Chip amber dot is removed.
    expect(find.byKey(const ValueKey('chip-amber-dot')), findsNothing);

    // 3. Board: content cards have no outline; amber is only the dot.
    final card = find.byKey(const ValueKey('ask-card')).first;
    bool amber(Color? c) => c == quietAmber || c == AppColors.run;
    expect(
        find.descendant(
            of: card,
            matching: find.byWidgetPredicate((w) =>
                w is Container &&
                w.decoration is BoxDecoration &&
                (w.decoration as BoxDecoration).border != null)),
        findsNothing);
    final amberInCard = find
        .descendant(
            of: card,
            matching: find.byWidgetPredicate((w) =>
                (w is Container &&
                    w.decoration is BoxDecoration &&
                    amber((w.decoration as BoxDecoration).color)) ||
                (w is Text && amber(w.style?.color))))
        .evaluate()
        .length;

    // Distinct amber elements on Agents root: the bar and the card's dot.
    var amberElements = amberInCard;
    if (find.byKey(const ValueKey('bar')).evaluate().isNotEmpty) {
      amberElements++;
    }
    if (find.byKey(const ValueKey('chip-amber-dot')).evaluate().isNotEmpty) {
      amberElements++;
    }
    expect(amberElements, lessThanOrEqualTo(2));
    report.add(
      'AGENTS_ROOT bar=(${barRect.top.toStringAsFixed(1)}..${barRect.bottom.toStringAsFixed(1)}) '
      'titleTop=${titleRect.top.toStringAsFixed(1)} amberElements=$amberElements',
    );
  });
}
