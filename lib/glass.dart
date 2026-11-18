import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'theme.dart';

class GlassStyle {
  static bool get light => AppColors.bg.computeLuminance() > 0.18;

  static Color get fill {
    final alpha = ThemeManager.instance.resolved.translucency.glassFill.current;
    return light
        ? AppColors.surface1.withValues(alpha: alpha)
        : AppColors.surface2.withValues(alpha: alpha);
  }

  static Color get edgeColor => AppColors.fg1
      .withValues(alpha: ThemeManager.instance.resolved.border.glassEdgeAlpha);
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
    this.blur,
  });

  final Widget child;
  final BorderRadius? radius;
  final Color? tint;
  final bool border;
  final double? blur;

  /// Escape hatch for perf and tests: skips the blur and hardens the fill.
  static bool enabled = true;

  static bool get effectiveEnabled =>
      enabled && ThemeManager.instance.resolved.translucency.enabled;

  @override
  Widget build(BuildContext context) {
    final on = Glass.effectiveEnabled;
    final fill = tint ?? GlassStyle.fill;
    final sigma = blur ?? ThemeManager.instance.resolved.translucency.glassBlur;
    Widget w = DecoratedBox(
      decoration: BoxDecoration(
        color: on ? fill : fill.withValues(alpha: 0.96),
        shape: radius == null ? BoxShape.circle : BoxShape.rectangle,
        borderRadius: radius,
        border: border ? Border.all(color: GlassStyle.edgeColor) : null,
      ),
      child: child,
    );
    if (on && sigma > 0 && !_Frosted.on(context)) {
      final f = ImageFilter.blur(sigmaX: sigma, sigmaY: sigma);
      w = BackdropGroup.of(context) == null
          ? BackdropFilter(filter: f, child: w)
          : BackdropFilter.grouped(filter: f, child: w);
    }
    return radius == null
        ? ClipOval(child: w)
        : ClipRRect(borderRadius: radius!, child: w);
  }
}

/// The status bar height a [SafeArea] took away, so frost can still reach under it.
class StatusInset extends InheritedWidget {
  const StatusInset({super.key, required this.top, required super.child});

  final double top;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StatusInset>()?.top ?? 0;

  @override
  bool updateShouldNotify(StatusInset oldWidget) => top != oldWidget.top;
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

  /// How far the blurred area runs below the header strip, in logical pixels.
  static const double _extra = 36;

  @override
  Widget build(BuildContext context) {
    final bg = color ?? AppColors.bg;
    final on = Glass.effectiveEnabled;
    final up = StatusInset.of(context);
    final frame = Stack(clipBehavior: Clip.none, children: [
      Positioned(
        top: -up,
        left: 0,
        right: 0,
        bottom: -_extra,
        child: IgnorePointer(
          child: Stack(children: [
            if (on)
              // One blurred rectangle whose strength melts away downward: a
              // gradient mask, no clip paths (stacked clipped layers crashed the
              // raster thread on a Pixel).
              Positioned.fill(
                child: ShaderMask(
                  blendMode: BlendMode.dstIn,
                  shaderCallback: (r) => const LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    stops: [0, 0.5, 1],
                    colors: [Colors.black, Colors.black, Colors.transparent],
                  ).createShader(r),
                  child: BackdropFilter(
                    filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            Positioned.fill(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    // Eased fade: solid at the status bar, gone at the lower edge.
                    // A plain gradient is free to paint; stacked backdrop blurs
                    // crashed the raster thread on a Pixel when a page slid in.
                    stops: const [0, 0.3, 0.55, 0.78, 1],
                    colors: [
                      bg.withValues(alpha: on ? 0.94 : 0.98),
                      bg.withValues(alpha: on ? 0.82 : 0.94),
                      bg.withValues(alpha: on ? 0.5 : 0.8),
                      bg.withValues(alpha: on ? 0.16 : 0.4),
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
    if (anim == null || !Glass.effectiveEnabled || _phone(context))
      return child;
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
