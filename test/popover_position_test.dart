import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/app_popover.dart';

void main() {
  const screen = Size(1440, 900);
  const menu = Size(200, 150);

  test('select menu opens under its control, right edges aligned', () {
    const control = Rect.fromLTWH(955, 225, 133, 28);
    final p = popoverPosition(
        const AppPopoverAnchor(
            control: control, vertical: control, below: true, alignEnd: true),
        screen,
        menu);
    expect(p.dx, control.right - menu.width);
    expect(p.dy, control.bottom + 6);
  });

  test('flips above when there is no room below', () {
    const control = Rect.fromLTWH(955, 800, 133, 28);
    final p = popoverPosition(
        const AppPopoverAnchor(
            control: control, vertical: control, below: true, alignEnd: true),
        screen,
        menu);
    expect(p.dy, control.top - 6 - menu.height);
  });

  test('stays on screen at the right edge', () {
    const control = Rect.fromLTWH(1400, 100, 30, 28);
    final p = popoverPosition(
        const AppPopoverAnchor(
            control: control, vertical: control, below: true),
        screen,
        menu);
    expect(p.dx + menu.width, lessThanOrEqualTo(screen.width - 8));
  });
}
