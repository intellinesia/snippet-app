import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'chat_scene.dart' show ScenePageFill;
import 'gesture_physics.dart';
import 'glass.dart' show GlassTopFrame;
import 'mobile_kit/tokens.dart' show kAndroidLook;
import 'motion_routes.dart';
import 'platform.dart';
import 'theme.dart';

/// Material 3 fade-forward for in-place pages on Android, matching what
/// [AppPageRoute] gets from the platform builder: the new page slides in a
/// quarter width and fades in, the old one slides a quarter back and fades.
class PlatformPageMotion {
  static bool get android => kMobile && kAndroidLook;
  static const Duration duration = Duration(milliseconds: 450);
  static const Curve _curve = Curves.easeInOutCubicEmphasized;
  static const Interval _fadeIn = Interval(0.0, 0.75);
  static const Interval _fadeOut = Interval(0.0, 0.25);

  /// [p] is 0 with the page gone, 1 with it fully shown; [opening] says
  /// which way it is heading.
  static Widget page(double p, bool opening, double width, Widget child) {
    final q = opening ? p : 1 - p;
    final shift = opening ? 1 - _curve.transform(q) : _curve.transform(q);
    final fade = opening ? _fadeIn.transform(q) : 1 - _fadeOut.transform(q);
    return Transform.translate(
      offset: Offset(0.25 * width * shift, 0),
      child: Opacity(opacity: fade.clamp(0.0, 1.0), child: child),
    );
  }

  /// The page underneath, at the same progress.
  static Widget base(double p, bool opening, double width, Widget child) {
    final q = opening ? p : 1 - p;
    final shift = opening ? _curve.transform(q) : 1 - _curve.transform(q);
    final fade = opening ? 1 - _fadeOut.transform(q) : _fadeIn.transform(q);
    return Transform.translate(
      offset: Offset(-0.25 * width * shift, 0),
      child: Opacity(opacity: fade.clamp(0.0, 1.0), child: child),
    );
  }
}

/// A phone page over a base, moved exactly like [AppPageRoute] moves pages:
/// page spring in and out, the base parallaxes and dims, and a back swipe
/// from anywhere on the page tracks the finger and carries its speed.
///
/// For in-place navigation that is state, not a route (session over the
/// list, Settings over home, a settings section, an agent's detail).
class PhonePageStack extends StatefulWidget {
  const PhonePageStack({
    super.key,
    required this.base,
    this.page,
    this.onBack,
    this.pageColor,
  });

  final Widget base;

  /// The page on top, or null for none. Key it when one page can replace
  /// another so state is not carried across.
  final Widget? page;

  /// Called when a back swipe commits; the owner should clear [page].
  final VoidCallback? onBack;

  final Color? pageColor;

  /// Outgoing base offset and dim at full cover, as in the motion spec.
  static const double parallax = 0.25;
  static const double dim = 0.10;

  @override
  State<PhonePageStack> createState() => _PhonePageStackState();
}

class _PhonePageStackState extends State<PhonePageStack>
    with SingleTickerProviderStateMixin {
  late final AnimationController _v = AnimationController.unbounded(
      vsync: this, value: widget.page == null ? 0.0 : 1.0);
  late Widget? _shown = widget.page;
  double? _commitVelocity;
  bool _opening = true;

  @override
  void didUpdateWidget(PhonePageStack old) {
    super.didUpdateWidget(old);
    final page = widget.page;
    if (page != null) {
      _shown = page;
      if (old.page == null) _go(1, 0);
    } else if (old.page != null) {
      final v = _commitVelocity ?? 0;
      _commitVelocity = null;
      _go(0, v);
    }
  }

  void _go(double to, double velocity) {
    final TickerFuture f;
    _opening = to > _v.value;
    if (PlatformPageMotion.android && !reduceMotion(context)) {
      f = _v.animateTo(to,
          duration: PlatformPageMotion.duration, curve: Curves.linear);
    } else if (reduceMotion(context)) {
      f = _v.animateTo(to,
          duration: const Duration(milliseconds: 150), curve: Curves.linear);
    } else {
      f = springTo(_v, to, velocity,
          spring: AppPageRoute.pageSpring, epsilon: 0.001);
    }
    f.whenCompleteOrCancel(GlassTopFrame.reflow);
    if (to == 0) {
      f.whenCompleteOrCancel(() {
        if (mounted && widget.page == null && _v.value <= 0.001) {
          setState(() => _shown = null);
        }
      });
    }
  }

  void _dragStart() => _v.stop();

  void _dragUpdate(double fraction) =>
      _v.value = (_v.value - fraction).clamp(0.0, 1.0);

  /// [velocity] in widths per second toward dismissal.
  void _dragEnd(double velocity, double width) {
    if (backSwipeStays(_v.value, velocity, width) || widget.onBack == null) {
      _go(1, -velocity);
      return;
    }
    HapticFeedback.selectionClick();
    _commitVelocity = -velocity;
    widget.onBack!();
    // The owner kept the page: settle back rather than hang mid-swipe.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _commitVelocity == null) return;
      _commitVelocity = null;
      if (widget.page != null) _go(1, 0);
    });
  }

  @override
  void dispose() {
    _v.dispose();
    super.dispose();
  }

  // System back is the gesture on Android; no in-app swipe.
  Widget _android(double p, double w, Widget? shown, bool open) =>
      Stack(clipBehavior: Clip.none, fit: StackFit.expand, children: [
        if (p > 0 && p < 1) ColoredBox(color: AppColors.bg),
        Offstage(
          offstage: shown != null && p >= 1.0,
          child: TickerMode(
            enabled: p < 1.0,
            child: IgnorePointer(
              ignoring: open,
              child: PlatformPageMotion.base(p, _opening, w, widget.base),
            ),
          ),
        ),
        if (shown != null)
          IgnorePointer(
            ignoring: !open,
            child: PlatformPageMotion.page(
                p,
                _opening,
                w,
                RepaintBoundary(
                  child: ScenePageFill(color: widget.pageColor, child: shown),
                )),
          ),
      ]);

  @override
  Widget build(BuildContext context) {
    final reduced = reduceMotion(context);
    final shown = _shown;
    final open = widget.page != null;
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      return AnimatedBuilder(
        animation: _v,
        builder: (context, _) {
          final p = _v.value.clamp(0.0, 1.0);
          if (PlatformPageMotion.android && !reduced) {
            return _android(p, w, shown, open);
          }
          return Stack(clipBehavior: Clip.none, fit: StackFit.expand, children: [
            Offstage(
              offstage: shown != null && p >= 1.0,
              child: TickerMode(
                enabled: p < 1.0,
                child: IgnorePointer(
                  ignoring: open,
                  child: Transform.translate(
                    offset: Offset(
                        reduced ? 0 : -PhonePageStack.parallax * w * p, 0),
                    child: Stack(fit: StackFit.expand, children: [
                      widget.base,
                      if (p > 0 && !reduced)
                        IgnorePointer(
                          child: ColoredBox(
                              color: Colors.black
                                  .withValues(alpha: PhonePageStack.dim * p)),
                        ),
                    ]),
                  ),
                ),
              ),
            ),
            if (shown != null)
              IgnorePointer(
                ignoring: !open,
                child: Transform.translate(
                  offset: Offset(reduced ? 0 : (1 - p) * w, 0),
                  child: Opacity(
                    opacity: reduced ? p : 1.0,
                    child: PageBackSwipe(
                      enabled: open && widget.onBack != null,
                      onStart: _dragStart,
                      onUpdate: _dragUpdate,
                      onEnd: _dragEnd,
                      child: RepaintBoundary(
                        child: ScenePageFill(
                          color: widget.pageColor,
                          child: shown,
                        ),
                      ),
                    ),
                  ),
                ),
              ),
          ]);
        },
      );
    });
  }
}

/// The page back swipe on its own: claims a clearly horizontal drag toward
/// dismissal anywhere on [child], unless what is under the finger owns
/// horizontal drags or edits text (the leading edge always wins).
class PageBackSwipe extends StatefulWidget {
  const PageBackSwipe({
    super.key,
    required this.onStart,
    required this.onUpdate,
    required this.onEnd,
    required this.child,
    this.enabled = true,
  });

  final bool enabled;
  final VoidCallback onStart;

  /// Fraction of the width moved toward dismissal since the last update.
  final ValueChanged<double> onUpdate;

  /// Velocity in widths per second toward dismissal, and the width.
  final void Function(double velocity, double width) onEnd;
  final Widget child;

  @override
  State<PageBackSwipe> createState() => _PageBackSwipeState();
}

class _PageBackSwipeState extends State<PageBackSwipe> {
  late final BackSwipeRecognizer _r = BackSwipeRecognizer(debugOwner: this)
    ..onStart = ((_) => widget.onStart())
    ..onUpdate = _update
    ..onEnd = _end
    ..onCancel = (() => widget.onEnd(0, _width));

  double get _width => context.size?.width ?? 0;

  double _logical(double v) =>
      Directionality.of(context) == TextDirection.rtl ? -v : v;

  void _update(DragUpdateDetails d) {
    final w = _width;
    if (w > 0) widget.onUpdate(_logical((d.primaryDelta ?? 0) / w));
  }

  void _end(DragEndDetails d) {
    final w = _width;
    widget.onEnd(w > 0 ? _logical(d.velocity.pixelsPerSecond.dx / w) : 0.0, w);
  }

  void _down(PointerDownEvent e) {
    if (!widget.enabled) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final local = box.globalToLocal(e.position);
    if (!backSwipeInEdge(context, box, local) && backSwipeYields(box, local)) {
      return;
    }
    _r.direction = Directionality.of(context);
    _r.addPointer(e);
  }

  @override
  void dispose() {
    _r.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: _down,
        behavior: HitTestBehavior.translucent,
        child: widget.child,
      );
}
