import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

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
  }) {
    assert(opaque);
  }

  final WidgetBuilder builder;

  @override
  final bool maintainState;

  static const Duration _phoneForward = Duration(milliseconds: 340);
  static const Duration _phoneReverse = Duration(milliseconds: 260);
  static const Duration _reducedDuration = Duration(milliseconds: 150);

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
    return super.didPop(result);
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
    final linear = Navigator.maybeOf(context)?.userGestureInProgress ?? false;
    return _AppOutgoingTransition(
      secondaryAnimation: secondaryAnimation,
      linear: linear,
      child: child,
    );
  }

  @override
  bool canTransitionTo(TransitionRoute<dynamic> nextRoute) {
    if (nextRoute is PageRoute && nextRoute.fullscreenDialog) return false;
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
        child: builder(context),
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
    final gesturedChild = _EdgeBackDetector<T>(
      enabledCallback: () => popGestureEnabled,
      onStartPopGesture: () => _BackGestureController<T>(
        navigator: navigator!,
        controller: controller!,
        getIsActive: () => isActive,
        getIsCurrent: () => isCurrent,
      ),
      child: child,
    );
    if (reduceMotion(context)) {
      return FadeTransition(opacity: animation, child: gesturedChild);
    }
    final outgoingLinear =
        Navigator.maybeOf(context)?.userGestureInProgress ?? false;
    return _AppOutgoingTransition(
      secondaryAnimation: secondaryAnimation,
      linear: outgoingLinear,
      child: _AppIncomingTransition(
        primaryAnimation: animation,
        linear: popGestureInProgress,
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
    end: const Offset(-0.3, 0.0),
  );
  static final Animatable<double> _scrimTween =
      Tween<double>(begin: 0.0, end: 0.18);

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
const double _kMinFlingVelocity = 1.0;
const double _kDismissFraction = 1.0 / 3.0;
const Duration _kSettleDuration = Duration(milliseconds: 260);

class _EdgeBackDetector<T> extends StatefulWidget {
  const _EdgeBackDetector({
    required this.enabledCallback,
    required this.onStartPopGesture,
    required this.child,
  });

  final ValueGetter<bool> enabledCallback;
  final ValueGetter<_BackGestureController<T>> onStartPopGesture;
  final Widget child;

  @override
  State<_EdgeBackDetector<T>> createState() => _EdgeBackDetectorState<T>();
}

class _EdgeBackDetectorState<T> extends State<_EdgeBackDetector<T>> {
  _BackGestureController<T>? _controller;
  late final HorizontalDragGestureRecognizer _recognizer;

  @override
  void initState() {
    super.initState();
    _recognizer = HorizontalDragGestureRecognizer(debugOwner: this)
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
    if (widget.enabledCallback()) {
      _recognizer.addPointer(event);
    }
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
    );
  }

  void _handleDragCancel() {
    _controller?.dragEnd(0.0);
    _controller = null;
  }

  @override
  Widget build(BuildContext context) {
    final inset = switch (Directionality.of(context)) {
      TextDirection.rtl => MediaQuery.paddingOf(context).right,
      TextDirection.ltr => MediaQuery.paddingOf(context).left,
    };
    return Stack(
      fit: StackFit.passthrough,
      children: [
        widget.child,
        PositionedDirectional(
          start: 0.0,
          width: math.max(inset, _kBackEdgeWidth),
          top: 0.0,
          bottom: 0.0,
          child: Listener(
            onPointerDown: _handlePointerDown,
            behavior: HitTestBehavior.translucent,
          ),
        ),
      ],
    );
  }
}

class _BackGestureController<T> {
  _BackGestureController({
    required this.navigator,
    required this.controller,
    required this.getIsActive,
    required this.getIsCurrent,
  }) {
    navigator.didStartUserGesture();
  }

  final AnimationController controller;
  final NavigatorState navigator;
  final ValueGetter<bool> getIsActive;
  final ValueGetter<bool> getIsCurrent;

  void dragUpdate(double delta) {
    controller.value -= delta;
  }

  void dragEnd(double velocity) {
    final isCurrent = getIsCurrent();
    final bool animateForward;
    if (!isCurrent) {
      animateForward = getIsActive();
    } else if (velocity.abs() >= _kMinFlingVelocity) {
      animateForward = velocity <= 0;
    } else {
      animateForward = controller.value >= (1.0 - _kDismissFraction);
    }

    if (animateForward) {
      controller.animateTo(
        1.0,
        duration: _kSettleDuration,
        curve: Curves.easeOutCubic,
      );
    } else {
      if (isCurrent) navigator.pop();
      if (controller.isAnimating) {
        controller.animateBack(
          0.0,
          duration: _kSettleDuration,
          curve: Curves.easeOutCubic,
        );
      }
    }

    if (controller.isAnimating) {
      late AnimationStatusListener listener;
      listener = (_) {
        navigator.didStopUserGesture();
        controller.removeStatusListener(listener);
      };
      controller.addStatusListener(listener);
    } else {
      navigator.didStopUserGesture();
    }
  }
}
