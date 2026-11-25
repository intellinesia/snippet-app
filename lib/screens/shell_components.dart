import 'package:flutter/material.dart';

import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';

/// Keeps a swiped-away tab mounted so its WebSocket attach and scroll position
/// survive switching between tabs.
class ShellKeepAlive extends StatefulWidget {
  final Widget child;
  final bool keep;
  const ShellKeepAlive({super.key, required this.child, this.keep = true});
  @override
  State<ShellKeepAlive> createState() => _ShellKeepAliveState();
}

class _ShellKeepAliveState extends State<ShellKeepAlive>
    with AutomaticKeepAliveClientMixin {
  @override
  bool get wantKeepAlive => widget.keep;
  @override
  void didUpdateWidget(covariant ShellKeepAlive oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.keep != widget.keep) updateKeepAlive();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    super.build(context);
    return widget.child;
  }
}

/// Small green pulsing dot indicating a running session.
class PulsingDot extends StatefulWidget {
  const PulsingDot({super.key});

  @override
  State<PulsingDot> createState() => _PulsingDotState();
}

class _PulsingDotState extends State<PulsingDot>
    with SingleTickerProviderStateMixin {
  late AnimationController _ctrl;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
        vsync: this, duration: const Duration(milliseconds: 1200));
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      if (_ctrl.isAnimating) _ctrl.stop();
      _ctrl.value = 1;
    } else if (!_ctrl.isAnimating) {
      _ctrl.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: FadeTransition(
        opacity: _ctrl.drive(Tween(begin: 0.4, end: 1.0)),
        child: Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            color: AppColors.ok,
            shape: BoxShape.circle,
          ),
        ),
      ),
    );
  }
}
