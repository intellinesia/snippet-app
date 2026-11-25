import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:snippet/components.dart';
import 'package:snippet/widgets.dart';

const _widths = [360.0, 393.0, 430.0];
const _scales = [1.0, 1.35, 2.0];

Future<void> _pump(WidgetTester t, double w, double scale, Widget child) async {
  t.view.physicalSize = Size(w, 800);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.reset);
  await t.pumpWidget(MaterialApp(
    builder: (c, ch) => MediaQuery(
        data: MediaQuery.of(c).copyWith(textScaler: TextScaler.linear(scale)),
        child: ch!),
    home: Scaffold(body: child),
  ));
}

void main() {
  for (final w in _widths) {
    for (final s in _scales) {
      testWidgets('empty block at $w x$s', (t) async {
        await _pump(
            t,
            w,
            s,
            EmptyState(
              icon: 'list',
              title: 'No tasks yet',
              body: 'Ask an agent to create one, or add your own.',
              action: StateButton('New task', onTap: () {}),
            ));
        expect(t.takeException(), isNull);
        expect(t.getSize(find.byType(AppIcon)), const Size(24, 24));
        final body = t.getSize(find.text('Ask an agent to create one, or add your own.'));
        expect(body.width, w - 72);
        final btn = t.getSize(find.byType(StateButton));
        expect(btn.height, greaterThanOrEqualTo(44));
        if (s == 1.0) {
          expect(btn.height, 44);
          // 13/500 label plus 32 padding hugs the label
          expect(btn.width, lessThan(140));
        }
        // 52 tile is gone: nothing 52 square
        expect(find.byWidgetPredicate((x) =>
            x is Container && x.constraints?.maxWidth == 52), findsNothing);
      });
    }
  }

  testWidgets('empty block 321 wide at 393 and centred', (t) async {
    await _pump(t, 393, 1, const EmptyState(icon: 'list', title: 'T', body: 'B'));
    expect(t.getSize(find.text('B')).width, 321);
    expect(t.getRect(find.text('B')).left, 36);
  });

  testWidgets('skeleton absent under 400 ms, geometry after', (t) async {
    await _pump(t, 393, 1, const ListSkeleton());
    await t.pump(const Duration(milliseconds: 399));
    expect(find.byType(Skeleton), findsNothing);
    await t.pump(const Duration(milliseconds: 2));
    final sk = find.byType(Skeleton);
    expect(sk, findsNWidgets(12));
    expect(t.getRect(sk.at(0)), const Rect.fromLTWH(24, 14, 28, 28)
        .shift(Offset(0, t.getRect(sk.at(0)).top - 14)));
    expect(t.getSize(sk.at(0)), const Size(28, 28));
    expect(t.getRect(sk.at(1)).left, 64);
    expect(t.getSize(sk.at(1)), const Size(182.7, 8));
    expect(t.getSize(sk.at(2)), const Size(117.5, 6));
    expect(t.getRect(sk.at(3)).top - t.getRect(sk.at(0)).top, 56);
  });
}
