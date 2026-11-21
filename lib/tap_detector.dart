import 'package:flutter/material.dart';

/// A GestureDetector that shows the hand cursor while it has a tap handler.
class TapDetector extends GestureDetector {
  TapDetector({super.key, super.child, super.onTapDown, super.onTapUp, super.onTap, super.onTapMove, super.onTapCancel, super.onSecondaryTap, super.onSecondaryTapDown, super.onSecondaryTapUp, super.onSecondaryTapCancel, super.onTertiaryTapDown, super.onTertiaryTapUp, super.onTertiaryTapCancel, super.onDoubleTapDown, super.onDoubleTap, super.onDoubleTapCancel, super.onLongPressDown, super.onLongPressCancel, super.onLongPress, super.onLongPressStart, super.onLongPressMoveUpdate, super.onLongPressUp, super.onLongPressEnd, super.onSecondaryLongPressDown, super.onSecondaryLongPressCancel, super.onSecondaryLongPress, super.onSecondaryLongPressStart, super.onSecondaryLongPressMoveUpdate, super.onSecondaryLongPressUp, super.onSecondaryLongPressEnd, super.onTertiaryLongPressDown, super.onTertiaryLongPressCancel, super.onTertiaryLongPress, super.onTertiaryLongPressStart, super.onTertiaryLongPressMoveUpdate, super.onTertiaryLongPressUp, super.onTertiaryLongPressEnd, super.onVerticalDragDown, super.onVerticalDragStart, super.onVerticalDragUpdate, super.onVerticalDragEnd, super.onVerticalDragCancel, super.onHorizontalDragDown, super.onHorizontalDragStart, super.onHorizontalDragUpdate, super.onHorizontalDragEnd, super.onHorizontalDragCancel, super.onForcePressStart, super.onForcePressPeak, super.onForcePressUpdate, super.onForcePressEnd, super.onPanDown, super.onPanStart, super.onPanUpdate, super.onPanEnd, super.onPanCancel, super.onScaleStart, super.onScaleUpdate, super.onScaleEnd, super.behavior, super.excludeFromSemantics, super.dragStartBehavior, super.trackpadScrollCausesScale, super.trackpadScrollToScaleFactor, super.supportedDevices});

  @override
  Widget build(BuildContext context) {
    final inner = super.build(context);
    if (onTap == null && onTapUp == null && onDoubleTap == null) return inner;
    return MouseRegion(cursor: SystemMouseCursors.click, child: inner);
  }
}
