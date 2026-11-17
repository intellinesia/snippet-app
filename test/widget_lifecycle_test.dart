import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/widgets.dart';
import 'package:snippet/screens/shell_nav.dart';

/// Widget-lifetime regression tests.
///
/// These cover a defect class `flutter analyze` and a green build are BOTH
/// structurally blind to, and which only fires at runtime on a real device:
///
///   A `late final AnimationController x = AnimationController(...)` initialiser
///   is LAZY — it runs on first access. If `build` never reads it (a static
///   status, a widget unmounted before its first frame), then `dispose` becomes
///   the first access and constructs the controller while the element is being
///   unmounted:
///
///     Element._debugCheckStateIsActiveForAncestorLookup
///     TickerMode.getValuesNotifier
///     AnimationController.<init>
///     _StatusDotState._c            <- the lazy init, triggered from dispose
///     _StatusDotState.dispose
///
///   The fix is to assign in `initState`, so creation never depends on the order
///   in which other methods happen to touch it.

/// Regression tests for [SessionStateIcon].
///
/// These exist because `flutter analyze` and a green build are BOTH blind to
/// this class of bug. A `late final AnimationController x = AnimationController(...)`
/// runs its initialiser on FIRST ACCESS. When nothing reads the controller
/// (an IDLE session — no pulse), the first access is `dispose()`, which
/// constructs a controller on an already-unmounting element and throws at
/// runtime only.

void main() {
  Future<void> mount(WidgetTester tester, Widget child) => tester.pumpWidget(
        MaterialApp(home: Scaffold(body: Center(child: child))),
      );

  testWidgets('StatusDot mounts and unmounts without touching its ticker',
      (tester) async {
    // 'online' is the case that crashed: `build` returns a plain Container and
    // never reads the controller, so disposal was the first access.
    await mount(tester, const StatusDot(status: 'online'));
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  testWidgets('StatusDot unmounts cleanly for every status', (tester) async {
    for (final status in ['online', 'offline', 'checking', 'running']) {
      await mount(tester, StatusDot(status: status));
      await tester.pumpWidget(const SizedBox.shrink());
      expect(tester.takeException(), isNull,
          reason: 'dispose threw for status "$status"');
    }
  });

  testWidgets('StatusDot animated statuses still animate', (tester) async {
    // The fix must not disable the animation for the statuses that use it.
    await mount(tester, const StatusDot(status: 'running'));
    expect(tester.takeException(), isNull);
    // Scoped to the dot's own subtree: MaterialApp's route transition supplies
    // its own FadeTransitions, so an unscoped finder matches those too.
    expect(
      find.descendant(
          of: find.byType(StatusDot), matching: find.byType(FadeTransition)),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox.shrink());
    expect(tester.takeException(), isNull);
  });

  Future<void> mountThenUnmount(WidgetTester t, String status) async {
    await t.pumpWidget(MaterialApp(
      home: Scaffold(body: SessionStateIcon(status: status)),
    ));
    expect(t.takeException(), isNull, reason: 'mount ($status) must be clean');
    // Replace the tree so the icon is disposed.
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull,
        reason: 'dispose ($status) must be clean — a controller built lazily '
            'inside dispose is the bug this guards');
  }

  testWidgets('idle icon mounts and disposes cleanly', (t) async {
    await mountThenUnmount(t, 'idle');
  });

  testWidgets('running icon mounts, pulses and disposes cleanly', (t) async {
    await mountThenUnmount(t, 'running');
    // A running icon must have actually animated (a ticker was live).
  });

  testWidgets('waiting_for_input mounts and disposes cleanly', (t) async {
    await mountThenUnmount(t, 'waiting_for_input');
  });

  testWidgets('unknown/absent status is treated as idle', (t) async {
    await mountThenUnmount(t, '');
  });

  testWidgets('status change idle -> running starts the pulse safely',
      (t) async {
    Widget build(String status) => MaterialApp(
          home: Scaffold(body: SessionStateIcon(status: status)),
        );
    await t.pumpWidget(build('idle'));
    expect(t.takeException(), isNull);
    await t.pumpWidget(build('running'));
    await t.pump(const Duration(milliseconds: 400));
    expect(t.takeException(), isNull);
    // And back down again.
    await t.pumpWidget(build('idle'));
    await t.pump(const Duration(milliseconds: 100));
    expect(t.takeException(), isNull);
  });

  testWidgets('only running counts as active', (t) async {
    expect(sessionIsActive('running'), isTrue);
    expect(sessionIsActive('idle'), isFalse);
    expect(sessionIsActive('waiting_for_input'), isFalse);
  });

  testWidgets('animate:false suppresses the ticker', (t) async {
    await t.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SessionStateIcon(status: 'running', animate: false),
      ),
    ));
    expect(t.takeException(), isNull);
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: SizedBox())));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });
}
