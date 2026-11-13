import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../mochi.dart';
import '../theme.dart';
import '../widgets.dart';
import 'mobile_chrome.dart';
import 'session_list_row.dart';

/// Phone home header: Mission Control, an inline search field, then actions.
class MobileSearchHeader extends StatelessWidget {
  const MobileSearchHeader({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.hint,
    required this.onChanged,
    this.mcBadgeCount = 0,
    this.onMc,
    this.listening = false,
    this.trailing = const [],
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final String hint;
  final ValueChanged<String> onChanged;
  final int mcBadgeCount;
  final VoidCallback? onMc;
  final bool listening;
  final List<Widget> trailing;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(M.gutter, 6, M.gutter, 10),
        child: SizedBox(
          height: 44,
          child: Row(children: [
            LiveRing(
              live: listening,
              child: RoundBtn(
                tooltip: listening ? 'Mission Control, voice on' : 'Mission Control',
                size: 40,
                badgeCount: mcBadgeCount,
                onTap: onMc,
                child: MochiIcon(
                    color: listening ? AppColors.ok : AppColors.fg1, size: 22),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(child: _field()),
            for (final t in trailing) ...[const SizedBox(width: 10), t],
          ]),
        ),
      );

  Widget _field() => ValueListenableBuilder<TextEditingValue>(
        valueListenable: controller,
        builder: (context, v, _) => Container(
          height: 40,
          padding: const EdgeInsets.only(left: 12, right: 4),
          decoration: BoxDecoration(
            color: AppColors.tint2,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(children: [
            AppIcon('search', size: 16, color: AppColors.fg4),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: controller,
                focusNode: focusNode,
                onChanged: onChanged,
                textInputAction: TextInputAction.search,
                style: sans(15, color: AppColors.fg1),
                cursorColor: AppColors.accent,
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: hint,
                  hintStyle: sans(15, color: AppColors.fg4),
                ),
              ),
            ),
            if (v.text.isNotEmpty)
              IconBtn('x', size: 32, iconSize: 14, tooltip: 'Clear', onTap: () {
                controller.clear();
                onChanged('');
              })
          ]),
        ),
      );
}

/// Section label over a group: an optional icon, the name and a count.
class MobileSectionLabel extends StatelessWidget {
  const MobileSectionLabel(this.label,
      {super.key, this.count, this.icon, this.tone, this.top = 18});

  final String label;
  final int? count;
  final String? icon;
  final Color? tone;
  final double top;

  @override
  Widget build(BuildContext context) {
    final c = tone ?? AppColors.fg3;
    return Padding(
      padding: EdgeInsets.fromLTRB(4, top, 4, 8),
      child: Row(children: [
        if (icon != null) ...[
          AppIcon(icon!, size: 14, color: c),
          const SizedBox(width: 6),
        ],
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(13, weight: W.label, color: c)),
        ),
        if (count != null) ...[
          const SizedBox(width: 6),
          Text('$count', style: mono(12, color: AppColors.fg4)),
        ],
      ]),
    );
  }
}

/// Rounded group surface; owns a Material so row ink stays inside the corners.
class MobileGroupCard extends StatelessWidget {
  const MobileGroupCard({super.key, required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(14),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      );
}

/// A running or waiting session, shown large at the top of the phone list.
class LiveSessionCard extends StatelessWidget {
  const LiveSessionCard({
    super.key,
    required this.session,
    required this.onTap,
    this.onLongPress,
    this.leading,
  });

  final SessionInfo session;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? leading;

  static String _since(int? t) {
    if (t == null || t <= 0) return '';
    final secs = t > 100000000000 ? t ~/ 1000 : t;
    final d = DateTime.now()
        .difference(DateTime.fromMillisecondsSinceEpoch(secs * 1000));
    if (d.inMinutes < 1) return 'just now';
    if (d.inMinutes < 60) return '${d.inMinutes}m';
    return '${d.inHours}h ${d.inMinutes % 60}m';
  }

  @override
  Widget build(BuildContext context) {
    final s = session;
    final needsYou = sessionNeedsYou(s);
    final tone = needsYou ? AppColors.run : AppColors.accent;
    final since = needsYou ? relativeTime(s.lastActive) : _since(s.runningSince);
    final label = needsYou ? sessionAttentionState(s).label : 'Working';
    final note = needsYou ? _attentionText(s) : null;
    final diff = sessionDiff(s);
    final branch = s.branch?.trim() ?? '';
    final title = s.title.trim().isEmpty ? '(untitled)' : s.title;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Semantics(
        button: true,
        label: '$label. $title',
        child: Material(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            onLongPress: onLongPress == null
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onLongPress!();
                  },
            child: Container(
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.line),
              ),
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    if (needsYou)
                      Container(
                        width: 8,
                        height: 8,
                        decoration:
                            BoxDecoration(color: tone, shape: BoxShape.circle),
                      )
                    else
                      const WorkingDots(),
                    const SizedBox(width: 8),
                    Text(since.isEmpty ? label : '$label · $since',
                        style: sans(12, weight: W.label, color: tone)),
                    const Spacer(),
                    if (leading != null)
                      SizedBox.square(
                          dimension: 18, child: Center(child: leading)),
                  ]),
                  const SizedBox(height: 6),
                  Text(title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: sans(16,
                          weight: W.label, height: 1.35, color: AppColors.fg1)),
                  if (note != null) ...[
                    const SizedBox(height: 4),
                    Text(note,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: sans(13, height: 1.4, color: AppColors.fg2)),
                  ],
                  const SizedBox(height: 10),
                  Row(children: [
                    _Tag(projectLabel(s)),
                    if (branch.isNotEmpty) ...[
                      const SizedBox(width: 8),
                      AppIcon('git-branch', size: 11, color: AppColors.fg4),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(branch,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TS.meta()),
                      ),
                    ] else
                      const Spacer(),
                    if (diff != null) ...[
                      const SizedBox(width: 8),
                      if (diff.added > 0)
                        Text('+${compactCount(diff.added)}',
                            style: TS.meta(AppColors.ok)),
                      if (diff.added > 0 && diff.removed > 0)
                        const SizedBox(width: 4),
                      if (diff.removed > 0)
                        Text('-${compactCount(diff.removed)}',
                            style: TS.meta(AppColors.danger)),
                    ],
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String? _attentionText(SessionInfo s) {
    final a = s.attention;
    if (a == null) return null;
    for (final k in const ['summary', 'text', 'question', 'message']) {
      final v = a[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.label);
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
          color: AppColors.tint2,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: sans(11, color: AppColors.fg3)),
      );
}

/// A breathing ring that marks a control as live, such as Mission Control
/// while ambient voice is on.
class LiveRing extends StatefulWidget {
  const LiveRing({super.key, required this.live, required this.child});

  final bool live;
  final Widget child;

  @override
  State<LiveRing> createState() => _LiveRingState();
}

class _LiveRingState extends State<LiveRing>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant LiveRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.live && !reduceMotion(context)) {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else {
      _c.stop();
      _c.value = widget.live ? 1 : 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.live) return widget.child;
    return AnimatedBuilder(
      animation: _c,
      child: widget.child,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_c.value);
        return DecoratedBox(
          position: DecorationPosition.foreground,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(
                color: AppColors.ok.withValues(alpha: 0.45 + 0.5 * t),
                width: 2),
            boxShadow: [
              BoxShadow(
                color: AppColors.ok.withValues(alpha: 0.10 + 0.22 * t),
                blurRadius: 6 + 8 * t,
              ),
            ],
          ),
          child: child,
        );
      },
    );
  }
}
