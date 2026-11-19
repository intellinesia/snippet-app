import 'dart:math' as math;

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Height of the trailing spacer that lets a just-sent message sit at the top
/// of a bottom-anchored transcript: whatever the turn (the message and the
/// reply so far) leaves empty below it, gone once the turn fills the viewport.
double turnSpaceHeight({
  required double viewport,
  required double paddingVertical,
  required double tail,
}) =>
    math.max(0, viewport - paddingVertical - tail);

/// Replaces the SliverPadding of a REVERSED list. When [active] it adds a
/// spacer at the bottom (scroll offset 0) sized by [turnSpaceHeight], measured
/// from [anchorKey]'s row (the last user message) to the end of the list. It is
/// solved inside this sliver's own layout, so the spacer shrinks in the same
/// frame the reply grows and nothing flickers.
class SliverTurnSpace extends SingleChildRenderObjectWidget {
  const SliverTurnSpace({
    super.key,
    required this.padding,
    required this.anchorKey,
    required this.active,
    super.child,
  });

  final EdgeInsets padding;
  final GlobalKey anchorKey;
  final bool active;

  @override
  RenderSliverTurnSpace createRenderObject(BuildContext context) =>
      RenderSliverTurnSpace(padding, anchorKey, active);

  @override
  void updateRenderObject(
      BuildContext context, RenderSliverTurnSpace renderObject) {
    renderObject
      ..padding = padding
      ..anchorKey = anchorKey
      ..active = active;
  }
}

class RenderSliverTurnSpace extends RenderSliverEdgeInsetsPadding {
  RenderSliverTurnSpace(this._padding, this._anchorKey, this._active);

  EdgeInsets _padding;
  GlobalKey _anchorKey;
  bool _active;
  double _spacer = 0;

  set padding(EdgeInsets v) {
    if (v == _padding) return;
    _padding = v;
    markNeedsLayout();
  }

  set anchorKey(GlobalKey v) {
    if (v == _anchorKey) return;
    _anchorKey = v;
    markNeedsLayout();
  }

  set active(bool v) {
    if (v == _active) return;
    _active = v;
    markNeedsLayout();
  }

  // The list is reversed, so the bottom inset is the leading ("before") edge.
  @override
  EdgeInsets? get resolvedPadding =>
      _padding.copyWith(bottom: _padding.bottom + _spacer);

  @override
  void performLayout() {
    super.performLayout();
    if (geometry?.scrollOffsetCorrection != null) return;
    final target = _targetSpacer();
    if ((target - _spacer).abs() < 0.5) return;
    _spacer = target;
    super.performLayout();
  }

  double _targetSpacer() {
    if (!_active) return 0;
    final list = child;
    // Element.renderObject, unlike findRenderObject, tolerates an inactive row.
    final anchor = (_anchorKey.currentContext as Element?)?.renderObject;
    if (list is! RenderSliverMultiBoxAdaptor ||
        anchor == null ||
        !anchor.attached) {
      return 0;
    }
    // The sliver's direct child (the list row) holds the layout offset.
    RenderObject row = anchor;
    while (row.parent != list) {
      final p = row.parent;
      if (p is! RenderObject) return 0;
      row = p;
    }
    if (row is! RenderBox) return 0;
    // A child's size is off limits here, so the row's far edge is where the
    // next (older) row starts, or the end of the list.
    final older = list.childAfter(row);
    final tail = older == null
        ? list.geometry!.scrollExtent
        : list.childScrollOffset(older);
    if (tail == null) return 0;
    return turnSpaceHeight(
      viewport: constraints.viewportMainAxisExtent,
      paddingVertical: _padding.vertical,
      tail: tail,
    );
  }
}
