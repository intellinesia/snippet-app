import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'theme.dart';

/// The new-session hero: a halftone Mochi drawn in dots.
class DottedMochi extends StatelessWidget {
  const DottedMochi({super.key, this.width = 300, this.color});

  final double width;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox(
        width: width,
        height: width * 0.7,
        child: CustomPaint(
            painter: _DottedMochiPainter(color ?? AppColors.accent)),
      );
}

class _DottedMochiPainter extends CustomPainter {
  _DottedMochiPainter(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 360;
    canvas.scale(k);
    const step = 9.0, cx = 180.0, cy = 150.0, rx = 132.0;
    const ryTop = 128.0, ryBot = 70.0;
    const eyes = [Offset(132, 150), Offset(228, 150)];
    final fill = Paint()..color = color;
    final faint = Paint()..color = color.withValues(alpha: 0.28);
    var seed = 7;
    double rnd() {
      seed = (seed * 9301 + 49297) % 233280;
      return seed / 233280;
    }

    for (var y = 6.0; y < 248; y += step) {
      final ox = ((y / step).floor() % 2) * step / 2;
      for (var x = 6.0; x < 356; x += step) {
        final px = x + ox;
        final dx = (px - cx) / rx;
        final dy = (y - cy) / (y < cy ? ryTop : ryBot);
        final r = math.pow(dx.abs(), 2.4) + math.pow(dy.abs(), 2.4);
        final eye = eyes.any((e) =>
            math.sqrt(math.pow(px - e.dx, 2) + math.pow((y - e.dy) * 0.8, 2)) <
            15);
        if (r <= 1 && !eye) {
          final lx = (px - 120) / 220, ly = (y - 70) / 200;
          final light = math.max(0.0, 1 - math.sqrt(lx * lx + ly * ly));
          final s = 2.4 +
              4.2 * (0.35 + 0.65 * light) * (1 - math.pow(r, 6) * 0.5);
          canvas.drawCircle(Offset(px, y), s / 2, fill);
        } else if (r > 1 && r < 2.6 && rnd() > 0.55 + (r - 1) * 0.25) {
          canvas.drawCircle(Offset(px, y), 0.8, faint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_DottedMochiPainter old) => old.color != color;
}
