import 'package:flutter/material.dart';

import 'platform.dart';
import 'theme.dart';
import 'widgets.dart';

class DesktopRecorderStrip extends StatelessWidget {
  const DesktopRecorderStrip({
    super.key,
    required this.recording,
    required this.time,
    required this.wave,
    required this.playing,
    required this.onDiscard,
    required this.onPlay,
    required this.onStop,
    required this.onSend,
    this.onSeek,
    this.onMore,
  });

  final bool recording;
  final String time;
  final Widget wave;
  final bool playing;
  final VoidCallback onDiscard;
  final VoidCallback onPlay;
  final VoidCallback onStop;
  final VoidCallback onSend;
  final ValueChanged<double>? onSeek;
  final VoidCallback? onMore;

  Widget _btn(String icon, String tip, VoidCallback onTap,
          {Color? color, Color? fill}) =>
      Tooltip(
        message: tip,
        child: Material(
          color: fill ?? Colors.transparent,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox.square(
              dimension: kMobile ? 40 : 32,
              child: Center(
                  child: AppIcon(icon,
                      size: kMobile ? 17 : 15, color: color ?? AppColors.fg2)),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final timeText = Text(time,
        style: sans(12, color: recording ? AppColors.danger : AppColors.fg3));
    final bar = SizedBox(height: 24, child: wave);
    Widget track = bar;
    if (!recording && onSeek != null) {
      track = LayoutBuilder(
        builder: (_, c) => GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) =>
              onSeek!((d.localPosition.dx / c.maxWidth).clamp(0.0, 1.0)),
          onHorizontalDragUpdate: (d) =>
              onSeek!((d.localPosition.dx / c.maxWidth).clamp(0.0, 1.0)),
          child: SizedBox(height: 44, child: Center(child: bar)),
        ),
      );
    }
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        color: kMobile ? AppColors.surface1 : AppColors.raised,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(children: [
        if (recording) ...[
          const SizedBox(width: 10),
          StatusDot(status: 'running', size: 8, color: AppColors.danger),
          const SizedBox(width: 8),
          timeText,
          const SizedBox(width: 10),
          Expanded(child: track),
          const SizedBox(width: 4),
          _btn('trash', 'Discard', onDiscard, color: AppColors.fg3),
          _btn('stop', 'Stop', onStop,
              color: kMobile ? AppColors.bg : AppColors.fg1,
              fill: kMobile ? AppColors.fg1 : AppColors.surface3),
        ] else ...[
          _btn(playing ? 'pause' : 'play', playing ? 'Pause' : 'Play', onPlay,
              color: AppColors.fg1),
          Expanded(child: track),
          const SizedBox(width: 8),
          timeText,
          const SizedBox(width: 4),
          if (onMore != null)
            _btn('mic', 'Record more', onMore!, color: AppColors.fg2),
          _btn('trash', 'Discard', onDiscard, color: AppColors.fg3),
          _btn('arrow-up', 'Send voice note', onSend,
              color: kMobile ? AppColors.accentFg : AppColors.bg,
              fill: kMobile ? AppColors.accentFill : AppColors.fg1),
        ],
      ]),
    );
  }
}
