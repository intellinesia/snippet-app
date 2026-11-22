import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// A scroll controller whose position can absorb a pending offset correction
/// inside the same layout pass, so a row that grows (an expanded card or tool
/// call) keeps its place without a one-frame jump of the whole list.
class AnchoredScrollController extends ScrollController {
  @override
  ScrollPosition createScrollPosition(ScrollPhysics physics,
          ScrollContext context, ScrollPosition? oldPosition) =>
      AnchoredScrollPosition(
        physics: physics,
        context: context,
        initialPixels: initialScrollOffset,
        keepScrollOffset: keepScrollOffset,
        oldPosition: oldPosition,
        debugLabel: debugLabel,
      );

  /// Queue a correction; the viewport applies it before this frame paints.
  void correctBy(double delta) {
    if (positions.length != 1) return;
    final p = position;
    if (p is AnchoredScrollPosition) p.pending += delta;
  }
}

class AnchoredScrollPosition extends ScrollPositionWithSingleContext {
  AnchoredScrollPosition({
    required super.physics,
    required super.context,
    super.initialPixels,
    super.keepScrollOffset,
    super.oldPosition,
    super.debugLabel,
  });

  double pending = 0;

  @override
  bool applyContentDimensions(double minScrollExtent, double maxScrollExtent) {
    if (pending != 0) {
      final next =
          (pixels + pending).clamp(minScrollExtent, maxScrollExtent).toDouble();
      pending = 0;
      if (next != pixels) {
        correctPixels(next);
        // Returning false makes the viewport lay out again at the new offset
        // in this same frame.
        super.applyContentDimensions(minScrollExtent, maxScrollExtent);
        return false;
      }
    }
    return super.applyContentDimensions(minScrollExtent, maxScrollExtent);
  }
}

/// Reports a row's height change during layout, with the row's bottom edge as
/// last painted relative to its viewport's top (null before the first paint).
class RowSizeWatch extends SingleChildRenderObjectWidget {
  const RowSizeWatch({super.key, required this.onResize, super.child});

  final void Function(double delta, double? bottomInViewport) onResize;

  @override
  RenderRowSizeWatch createRenderObject(BuildContext context) =>
      RenderRowSizeWatch(onResize);

  @override
  void updateRenderObject(
          BuildContext context, RenderRowSizeWatch renderObject) =>
      renderObject.onResize = onResize;
}

class RenderRowSizeWatch extends RenderProxyBox {
  RenderRowSizeWatch(this.onResize);

  void Function(double delta, double? bottomInViewport) onResize;
  double? _height;
  double? _bottomInViewport;

  @override
  void performLayout() {
    super.performLayout();
    final height = size.height;
    final previous = _height;
    _height = height;
    if (previous != null && previous != height) {
      onResize(height - previous, _bottomInViewport);
    }
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    super.paint(context, offset);
    final viewport = RenderAbstractViewport.maybeOf(this);
    if (viewport is RenderBox) {
      _bottomInViewport = MatrixUtils.transformPoint(
              getTransformTo(viewport as RenderBox), Offset(0, size.height))
          .dy;
    }
  }
}
