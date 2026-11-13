import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../../ambient/live_caption.dart';
import '../../../glass.dart';
import '../../../models.dart';
import '../../../theme.dart';
import '../../../widgets.dart';
import 'ambient_stage.dart' show AmbientHeardLine;

/// Desktop body of the ambient stage: header, live caption, recent heard rows.
class AmbientDesktopPanel extends StatelessWidget {
  const AmbientDesktopPanel({
    super.key,
    required this.stateWord,
    required this.live,
    required this.color,
    required this.canToggle,
    required this.onToggle,
    required this.onClose,
    required this.recent,
    this.feed,
    this.error,
    this.footer,
    this.orb,
  });

  static const width = 360.0;
  static const height = 520.0;

  final String stateWord;
  final bool live;
  final Color color;
  final bool canToggle;
  final VoidCallback onToggle;
  final VoidCallback onClose;
  final List<AmbientEvent> recent;
  final LiveCaptionFeed? feed;
  final String? error;
  final Widget? footer;
  final Widget? orb;

  static String ago(DateTime t) {
    final d = DateTime.now().difference(t);
    if (d.inSeconds < 60) return 'now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    if (d.inHours < 24) return '${d.inHours}h';
    return '${d.inDays}d';
  }

  @override
  Widget build(BuildContext context) {
    final end = live;
    return SizedBox(
      width: width,
      height: height,
      child: Glass(
        radius: BorderRadius.circular(16),
        tint: GlassStyle.fill,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 8, 0),
              child: Row(children: [
                _LiveBars(active: live, color: color),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('Snippet voice',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(12, weight: W.label, color: AppColors.fg3)),
                ),
                if (footer != null) ...[footer!, const SizedBox(width: 4)],
                IconBtn('x', size: 32, iconSize: 16, tooltip: 'Close', onTap: onClose),
              ]),
            ),
            const SizedBox(height: 12),
            Center(
              child: SizedBox.square(
                dimension: 112,
                child: orb ??
                    DecoratedBox(
                      decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: color.withValues(alpha: live ? 0.25 : 0.1)),
                    ),
              ),
            ),
            const SizedBox(height: 14),
            Text(stateWord,
                key: const ValueKey('ambient-state-word'),
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(18, weight: W.title, color: AppColors.fg1)),
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 6, 24, 0),
              child: ConstrainedBox(
                key: const ValueKey('ambient-caption'),
                constraints: const BoxConstraints(minHeight: 40),
                child: Center(child: AmbientHeardLine(wide: true, feed: feed)),
              ),
            ),
            if (error != null)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                child: NoteLine(error!, error: true),
              ),
            const SizedBox(height: 12),
            Divider(height: 1, thickness: 1, color: AppColors.line),
            Expanded(
              child: recent.isEmpty
                  ? Center(
                      child: Text('Nothing heard yet',
                          style: sans(12, color: AppColors.fg4)),
                    )
                  : ListView(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                      children: [for (final e in recent) _Row(e)],
                    ),
            ),
            Divider(height: 1, thickness: 1, color: AppColors.line),
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(
                child: _CallButton(
                  icon: end ? 'phone-off' : 'mic',
                  label: end ? 'End' : 'Start',
                  color: end ? AppColors.danger : AppColors.accent,
                  onTap: canToggle ? onToggle : null,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _CallButton extends StatelessWidget {
  const _CallButton(
      {required this.icon, required this.label, required this.color, this.onTap});
  final String icon;
  final String label;
  final Color color;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = onTap != null;
    return Semantics(
      button: true,
      label: label,
      child: GestureDetector(
        onTap: onTap,
        behavior: HitTestBehavior.opaque,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: color.withValues(alpha: enabled ? 1 : 0.4),
            ),
            child: Center(
              child: AppIcon(icon,
                  size: 22,
                  color: label == 'End' ? Colors.white : AppColors.accentFg),
            ),
          ),
          const SizedBox(height: 6),
          Text(label, style: sans(12, weight: W.label, color: AppColors.fg2)),
        ]),
      ),
    );
  }
}

class _Row extends StatelessWidget {
  const _Row(this.e);
  final AmbientEvent e;

  @override
  Widget build(BuildContext context) {
    final routed = e.verdict;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 5),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 34,
            child: Text(AmbientDesktopPanel.ago(e.startedAt),
                style: mono(11, color: AppColors.fg4)),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(e.text.trim(),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: sans(12, height: 1.35, color: AppColors.fg2)),
                if (routed != null && routed.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(routed,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(11, color: AppColors.fg4)),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _LiveBars extends StatefulWidget {
  const _LiveBars({required this.active, required this.color});
  final bool active;
  final Color color;

  @override
  State<_LiveBars> createState() => _LiveBarsState();
}

class _LiveBarsState extends State<_LiveBars>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1100));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final run = widget.active && !reduceMotion(context);
    if (run && !_c.isAnimating) {
      _c.repeat();
    } else if (!run && _c.isAnimating) {
      _c.stop();
    }
  }

  @override
  void didUpdateWidget(covariant _LiveBars old) {
    super.didUpdateWidget(old);
    didChangeDependencies();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 18,
      height: 16,
      child: AnimatedBuilder(
        animation: _c,
        builder: (_, __) => Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            for (var i = 0; i < 4; i++)
              Container(
                width: 3,
                height: widget.active
                    ? 5 + 11 * (0.5 + 0.5 * math.sin((_c.value + i * 0.25) * math.pi * 2))
                    : 4,
                decoration: BoxDecoration(
                  color: widget.active ? widget.color : AppColors.fg4,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
