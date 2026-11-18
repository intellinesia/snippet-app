import 'dart:math' as math;
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
  // (how far the layer reaches, blur sigma, shape seed), widest and faintest
  // first so the strongest, smallest layer is painted on top. Each step in
  // sigma is small and each edge differs, so no single outline shows.
  static const List<(double, double, int)> _arches = [
    (1.0, 1.2, 3),
    (0.86, 3.0, 11),
    (0.72, 5.8, 23),
    (0.56, 9.0, 37),
  ];

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
        bottom: 0,
        child: IgnorePointer(
          child: Stack(children: [
            if (on)
              // Two arched clips, not 14 wavy bands (those crashed the raster
              // thread on a Pixel). The arch dips toward the centre pill.
              for (final (reach, sigma, seed) in _arches)
                Positioned.fill(
                  child: ClipPath(
                    clipper: ArchClip(reach, seed),
                    child: BackdropFilter.grouped(
                      filter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
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

/// An uneven arch: its lower edge is a smooth curve through knots that rise and
/// fall by a seeded amount, deepest near the centre pill. Different seeds give
/// different outlines, so stacked layers never trace one visible border.
class ArchClip extends CustomClipper<Path> {
  const ArchClip(this.reach, this.seed);

  final double reach;
  final int seed;

  static const _knots = 7;

  @override
  Path getClip(Size size) {
    final w = size.width, h = size.height * reach;
    final ys = <double>[];
    for (var i = 0; i < _knots; i++) {
      final t = i / (_knots - 1);
      final arch = 0.55 + 0.45 * math.sin(math.pi * t);
      final n = math.sin((seed * 12.9898 + i * 78.233) * 1.7) * 0.5 + 0.5;
      ys.add(h * (arch * (0.82 + 0.18 * n)).clamp(0.2, 1.0));
    }
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w, ys.last);
    // Catmull-Rom through the knots, right to left.
    for (var i = _knots - 1; i > 0; i--) {
      final x0 = w * i / (_knots - 1), x1 = w * (i - 1) / (_knots - 1);
      final y0 = ys[i], y1 = ys[i - 1];
      final yp = i + 1 < _knots ? ys[i + 1] : y0;
      final yn = i - 2 >= 0 ? ys[i - 2] : y1;
      final dx = (x0 - x1) / 3;
      path.cubicTo(
          x0 - dx, y0 + (y1 - yp) / 6, x1 + dx, y1 - (yn - y0) / 6, x1, y1);
    }
    return path..close();
  }

  @override
  bool shouldReclip(ArchClip old) => old.reach != reach || old.seed != seed;
}
