import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ambient/ambient_model.dart';
import '../ambient/live_caption.dart';
import '../ambient/controller.dart';
import '../ambient/voice.dart';
import '../api.dart';
import '../media_views.dart';
import '../mochi.dart';
import '../models.dart';
import '../swr.dart';
import '../theme.dart';
import '../widgets.dart';
import 'mobile_chrome.dart';

final ValueNotifier<AmbientStateEvent?> _emptyVoiceState = ValueNotifier(null);

/// Opens Voice, first turning ambient on and starting to listen on this phone
/// when it is off.
Future<void> startMobileVoice(BuildContext context, DaemonClient client) async {
  if (AmbientController.instance.running) {
    return openMobileVoicePage(context, client: client);
  }
  final m = AmbientModel(client);
  try {
    await m.load();
    await m.press();
    final err = m.error;
    if (!context.mounted) return;
    if (err != null) {
      toast(context, err);
      return;
    }
    await openMobileVoicePage(context, client: client);
  } finally {
    m.dispose();
  }
}

Future<void> openMobileVoicePage(
  BuildContext context, {
  DaemonClient? client,
  AmbientControl? controller,
}) {
  final resolved =
      client ?? DaemonScope.maybeOf(context) ?? DaemonScope.current;
  return Navigator.of(context).push<void>(PageRouteBuilder<void>(
    transitionDuration: Motion.page,
    reverseTransitionDuration: Motion.close,
    pageBuilder: (_, __, ___) => MobileVoicePage(
      client: resolved,
      controller: controller,
    ),
    transitionsBuilder: (context, animation, __, child) {
      if (reduceMotion(context)) {
        return FadeTransition(opacity: animation, child: child);
      }
      final curved = CurvedAnimation(
        parent: animation,
        curve: Motion.enter,
        reverseCurve: Motion.exit,
      );
      return SlideTransition(
        position: Tween<Offset>(
          begin: const Offset(0, 1),
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
    },
  ));
}

class MobileVoicePage extends StatefulWidget {
  const MobileVoicePage({
    super.key,
    this.client,
    this.controller,
    this.initialSettings,
    this.initialEvents,
    this.replyText,
    this.onChat,
  });

  final DaemonClient? client;
  final AmbientControl? controller;
  final AmbientSettings? initialSettings;
  final List<AmbientEvent>? initialEvents;
  final String? replyText;
  final VoidCallback? onChat;

  @override
  State<MobileVoicePage> createState() => _MobileVoicePageState();
}

class _MobileVoicePageState extends State<MobileVoicePage>
    with SingleTickerProviderStateMixin {
  late final AmbientModel _m = AmbientModel(
    widget.client,
    ambient: widget.controller,
    initialSettings: widget.initialSettings,
  )..addListener(_changed);
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(seconds: 2),
  );
  late List<AmbientEvent> _recent = widget.initialEvents != null
      ? filterAmbientEvents(widget.initialEvents!)
      : const [];
  Revalidator? _recentLive;
  bool _ending = false;

  @override
  void initState() {
    super.initState();
    LiveCaptionFeed.instance.text.addListener(_feedChanged);
    LiveCaptionFeed.instance.lastFinal.addListener(_feedChanged);
    final c = widget.client;
    if (c != null) {
      _loadRecent();
      _recentLive = Revalidator(
        client: c,
        on: (e) => (e['kind'] as String? ?? '').startsWith('ambient_'),
        debounce: const Duration(seconds: 2),
        onRevalidate: ({required bool force}) => _loadRecent(),
      );
    }
  }

  Future<void> _loadRecent() async {
    final c = widget.client;
    if (c == null) return;
    try {
      final events = await c.ambientEvents(limit: 16);
      if (!mounted) return;
      setState(() => _recent = filterAmbientEvents(events));
    } catch (_) {}
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  void _feedChanged() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    LiveCaptionFeed.instance.text.removeListener(_feedChanged);
    LiveCaptionFeed.instance.lastFinal.removeListener(_feedChanged);
    _tick?.cancel();
    _recentLive?.dispose();
    _pulse.dispose();
    _m.removeListener(_changed);
    _m.dispose();
    super.dispose();
  }

  Future<void> _end() async {
    if (_ending) return;
    _ending = true;
    HapticFeedback.mediumImpact();
    await _m.ambient.stop();
    if (mounted) Navigator.of(context).maybePop();
  }

  void _pop() {
    Navigator.of(context).maybePop();
  }

  Widget _stateBuilder(
    BuildContext context,
    Widget Function(BuildContext, AmbientStateEvent?) builder,
  ) {
    final direct = _m.ambient.stateListenable;
    if (direct != null) {
      return ValueListenableBuilder<AmbientStateEvent?>(
        valueListenable: direct,
        builder: (context, event, _) => builder(context, event),
      );
    }
    return ValueListenableBuilder<AmbientVoice?>(
      valueListenable: _m.ambient.voice,
      builder: (context, voice, _) => ValueListenableBuilder<AmbientStateEvent?>(
        valueListenable: voice?.state ?? _emptyVoiceState,
        builder: (context, event, _) => builder(context, event),
      ),
    );
  }

  static DateTime? _liveSince;
  Timer? _tick;

  void _syncClock(bool live) {
    if (live) {
      _liveSince ??= DateTime.now();
      _tick ??= Timer.periodic(const Duration(seconds: 1), (_) {
        if (mounted) setState(() {});
      });
    } else {
      _liveSince = null;
      _tick?.cancel();
      _tick = null;
    }
  }

  String _elapsed() {
    final since = _liveSince;
    if (since == null) return '00:00';
    final d = DateTime.now().difference(since);
    String two(int n) => n.toString().padLeft(2, '0');
    final h = d.inHours;
    final m = two(d.inMinutes % 60);
    final s = two(d.inSeconds % 60);
    return h > 0 ? '$h:$m:$s' : '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    final reduce = reduceMotion(context);
    final liveHeard = LiveCaptionFeed.instance.text.value;
    final heard = liveHeard ??
        LiveCaptionFeed.instance.lastFinal.value ??
        (_recent.isNotEmpty ? _recent.first.text.trim() : '');
    final heardColor = liveHeard != null ? AppColors.fg1 : AppColors.fg2;
    final reply = widget.replyText?.trim() ?? '';
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: _stateBuilder(context, (context, event) {
          final live = _m.liveOrRunning && !_m.elsewhere && !_m.status.displaced;
          final statusText = ambientStatusText(
            settings: _m.settings,
            status: _m.status,
            event: event,
            elsewhere: _m.elsewhere,
            busy: _m.busy,
            liveOverride: live,
          );
          final shouldPulse = !reduce &&
              live &&
              (statusText == 'Listening' ||
                  statusText == 'Hearing you' ||
                  statusText == 'In conversation');
          if (shouldPulse && !_pulse.isAnimating) _pulse.repeat();
          if (!shouldPulse && _pulse.isAnimating) {
            _pulse.stop();
            _pulse.value = 0;
          }
          _syncClock(live);
          final modeLabel = ambientModeLabel(_m.settings);
          final recent = _recent
              .where((e) => e.text.trim().isNotEmpty)
              .take(3)
              .toList();

          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Row(
                  children: [
                    RoundBtn(
                      icon: 'chevron-down',
                      tooltip: 'Close',
                      size: 40,
                      iconSize: 20,
                      onTap: _pop,
                    ),
                    Expanded(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text('Mission Control',
                              style: sans(15, weight: W.label)),
                          if (live)
                            Text(modeLabel,
                                style: sans(12, color: AppColors.fg3)),
                        ],
                      ),
                    ),
                    const SizedBox(width: 40),
                  ],
                ),
              ),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 40, 24, 24),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _avatar(live, shouldPulse),
                      const SizedBox(height: 20),
                      if (live) ...[
                        Text(_elapsed(),
                            style: mono(15, color: AppColors.fg2)),
                        const SizedBox(height: 2),
                      ],
                      Text(
                        statusText,
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style:
                            sans(13, color: live ? AppColors.ok : AppColors.fg3),
                      ),
                      const SizedBox(height: 16),
                      _LevelBars(
                        animation: _pulse,
                        active: shouldPulse,
                        color: live ? AppColors.ok : AppColors.border,
                      ),
                      if (heard.isNotEmpty) ...[
                        const SizedBox(height: 20),
                        Text(
                          '“$heard”',
                          textAlign: TextAlign.center,
                          maxLines: 3,
                          overflow: TextOverflow.ellipsis,
                          style: sans(20, color: heardColor, height: 1.35),
                        ),
                      ],
                      if (reply.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        Text(
                          reply,
                          textAlign: TextAlign.center,
                          maxLines: 4,
                          overflow: TextOverflow.ellipsis,
                          style: sans(15, color: AppColors.fg3),
                        ),
                      ],
                      if (recent.isNotEmpty) ...[
                        const SizedBox(height: 32),
                        Align(
                          alignment: Alignment.centerLeft,
                          child: Text('Recent',
                              style: sans(12, color: AppColors.fg4)),
                        ),
                        const SizedBox(height: 6),
                        for (final e in recent) _recentRow(e),
                      ],
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    if (_m.ambient.supportsMute)
                      _VoiceCircleBtn(
                        icon: _m.ambient.muted ? 'mic-off' : 'mic',
                        fill: _m.ambient.muted
                            ? AppColors.fg1
                            : AppColors.surface2,
                        iconColor:
                            _m.ambient.muted ? AppColors.bg : AppColors.fg1,
                        tooltip: _m.ambient.muted ? 'Unmute' : 'Mute',
                        onTap: () => _m.ambient.toggleMute(),
                      )
                    else
                      const SizedBox(width: 56),
                    const SizedBox(width: 28),
                    _VoiceCircleBtn(
                      icon: 'phone-off',
                      fill: AppColors.danger,
                      iconColor: Colors.white,
                      tooltip: 'End',
                      size: 68,
                      onTap: _end,
                    ),
                    const SizedBox(width: 28),
                    _VoiceCircleBtn(
                      icon: 'message-square',
                      fill: AppColors.surface2,
                      iconColor: AppColors.fg1,
                      tooltip: 'Chat',
                      onTap: widget.onChat ?? _pop,
                    ),
                  ],
                ),
              ),
            ],
          );
        }),
      ),
    );
  }

  Widget _avatar(bool live, bool shouldPulse) {
    final ring = live
        ? AppColors.ok.withValues(alpha: 0.22)
        : AppColors.border;
    Widget circle(double d, double alpha) => Container(
          width: d,
          height: d,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: ring.withValues(alpha: ring.a * alpha)),
          ),
        );
    return SizedBox(
      width: 196,
      height: 196,
      child: Stack(
        alignment: Alignment.center,
        children: [
          circle(196, 0.5),
          circle(164, 1),
          AnimatedBuilder(
            animation: _pulse,
            builder: (_, child) {
              final wave = 0.5 - 0.5 * math.cos(2 * math.pi * _pulse.value);
              final scale = shouldPulse ? 1.0 + 0.04 * wave : 1.0;
              return Transform.scale(scale: scale, child: child);
            },
            child: Container(
              width: 132,
              height: 132,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: live ? AppColors.okBg : AppColors.surface1,
              ),
              alignment: Alignment.center,
              child: Container(
                width: 96,
                height: 96,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: AppColors.surface2,
                ),
                alignment: Alignment.center,
                child: const AgentMochi('mission-control', size: 48),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _recentRow(AmbientEvent e) {
    final t = e.startedAt.toLocal();
    final hm =
        '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 48,
            child: Text(hm, style: mono(12, color: AppColors.fg4)),
          ),
          Expanded(
            child: Text(
              e.text.trim(),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: sans(14, color: AppColors.fg2),
            ),
          ),
        ],
      ),
    );
  }
}

class _LevelBars extends StatelessWidget {
  const _LevelBars({
    required this.animation,
    required this.active,
    required this.color,
  });

  final Animation<double> animation;
  final bool active;
  final Color color;

  static const _n = 21;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 28,
        child: AnimatedBuilder(
          animation: animation,
          builder: (_, __) => Row(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              for (var i = 0; i < _n; i++)
                Container(
                  width: 3,
                  height: _height(i),
                  margin: const EdgeInsets.symmetric(horizontal: 2),
                  decoration: BoxDecoration(
                    color: color.withValues(
                        alpha: color.a * (active ? 0.85 : 0.6)),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
            ],
          ),
        ),
      );

  double _height(int i) {
    final centre = 1 - (i - _n ~/ 2).abs() / (_n / 2);
    if (!active) return 3 + 3 * centre;
    final phase = 2 * math.pi * (animation.value * 2 + i * 0.37);
    final wave = 0.5 + 0.5 * math.sin(phase) * math.cos(phase * 0.6 + i);
    return 4 + (10 + 14 * centre) * wave;
  }
}

class _VoiceCircleBtn extends StatelessWidget {
  const _VoiceCircleBtn({
    required this.icon,
    required this.fill,
    required this.iconColor,
    required this.tooltip,
    required this.onTap,
    this.size = 56,
  });

  final double size;
  final String icon;
  final Color fill;
  final Color iconColor;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          label: tooltip,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              HapticFeedback.selectionClick();
              onTap();
            },
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                color: fill,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: AppIcon(icon, size: size > 60 ? 26 : 22, color: iconColor),
            ),
          ),
        ),
      );
}
