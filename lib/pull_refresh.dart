import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import 'platform.dart';
import 'theme.dart';
import 'widgets.dart';

/// Refresh by pulling past the top of a list.
///
/// Phones get the standard pull-down. Desktop has nothing to pull, so a hard
/// scroll upward while already at the top (wheel or trackpad) refreshes; a
/// gentle scroll that merely reaches the top does not.
class PullToRefresh extends StatefulWidget {
  const PullToRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
    this.reverse = false,
    this.indicatorTop = 6,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  /// The list is reversed: its oldest end, at the top of the screen, refreshes.
  /// RefreshIndicator only watches the leading edge, so phones use the pull detector too.
  final bool reverse;
  final double indicatorTop;

  @override
  State<PullToRefresh> createState() => _PullToRefreshState();
}

class _PullToRefreshState extends State<PullToRefresh> {
  static double get _threshold => kMobile ? 100.0 : 260.0;
  static const _window = Duration(milliseconds: 450);

  bool _atTop = true;
  double _pull = 0;
  DateTime _lastPull = DateTime.fromMillisecondsSinceEpoch(0);
  bool _refreshing = false;
  bool _fired = false;

  void _addPull(double amount) {
    if (_refreshing || amount <= 0) return;
    final now = DateTime.now();
    if (now.difference(_lastPull) > _window) _pull = 0;
    _lastPull = now;
    _pull += amount;
    if (_pull >= _threshold) {
      _pull = 0;
      _fired = true;
      unawaited(_run());
    }
  }

  Future<void> _run() async {
    setState(() => _refreshing = true);
    try {
      await widget.onRefresh();
    } catch (_) {
    } finally {
      if (mounted) setState(() => _refreshing = false);
    }
  }

  bool _atEdge(ScrollMetrics m) => widget.reverse
      ? m.pixels >= m.maxScrollExtent - 0.5
      : m.pixels <= m.minScrollExtent + 0.5;

  bool _onScroll(ScrollNotification n) {
    if (n.depth != 0 || n.metrics.axis != Axis.vertical) return false;
    final m = n.metrics;
    _atTop = _atEdge(m);
    // Past the edge, a reversed list moves towards larger offsets.
    final sign = widget.reverse ? 1.0 : -1.0;
    final beyond = widget.reverse
        ? m.pixels > m.maxScrollExtent
        : m.pixels < m.minScrollExtent;
    if (kMobile) {
      // Only the finger pulls, measured undamped, once per drag; a fling coasting in does not.
      if (n is ScrollEndNotification) _fired = false;
      final drag = n is OverscrollNotification
          ? n.dragDetails
          : n is ScrollUpdateNotification
              ? n.dragDetails
              : null;
      final past = n is OverscrollNotification || beyond;
      if (drag != null && past && !_fired && drag.delta.dy > 0) {
        _addPull(drag.delta.dy);
      }
      return false;
    }
    if (n is OverscrollNotification && n.overscroll * sign > 0) {
      _addPull(n.overscroll * sign);
    } else if (n is ScrollUpdateNotification &&
        beyond &&
        (n.scrollDelta ?? 0) * sign > 0) {
      _addPull((n.scrollDelta ?? 0) * sign);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    if (kMobile && !widget.reverse) {
      return RefreshIndicator(
        color: AppColors.accent,
        backgroundColor: AppColors.surface3,
        onRefresh: widget.onRefresh,
        child: widget.child,
      );
    }
    return Listener(
      onPointerSignal: (e) {
        if (e is PointerScrollEvent && _atTop && e.scrollDelta.dy < 0) {
          _addPull(-e.scrollDelta.dy);
        }
      },
      child: NotificationListener<ScrollNotification>(
        onNotification: _onScroll,
        child: NotificationListener<ScrollMetricsNotification>(
          onNotification: (n) {
            if (n.depth == 0 && n.metrics.axis == Axis.vertical) {
              _atTop = _atEdge(n.metrics);
            }
            return false;
          },
          child: Stack(children: [
            widget.child,
            Positioned(
              top: widget.indicatorTop,
              left: 0,
              right: 0,
              child: IgnorePointer(
                child: Center(
                  child: AnimatedSwitcher(
                    duration: Motion.fast,
                    child: !_refreshing
                        ? const SizedBox.shrink()
                        : Container(
                            width: 28,
                            height: 28,
                            alignment: Alignment.center,
                            decoration: BoxDecoration(
                              color: AppColors.surface3,
                              shape: BoxShape.circle,
                            ),
                            child: Spinner(size: 14, color: AppColors.accent),
                          ),
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
