import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../gesture_physics.dart';
import '../theme.dart';
import 'shell_models.dart';

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
        ..addListener(() => setState(() {}));
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
    if (velocity != null) {
      springTo(_v, to, velocity, epsilon: 0.001);
    } else {
      _v.animateTo(to, duration: Motion.base, curve: Motion.enter);
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

  /// [onCommit] runs when the drag carries far or fast enough to switch.
  void _dragEnd(double velocityPx, double width, VoidCallback onCommit) {
    final here = _chatsVisible ? 0.0 : 1.0;
    final toward = _chatsVisible ? 1.0 : 0.0;
    final vel = velocityPx / width * _exitX;
    final dir = toward - here;
    final moved = (_v.value - here) * dir;
    if (dragDismisses(
        distance: moved * width,
        velocity: vel * dir * width,
        distanceThreshold: 80,
        velocityThreshold: 600)) {
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

    final shell = Scaffold(
      backgroundColor: AppColors.bg,
      body: Stack(children: [
        if (activeTabBody != null)
          Positioned.fill(
            child: IgnorePointer(
              ignoring: chatsVisible,
              child: FractionalTranslation(
                translation: Offset(
                    (missionPair ? -0.25 : 0.15) *
                        (1 - _v.value.clamp(0.0, 1.0)),
                    0),
                child: Opacity(
                  opacity: _v.value.clamp(0.0, 1.0),
                  child: SafeArea(
                    bottom: false,
                    child: activeTabBody,
                  ),
                ),
              ),
            ),
          ),
        Positioned.fill(
          child: Offstage(
            offstage: !chatsVisible && _v.value == 1.0,
            child: IgnorePointer(
              ignoring: !chatsVisible,
              child: FractionalTranslation(
                translation: Offset(_exitX * _v.value, 0),
                child: Material(
                  color: AppColors.bg,
                  child: SafeArea(
                    child: sidebar,
                  ),
                ),
              ),
            ),
          ),
        ),
        // iOS has no system back gesture for this in-app stack, so an edge
        // swipe provides one. It fires once per gesture, after a deliberate
        // travel or flick. Android already routes its back gesture through
        // PopScope below; a second detector there made one swipe go back
        // several screens.
        if (!chatsVisible &&
            defaultTargetPlatform == TargetPlatform.iOS &&
            (onOpenChats != null || onPopRoute != null))
          Positioned(
            top: 0,
            bottom: 0,
            left: 0,
            width: 20,
            child: _EdgeSwipeBack(
              onStart: _dragStart,
              onDelta: (dx, w) => _dragUpdate(-dx * _exitX, w),
              onEnd: (v, w) => _dragEnd(-v * _exitX, w, handleBack),
            ),
          ),
      ]),
    );

    final swipe = chatsVisible
        ? (mobileHome == MobileHome.chats && !drilledDown
            ? onSwipeToMission
            : null)
        : (missionPair ? onSwipeToSessions : null);
    final body = swipe != null
        ? _PairSwipe(
            onStart: _dragStart,
            onDelta: _dragUpdate,
            onEnd: (v, w) => _dragEnd(v, w, swipe),
            child: shell)
        : shell;

    if (canPop) {
      return PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (didPop) return;
          handleBack();
        },
        child: body,
      );
    }

    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
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
