import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'theme.dart';

class GlassStyle {
  static bool get light => AppColors.bg.computeLuminance() > 0.18;

  static Color get fill => light
      ? AppColors.surface1.withValues(alpha: 0.72)
      : AppColors.surface2.withValues(alpha: 0.62);
}

/// Frosted surface for elements floating over content: blur behind a tinted,
/// hairline-bordered fill. [radius] null means a circle.
class Glass extends StatelessWidget {
  const Glass({
    super.key,
    required this.child,
    this.radius,
    this.tint,
    this.border = true,
    this.blur = 24,
  });

  final Widget child;
  final BorderRadius? radius;
  final Color? tint;
  final bool border;
  final double blur;

  /// Escape hatch for perf and tests: skips the blur and hardens the fill.
  static bool enabled = true;

  @override
  Widget build(BuildContext context) {
    final fill = tint ?? GlassStyle.fill;
    Widget w = DecoratedBox(
      decoration: BoxDecoration(
        color: Glass.enabled ? fill : fill.withValues(alpha: 0.96),
        shape: radius == null ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: radius,
        border: border
            ? Border.all(color: AppColors.fg1.withValues(alpha: 0.08))
            : null,
      ),
      child: child,
    );
    if (Glass.enabled) {
      w = BackdropFilter(
          filter: ImageFilter.blur(sigmaX: blur, sigmaY: blur), child: w);
    }
    return radius == null
        ? ClipOval(child: w)
        : ClipRRect(borderRadius: radius!, child: w);
  }
}
