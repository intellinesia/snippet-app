import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../ambient/ambient_model.dart';
import '../../../ambient/live_caption.dart';
import '../../../ambient/controller.dart';
import '../../../ambient/voice.dart';
import '../../../api.dart';
import '../../../swr.dart';
import '../../../gesture_physics.dart';
import '../../../models.dart';
import '../../../platform.dart';
import '../../../settings_form.dart';
import '../../../theme.dart';
import '../../../widgets.dart';
import '../../mobile_voice_page.dart';

final ValueNotifier<AmbientStateEvent?> _emptyAmbientState = ValueNotifier(null);

/// The words being heard right now (or the last finished utterance) under the status line.
class AmbientHeardLine extends StatelessWidget {
  const AmbientHeardLine({super.key, required this.wide, this.feed});

  final bool wide;
  final LiveCaptionFeed? feed;

  @override
  Widget build(BuildContext context) {
    final f = feed ?? LiveCaptionFeed.instance;
    final motion =
        reduceMotion(context) ? Duration.zero : Motion.fast;
    return AnimatedSize(
      duration: motion,
      child: ValueListenableBuilder<String?>(
        valueListenable: f.text,
        builder: (context, live, _) =>
            ValueListenableBuilder<String?>(
          valueListenable: f.lastFinal,
          builder: (context, last, _) {
            final shown = live ?? last;
            return AnimatedSwitcher(
              duration: motion,
              child: shown == null
                  ? const SizedBox.shrink(key: ValueKey('none'))
                  : Text(
                      '\u201C$shown\u201D',
                      key: ValueKey(shown),
                      textAlign:
                          wide ? TextAlign.start : TextAlign.center,
                      maxLines: wide ? 2 : 3,
                      overflow: TextOverflow.ellipsis,
                      style: sans(wide ? 13 : 16,
                          color: live != null
                              ? AppColors.fg1
                              : AppColors.fg2),
                    ),
            );
          },
        ),
      ),
    );
  }
}

class _OrbDots {
  _OrbDots(this.x, this.y, this.size, this.alpha, this.depth);
  final Float32List x, y, size, alpha, depth;

  int get length => x.length;

  static final Map<(int, bool, bool), _OrbDots> _cache = {};

  static _OrbDots of(double shortestSide, bool alive, bool blink) =>
      _cache.putIfAbsent((shortestSide.round(), alive, blink), () => _build(shortestSide, alive, blink));

  static _OrbDots _build(double shortestSide, bool alive, bool blink) {
    final radius = shortestSide / 2 * 0.9;
    final step = math.max(shortestSide / 40, 2.3);
    final eyeH = blink ? 0.18 : 1.0;
    final eyes = [Offset(-radius * 0.34, radius * 0.06), Offset(radius * 0.34, radius * 0.06)];
    final eyeRx = radius * 0.085, eyeRy = radius * 0.13 * eyeH;
    final xs = <double>[], ys = <double>[], sizes = <double>[], alphas = <double>[], depths = <double>[];
    final rows = (radius * 2 / step).ceil() + 2;
    for (var j = 0; j < rows; j++) {
      final y = -radius + j * step * 0.866;
      final ox = (j % 2) * step / 2;
      for (var x = -radius - step + ox; x <= radius + step; x += step) {
        final d = math.sqrt(x * x + y * y) / radius;
        if (d > 1) continue;
        var skip = false;
        for (final e in eyes) {
          final ex = (x - e.dx) / eyeRx, ey = (y - e.dy) / math.max(eyeRy, 0.01);
          if (ex * ex + ey * ey < 1) skip = true;
        }
        if (!alive && (y - eyes[0].dy).abs() < step * 0.5) {
          for (final e in eyes) {
            if ((x - e.dx).abs() < eyeRx * 1.4) skip = true;
          }
        }
        if (skip) continue;
        final nx = x / radius, ny = y / radius;
        final z = math.sqrt(math.max(0.0, 1 - nx * nx - ny * ny));
        final light = (nx * -0.38 + ny * -0.5 + z * 0.78).clamp(0.0, 1.0);
        xs.add(x);
        ys.add(y);
        sizes.add(step * (0.2 + 0.66 * light) * (1 - math.pow(d, 8) * 0.45));
        alphas.add(alive ? 0.55 + 0.45 * light : 0.22 + 0.25 * light);
        depths.add(d);
      }
    }
    return _OrbDots(Float32List.fromList(xs), Float32List.fromList(ys), Float32List.fromList(sizes),
        Float32List.fromList(alphas), Float32List.fromList(depths));
  }
}

class _OrbPainter extends CustomPainter {
  _OrbPainter(this.t, this.level, this.color, this.alive);
  final double t;
  final double level;
  final Color color;
  final bool alive;

  @override
  void paint(Canvas canvas, Size size) {
    final r = size.shortestSide / 2;
    final c = size.center(Offset.zero);
    final tau = math.pi * 2;
    if (alive) {
      canvas.drawCircle(
          c,
          r,
          Paint()
            ..shader = RadialGradient(colors: [
              color.withValues(alpha: 0.16 + level * 0.1),
              color.withValues(alpha: 0),
            ]).createShader(Rect.fromCircle(center: c, radius: r)));
    }
    final dots = _OrbDots.of(size.shortestSide, alive, alive && t > 0.86 && t < 0.92);
    final amp = alive ? 0.12 + level * 0.22 : 0.0;
    final rgb = color.toARGB32() & 0xFFFFFF;
    final paint = Paint();
    canvas.save();
    canvas.translate(c.dx, c.dy);
    canvas.scale(alive ? 1 + math.sin(t * tau) * 0.025 : 1.0);
    for (var i = 0; i < dots.length; i++) {
      var s = dots.size[i].toDouble();
      var a = dots.alpha[i].toDouble();
      if (alive) {
        final w = math.sin((dots.depth[i] * 2.0 - t * 2) * tau);
        s *= 1 + amp * w;
        a = (a + w * 0.12).clamp(0.2, 1.0);
      }
      paint.color = Color(((a * 255).round() << 24) | rgb);
      canvas.drawCircle(Offset(dots.x[i], dots.y[i]), math.max(s / 2, 0.3), paint);
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _OrbPainter old) =>
      old.t != t || old.level != level || old.color != color || old.alive != alive;
}

class _Orb extends StatefulWidget {
  const _Orb(
      {required this.size,
      required this.color,
      required this.alive,
      required this.level,
      this.period = const Duration(milliseconds: 3200)});
  final double size;
  final Color color;
  final bool alive;
  final double level;
  final Duration period;

  @override
  State<_Orb> createState() => _OrbState();
}

class _OrbState extends State<_Orb> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: widget.period);

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final animate = widget.alive && !reduce;
    if (animate && !_c.isAnimating) _c.repeat();
    if (!animate && _c.isAnimating) _c.stop();
    final frames = widget.period.inMilliseconds * 30 / 1000;
    return RepaintBoundary(
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => CustomPaint(
          size: Size.square(widget.size),
          painter: _OrbPainter((_c.value * frames).floor() / frames, widget.level, widget.color, widget.alive),
        ),
      ),
    );
  }
}

class AmbientHeaderOrb extends StatefulWidget {
  const AmbientHeaderOrb({super.key, required this.client, this.size = 38});
  final DaemonClient client;
  final double size;

  @override
  State<AmbientHeaderOrb> createState() => _AmbientHeaderOrbState();
}

class _AmbientHeaderOrbState extends State<AmbientHeaderOrb> {
  late final AmbientModel _m = AmbientModel(widget.client)
    ..addListener(_changed);

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _m.removeListener(_changed);
    _m.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final color = ambientStateColor(_m.settings, _m.status);
    return Semantics(
      button: true,
      label: 'Ambient listening',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => kMobile
            ? openMobileVoicePage(context, client: widget.client)
            : showAmbientStage(context, widget.client),
        onLongPress: () {
          if (_m.settings == null) return;
          HapticFeedback.mediumImpact();
          _m.press();
        },
        onHorizontalDragEnd: (d) {
          final v = d.primaryVelocity ?? 0;
          if (v.abs() < 150) return;
          HapticFeedback.selectionClick();
          _m.shiftMode(v < 0 ? 1 : -1);
        },
        child: SizedBox(
          width: widget.size + 6,
          height: widget.size + 6,
          child: Center(
            child: _Orb(
              size: widget.size,
              color: color,
              alive: _m.listening,
              level: _m.status.speaking ? 1 : 0,
              period: const Duration(milliseconds: 2400),
            ),
          ),
        ),
      ),
    );
  }
}

Future<void> showAmbientStage(BuildContext context, DaemonClient client) {
  Rect? anchor;
  if (!kMobile) {
    final ro = context.findRenderObject();
    if (ro is RenderBox && ro.hasSize) {
      anchor = ro.localToGlobal(Offset.zero) & ro.size;
    }
  }
  return Navigator.of(context, rootNavigator: true).push(PageRouteBuilder<void>(
    opaque: false,
    transitionDuration: Motion.open,
    reverseTransitionDuration: Motion.close,
    pageBuilder: (_, animation, __) =>
        AmbientStage(client: client, animation: animation, anchor: anchor),
  ));
}

class AmbientStage extends StatefulWidget {
  const AmbientStage({
    super.key,
    required this.client,
    required this.animation,
    this.anchor,
  });
  final DaemonClient client;
  final Animation<double> animation;
  final Rect? anchor;

  @override
  State<AmbientStage> createState() => _AmbientStageState();
}

class _AmbientStageState extends State<AmbientStage>
    with SingleTickerProviderStateMixin {
  late final AmbientModel _m = AmbientModel(widget.client)
    ..addListener(_changed);
  late final CurvedAnimation _a = CurvedAnimation(
      parent: widget.animation, curve: Motion.enter, reverseCurve: Motion.exit);
  List<AmbientEvent> _recent = const [];
  Revalidator? _recentLive;
  late final AnimationController _dragC =
      AnimationController.unbounded(vsync: this)..addListener(_changed);
  double get _drag => _dragC.value;

  @override
  void initState() {
    super.initState();
    _loadRecent();
    _recentLive = Revalidator(
        client: widget.client,
        on: (e) => (e['kind'] as String? ?? '').startsWith('ambient_'),
        debounce: const Duration(seconds: 2),
        onRevalidate: ({required bool force}) => _loadRecent());
  }

  Future<void> _loadRecent() async {
    try {
      final events = await widget.client.ambientEvents(limit: 16);
      if (!mounted) return;
      setState(() => _recent = filterAmbientEvents(events).take(3).toList());
    } catch (_) {}
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _recentLive?.dispose();
    _dragC.dispose();
    _m.removeListener(_changed);
    _m.dispose();
    _a.dispose();
    super.dispose();
  }

  void _close() => Navigator.of(context).maybePop();

  String get _mode => _m.settings?.shownMode ?? 'passive';
  bool get _live => _m.on && _m.listening;
  bool get _canToggle => !kIsWeb && _m.settings != null && !_m.busy;

  void _toggle() {
    if (!_canToggle) return;
    HapticFeedback.mediumImpact();
    _m.press();
  }

  void _setMode(String mode) {
    if (_mode == mode) return;
    HapticFeedback.selectionClick();
    _m.setMode(mode);
  }

  String _caption(AmbientStateEvent? event) => ambientStatusText(
        settings: _m.settings,
        status: _m.status,
        event: event,
        elsewhere: _m.elsewhere,
        busy: _m.busy,
        liveOverride: _live,
      );

  String _ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }

  Widget _statusText({required double fontSize, TextAlign? align}) =>
      ValueListenableBuilder<AmbientVoice?>(
        valueListenable: AmbientController.instance.voice,
        builder: (context, voice, _) =>
            ValueListenableBuilder<AmbientStateEvent?>(
          valueListenable: voice?.state ?? _emptyAmbientState,
          builder: (context, event, _) => Text(
            _caption(event),
            textAlign: align,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: sans(fontSize,
                weight: W.label, color: _live ? AppColors.fg1 : AppColors.fg3),
          ),
        ),
      );

  Widget _toggleControl() => _m.elsewhere
      ? Btn('Take over',
          small: true,
          variant: BtnVariant.secondary,
          disabled: !_canToggle,
          onTap: _canToggle ? _toggle : null)
      : SettingsSwitch(
          value: _live,
          onChanged: _canToggle ? (_) => _toggle() : null,
        );

  Widget _modePills() => Pills<String>(
        items: const [
          ('passive', 'Passive'),
          ('active', 'Active'),
        ],
        selected: _mode,
        onSelect: _setMode,
      );

  Widget _panel(bool wide, double orb) {
    final err = _m.error ?? _m.status.error;
    final color = ambientStateColor(_m.settings, _m.status);
    final popover = wide && widget.anchor != null;
    final orbWidget = Semantics(
      button: true,
      label: _live ? 'Stop listening' : 'Start listening',
      child: GestureDetector(
        onTap: _canToggle ? _toggle : null,
        onLongPress: _canToggle ? _toggle : null,
        child: _Orb(
          size: orb,
          color: color,
          alive: _live,
          level: _live && (_m.status.speaking || _m.status.assistantSpeaking)
              ? 1
              : 0,
        ),
      ),
    );
    return Container(
      width: popover ? 296 : (wide ? 312 : double.infinity),
      padding: wide
          ? const EdgeInsets.fromLTRB(14, 12, 14, 12)
          : const EdgeInsets.fromLTRB(20, 10, 20, 22),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(wide ? R.lg : 22),
        border: Border.all(color: AppColors.border),
        boxShadow: overlayShadow,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (wide) ...[
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                orbWidget,
                const SizedBox(width: 10),
                Expanded(child: _statusText(fontSize: 13)),
                const SizedBox(width: 8),
                _toggleControl(),
              ],
            ),
            AmbientHeardLine(wide: true),
            const SizedBox(height: 10),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text('Mode', style: sans(12, color: AppColors.fg3)),
                const Spacer(),
                _modePills(),
              ],
            ),
          ] else ...[
            Center(
              child: Container(
                width: 36,
                height: 4,
                margin: const EdgeInsets.only(bottom: 18),
                decoration: BoxDecoration(
                  color: AppColors.border2,
                  borderRadius: BorderRadius.circular(R.pill),
                ),
              ),
            ),
            Center(child: orbWidget),
            const SizedBox(height: 12),
            _statusText(fontSize: 15, align: TextAlign.center),
            AmbientHeardLine(wide: false),
            const SizedBox(height: 20),
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                _modePills(),
                const Spacer(),
                _toggleControl(),
              ],
            ),
          ],
          if (err != null && !kIsWeb) ...[
            const SizedBox(height: 10),
            NoteLine(err, error: true),
          ],
          if (_recent.isNotEmpty) ...[
            SizedBox(height: wide ? 10 : 14),
            Divider(height: 1, thickness: 1, color: AppColors.line),
            SizedBox(height: wide ? 6 : 8),
            for (final e in _recent)
              Padding(
                padding: EdgeInsets.symmetric(vertical: wide ? 3.5 : 5),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(e.text.trim(),
                          maxLines: wide ? 1 : 2,
                          overflow: TextOverflow.ellipsis,
                          style: sans(wide ? 12 : 13,
                              height: 1.35, color: AppColors.fg2)),
                    ),
                    const SizedBox(width: 10),
                    Text(_ago(e.startedAt),
                        style: mono(11, color: AppColors.fg4)),
                  ],
                ),
              ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    final wide = size.width >= 720;
    final anchor = wide ? widget.anchor : null;
    final still = reduceMotion(context);
    final orb = wide ? 38.0 : 116.0;
    final panel = ConstrainedBox(
      constraints: BoxConstraints(
        maxHeight: anchor != null
            ? (size.height - anchor.bottom - 24).clamp(260.0, size.height * 0.86)
            : size.height * 0.92,
      ),
      child: SingleChildScrollView(child: _panel(wide, orb)),
    );
    final Widget placed = anchor != null
        ? Builder(builder: (_) {
            const width = 296.0;
            final left =
                (anchor.center.dx - width + 24).clamp(12.0, size.width - width - 12);
            final top = (anchor.bottom + 8).clamp(12.0, size.height - 320.0);
            final alignX =
                (((anchor.center.dx - left) / width) * 2 - 1).clamp(-0.9, 0.9);
            return Stack(children: [
              Positioned(
                left: left,
                top: top,
                child: FadeTransition(
                  opacity: _a,
                  child: still
                      ? panel
                      : ScaleTransition(
                          alignment: Alignment(alignX, -1.0),
                          scale: Tween(begin: 0.94, end: 1.0).animate(_a),
                          child: panel),
                ),
              ),
            ]);
          })
        : wide
            ? Center(
                child: FadeTransition(
                  opacity: _a,
                  child: still
                      ? panel
                      : ScaleTransition(
                          scale: Tween(begin: 0.96, end: 1.0).animate(_a),
                          child: panel),
                ),
              )
            : Align(
            alignment: Alignment.bottomCenter,
            child: AnimatedBuilder(
              animation: _a,
              builder: (_, child) => Opacity(
                opacity: still ? _a.value : 1,
                child: Transform.translate(
                  offset: Offset(0, (still ? 0 : (1 - _a.value) * 360) + _drag),
                  child: child,
                ),
              ),
              child: GestureDetector(
                onVerticalDragStart: (_) => _dragC.stop(),
                onVerticalDragUpdate: (d) {
                  final y = _dragC.value + d.delta.dy;
                  _dragC.value = y >= 0 ? y : y * .25;
                },
                onVerticalDragEnd: (d) {
                  final v = d.primaryVelocity ?? 0;
                  if (dragDismisses(
                      distance: _drag,
                      velocity: v,
                      distanceThreshold: 90,
                      velocityThreshold: 700)) {
                    HapticFeedback.lightImpact();
                    _close();
                    springTo(_dragC, _drag + 360, math.max(v, 0));
                  } else {
                    springTo(_dragC, 0, v);
                  }
                },
                onVerticalDragCancel: () => springTo(_dragC, 0, 0),
                child: SafeArea(
                  top: false,
                  minimum: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: panel,
                ),
              ),
            ),
          );
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _close,
        const SingleActivator(LogicalKeyboardKey.space): _toggle,
        const SingleActivator(LogicalKeyboardKey.arrowLeft): () =>
            _setMode('passive'),
        const SingleActivator(LogicalKeyboardKey.arrowRight): () =>
            _setMode('active'),
      },
      child: Focus(
        autofocus: true,
        child: Material(
          type: MaterialType.transparency,
          child: Stack(children: [
            Positioned.fill(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _close,
                child: AnimatedBuilder(
                  animation: Listenable.merge([_a, _dragC]),
                  builder: (_, __) {
                    final lift = (1 - _drag.clamp(0.0, 400.0) / 400);
                    final v = _a.value.clamp(0.0, 1.0) * lift;
                    if (anchor != null) {
                      return ColoredBox(
                          color: Colors.black.withValues(alpha: 0.14 * v));
                    }
                    return BackdropFilter(
                      filter: ui.ImageFilter.blur(sigmaX: 14 * v, sigmaY: 14 * v),
                      child: ColoredBox(
                          color: Colors.black.withValues(alpha: 0.4 * v)),
                    );
                  },
                ),
              ),
            ),
            placed,
          ]),
        ),
      ),
    );
  }
}
