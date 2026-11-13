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

  @override
  Widget build(BuildContext context) {
    final reduce = reduceMotion(context);
    final liveHeard = LiveCaptionFeed.instance.text.value;
    final heard = liveHeard ??
        LiveCaptionFeed.instance.lastFinal.value ??
        (_recent.isNotEmpty ? _recent.first.text.trim() : '');
    final heardColor =
        liveHeard != null ? AppColors.fg1 : AppColors.fg2;
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
          final modeLabel = ambientModeLabel(_m.settings);

          return LayoutBuilder(
            builder: (context, constraints) {
              // 48px accounts for the top row (8px top + 40px RoundBtn).
              final topGap =
                  (constraints.maxHeight * 0.22 - 48).clamp(16.0, 240.0);
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
                        const Spacer(),
                        if (live)
                          Container(
                            height: 28,
                            padding: const EdgeInsets.symmetric(horizontal: 12),
                            decoration: BoxDecoration(
                              color: AppColors.okBg,
                              borderRadius: BorderRadius.circular(14),
                            ),
                            alignment: Alignment.center,
                            child: Text(
                              modeLabel,
                              style: sans(13, color: AppColors.ok)
                                  .copyWith(height: 1),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: EdgeInsets.only(top: topGap, bottom: 24),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          SizedBox(
                            width: 120,
                            height: 120,
                            child: Stack(
                              clipBehavior: Clip.none,
                              alignment: Alignment.center,
                              children: [
                                if (live)
                                  OverflowBox(
                                    maxWidth: 200,
                                    maxHeight: 200,
                                    child: Container(
                                      width: 200,
                                      height: 200,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        gradient: RadialGradient(
                                          colors: [
                                            AppColors.ok
                                                .withValues(alpha: 0.18),
                                            AppColors.ok.withValues(alpha: 0.0),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ),
                                AnimatedBuilder(
                                  animation: _pulse,
                                  builder: (_, child) {
                                    final wave = 0.5 -
                                        0.5 *
                                            math.cos(2 * math.pi * _pulse.value);
                                    final scale =
                                        shouldPulse ? 1.0 + 0.04 * wave : 1.0;
                                    return Transform.scale(
                                      scale: scale,
                                      child: child,
                                    );
                                  },
                                  child: Container(
                                    width: 120,
                                    height: 120,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: live
                                          ? AppColors.okBg
                                          : AppColors.surface1,
                                    ),
                                    alignment: Alignment.center,
                                    child: Container(
                                      width: 88,
                                      height: 88,
                                      decoration: BoxDecoration(
                                        shape: BoxShape.circle,
                                        color: AppColors.surface2,
                                      ),
                                      alignment: Alignment.center,
                                      child: const AgentMochi(
                                        'mission-control',
                                        size: 44,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              statusText,
                              textAlign: TextAlign.center,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(13,
                                  color: live ? AppColors.ok : AppColors.fg3),
                            ),
                          ),
                          if (heard.isNotEmpty) ...[
                            const SizedBox(height: 8),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 32),
                              child: Text(
                                '\u201C$heard\u201D',
                                textAlign: TextAlign.center,
                                maxLines: 3,
                                overflow: TextOverflow.ellipsis,
                                style: sans(22, color: heardColor),
                              ),
                            ),
                          ],
                          if (reply.isNotEmpty) ...[
                            const SizedBox(height: 16),
                            Padding(
                              padding:
                                  const EdgeInsets.symmetric(horizontal: 32),
                              child: Text(
                                reply,
                                textAlign: TextAlign.center,
                                maxLines: 4,
                                overflow: TextOverflow.ellipsis,
                                style: sans(16, color: AppColors.fg3),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (_m.ambient.supportsMute) ...[
                          _VoiceCircleBtn(
                            icon: _m.ambient.muted ? 'mic-off' : 'mic',
                            fill: AppColors.surface2,
                            iconColor: AppColors.fg1,
                            tooltip: _m.ambient.muted ? 'Unmute' : 'Mute',
                            onTap: () => _m.ambient.toggleMute(),
                          ),
                          const SizedBox(width: 16),
                        ],
                        _VoiceCircleBtn(
                          icon: 'message-square',
                          fill: AppColors.surface2,
                          iconColor: AppColors.fg1,
                          tooltip: 'Chat',
                          onTap: widget.onChat ?? _pop,
                        ),
                        const SizedBox(width: 16),
                        _VoiceCircleBtn(
                          icon: 'x',
                          fill: AppColors.danger,
                          iconColor: Colors.white,
                          tooltip: 'End',
                          onTap: _end,
                        ),
                      ],
                    ),
                  ),
                ],
              );
            },
          );
        }),
      ),
    );
  }
}

class _VoiceCircleBtn extends StatelessWidget {
  const _VoiceCircleBtn({
    required this.icon,
    required this.fill,
    required this.iconColor,
    required this.tooltip,
    required this.onTap,
  });

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
              width: 56,
              height: 56,
              decoration: BoxDecoration(
                color: fill,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: AppIcon(icon, size: 22, color: iconColor),
            ),
          ),
        ),
      );
}
