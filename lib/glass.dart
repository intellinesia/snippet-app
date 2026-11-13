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

/// The frosted strip a chat header floats on; the transcript scrolls under it.
class GlassTopFrame extends StatelessWidget {
  const GlassTopFrame({super.key, required this.child, this.color});

  final Widget child;
  final Color? color;

  /// Room the transcript leaves at its top so the newest-first scroll can
  /// still reach the oldest row from under the header.
  static const double inset = 60;
  static const double fade = 22;
  static const _steps = 8;

  @override
  Widget build(BuildContext context) {
    final bg = color ?? AppColors.bg;
    final on = Glass.enabled;
    return Stack(children: [
      Positioned.fill(
        child: IgnorePointer(
          child: Stack(children: [
            if (on)
              // Many small stacked blurs, each a little shorter: the frost
              // tapers with no visible step. A masked blur renders unblurred.
              Positioned.fill(child: LayoutBuilder(builder: (context, c) {
                final h = c.maxHeight;
                return Stack(children: [
                  for (var i = 0; i < _steps; i++)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      height: h * (1 - 0.55 * i / (_steps - 1)),
                      child: ClipRect(
                        child: BackdropFilter(
                          filter: ImageFilter.blur(sigmaX: 4, sigmaY: 4),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                ]);
              })),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: const [0, 0.5, 0.8, 1],
                    colors: [
                      bg.withValues(alpha: on ? 0.72 : 0.96),
                      bg.withValues(alpha: on ? 0.55 : 0.9),
                      bg.withValues(alpha: on ? 0.2 : 0.5),
                      bg.withValues(alpha: 0),
                    ],
                  ),
                ),
              ),
            ),
          ]),
        ),
      ),
      Padding(padding: const EdgeInsets.only(bottom: fade), child: child),
    ]);
  }
}
