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

  static Color get edgeColor => AppColors.fg1.withValues(
      alpha: ThemeManager.instance.resolved.border.glassEdgeAlpha);
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
    final sigma =
        blur ?? ThemeManager.instance.resolved.translucency.glassBlur;
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
  // (lower edge as a fraction of the height, blur sigma), top band first. Many
  // small steps on wavy edges, so neither the start nor a step reads as a line.
  static final List<(double, double)> _bands = [
    for (var i = 0; i < 14; i++)
      (
        0.34 + 0.66 * (i + 1) / 14,
        0.5 + 10.5 * math.pow(1 - i / 13, 1.6).toDouble(),
      ),
  ];

  @override
  Widget build(BuildContext context) {
    final bg = color ?? AppColors.bg;
    final on = Glass.effectiveEnabled;
    // Test: edge blur off while chasing a raster-thread crash on session open.
    const edgeBlur = false;
    final up = StatusInset.of(context);
    final frame = Stack(clipBehavior: Clip.none, children: [
      Positioned(
        top: -up,
        left: 0,
        right: 0,
        bottom: 0,
        child: IgnorePointer(
          child: Stack(children: [
            if (edgeBlur)
              // Bands share one backdrop read; overlapping stacked blurs cost a
              // full pass each and were the main source of scroll jank.
              Positioned.fill(
                child: Stack(children: [
                  for (var i = 0; i < _bands.length; i++)
                    Positioned.fill(
                      child: ClipPath(
                        clipper: _BandClip(i, _bands),
                        child: BackdropFilter.grouped(
                          filter: ImageFilter.blur(
                              sigmaX: _bands[i].$2, sigmaY: _bands[i].$2),
                          child: const SizedBox.expand(),
                        ),
                      ),
                    ),
                ]),
              ),
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

/// One frost band: the region between the wavy lower edge of the band above
/// and its own. Neighbours share an edge, so bands tile without overlap.
class _BandClip extends CustomClipper<Path> {
  _BandClip(this.index, this.bands);

  final int index;
  final List<(double, double)> bands;

  static const _knot = 32.0;

  // Seeded per edge so the contour is irregular but stable across frames.
  List<double> _knots(int edge, Size size) {
    final h = size.height;
    final frac = bands[edge].$1;
    final amp = h * 0.03;
    final rnd = math.Random(31 + edge * 977);
    final n = (size.width / _knot).ceil() + 1;
    return [
      for (var k = 0; k <= n; k++)
        frac >= 1
            ? h - rnd.nextDouble() * amp * 1.5
            : (h * frac + (rnd.nextDouble() - 0.5) * 2 * amp).clamp(0.0, h),
    ];
  }

  // A smooth curve through the knots: quadratic segments between midpoints.
  static void _curve(Path p, List<double> ys, {required bool reverse}) {
    final pts = [
      for (var k = 0; k < ys.length; k++) Offset(k * _knot, ys[k]),
    ];
    final seq = reverse ? pts.reversed.toList() : pts;
    p.lineTo(seq.first.dx, seq.first.dy);
    for (var k = 1; k < seq.length - 1; k++) {
      final mid = Offset((seq[k].dx + seq[k + 1].dx) / 2,
          (seq[k].dy + seq[k + 1].dy) / 2);
      p.quadraticBezierTo(seq[k].dx, seq[k].dy, mid.dx, mid.dy);
    }
    p.lineTo(seq.last.dx, seq.last.dy);
  }

  @override
  Path getClip(Size size) {
    final path = Path();
    if (index == 0) {
      path.moveTo(0, 0);
      path.lineTo(size.width + _knot, 0);
    } else {
      final top = _knots(index - 1, size);
      path.moveTo(0, top.first);
      _curve(path, top, reverse: false);
    }
    _curve(path, _knots(index, size), reverse: true);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(_BandClip old) => old.index != index;
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
    if (anim == null || !Glass.effectiveEnabled || _phone(context)) return child;
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
