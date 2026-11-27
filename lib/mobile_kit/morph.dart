import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';

/// The single working indicator: a seven-lobed shape that slowly turns and
/// breathes. Used wherever something is running; no spinners elsewhere.
class MkMorph extends StatefulWidget {
  const MkMorph({super.key, this.size = 18, this.color, this.animate = true});
  final double size;
  final Color? color;

  /// Off in tests and reduced-motion; draws the resting shape.
  final bool animate;

  @override
  State<MkMorph> createState() => _MkMorphState();
}

class _MkMorphState extends State<MkMorph> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(seconds: 6));

  @override
  void initState() {
    super.initState();
    _sync();
  }

  @override
  void didUpdateWidget(MkMorph old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final still = !widget.animate ||
        (WidgetsBinding.instance.platformDispatcher.accessibilityFeatures
            .disableAnimations);
    if (still) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Working',
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _c,
            builder: (_, __) => CustomPaint(
              size: Size.square(widget.size),
              painter: _MorphPainter(_c.value, widget.color ?? AppColors.fg2),
            ),
          ),
        ),
      );
}

class _MorphPainter extends CustomPainter {
  _MorphPainter(this.t, this.color);
  final double t;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = size.shortestSide / 2;
    final turn = t * 2 * math.pi;
    // Lobe depth breathes between soft and pronounced as it turns.
    final depth = 0.09 + 0.05 * math.sin(turn * 2);
    final path = Path();
    const steps = 140;
    for (var i = 0; i <= steps; i++) {
      final a = i / steps * 2 * math.pi;
      final rr = r * (1 - depth + depth * math.cos(7 * (a - turn / 3.5)));
      final p = c + Offset(math.cos(a), math.sin(a)) * rr;
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(
        path..close(),
        Paint()
          ..color = color
          ..isAntiAlias = true);
  }

  @override
  bool shouldRepaint(_MorphPainter old) => old.t != t || old.color != color;
}
