import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:progressive_background_blur/progressive_background_blur.dart';

import 'theme.dart';
import 'mobile_kit.dart' show MkThreadCap;

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
  const StatusInset(
      {super.key, required this.top, this.bottom = 0, required super.child});

  final double top;

  /// The bottom inset the host's SafeArea consumed; 0 when it left it.
  final double bottom;

  static double of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StatusInset>()?.top ?? 0;

  static double bottomOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<StatusInset>()?.bottom ?? 0;

  /// Lays [child] out as if the host had not consumed the status bar: it
  /// reaches up behind it and sees that height as its own top padding.
  static Widget reclaim(BuildContext context, Widget child) {
    final mq = MediaQuery.of(context);
    final eaten = mq.padding.top > 0 ? 0.0 : of(context);
    if (eaten == 0) return child;
    return Stack(clipBehavior: Clip.none, children: [
      Positioned(
        top: -eaten,
        left: 0,
        right: 0,
        bottom: 0,
        child: MediaQuery(
          data: mq.copyWith(padding: mq.padding.copyWith(top: eaten)),
          child: StatusInset(
              top: 0, bottom: bottomOf(context), child: child),
        ),
      ),
    ]);
  }

  /// For a page: its own top padding, or the inset its host passes down
  /// when the page sits under the host's SafeArea.
  static double page(BuildContext context) {
    final pad = MediaQuery.paddingOf(context).top;
    return pad > 0 ? pad : of(context);
  }

  @override
  bool updateShouldNotify(StatusInset oldWidget) =>
      top != oldWidget.top || bottom != oldWidget.bottom;
}

/// The frosted strip a chat header floats on; the transcript scrolls under it.
class GlassTopFrame extends StatelessWidget {
  const GlassTopFrame(
      {super.key, required this.child, this.color, this.thread = false});

  /// Phone chat: the header layer ends where the rounded thread begins.
  final bool thread;

  final Widget child;
  final Color? color;

  /// Room the transcript leaves at its top so the newest-first scroll can
  /// still reach the oldest row from under the header.
  static const double inset = 52;
  static const double fade = 12;

  static final ValueNotifier<int> _settled = ValueNotifier(0);

  /// Call when a page that may hold a header stops moving.
  static void reflow() => _settled.value++;

  @override
  Widget build(BuildContext context) {
    final bg = color ?? AppColors.bg;
    final up = StatusInset.of(context);
    // Quiet v10: the status bar and header sit on solid ground, no blur;
    // a 24pt eased fade on the content side is the only transition.
    final frame = Stack(clipBehavior: Clip.none, children: [
      if (thread)
        Positioned(
          top: -up,
          left: 0,
          right: 0,
          bottom: fade - MkThreadCap.reach,
          child: IgnorePointer(child: MkThreadCap.paint(bg)),
        )
      else
        Positioned(
          top: -up,
          left: 0,
          right: 0,
          bottom: -(24 - fade),
          child: IgnorePointer(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(child: ColoredBox(color: bg)),
                  Container(
                    height: 24,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        stops: const [0, 0.5, 1],
                        colors: [
                          bg,
                          bg.withValues(alpha: 0.6),
                          bg.withValues(alpha: 0),
                        ],
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

/// The blur reads its screen position only when it paints, and a sliding
/// page does not repaint it, so rebuild it fresh whenever a page settles.
class _SettledBlur extends StatefulWidget {
  const _SettledBlur({required this.sigma});
  final double sigma;

  @override
  State<_SettledBlur> createState() => _SettledBlurState();
}

class _SettledBlurState extends State<_SettledBlur> {
  int _gen = 0;
  Animation<double>? _route;

  @override
  void initState() {
    super.initState();
    GlassTopFrame._settled.addListener(_bump);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final a = ModalRoute.of(context)?.animation;
    if (a == _route) return;
    _route?.removeStatusListener(_onStatus);
    _route = a?..addStatusListener(_onStatus);
  }

  void _onStatus(AnimationStatus s) {
    if (s == AnimationStatus.completed) _bump();
  }

  void _bump() {
    if (mounted) setState(() => _gen++);
  }

  @override
  void dispose() {
    _route?.removeStatusListener(_onStatus);
    GlassTopFrame._settled.removeListener(_bump);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ProgressiveBlur(
      key: ValueKey(_gen),
      begin: const Alignment(0, 0.45),
      end: Alignment.bottomCenter,
      sigmaStart: widget.sigma,
      sigmaEnd: 0);
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
    if (anim == null || !Glass.effectiveEnabled || _phone(context)) {
      return child;
    }
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
