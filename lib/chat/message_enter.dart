import 'package:flutter/material.dart';

import '../theme.dart';
import 'anchored_scroll.dart';

/// Animates a newly added chat message into place: smoothly expands its layout
/// height (so older messages glide upward instead of jumping in a reversed
/// list) while fading and sliding up over 180 ms.
///
/// Plays once on mount when [animate] is true, and renders immediately at rest
/// under reduced motion.
class MessageEnter extends StatefulWidget {
  const MessageEnter({
    super.key,
    required this.child,
    this.animate = true,
    this.duration = const Duration(milliseconds: 180),
    this.offset = 10,
  });

  final Widget child;
  final bool animate;
  final Duration duration;
  final double offset;

  @override
  State<MessageEnter> createState() => _MessageEnterState();
}

class _MessageEnterState extends State<MessageEnter>
    with SingleTickerProviderStateMixin {
  AnimationController? _c;
  Animation<double>? _curve;
  Animation<double>? _size;
  Animation<double>? _fade;
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (!widget.animate ||
        reduceMotion(context) ||
        MediaQuery.disableAnimationsOf(context)) {
      return;
    }
    final c = AnimationController(vsync: this, duration: widget.duration);
    _c = c;
    final curve = CurvedAnimation(parent: c, curve: Curves.easeOutCubic);
    _curve = curve;
    // Start at a tiny non-zero factor so the child stays laid out on frame 0.
    _size = Tween<double>(begin: 0.01, end: 1).animate(curve);
    _fade = CurvedAnimation(
        parent: c, curve: const Interval(0, 0.85, curve: Curves.easeOut));
    c.forward();
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final curve = _curve;
    final size = _size;
    final fade = _fade;
    // Keep the tree shape constant for the widget's lifetime so stateful
    // children (popovers, expanded cards, images) never remount on completion.
    if (curve == null || size == null || fade == null) return widget.child;
    return SizeTransition(
      sizeFactor: size,
      alignment: Alignment.topCenter,
      child: FadeTransition(
        opacity: fade,
        child: AnimatedBuilder(
          animation: curve,
          child: widget.child,
          builder: (_, child) => Transform.translate(
            offset: Offset(0, widget.offset * (1 - curve.value)),
            child: child,
          ),
        ),
      ),
    );
  }
}

/// Tracks whether a reversed chat transcript is pinned to the bottom (offset 0)
/// across both touch drags and desktop wheel/trackpad scrolling, and drives
/// smooth bottom-follow scrolling without yanking scrolled-up readers.
class ChatBottomTracker {
  bool stickToBottom = true;
  bool userScrolling = false;
  bool _programmatic = false;

  static const double _bottomThreshold = 80;

  bool atBottom(ScrollController scroll) {
    if (scroll.positions.length != 1) return true;
    return scroll.position.pixels <= _bottomThreshold;
  }

  /// Updates [stickToBottom] from scroll notifications. Returns true only when
  /// [stickToBottom] flips, so callers avoid per-frame rebuilds.
  bool handleScroll(ScrollNotification n, ScrollController scroll) {
    if (n.depth != 0) return false;
    final was = stickToBottom;
    if (n is ScrollStartNotification && n.dragDetails != null) {
      userScrolling = true;
    } else if (n is ScrollUpdateNotification) {
      final delta = n.scrollDelta ?? 0;
      if (n.dragDetails != null) {
        userScrolling = true;
        stickToBottom = delta > 0 ? false : atBottom(scroll);
      } else if (!_programmatic && delta != 0) {
        // Desktop mouse wheel / trackpad updates carry no dragDetails.
        if (delta > 0) {
          stickToBottom = false;
        } else if (atBottom(scroll)) {
          stickToBottom = true;
        }
      }
    } else if (n is ScrollEndNotification) {
      userScrolling = false;
      if (!_programmatic) stickToBottom = atBottom(scroll);
    }
    return was != stickToBottom;
  }

  /// Smoothly scrolls to offset 0 (instant under reduced motion or when
  /// [animated] is false). No-op when already at 0 or while the user drags.
  void scrollToBottom(
    ScrollController scroll,
    BuildContext context, {
    bool animated = true,
  }) {
    if (scroll.positions.length != 1 || userScrolling) return;
    if (scroll.offset <= 0.5) return;
    final noAnim = !animated ||
        reduceMotion(context) ||
        MediaQuery.disableAnimationsOf(context);
    if (noAnim) {
      scroll.jumpTo(0);
      return;
    }
    _programmatic = true;
    scroll
        .animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOutCubic,
        )
        .whenComplete(() => _programmatic = false);
  }

  /// Compensates a row height delta while scrolled up so the viewport stays
  /// anchored in the same layout pass.
  void rowResized(
    AnchoredScrollController scroll,
    double delta,
    double? bottomInViewport,
  ) {
    if (stickToBottom || userScrolling || delta == 0 || !scroll.hasClients) {
      return;
    }
    if (bottomInViewport != null && bottomInViewport <= 0) return;
    scroll.correctBy(delta);
  }
}
