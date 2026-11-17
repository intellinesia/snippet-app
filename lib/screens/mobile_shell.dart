import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';

import '../gesture_physics.dart';
import '../glass.dart' show StatusInset;
import '../theme.dart';
import 'shell_models.dart';
import '../chat_scene.dart' show SceneBackdrop;

/// Full-screen mobile shell layout with sliding sidebar and platform back handling.
class MobileShell extends StatefulWidget {
  final Widget? activeTabBody;
  final Widget sidebar;
  final bool hasActiveTab;
  final bool chatsOpen;
  final bool drilledDown;
  final MobileHome mobileHome;
  final VoidCallback onClearDrillDown;
  final ValueChanged<MobileHome> onMobileHome;
  final VoidCallback onCloseChats;
  final VoidCallback? onOpenChats;
  final bool? canPopRoute;
  final VoidCallback? onPopRoute;
  final bool missionPair;
  final VoidCallback? onSwipeToSessions;
  final VoidCallback? onSwipeToMission;

  const MobileShell({
    super.key,
    required this.activeTabBody,
    required this.sidebar,
    required this.hasActiveTab,
    required this.chatsOpen,
    required this.drilledDown,
    required this.mobileHome,
    required this.onClearDrillDown,
    required this.onMobileHome,
    required this.onCloseChats,
    this.onOpenChats,
    this.canPopRoute,
    this.onPopRoute,
    this.missionPair = false,
    this.onSwipeToSessions,
    this.onSwipeToMission,
  });

  @override
  State<MobileShell> createState() => _MobileShellState();
}

class _MobileShellState extends State<MobileShell>
    with SingleTickerProviderStateMixin {
  // 0 = sessions list in front, 1 = the tab body in front. Dragged 1:1.
  late final AnimationController _v =
      AnimationController.unbounded(vsync: this, value: _chatsVisible ? 0 : 1)
        ..addListener(_onV);
  (bool, bool, bool) _vEnds = (false, false, false);
  late final Animation<double> _vUnit = _v.drive(_Unit());

  // Only the discrete states (offstage, tickers) rebuild; transforms follow _v.
  static (bool, bool, bool) _endsOf(double v) => (v == 0.0, v == 1.0, v > 0);

  void _onV() {
    final e = _endsOf(_v.value);
    if (e == _vEnds) return;
    setState(() => _vEnds = e);
  }

  double _base = 0;
  double _raw = 0;
  double? _commitVelocity;

  bool get _chatsVisible => widget.chatsOpen || !widget.hasActiveTab;
  double get _exitX => widget.missionPair ? 1.0 : -1.0;

  @override
  void didUpdateWidget(MobileShell old) {
    super.didUpdateWidget(old);
    final was = old.chatsOpen || !old.hasActiveTab;
    if (was == _chatsVisible) return;
    final to = _chatsVisible ? 0.0 : 1.0;
    final velocity = _commitVelocity;
    _commitVelocity = null;
    final reduced = reduceMotion(context);
    if (velocity != null && !reduced) {
      springTo(_v, to, velocity, epsilon: 0.001);
    } else if (reduced) {
      _v.animateTo(to,
          duration: const Duration(milliseconds: 150), curve: Curves.linear);
    } else if (widget.missionPair) {
      _v.animateTo(to, duration: Motion.base, curve: Motion.enter);
    } else {
      _v.animateTo(
        to,
        duration: Duration(milliseconds: _chatsVisible ? 260 : 340),
        curve: Curves.easeOutCubic,
      );
    }
  }

  @override
  void dispose() {
    _v.dispose();
    super.dispose();
  }

  void _dragStart() {
    _v.stop();
    _base = _v.value;
    _raw = 0;
  }

  void _dragUpdate(double dx, double width) {
    _raw += dx / width * _exitX;
    var v = _base + _raw;
    if (v < 0) v = -rubberBand(-v, .35);
    if (v > 1) v = 1 + rubberBand(v - 1, .35);
    _v.value = v;
  }

  // On Android gesture navigation an edge swipe is also a system back; let
  // whichever lands first win so one swipe never navigates twice.
  DateTime? _swipeNavAt;
  DateTime? _systemBackAt;
  static bool _recent(DateTime? t) =>
      t != null &&
      DateTime.now().difference(t) < const Duration(milliseconds: 600);

  /// [onCommit] runs when the drag carries far or fast enough to switch.
  void _dragEnd(double velocityPx, double width, VoidCallback onCommit,
      {double? distanceThreshold, double? velocityThreshold}) {
    final here = _chatsVisible ? 0.0 : 1.0;
    final toward = _chatsVisible ? 1.0 : 0.0;
    final vel = velocityPx / width * _exitX;
    final dir = toward - here;
    final moved = (_v.value - here) * dir;
    final vThresh = velocityThreshold ?? 600;
    final vAlong = vel * dir * width;
    if (vAlong > -vThresh &&
        dragDismisses(
            distance: moved * width,
            velocity: vAlong,
            distanceThreshold: distanceThreshold ?? 80,
            velocityThreshold: vThresh)) {
      if (_recent(_systemBackAt)) {
        springTo(_v, _chatsVisible ? 0.0 : 1.0, vel, epsilon: 0.001);
        return;
      }
      _swipeNavAt = DateTime.now();
      HapticFeedback.selectionClick();
      _commitVelocity = vel;
      onCommit();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_commitVelocity == null || !mounted) return;
        _commitVelocity = null;
        springTo(_v, here, vel, epsilon: 0.001);
      });
    } else {
      springTo(_v, here, vel, epsilon: 0.001);
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeTabBody = widget.activeTabBody;
    final sidebar = widget.sidebar;
    final drilledDown = widget.drilledDown;
    final mobileHome = widget.mobileHome;
    final onClearDrillDown = widget.onClearDrillDown;
    final onMobileHome = widget.onMobileHome;
    final onCloseChats = widget.onCloseChats;
    final onOpenChats = widget.onOpenChats;
    final onPopRoute = widget.onPopRoute;
    final missionPair = widget.missionPair;
    final onSwipeToSessions = widget.onSwipeToSessions;
    final onSwipeToMission = widget.onSwipeToMission;
    final chatsVisible = _chatsVisible;
    final canPopRoute = widget.canPopRoute;
    final canPop = canPopRoute ??
        (!chatsVisible || drilledDown || mobileHome != MobileHome.chats);

    void handleBack() {
      final route = ModalRoute.of(context);
      if (route?.willHandlePopInternally ?? false) {
        Navigator.of(context).pop();
        return;
      }
      if (onPopRoute != null) {
        onPopRoute();
        return;
      }
      if (!chatsVisible) {
        if (onOpenChats != null) {
          onOpenChats();
        } else {
          onCloseChats();
        }
      } else if (drilledDown) {
        onClearDrillDown();
      } else if (mobileHome != MobileHome.chats) {
        onMobileHome(MobileHome.chats);
      }
    }

    _vEnds = _endsOf(_v.value);
    final reduced = reduceMotion(context);
    final chatLayer = activeTabBody == null
        ? null
        : Positioned.fill(
            child: Offstage(
              offstage: !missionPair && chatsVisible && _v.value == 0.0,
              child: IgnorePointer(
                ignoring: chatsVisible,
                child: AnimatedBuilder(
                  animation: _v,
                  child: RepaintBoundary(
                    child: Material(
                      color: AppColors.bg,
                      child: TickerMode(
                        enabled: _v.value > 0,
                        child: SceneBackdrop(
                          child: StatusInset(
                            top: MediaQuery.paddingOf(context).top,
                            child: SafeArea(
                              bottom: false,
                              child: activeTabBody,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  builder: (context, child) {
                    final vc = _v.value.clamp(0.0, 1.0);
                    Widget c = child!;
                    if (reduced || missionPair) {
                      c = FadeTransition(opacity: _vUnit, child: c);
                    }
                    return FractionalTranslation(
                      translation: reduced
                          ? Offset.zero
                          : missionPair
                              ? Offset(-0.25 * (1 - vc), 0)
                              : Offset(1 - vc, 0),
                      child: c,
                    );
                  },
                ),
              ),
            ),
          );
    final sidebarLayer = Positioned.fill(
      child: Offstage(
        offstage: !chatsVisible && _v.value == 1.0,
        child: IgnorePointer(
          ignoring: !chatsVisible,
          child: AnimatedBuilder(
            animation: _v,
            builder: (context, child) => FractionalTranslation(
              translation: reduced
                  ? Offset.zero
                  : missionPair
                      ? Offset(_exitX * _v.value, 0)
                      : Offset(-0.3 * _v.value.clamp(0.0, 1.0), 0),
              child: child,
            ),
            child: Stack(
              fit: StackFit.expand,
              children: [
                RepaintBoundary(
                  child: Material(
                    color: AppColors.bg,
                    child: TickerMode(
                      enabled: chatsVisible || _v.value < 1.0,
                      child: SceneBackdrop(
                        child: SafeArea(
                          child: sidebar,
                        ),
                      ),
                    ),
                  ),
                ),
                if (!missionPair && !reduced)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: AnimatedBuilder(
                        animation: _v,
                        builder: (context, _) {
                          final vc = _v.value.clamp(0.0, 1.0);
                          return vc > 0
                              ? ColoredBox(
                                  color:
                                      Colors.black.withValues(alpha: 0.18 * vc))
                              : const SizedBox.expand();
                        },
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    final shell = Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        if (missionPair) ...[
          if (chatLayer != null) chatLayer,
          sidebarLayer,
        ] else ...[
          sidebarLayer,
          if (chatLayer != null) chatLayer,
        ],
        if (!chatsVisible && (onOpenChats != null || onPopRoute != null))
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            width: 20,
            child: _EdgeSwipeBack(
              onStart: _dragStart,
              onDelta: (dx, w) => _dragUpdate(-dx * _exitX, w),
              onEnd: (v, w) => _dragEnd(
                -v * _exitX,
                w,
                handleBack,
                distanceThreshold: w / 3,
                velocityThreshold: w,
              ),
            ),
          ),
      ]),
    );

    final swipe = chatsVisible
        ? (mobileHome == MobileHome.chats && !drilledDown
            ? onSwipeToMission
            : null)
        : (missionPair ? onSwipeToSessions : null);
    void start() => _dragStart();
    void delta(double dx, double w) => _dragUpdate(dx, w);
    void end(double v, double w) => _dragEnd(v, w, swipe!);

    final body = swipe != null
        ? _PairSwipe(onStart: start, onDelta: delta, onEnd: end, child: shell)
        : shell;

    if (canPop) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop || _recent(_swipeNavAt)) return;
          _systemBackAt = DateTime.now();
          handleBack();
        },
        child: body,
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop || _recent(_swipeNavAt)) return;
        _systemBackAt = DateTime.now();
        if (ModalRoute.of(context)?.willHandlePopInternally ?? false) {
          Navigator.of(context).pop();
          return;
        }
        SystemNavigator.pop();
      },
      child: body,
    );
  }
}

class _Unit extends Animatable<double> {
  @override
  double transform(double t) => t.clamp(0.0, 1.0);
}

typedef _DragEnd = void Function(double velocityPx, double width);

class _PairSwipe extends StatelessWidget {
  final VoidCallback onStart;
  final void Function(double dx, double width) onDelta;
  final _DragEnd onEnd;
  final Widget child;
  const _PairSwipe(
      {required this.onStart,
      required this.onDelta,
      required this.onEnd,
      required this.child});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => onStart(),
      onHorizontalDragUpdate: (d) => onDelta(d.delta.dx, width),
      onHorizontalDragEnd: (d) => onEnd(d.primaryVelocity ?? 0, width),
      onHorizontalDragCancel: () => onEnd(0, width),
      child: child,
    );
  }
}

class _EdgeSwipeBack extends StatelessWidget {
  final VoidCallback onStart;
  final void Function(double dx, double width) onDelta;
  final _DragEnd onEnd;
  const _EdgeSwipeBack(
      {required this.onStart, required this.onDelta, required this.onEnd});

  @override
  Widget build(BuildContext context) {
    final width = MediaQuery.sizeOf(context).width;
    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: (_) => onStart(),
      onHorizontalDragUpdate: (d) => onDelta(d.delta.dx, width),
      onHorizontalDragEnd: (d) => onEnd(d.primaryVelocity ?? 0, width),
      onHorizontalDragCancel: () => onEnd(0, width),
    );
  }
}

/// Drives the Sessions | Agents pager: 0 is Sessions, 1 is Agents. The finger
/// moves it 1:1 (rubber-banded past the ends); release projects 200 ms of
/// velocity and settles on a 1/500/44 spring.
class HomePagerController extends ChangeNotifier {
  HomePagerController({
    required TickerProvider vsync,
    int initial = 0,
    this.onCommit,
  })  : _page = initial,
        _c = AnimationController.unbounded(vsync: vsync, value: initial * 1.0) {
    _c.addListener(notifyListeners);
  }

  static const SpringDescription spring =
      SpringDescription(mass: 1, stiffness: 500, damping: 44);

  final AnimationController _c;
  int _page;
  bool _dragging = false;

  /// Called once per committed change, after the selection haptic.
  ValueChanged<int>? onCommit;

  int get page => _page;
  bool get dragging => _dragging;

  /// Fractional page, 0..1 (may overshoot slightly while rubber-banding).
  double get position => _c.value;

  void _settle(int to, double velocity) {
    _c.animateWith(SpringSimulation(spring, _c.value, to.toDouble(), velocity,
        snapToEnd: true,
        tolerance: const Tolerance(distance: 0.001, velocity: 0.01)));
  }

  /// Moves to [page] without a drag (tap on the indicator, external change).
  void animateTo(int page) {
    if (_dragging) return;
    _page = page;
    _settle(page, 0);
  }

  void dragStart() {
    _c.stop();
    _dragging = true;
  }

  void dragUpdate(double dx, double width) {
    if (width <= 0) return;
    var v = _c.value - dx / width;
    if (v < 0) v = -rubberBand(-v, .35);
    if (v > 1) v = 1 + rubberBand(v - 1, .35);
    _c.value = v;
  }

  void dragEnd(double velocityPx, double width) {
    if (!_dragging) return;
    _dragging = false;
    if (width <= 0) return;
    final v = -velocityPx / width;
    final projected = _c.value + v * 0.2;
    final to = projected.round().clamp(0, 1);
    if (to != _page) {
      _page = to;
      HapticFeedback.selectionClick();
      onCommit?.call(to);
    }
    _settle(to, v);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }
}

/// Owns a [HomePagerController] and shares it with the pager body and the top
/// bar indicator below it. [page] is the selected page (0 or 1); [onPage] fires
/// when a drag commits.
class HomePagerScope extends StatefulWidget {
  const HomePagerScope({
    super.key,
    required this.page,
    required this.onPage,
    required this.child,
  });

  final int page;
  final ValueChanged<int> onPage;
  final Widget child;

  static HomePagerController? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<_HomePagerInherited>()
      ?.notifier;

  @override
  State<HomePagerScope> createState() => _HomePagerScopeState();
}

class _HomePagerScopeState extends State<HomePagerScope>
    with SingleTickerProviderStateMixin {
  late final HomePagerController _ctl = HomePagerController(
      vsync: this, initial: widget.page, onCommit: (p) => widget.onPage(p));

  @override
  void didUpdateWidget(HomePagerScope old) {
    super.didUpdateWidget(old);
    if (widget.page != _ctl.page && !_ctl.dragging) {
      if (reduceMotion(context)) {
        _ctl._c.value = widget.page.toDouble();
        _ctl._page = widget.page;
      } else {
        _ctl.animateTo(widget.page);
      }
    }
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _HomePagerInherited(notifier: _ctl, child: widget.child);
}

class _HomePagerInherited extends InheritedNotifier<HomePagerController> {
  const _HomePagerInherited({required super.notifier, required super.child});
}

/// The two home bodies side by side, dragged 1:1 under the finger. Needs a
/// [HomePagerScope] above it.
class HomePager extends StatelessWidget {
  const HomePager({super.key, required this.sessions, required this.agents});

  final Widget sessions;
  final Widget agents;

  @override
  Widget build(BuildContext context) {
    final ctl = HomePagerScope.maybeOf(context);
    if (ctl == null) return sessions;
    return LayoutBuilder(builder: (context, box) {
      final w = box.maxWidth;
      return RawGestureDetector(
        behavior: HitTestBehavior.translucent,
        gestures: {
          _EdgeYieldDrag: GestureRecognizerFactoryWithHandlers<_EdgeYieldDrag>(
            () => _EdgeYieldDrag(ctl),
            (r) => r
              ..onStart = ((_) => ctl.dragStart())
              ..onUpdate = ((d) => ctl.dragUpdate(d.delta.dx, w))
              ..onEnd = ((d) => ctl.dragEnd(d.primaryVelocity ?? 0, w))
              ..onCancel = (() => ctl.dragEnd(0, w)),
          ),
        },
        child: ClipRect(
          child: AnimatedBuilder(
            animation: ctl,
            builder: (context, _) {
              final p = ctl.position;
              return Stack(fit: StackFit.expand, children: [
                Offstage(
                  offstage: p >= 1,
                  child: Transform.translate(
                      offset: Offset(-p * w, 0), child: sessions),
                ),
                Offstage(
                  offstage: p <= 0,
                  child: Transform.translate(
                      offset: Offset((1 - p) * w, 0), child: agents),
                ),
              ]);
            },
          ),
        ),
      );
    });
  }
}

/// Horizontal drag that backs off when it would only pull past an end of the
/// pager, so an outer swipe (Mission Control) can take it.
class _EdgeYieldDrag extends HorizontalDragGestureRecognizer {
  _EdgeYieldDrag(this.ctl);

  final HomePagerController ctl;
  double _dx = 0;
  bool _decided = false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _dx = 0;
    _decided = false;
    super.addAllowedPointer(event);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (!_decided && event is PointerMoveEvent) {
      _dx += event.delta.dx;
      if (_dx.abs() > 4) {
        _decided = true;
        final atStart = ctl.position <= 0.001 && _dx > 0;
        final atEnd = ctl.position >= 0.999 && _dx < 0;
        if (atStart || atEnd) {
          resolve(GestureDisposition.rejected);
          stopTrackingPointer(event.pointer);
          return;
        }
      }
    }
    super.handleEvent(event);
  }
}
