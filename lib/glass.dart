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
  // first so the strongest, smallest layer is painted on top. Each edge is a
  // different big irregular outline, so no single border shows.
  static const List<(double, double, int)> _arches = [
    (1.0, 1.0, 3),
    (0.88, 2.6, 11),
    (0.74, 5.0, 23),
    (0.58, 8.5, 37),
  ];

  /// How far the blurred area runs below the header strip, in logical pixels.
  static const double _extra = 44;

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

/// A big irregular blob edge: many uneven lobes along the bottom, deepest near
/// the centre pill, plus a few loose droplets just below. Each seed draws a
/// different outline, so stacked layers never trace one visible border.
class ArchClip extends CustomClipper<Path> {
  const ArchClip(this.reach, this.seed);

  final double reach;
  final int seed;

  static const _knots = 13;

  double _rnd(int i, int salt) =>
      (math.sin((seed * 12.9898 + i * 78.233 + salt * 37.719) * 1.7) *
              43758.5453)
          .abs() %
      1.0;

  @override
  Path getClip(Size size) {
    final w = size.width, h = size.height * reach;
    final xs = <double>[], ys = <double>[];
    for (var i = 0; i < _knots; i++) {
      final t = i / (_knots - 1);
      final arch = 0.62 + 0.38 * math.sin(math.pi * t);
      xs.add(w * t +
          (i == 0 || i == _knots - 1 ? 0 : (_rnd(i, 1) - 0.5) * w * 0.05));
      ys.add(h * arch * (0.5 + 0.5 * _rnd(i, 2)));
    }
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(xs.last, ys.last);
    // Rounded lobes: quadratic through the midpoints, knots as the controls.
    for (var i = _knots - 1; i > 0; i--) {
      final mx = (xs[i] + xs[i - 1]) / 2, my = (ys[i] + ys[i - 1]) / 2;
      path.quadraticBezierTo(xs[i], ys[i], mx, my);
    }
    path.lineTo(xs.first, ys.first);
    path.close();
    // Loose droplets under the edge.
    for (var k = 0; k < 7; k++) {
      final x = w * (0.06 + 0.88 * _rnd(k, 3));
      final r = 5 + 9 * _rnd(k, 4);
      final yEdge = ys[(x / w * (_knots - 1)).round().clamp(0, _knots - 1)];
      path.addOval(Rect.fromCircle(
          center: Offset(x, yEdge + r * (0.3 + 1.1 * _rnd(k, 5))), radius: r));
    }
    return path;
  }

  @override
  bool shouldReclip(ArchClip old) => old.reach != reach || old.seed != seed;
}
