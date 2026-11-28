import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../motion_routes.dart';
import '../ambient/ambient_model.dart';
import '../ambient/live_caption.dart';
import '../ambient/controller.dart';
import '../ambient/voice.dart';
import '../api.dart';
import '../media_views.dart';
import '../models.dart';
import '../swr.dart';
import '../theme.dart';
import '../widgets.dart';
import 'mobile_home/agents_home.dart' show PushedBar, BarIcon;
import 'mobile_home/autonomy_phone.dart';
import '../chat_scene.dart' show SceneBackdrop;
import '../tap_detector.dart';

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
{
  late final AmbientModel _m = AmbientModel(
    widget.client,
    ambient: widget.controller,
    initialSettings: widget.initialSettings,
  )..addListener(_changed);
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
      body: SceneBackdrop(child: SafeArea(
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
          // Static at rest: a state change cross-fades, nothing pulses.
          const shouldPulse = false;
          _syncClock(live);
          final modeLabel = ambientModeLabel(_m.settings);

          final device = _m.settings?.listeningDevice;
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              PushedBar(
                  title: 'Lead ambient',
                  onBack: _pop,
                  actions: [
                    if (widget.client != null)
                      BarIcon('sliders', 'Autonomy', () {
                        Navigator.of(context).push(AppPageRoute(
                            builder: (_) =>
                                AutonomyPhonePage(client: widget.client!)));
                      }),
                  ]),
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(16, 24, 16, 16),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      _avatar(live, shouldPulse),
                      const SizedBox(height: 16),
                      AnimatedSwitcher(
                        duration: reduce
                            ? Duration.zero
                            : const Duration(milliseconds: 200),
                        child: Text(
                          statusText,
                          key: ValueKey(statusText),
                          textAlign: TextAlign.center,
                          style: sans(15,
                              weight: FontWeight.w500, color: AppColors.fg1),
                        ),
                      ),
                      if (device != null && device.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 4),
                          child: Text('Mic $device',
                              style: sans(12, color: AppColors.fg3)),
                        ),
                      if (live)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text('$modeLabel \u00b7 ${_elapsed()}',
                              style: sans(12, color: AppColors.fg3)),
                        ),
                      const SizedBox(height: 24),
                      Container(
                        key: const ValueKey('last-heard'),
                        constraints: const BoxConstraints(minHeight: 116),
                        padding: const EdgeInsets.all(14),
                        alignment: Alignment.topLeft,
                        decoration: BoxDecoration(
                            color: AppColors.surface1,
                            borderRadius: BorderRadius.circular(12)),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text('Last heard',
                                  style: sans(12,
                                      weight: FontWeight.w500,
                                      color: AppColors.fg3)),
                              const SizedBox(height: 6),
                              Text(heard.isEmpty ? 'Nothing yet' : heard,
                                  maxLines: 4,
                                  overflow: TextOverflow.ellipsis,
                                  style: sans(15, color: heardColor)),
                              if (reply.isNotEmpty) ...[
                                const SizedBox(height: 6),
                                Text(reply,
                                    maxLines: 3,
                                    overflow: TextOverflow.ellipsis,
                                    style: sans(13, color: AppColors.fg3)),
                              ],
                            ]),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_m.ambient.supportsMute) ...[
                      _VoiceCircleBtn(
                        icon: _m.ambient.muted ? 'mic-off' : 'mic',
                        fill: AppColors.surface2,
                        iconColor: AppColors.fg1,
                        tooltip: _m.ambient.muted ? 'Unmute' : 'Mute',
                        onTap: () => _m.ambient.toggleMute(),
                      ),
                      const SizedBox(width: 40),
                    ],
                    _VoiceCircleBtn(
                      icon: 'phone-off',
                      fill: AppColors.surface2,
                      iconColor: AppColors.fg1,
                      tooltip: 'End',
                      onTap: _end,
                    ),
                  ],
                ),
              ),
            ],
          );
        }),
      )),
    );
  }

  Widget _avatar(bool live, bool shouldPulse) {
    Widget disc(double d, Color c) => Container(
        width: d,
        height: d,
        decoration: BoxDecoration(color: c, shape: BoxShape.circle));
    return SizedBox(
      key: const ValueKey('ambient-circles'),
      width: 180,
      height: 180,
      child: Stack(alignment: Alignment.center, children: [
        disc(180, AppColors.surface2),
        disc(140.4, AppColors.surface3),
        disc(93.6, AppColors.fg3),
        disc(54, AppColors.fg1),
      ]),
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

  static const double size = 64;
  final String icon;
  final Color fill;
  final Color iconColor;
  final String tooltip;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Column(mainAxisSize: MainAxisSize.min, children: [
        _btn(context),
        const SizedBox(height: 6),
        Text(tooltip, style: sans(11, color: AppColors.fg2)),
      ]);

  Widget _btn(BuildContext context) => Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          label: tooltip,
          child: TapDetector(
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
