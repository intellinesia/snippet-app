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
    if (Glass.enabled && !_Frosted.on(context)) {
      final f = ImageFilter.blur(sigmaX: blur, sigmaY: blur);
      w = BackdropGroup.of(context) == null
          ? BackdropFilter(filter: f, child: w)
          : BackdropFilter.grouped(filter: f, child: w);
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
  static const double inset = 52;
  static const double fade = 14;
  static const _bands = [
    (0.0, 0.5, 11.0),
    (0.5, 0.66, 9.0),
    (0.66, 0.8, 7.0),
    (0.8, 0.92, 5.0),
    (0.92, 1.0, 3.0),
  ];

  @override
  Widget build(BuildContext context) {
    final bg = color ?? AppColors.bg;
    final on = Glass.enabled;
    final frame = Stack(children: [
      Positioned.fill(
        child: IgnorePointer(
          child: Stack(children: [
            if (on)
              // Bands share one backdrop read; overlapping stacked blurs cost a
              // full pass each and were the main source of scroll jank.
              Positioned.fill(child: LayoutBuilder(builder: (context, c) {
                final h = c.maxHeight;
                return Stack(children: [
                  for (final (from, to, sigma) in _bands)
                    Positioned(
                      top: h * from,
                      left: 0,
                      right: 0,
                      height: h * (to - from),
                      child: ClipRect(
                        child: BackdropFilter.grouped(
                          filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
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
      Padding(
          padding: const EdgeInsets.only(bottom: fade),
          child: _Frosted(child: child)),
    ]);
    return BackdropGroup.of(context) == null
        ? BackdropGroup(child: frame)
        : frame;
  }
}

/// Marks content already sitting on frost, so nested [Glass] skips its blur.
class _Frosted extends InheritedWidget {
  const _Frosted({required super.child});

  static bool on(BuildContext context) =>
      context.getInheritedWidgetOfExactType<_Frosted>() != null;

  @override
  bool updateShouldNotify(_Frosted oldWidget) => false;
}

/// Fades a scrolling body out under a floating header without painting a fill,
/// so a see-through desktop window stays see-through.
class TopFadeMask extends StatelessWidget {
  const TopFadeMask(
      {super.key, required this.clear, this.fade = 16, required this.child});

  final double clear;
  final double fade;
  final Widget child;

  @override
  Widget build(BuildContext context) => ShaderMask(
        blendMode: BlendMode.dstIn,
        shaderCallback: (r) {
          final h = r.height <= 0 ? 1.0 : r.height;
          final a = (clear / h).clamp(0.0, 1.0);
          final b = ((clear + fade) / h).clamp(a, 1.0);
          return LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: [0, a, b, 1],
            colors: const [
              Colors.transparent,
              Colors.transparent,
              Colors.white,
              Colors.white,
            ],
          ).createShader(r);
        },
        child: child,
      );
}

/// Blurs the window behind a centred desktop modal, fading with its route.
class ModalGlass extends StatelessWidget {
  const ModalGlass({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final anim = ModalRoute.of(context)?.animation;
    if (anim == null || !Glass.enabled || _phone(context)) return child;
    return Stack(fit: StackFit.passthrough, children: [
      Positioned.fill(
        child: IgnorePointer(
          child: AnimatedBuilder(
            animation: anim,
            builder: (_, __) {
              final t = anim.value;
              if (t < 0.01) return const SizedBox.shrink();
              return BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 14 * t, sigmaY: 14 * t),
                child: const SizedBox.expand(),
              );
            },
          ),
        ),
      ),
      child,
    ]);
  }

  static bool _phone(BuildContext context) =>
      MediaQuery.sizeOf(context).width < 700 ||
      const {TargetPlatform.android, TargetPlatform.iOS}
          .contains(Theme.of(context).platform);
}
