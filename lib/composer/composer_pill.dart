import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../gesture_physics.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import '../mobile_kit.dart' show MkGlass, kAndroidLook;
import '../tap_detector.dart';

/// Round 7 composer tokens, local so the theme file stays with its owner.
abstract final class C7 {
  static Color get row => AppColors.surface3;
  static Color get rowHi => Color.alphaBlend(
      AppColors.fg1.withValues(alpha: 0.07), AppColors.surface3);
  static double get pill => kMobile ? 56 : 52;
  static double get pillRadius => kMobile ? 28 : 26;
  // Board: 44 slots inside the phone field on both platforms.
  static double get btn => kMobile ? 44 : 40;
  static const double ends = 20;
  static const double inner = 4;
  static double get field => kMobile ? 15.5 : 16;
  // Phone spec: 15 on a 21 line; desktop keeps 22.
  static double get line => kMobile ? 21 : 22;
  static const SpringDescription morph =
      SpringDescription(mass: 1, stiffness: 700, damping: 46);
  static const SpringDescription tray =
      SpringDescription(mass: 1, stiffness: 450, damping: 38);
}

enum ComposerAction { mic, send, stop }

/// Mic, send and stop as one button that morphs between them on a spring.
class ComposerMorphButton extends StatefulWidget {
  const ComposerMorphButton({
    super.key,
    required this.action,
    this.enabled = true,
    this.busy = false,
    this.onTap,
    this.onLongPress,
    this.label,
  });

  final ComposerAction action;

  /// Overrides the spoken name, e.g. "Send voice note".
  final String? label;
  final bool enabled;
  final bool busy;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  State<ComposerMorphButton> createState() => _ComposerMorphButtonState();
}

class _ComposerMorphButtonState extends State<ComposerMorphButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _v = AnimationController.unbounded(
      vsync: this, value: widget.action.index.toDouble());

  @override
  void didUpdateWidget(ComposerMorphButton old) {
    super.didUpdateWidget(old);
    final to = widget.action.index.toDouble();
    if (old.action == widget.action) return;
    if (reduceMotion(context)) {
      _v.value = to;
    } else {
      springTo(_v, to, _v.velocity, spring: C7.morph, epsilon: 0.002);
    }
  }

  @override
  void dispose() {
    _v.dispose();
    super.dispose();
  }

  String get _label => switch (widget.action) {
        ComposerAction.mic => 'Record',
        ComposerAction.send => 'Send',
        ComposerAction.stop => 'Stop',
      };

  @override
  Widget build(BuildContext context) {
    final on = widget.enabled && widget.onTap != null;
    return Semantics(
      button: true,
      enabled: on,
      label: widget.label ?? _label,
      child: TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: on
            ? () {
                if (widget.action != ComposerAction.mic) {
                  HapticFeedback.selectionClick();
                }
                widget.onTap!();
              }
            : null,
        onLongPress: on && widget.onLongPress != null
            ? () {
                HapticFeedback.mediumImpact();
                widget.onLongPress!();
              }
            : null,
        child: AnimatedBuilder(
          animation: _v,
          builder: (context, _) => _paint(_v.value, on),
        ),
      ),
    );
  }

  Widget _paint(double v, bool on) {
    double w(int i) => (1 - (v - i).abs()).clamp(0.0, 1.0);
    final mic = w(0), send = w(1), stop = w(2);
    final sendFill = on ? AppColors.accentFill : C7.rowHi;
    final sendInk = on ? AppColors.accentFg : AppColors.fg4;
    final fill = Color.lerp(
        Color.lerp(sendFill.withValues(alpha: 0), sendFill, send)!,
        AppColors.fg1,
        stop)!;
    final ink = Color.lerp(
        Color.lerp(AppColors.fg2, sendInk, send)!, AppColors.bg, stop)!;
    return Container(
      width: C7.btn,
      height: C7.btn,
      decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
      child: Stack(alignment: Alignment.center, children: [
        if (mic > 0)
          Opacity(
            opacity: mic,
            child: Transform.scale(
                scale: 0.6 + 0.4 * mic,
                child: AppIcon('mic', size: 22, color: AppColors.fg2)),
          ),
        if (send > 0)
          Opacity(
            opacity: send,
            child: Transform.rotate(
              angle: (v - 1) * math.pi / 2,
              child: Transform.scale(
                scale: 0.6 + 0.4 * send,
                child: widget.busy
                    ? Spinner(size: 16, color: ink)
                    : AppIcon('arrow-up', size: 19, color: ink),
              ),
            ),
          ),
        if (stop > 0)
          Opacity(
            opacity: stop,
            child: Transform.scale(
              scale: 0.4 + 0.6 * stop,
              child: Container(
                width: 12,
                height: 12,
                decoration: BoxDecoration(
                  color: ink,
                  borderRadius: BorderRadius.circular(7 + (3 - 7) * stop),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// A bare 40px circular icon button, the pill's plus and mic.
class ComposerBareButton extends StatelessWidget {
  const ComposerBareButton(this.icon,
      {super.key,
      required this.label,
      required this.onTap,
      this.color,
      this.fill,
      this.size = 22});

  final String icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;
  final Color? fill;
  final double size;

  @override
  Widget build(BuildContext context) {
    final w = Semantics(
      button: true,
      label: label,
      child: Material(
        color: fill ?? Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: () {
            tapHaptic();
            onTap();
          },
          child: SizedBox.square(
            dimension: C7.btn,
            child: Center(
                child:
                    AppIcon(icon, size: size, color: color ?? AppColors.fg2)),
          ),
        ),
      ),
    );
    return kMobile ? w : Tooltip(message: label, child: w);
  }
}

/// The flat Duet pill every composer state sits in.
class ComposerPillSurface extends StatelessWidget {
  const ComposerPillSurface(
      {super.key,
      required this.child,
      this.highlight = false,
      this.fill,
      this.radius});

  final Widget child;
  final bool highlight;
  final Color? fill;
  final double? radius;

  @override
  Widget build(BuildContext context) {
    // Board: a 56 glass capsule on iPhone; a 52 filled s3 field on Android.
    if (kMobile && fill == null && !highlight) {
      final r = radius ?? (kAndroidLook ? 26.0 : C7.pillRadius);
      final body = Container(
        constraints: BoxConstraints(minHeight: kAndroidLook ? 52 : 56),
        padding:
            EdgeInsets.symmetric(horizontal: 6, vertical: kAndroidLook ? 2 : 6),
        child: child,
      );
      return kAndroidLook
          ? DecoratedBox(
              decoration: BoxDecoration(
                  color: AppColors.surface3,
                  borderRadius: BorderRadius.circular(r)),
              child: body)
          : MkGlass(radius: r, child: body);
    }
    return Container(
      constraints: BoxConstraints(minHeight: C7.pill),
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: fill ?? (kMobile ? AppColors.surface2 : C7.row),
        borderRadius: BorderRadius.circular(radius ?? C7.pillRadius),
        border:
            highlight ? Border.all(color: AppColors.accent, width: 1.5) : null,
      ),
      child: child,
    );
  }
}

/// Voice in the pill: discard, timer, wave, then stop or send.
class ComposerVoicePill extends StatelessWidget {
  const ComposerVoicePill({
    super.key,
    required this.recording,
    required this.time,
    required this.wave,
    required this.playing,
    required this.onDiscard,
    required this.onPlay,
    required this.onStop,
    required this.onSend,
    this.sending = false,
    this.onSeek,
    this.onMore,
  });

  final bool recording;
  final String time;
  final Widget wave;
  final bool playing;
  final bool sending;
  final VoidCallback onDiscard;
  final VoidCallback onPlay;
  final VoidCallback onStop;
  final VoidCallback onSend;
  final ValueChanged<double>? onSeek;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final bar = SizedBox(
      height: 28,
      child: recording && kMobile
          ? Stack(alignment: Alignment.center, children: [
              Positioned.fill(child: wave),
              IgnorePointer(
                child: Text('Slide to cancel',
                    style: sans(13, height: 18 / 13, color: AppColors.fg2)),
              ),
            ])
          : wave,
    );
    Widget track = bar;
    if (!recording && onSeek != null) {
      // Wraps [bar], not [track]: the builder runs later, when track is this
      // LayoutBuilder itself, which recursed until the stack overflowed.
      track = LayoutBuilder(
        builder: (_, c) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) =>
              onSeek!((d.localPosition.dx / c.maxWidth).clamp(0.0, 1.0)),
          onHorizontalDragUpdate: (d) =>
              onSeek!((d.localPosition.dx / c.maxWidth).clamp(0.0, 1.0)),
          child: SizedBox(height: C7.btn, child: Center(child: bar)),
        ),
      );
    }
    final timer = Row(mainAxisSize: MainAxisSize.min, children: [
      // Phone spec CH-09: no red anywhere; the timer alone says it is live.
      if (recording) ...[
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
              color: kMobile ? AppColors.fg1 : AppColors.danger,
              shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
      ],
      Text(time,
          style: sans(kMobile ? 15 : 14,
              weight: kMobile ? FontWeight.w500 : null,
              tabular: true,
              color: recording ? AppColors.fg1 : AppColors.fg3)),
    ]);
    return ComposerPillSurface(
      fill: kMobile ? AppColors.surface1 : null,
      radius: kMobile ? 24 : null,
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        ComposerBareButton('x', label: 'Discard', onTap: onDiscard),
        if (!recording)
          ComposerBareButton(playing ? 'pause' : 'play',
              label: playing ? 'Pause' : 'Play',
              onTap: onPlay,
              color: AppColors.fg1,
              size: 18),
        if (recording)
          Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4), child: timer),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: track,
          ),
        ),
        if (!recording)
          Padding(padding: const EdgeInsets.only(right: 4), child: timer),
        if (recording)
          ComposerBareButton('pause',
              label: 'Stop and review', onTap: onStop, size: 18)
        else if (onMore != null)
          ComposerBareButton('mic', label: 'Record more', onTap: onMore!),
        const SizedBox(width: 4),
        ComposerMorphButton(
          action: ComposerAction.send,
          label: 'Send voice note',
          busy: sending,
          enabled: !sending,
          onTap: onSend,
        ),
      ]),
    );
  }
}

/// A Duet group: rows on their own surface, 2px apart, rounder at the ends.
class ComposerGroup extends StatelessWidget {
  const ComposerGroup({super.key, required this.children, this.ends = C7.ends});

  final List<Widget> children;
  final double ends;

  @override
  Widget build(BuildContext context) {
    final n = children.length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < n; i++) ...[
          if (i > 0) const SizedBox(height: 2),
          ClipRRect(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(i == 0 ? ends : C7.inner),
              bottom: Radius.circular(i == n - 1 ? ends : C7.inner),
            ),
            child: children[i],
          ),
        ],
      ],
    );
  }
}
