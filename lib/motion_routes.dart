import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/rendering.dart';

import 'chat_scene.dart';
import 'gesture_physics.dart';
import 'morph_sheet.dart' show AppSheetRoute;
import 'platform.dart';
import 'theme.dart';

Future<T?> pushApp<T>(
  BuildContext context,
  WidgetBuilder builder, {
  bool rootNavigator = false,
  RouteSettings? settings,
  bool fullscreenDialog = false,
  bool maintainState = true,
}) =>
    Navigator.of(context, rootNavigator: rootNavigator).push<T>(
      AppPageRoute<T>(
        builder: builder,
        settings: settings,
        fullscreenDialog: fullscreenDialog,
        maintainState: maintainState,
      ),
    );

class AppPageRoute<T> extends PageRoute<T> {
  AppPageRoute({
    required this.builder,
    super.settings,
    super.requestFocus,
    this.maintainState = true,
    super.fullscreenDialog,
    super.allowSnapshotting = true,
    super.barrierDismissible = false,
    this.backSwipe = true,
  }) {
    assert(opaque);
  }

  final WidgetBuilder builder;

  /// Off for screens that must not be dismissed by a drag.
  final bool backSwipe;

  @override
  final bool maintainState;

  static const Duration _phoneForward = Duration(milliseconds: 340);
  static const Duration _phoneReverse = Duration(milliseconds: 260);
  static const Duration _reducedDuration = Duration(milliseconds: 150);

  /// Push, pop and back-swipe settle on phones (zeta 0.95, about 380ms).
  static const SpringDescription pageSpring =
      SpringDescription(mass: 1, stiffness: 380, damping: 37);

  static Simulation _pageSim(double from, double to, double velocity) =>
      SpringSimulation(pageSpring, from, to, velocity,
          snapToEnd: true,
          tolerance: const Tolerance(distance: 0.001, velocity: 0.01));

  bool get _springs => kMobile && !_reducedMotion;

  // Finger velocity handed from a committed back swipe to the pop spring.
  double _popVelocity = 0;

  @override
  TickerFuture didPush() {
    final linear = super.didPush();
    final c = controller;
    if (!_springs || c == null) return linear;
    return c.animateWith(_pageSim(c.value, 1, 0));
  }

  bool get _reducedMotion {
    final ctx = navigator?.context;
    if (ctx != null && (MediaQuery.maybeDisableAnimationsOf(ctx) ?? false)) {
      return true;
    }
    return WidgetsBinding
        .instance.platformDispatcher.accessibilityFeatures.disableAnimations;
  }

  @override
  Duration get transitionDuration {
    if (!kMobile) return Motion.page;
    return _reducedMotion ? _reducedDuration : _phoneForward;
  }

  @override
  Duration get reverseTransitionDuration {
    if (!kMobile) return Motion.close;
    return _reducedMotion ? _reducedDuration : _phoneReverse;
  }

  @override
  bool didPop(T? result) {
    controller?.reverseDuration = reverseTransitionDuration;
    final popped = super.didPop(result);
    final c = controller;
    final v = _popVelocity;
    _popVelocity = 0;
    if (_springs && c != null && !c.isDismissed) {
      c.animateBackWith(_pageSim(c.value, 0, v));
    }
    return popped;
  }

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  String get debugLabel => '${super.debugLabel}(${settings.name})';

  @override
  DelegatedTransitionBuilder? get delegatedTransition =>
      kMobile ? _delegatedTransition : null;

  static Widget? _delegatedTransition(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    bool allowSnapshotting,
    Widget? child,
  ) {
    if (child == null) return null;
    if (reduceMotion(context)) return child;
    return _AppOutgoingTransition(
      secondaryAnimation: secondaryAnimation,
      linear: true,
      child: child,
    );
  }

  @override
  bool canTransitionTo(TransitionRoute<dynamic> nextRoute) {
    if (nextRoute is PageRoute && nextRoute.fullscreenDialog) return false;
    // The sheet scales this page back through its delegated transition.
    if (nextRoute is AppSheetRoute) return kMobile;
    if (!nextRoute.opaque) return false;
    if (!kMobile) {
      return nextRoute is AppPageRoute ||
          nextRoute is MaterialRouteTransitionMixin ||
          (nextRoute is ModalRoute && nextRoute.delegatedTransition != null);
    }
    return nextRoute is AppPageRoute ||
        (nextRoute is ModalRoute && nextRoute.delegatedTransition != null);
  }

  @override
  bool canTransitionFrom(TransitionRoute<dynamic> previousRoute) =>
      previousRoute is PageRoute && !fullscreenDialog;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) =>
      Semantics(
        scopesRoute: true,
        explicitChildNodes: true,
        child: ListenableBuilder(
          listenable: ChatScene.instance,
          builder: (context, _) {
            final base = Theme.of(context);
            return Theme(
              data: ChatScene.instance.ready
                  ? base.copyWith(scaffoldBackgroundColor: Colors.transparent)
                  : base,
              child: SceneBackdrop(child: builder(context)),
            );
          },
        ),
      );

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    if (!kMobile) {
      return Theme.of(context).pageTransitionsTheme.buildTransitions<T>(
            this,
            context,
            animation,
            secondaryAnimation,
            child,
          );
    }
    final gesturedChild = _BackSwipeDetector<T>(
      enabledCallback: () => popGestureEnabled && backSwipe,
      onStartPopGesture: () => _BackGestureController<T>(
        navigator: navigator!,
        controller: controller!,
        getIsActive: () => isActive,
        getIsCurrent: () => isCurrent,
        springs: () => _springs,
        setPopVelocity: (v) => _popVelocity = v,
      ),
      child: child,
    );
    if (reduceMotion(context)) {
      return FadeTransition(opacity: animation, child: gesturedChild);
    }
    // The spring is the curve; easing on top would distort it.
    return _AppOutgoingTransition(
      secondaryAnimation: secondaryAnimation,
      linear: true,
      child: _AppIncomingTransition(
        primaryAnimation: animation,
        linear: true,
        child: gesturedChild,
      ),
    );
  }
}

class _AppIncomingTransition extends StatefulWidget {
  const _AppIncomingTransition({
    required this.primaryAnimation,
    required this.linear,
    required this.child,
  });

  final Animation<double> primaryAnimation;
  final bool linear;
  final Widget child;

  @override
  State<_AppIncomingTransition> createState() => _AppIncomingTransitionState();
}

class _AppIncomingTransitionState extends State<_AppIncomingTransition> {
  static final Animatable<Offset> _slideTween = Tween<Offset>(
    begin: const Offset(1.0, 0.0),
    end: Offset.zero,
  );

  CurvedAnimation? _curve;
  late Animation<Offset> _position;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  @override
  void didUpdateWidget(covariant _AppIncomingTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.primaryAnimation != widget.primaryAnimation ||
        oldWidget.linear != widget.linear) {
      _curve?.dispose();
      _curve = null;
      _setup();
    }
  }

  void _setup() {
    if (!widget.linear) {
      _curve = CurvedAnimation(
        parent: widget.primaryAnimation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeOutCubic.flipped,
      );
    }
    _position = (_curve ?? widget.primaryAnimation).drive(_slideTween);
  }

  @override
  void dispose() {
    _curve?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SlideTransition(
        position: _position,
        textDirection: Directionality.of(context),
        child: widget.child,
      );
}

class _AppOutgoingTransition extends StatefulWidget {
  const _AppOutgoingTransition({
    required this.secondaryAnimation,
    required this.linear,
    required this.child,
  });

  final Animation<double> secondaryAnimation;
  final bool linear;
  final Widget child;

  @override
  State<_AppOutgoingTransition> createState() => _AppOutgoingTransitionState();
}

class _AppOutgoingTransitionState extends State<_AppOutgoingTransition> {
  static final Animatable<Offset> _parallaxTween = Tween<Offset>(
    begin: Offset.zero,
    end: const Offset(-0.25, 0.0),
  );
  static final Animatable<double> _scrimTween =
      Tween<double>(begin: 0.0, end: 0.24);

  CurvedAnimation? _curve;
  late Animation<Offset> _position;
  late Animation<double> _scrim;

  @override
  void initState() {
    super.initState();
    _setup();
  }

  @override
  void didUpdateWidget(covariant _AppOutgoingTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.secondaryAnimation != widget.secondaryAnimation ||
        oldWidget.linear != widget.linear) {
      _curve?.dispose();
      _curve = null;
      _setup();
    }
  }

  void _setup() {
    if (!widget.linear) {
      _curve = CurvedAnimation(
        parent: widget.secondaryAnimation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeOutCubic.flipped,
      );
    }
    final anim = _curve ?? widget.secondaryAnimation;
    _position = anim.drive(_parallaxTween);
    _scrim = anim.drive(_scrimTween);
  }

  @override
  void dispose() {
    _curve?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SlideTransition(
        position: _position,
        textDirection: Directionality.of(context),
        transformHitTests: false,
        child: Stack(
          fit: StackFit.passthrough,
          children: [
            widget.child,
            Positioned.fill(
              child: IgnorePointer(
                child: FadeTransition(
                  opacity: _scrim,
                  child: const ColoredBox(color: Colors.black),
                ),
              ),
            ),
          ],
        ),
      );
}

const double _kBackEdgeWidth = 20.0;
const double _kBackSlop = 8.0;
const double _kBackAxisRatio = 1.2;
const double _kProjectSeconds = 0.2;
const double _kFlickBack = 200.0;

/// Whether [local] sits in the leading-edge strip where a back swipe always wins.
bool backSwipeInEdge(BuildContext context, RenderBox box, Offset local) {
  final rtl = Directionality.of(context) == TextDirection.rtl;
  final media = MediaQuery.paddingOf(context);
  final strip = math.max(rtl ? media.right : media.left, _kBackEdgeWidth);
  return rtl ? local.dx >= box.size.width - strip : local.dx <= strip;
}

/// Anything under the finger that owns horizontal drags, or edits text, wins
/// over a back swipe that starts mid-page.
bool backSwipeYields(RenderBox box, Offset local) {
  final result = BoxHitTestResult();
  box.hitTest(result, position: local);
  for (final entry in result.path) {
    final t = entry.target;
    if (t == box) break;
    if (t is RenderEditable) return true;
    if (t is RenderBackSwipeYield && t.enabled) return true;
    if (t is RenderSemanticsGestureHandler &&
        t.onHorizontalDragUpdate != null) {
      return true;
    }
  }
  return false;
}

/// Release rule shared by every page back swipe: [position] is 1 when the
/// page is fully shown, [velocity] in widths per second toward dismissal.
bool backSwipeStays(double position, double velocity, double width) =>
    velocity * width <= -_kFlickBack ||
    position - velocity * _kProjectSeconds >= 0.5;

/// Wrap a horizontal gesture surface (swipe actions, sliders) so a page back
/// swipe that starts on it leaves it alone. Scrollables and horizontal
/// GestureDetectors already yield without this.
class BackSwipeYield extends SingleChildRenderObjectWidget {
  const BackSwipeYield({super.key, this.enabled = true, super.child});

  final bool enabled;

  @override
  RenderBackSwipeYield createRenderObject(BuildContext context) =>
      RenderBackSwipeYield(enabled);

  @override
  void updateRenderObject(
          BuildContext context, RenderBackSwipeYield renderObject) =>
      renderObject.enabled = enabled;
}

class RenderBackSwipeYield extends RenderProxyBox {
  RenderBackSwipeYield(this.enabled);
  bool enabled;

  // Listed in the hit path even over empty space, without absorbing the hit.
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final hit = super.hitTest(result, position: position);
    if (!hit && enabled && size.contains(position)) {
      result.add(BoxHitTestEntry(this, position));
    }
    return hit;
  }
}

/// Claims a rightward drag (leftward in RTL) once it travels 8px and is
/// clearly horizontal, so vertical scrolling keeps every diagonal-ish drag.
class BackSwipeRecognizer extends HorizontalDragGestureRecognizer {
  BackSwipeRecognizer({super.debugOwner});

  TextDirection direction = TextDirection.ltr;
  Offset _travel = Offset.zero;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _travel = Offset.zero;
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) _travel += event.delta;
    super.handleEvent(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
      PointerDeviceKind pointerDeviceKind, double? deviceTouchSlop) {
    final dx = direction == TextDirection.rtl ? -_travel.dx : _travel.dx;
    return dx > _kBackSlop && dx > _kBackAxisRatio * _travel.dy.abs();
  }
}

class _BackSwipeDetector<T> extends StatefulWidget {
  const _BackSwipeDetector({
    required this.enabledCallback,
    required this.onStartPopGesture,
    required this.child,
  });

  final ValueGetter<bool> enabledCallback;
  final ValueGetter<_BackGestureController<T>> onStartPopGesture;
  final Widget child;

  @override
  State<_BackSwipeDetector<T>> createState() => _BackSwipeDetectorState<T>();
}

class _BackSwipeDetectorState<T> extends State<_BackSwipeDetector<T>> {
  _BackGestureController<T>? _controller;
  late final BackSwipeRecognizer _recognizer;

  @override
  void initState() {
    super.initState();
    _recognizer = BackSwipeRecognizer(debugOwner: this)
      ..onStart = _handleDragStart
      ..onUpdate = _handleDragUpdate
      ..onEnd = _handleDragEnd
      ..onCancel = _handleDragCancel;
  }

  @override
  void dispose() {
    _recognizer.dispose();
    final active = _controller;
    if (active != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (active.navigator.mounted) active.navigator.didStopUserGesture();
      });
      _controller = null;
    }
    super.dispose();
  }

  double _toLogical(double value) => switch (Directionality.of(context)) {
        TextDirection.rtl => -value,
        TextDirection.ltr => value,
      };

  void _handlePointerDown(PointerDownEvent event) {
    if (!widget.enabledCallback()) return;
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return;
    final local = box.globalToLocal(event.position);
    if (!backSwipeInEdge(context, box, local) && backSwipeYields(box, local)) {
      return;
    }
    _recognizer.direction = Directionality.of(context);
    _recognizer.addPointer(event);
  }

  void _handleDragStart(DragStartDetails details) {
    assert(_controller == null);
    _controller = widget.onStartPopGesture();
  }

  void _handleDragUpdate(DragUpdateDetails details) {
    final c = _controller;
    final w = context.size?.width ?? 0;
    if (c == null || w <= 0) return;
    c.dragUpdate(_toLogical((details.primaryDelta ?? 0) / w));
  }

  void _handleDragEnd(DragEndDetails details) {
    final c = _controller;
    _controller = null;
    final w = context.size?.width ?? 0;
    if (c == null) return;
    c.dragEnd(
      w > 0 ? _toLogical(details.velocity.pixelsPerSecond.dx / w) : 0.0,
      w,
    );
  }

  void _handleDragCancel() {
    _controller?.dragEnd(0.0, context.size?.width ?? 0);
    _controller = null;
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: _handlePointerDown,
        behavior: HitTestBehavior.translucent,
        child: widget.child,
      );
}

class _BackGestureController<T> {
  _BackGestureController({
    required this.navigator,
    required this.controller,
    required this.getIsActive,
    required this.getIsCurrent,
    required this.springs,
    required this.setPopVelocity,
  }) {
    navigator.didStartUserGesture();
  }

  final AnimationController controller;
  final NavigatorState navigator;
  final ValueGetter<bool> getIsActive;
  final ValueGetter<bool> getIsCurrent;
  final ValueGetter<bool> springs;
  final ValueSetter<double> setPopVelocity;

  void dragUpdate(double delta) {
    controller.value -= delta;
  }

  /// [velocity] is in page widths per second, positive toward dismissal.
  void dragEnd(double velocity, double width) {
    final isCurrent = getIsCurrent();
    final bool stay;
    if (!isCurrent) {
      stay = getIsActive();
    } else {
      stay = backSwipeStays(controller.value, velocity, width);
    }

    if (stay) {
      if (springs()) {
        springTo(controller, 1, -velocity,
            spring: AppPageRoute.pageSpring, epsilon: 0.001);
      } else {
        controller.animateTo(1, duration: AppPageRoute._reducedDuration);
      }
    } else {
      setPopVelocity(-velocity);
      if (isCurrent) {
        navigator.pop();
      } else if (controller.isAnimating && springs()) {
        controller.animateBackWith(
            AppPageRoute._pageSim(controller.value, 0, -velocity));
      }
    }

    if (controller.isAnimating) {
      late AnimationStatusListener listener;
      listener = (status) {
        if (status.isAnimating) return;
        navigator.didStopUserGesture();
        controller.removeStatusListener(listener);
      };
      controller.addStatusListener(listener);
    } else {
      navigator.didStopUserGesture();
    }
  }
}

/// Shared element for a list row to its chat header: wrap the avatar and the
/// title with the same two tags on both pages, e.g.
/// `AppHero(tag: 'session-avatar-$id', child: avatar)` and
/// `AppHero.title(tag: 'session-title-$id', from: 17, to: 15, child: Text(..))`.
/// The flight is a straight line, rides the route spring, and scrubs with the
/// back swipe.
class AppHero extends StatelessWidget {
  const AppHero({super.key, required this.tag, required this.child})
      : _from = null,
        _to = null;

  /// A text hero whose font size flies from [from] to [to] and back.
  const AppHero.title({
    super.key,
    required this.tag,
    required this.child,
    required double from,
    required double to,
  })  : _from = from,
        _to = to;

  final Object tag;
  final Widget child;
  final double? _from;
  final double? _to;

  static Tween<Rect?> _rect(Rect? begin, Rect? end) =>
      RectTween(begin: begin, end: end);

  @override
  Widget build(BuildContext context) {
    final from = _from, to = _to;
    return Hero(
      tag: tag,
      transitionOnUserGestures: true,
      createRectTween: _rect,
      flightShuttleBuilder: from == null || to == null
          ? null
          : (context, animation, direction, fromCtx, toCtx) {
              final push = direction == HeroFlightDirection.push;
              final a = push ? from : to;
              final b = push ? to : from;
              return AnimatedBuilder(
                animation: animation,
                builder: (context, _) {
                  final base = DefaultTextStyle.of(toCtx).style;
                  return DefaultTextStyle(
                    style:
                        base.copyWith(fontSize: a + (b - a) * animation.value),
                    child:
                        Material(type: MaterialType.transparency, child: child),
                  );
                },
              );
            },
      child: child,
    );
  }
}
