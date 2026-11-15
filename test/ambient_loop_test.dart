import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/ambient_loop.dart';
import 'package:snippet/screens/session_list_row.dart';

List<double> _bottoms(WidgetTester tester) => tester
    .widgetList<Positioned>(find.descendant(
        of: find.byType(WorkingDots), matching: find.byType(Positioned)))
    .map((p) => p.bottom!)
    .toList();

void main() {
  testWidgets('WorkingDots advances on the clock without vsync frames',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: Center(child: WorkingDots())));
    await tester.pump();
    expect(AmbientClock.instance.isRunning, isTrue);
    expect(tester.binding.hasScheduledFrame, isFalse);

    final before = _bottoms(tester);
    await tester.pump(const Duration(milliseconds: 30));
    expect(tester.binding.hasScheduledFrame, isFalse);
    // Crosses one tick; pump draws the frame it asked for and no more.
    await tester.pump(const Duration(milliseconds: 40));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(_bottoms(tester), isNot(equals(before)));

    await tester.pumpWidget(const SizedBox());
    expect(AmbientClock.instance.isRunning, isFalse);
  });

  testWidgets('a frame drawn for something else carries the tick early',
      (tester) async {
    await tester.pumpWidget(
        const MaterialApp(home: Center(child: WorkingDots())));
    await tester.pump();
    final before = _bottoms(tester);
    // 45 ms is short of the 66 ms timer, past the 60% ride threshold.
    tester.binding.scheduleFrame();
    await tester.pump(const Duration(milliseconds: 45));
    expect(_bottoms(tester), isNot(equals(before)));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('TickerMode disabled stops updates', (tester) async {
    final enabled = ValueNotifier(true);
    addTearDown(enabled.dispose);
    await tester.pumpWidget(MaterialApp(
      home: ValueListenableBuilder<bool>(
        valueListenable: enabled,
        builder: (_, on, __) => TickerMode(
            enabled: on, child: const Center(child: WorkingDots())),
      ),
    ));
    expect(AmbientClock.instance.isRunning, isTrue);

    enabled.value = false;
    await tester.pump();
    expect(AmbientClock.instance.isRunning, isFalse);
    final held = _bottoms(tester);
    await tester.pump(const Duration(milliseconds: 500));
    expect(tester.binding.hasScheduledFrame, isFalse);
    expect(_bottoms(tester), equals(held));

    enabled.value = true;
    await tester.pump();
    expect(AmbientClock.instance.isRunning, isTrue);
    await tester.pump(const Duration(milliseconds: 200));
    expect(_bottoms(tester), isNot(equals(held)));
  });

  testWidgets('AmbientLoop phase, reverse and stop', (tester) async {
    final loop = AmbientLoop(const Duration(milliseconds: 660));
    final back = AmbientLoop(const Duration(milliseconds: 660), reverse: true);
    var ticks = 0;
    loop.addListener(() => ticks++);
    loop.start();
    back.start();
    final t0 = loop.value;
    await tester.pump(const Duration(milliseconds: 330));
    expect(ticks, 5);
    expect((loop.value - t0) % 1.0, closeTo(0.5, 0.01));
    for (var i = 0; i < 40; i++) {
      await tester.pump(const Duration(milliseconds: 66));
      expect(loop.value, inInclusiveRange(0, 1));
      expect(back.value, inInclusiveRange(0, 1));
    }

    loop.stop(at: 0.25);
    expect(loop.value, 0.25);
    final seen = ticks;
    await tester.pump(const Duration(milliseconds: 330));
    expect(ticks, seen);
    expect(loop.value, 0.25);

    loop.dispose();
    back.dispose();
    expect(AmbientClock.instance.isRunning, isFalse);
  });
}
