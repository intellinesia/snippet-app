import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'platform.dart';
import 'theme.dart';

/// A GestureDetector that shows the hand cursor while it has a tap handler.
class TapDetector extends GestureDetector {
  TapDetector(
      {super.key,
      super.child,
      super.onTapDown,
      super.onTapUp,
      super.onTap,
      super.onTapMove,
      super.onTapCancel,
      super.onSecondaryTap,
      super.onSecondaryTapDown,
      super.onSecondaryTapUp,
      super.onSecondaryTapCancel,
      super.onTertiaryTapDown,
      super.onTertiaryTapUp,
      super.onTertiaryTapCancel,
      super.onDoubleTapDown,
      super.onDoubleTap,
      super.onDoubleTapCancel,
      super.onLongPressDown,
      super.onLongPressCancel,
      super.onLongPress,
      super.onLongPressStart,
      super.onLongPressMoveUpdate,
      super.onLongPressUp,
      super.onLongPressEnd,
      super.onSecondaryLongPressDown,
      super.onSecondaryLongPressCancel,
      super.onSecondaryLongPress,
      super.onSecondaryLongPressStart,
      super.onSecondaryLongPressMoveUpdate,
      super.onSecondaryLongPressUp,
      super.onSecondaryLongPressEnd,
      super.onTertiaryLongPressDown,
      super.onTertiaryLongPressCancel,
      super.onTertiaryLongPress,
      super.onTertiaryLongPressStart,
      super.onTertiaryLongPressMoveUpdate,
      super.onTertiaryLongPressUp,
      super.onTertiaryLongPressEnd,
      super.onVerticalDragDown,
      super.onVerticalDragStart,
      super.onVerticalDragUpdate,
      super.onVerticalDragEnd,
      super.onVerticalDragCancel,
      super.onHorizontalDragDown,
      super.onHorizontalDragStart,
      super.onHorizontalDragUpdate,
      super.onHorizontalDragEnd,
      super.onHorizontalDragCancel,
      super.onForcePressStart,
      super.onForcePressPeak,
      super.onForcePressUpdate,
      super.onForcePressEnd,
      super.onPanDown,
      super.onPanStart,
      super.onPanUpdate,
      super.onPanEnd,
      super.onPanCancel,
      super.onScaleStart,
      super.onScaleUpdate,
      super.onScaleEnd,
      super.behavior,
      super.excludeFromSemantics,
      super.dragStartBehavior,
      super.trackpadScrollCausesScale,
      super.trackpadScrollToScaleFactor,
      super.supportedDevices});

  @override
  Widget build(BuildContext context) {
    final inner = super.build(context);
    if (onTap == null && onTapUp == null && onDoubleTap == null) return inner;
    final tap = MouseRegion(cursor: SystemMouseCursors.click, child: inner);
    if (kMobile || onTap == null) return tap;
    return _KeyFocus(onActivate: onTap!, child: tap);
  }
}

/// Desktop keyboard focus: Tab reaches the target, Enter or Space taps it, and
/// a 2 pt ring sits 2 pt outside it, only while navigating by keyboard.
class _KeyFocus extends StatefulWidget {
  const _KeyFocus({required this.onActivate, required this.child});
  final VoidCallback onActivate;
  final Widget child;

  @override
  State<_KeyFocus> createState() => _KeyFocusState();
}

class _KeyFocusState extends State<_KeyFocus> {
  bool _focused = false;

  @override
  Widget build(BuildContext context) {
    final ring = _focused &&
        FocusManager.instance.highlightMode == FocusHighlightMode.traditional;
    return Focus(
      onFocusChange: (f) => setState(() => _focused = f),
      onKeyEvent: (_, e) {
        if (e is KeyDownEvent &&
            (e.logicalKey == LogicalKeyboardKey.enter ||
                e.logicalKey == LogicalKeyboardKey.space)) {
          widget.onActivate();
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child:
          Stack(fit: StackFit.passthrough, clipBehavior: Clip.none, children: [
        widget.child,
        if (ring)
          Positioned(
            left: -4,
            top: -4,
            right: -4,
            bottom: -4,
            child: IgnorePointer(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: AppColors.fg1, width: 2),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}
