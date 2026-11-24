import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../gesture_physics.dart';
import '../motion_routes.dart' show AppPageRoute, backSwipeStays;
import '../page_stack.dart';
import '../glass.dart' show GlassTopFrame, StatusInset;
import '../quiet.dart';
import '../theme.dart';
import 'shell_models.dart';
import 'sidebar_mode.dart' show homeFirstTab;
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

  /// Shows the floating tab bar on the top-level places when set.
  final VoidCallback? onNew;
  final VoidCallback? onNewLong;

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
    this.onNew,
    this.onNewLong,
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
    if (e.$1 || e.$2) GlassTopFrame.reflow();
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
    if (reduced) {
      _v.animateTo(to,
          duration: const Duration(milliseconds: 150), curve: Curves.linear);
    } else {
      springTo(_v, to, velocity ?? 0,
          spring: AppPageRoute.pageSpring, epsilon: 0.001);
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
      {double? distanceThreshold,
      double? velocityThreshold,
      bool projected = false}) {
    final here = _chatsVisible ? 0.0 : 1.0;
    final toward = _chatsVisible ? 1.0 : 0.0;
    final vel = velocityPx / width * _exitX;
    final dir = toward - here;
    final moved = (_v.value - here) * dir;
    final vThresh = velocityThreshold ?? 600;
    final vAlong = vel * dir * width;
    final commit = projected
        ? !backSwipeStays(1 - moved, vAlong / width, width)
        : vAlong > -vThresh &&
            dragDismisses(
                distance: moved * width,
                velocity: vAlong,
                distanceThreshold: distanceThreshold ?? 80,
                velocityThreshold: vThresh);
    if (commit) {
      if (_recent(_systemBackAt)) {
        springTo(_v, _chatsVisible ? 0.0 : 1.0, vel,
            spring: AppPageRoute.pageSpring, epsilon: 0.001);
        return;
      }
      _swipeNavAt = DateTime.now();
      HapticFeedback.selectionClick();
      _commitVelocity = vel;
      onCommit();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_commitVelocity == null || !mounted) return;
        _commitVelocity = null;
        springTo(_v, here, vel,
            spring: AppPageRoute.pageSpring, epsilon: 0.001);
      });
    } else {
      springTo(_v, here, vel, spring: AppPageRoute.pageSpring, epsilon: 0.001);
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
    final chatsVisible = _chatsVisible;
    final canPopRoute = widget.canPopRoute;
    final canPop = canPopRoute ??
        (!chatsVisible || drilledDown || !mobileHome.isSessionsHome);

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
      } else if (!mobileHome.isSessionsHome) {
        onMobileHome(homeFirstTab());
      }
    }

    _vEnds = _endsOf(_v.value);
    final reduced = reduceMotion(context);
    final width = MediaQuery.sizeOf(context).width;
    final canSwipeBack =
        !chatsVisible && (onOpenChats != null || onPopRoute != null);
    final chatLayer = activeTabBody == null
        ? null
        : Positioned.fill(
            child: Offstage(
              offstage: !missionPair && chatsVisible && _v.value == 0.0,
              child: IgnorePointer(
                ignoring: chatsVisible,
                child: AnimatedBuilder(
                  animation: _v,
                  child: PageBackSwipe(
                    enabled: !missionPair && canSwipeBack,
                    onStart: _dragStart,
                    onUpdate: (f) => _dragUpdate(f * width, width),
                    onEnd: (v, w) =>
                        _dragEnd(v * w, w, handleBack, projected: true),
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
                      : Offset(
                          -PhonePageStack.parallax * _v.value.clamp(0.0, 1.0),
                          0),
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
                        // Pages opened over home float their header frost up here.
                        child: StatusInset(
                          top: MediaQuery.paddingOf(context).top,
                          child: SafeArea(
                            child: sidebar,
                          ),
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
                                  color: Colors.black.withValues(
                                      alpha: PhonePageStack.dim * vc))
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
    final showBar = widget.onNew != null &&
        chatsVisible &&
        !drilledDown &&
        mobileHome != MobileHome.settings;
    final shell = Scaffold(
      backgroundColor: AppColors.bg,
      bottomNavigationBar: showBar
          ? ColoredBox(
              color: AppColors.bg,
              child: SafeArea(
                top: false,
                child: QuietTabBar(
                  // Agents is Home on the phone: faces first, then the lists.
                  places: const [
                    QuietPlace.agents,
                    QuietPlace.sessions,
                    QuietPlace.tasks,
                  ],
                  selected: switch (mobileHome) {
                    MobileHome.home => QuietPlace.agents,
                    MobileHome.chats => QuietPlace.sessions,
                    MobileHome.tasks => QuietPlace.tasks,
                    MobileHome.agents => QuietPlace.agents,
                    MobileHome.settings => null,
                  },
                  onSelect: (p) => onMobileHome(switch (p) {
                    QuietPlace.home => MobileHome.home,
                    QuietPlace.sessions => MobileHome.chats,
                    QuietPlace.tasks => MobileHome.tasks,
                    QuietPlace.agents => MobileHome.home,
                  }),
                  onNew: widget.onNew!,
                  onNewLong: widget.onNewLong,
                ),
              ),
            )
          : null,
      body: Stack(children: [
        if (missionPair) ...[
          if (chatLayer != null) chatLayer,
          sidebarLayer,
        ] else ...[
          sidebarLayer,
          if (chatLayer != null) chatLayer,
        ],
        if (missionPair && canSwipeBack)
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

    // Mission opens only from the bottom bar; swiping back to Sessions stays.
    final swipe = !chatsVisible && missionPair ? onSwipeToSessions : null;
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
