import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models.dart';
import '../platform.dart';
import '../settled_sessions.dart';
import '../theme.dart';
import '../widgets.dart';
import 'shell_nav.dart';

/// "12.9k" style count: whole numbers to 9,999, then one decimal, then none.
String compactCount(int n) {
  if (n < 10000) return '$n';
  if (n < 100000) return '${_trim((n / 1000).toStringAsFixed(1))}k';
  if (n < 1000000) return '${(n / 1000).round()}k';
  return '${_trim((n / 1000000).toStringAsFixed(1))}M';
}

String _trim(String s) => s.endsWith('.0') ? s.substring(0, s.length - 2) : s;

/// Added/removed lines worth showing: null when both are zero, and a zero side
/// is dropped rather than printed as "-0".
({int added, int removed})? sessionDiff(SessionInfo s) {
  final c = s.shownChanges;
  if (c == null || (c.added <= 0 && c.removed <= 0)) return null;
  return (
    added: c.added < 0 ? 0 : c.added,
    removed: c.removed < 0 ? 0 : c.removed
  );
}

/// Project group label: the folder name, never the full path.
/// Groups sessions by project regardless of home prefix or trailing slash.
String projectKey(SessionInfo s) => s.projectFolder
    .trim()
    .replaceFirst(RegExp(r'^(/home/[^/]+|/Users/[^/]+)(?=/|$)'), '~')
    .replaceFirst(RegExp(r'/+$'), '');

String projectLabel(SessionInfo s) {
  final f = s.projectFolder.trim();
  if (f.isEmpty) return 'No project';
  return lastPathSegment(f, ifEmpty: f);
}

/// Project name as a list section header.
class SessionGroupHeader extends StatelessWidget {
  const SessionGroupHeader(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) => Semantics(
        header: true,
        child: Container(
          height: kMobile ? 40 : 30,
          alignment: Alignment.bottomLeft,
          padding: EdgeInsets.fromLTRB(
              (kMobile ? 4 : 10) + SessionListRow.dotSlot,
              0,
              kMobile ? 4 : 10,
              kMobile ? 4 : 2),
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TS.label(AppColors.fg3)),
        ),
      );
}

/// A session as a two-line list row: state dot + title + time, then branch,
/// diff and agent badge.
class SessionListRow extends StatelessWidget {
  const SessionListRow({
    super.key,
    required this.session,
    required this.onTap,
    this.onLongPress,
    this.onSecondaryTapDown,
    this.selected = false,
    this.selecting = false,
    this.checked = false,
    this.draft = false,
    this.divider = false,
    this.renameField,
    this.badge,
  });

  final SessionInfo session;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final GestureTapDownCallback? onSecondaryTapDown;
  final bool selected;
  final bool selecting;
  final bool checked;
  final bool draft;
  final bool divider;

  /// Replaces the title while renaming.
  final Widget? renameField;

  /// Agent or provider mark shown at the end of the second line.
  final Widget? badge;

  static double get dotSlot => kMobile ? 18 : 16;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final settled = s.settled;
    final waiting = !settled && s.status == 'waiting_for_input';
    final working = !settled && !waiting && sessionIsActive(s.status);
    final title = s.title.trim().isEmpty ? '(untitled)' : s.title;
    final left = settled ? settledDaysLeft(s) : null;
    final timeText = settled
        ? (left == null ? 'Settled' : '${left}d left')
        : draft
            ? 'Draft'
            : relativeTime(s.lastActive);
    final titleStyle = settled
        ? TS.rowTitle(AppColors.fg3).copyWith(fontWeight: W.body)
        : TS.rowTitle(AppColors.fg1);
    final lineH = kMobile ? 22.0 : 18.0;
    final diff = sessionDiff(s);
    final branch = s.branch?.trim() ?? '';
    final hasMeta = branch.isNotEmpty || diff != null || badge != null;

    final stateLabel = waiting
        ? 'Needs input'
        : working
            ? 'Working'
            : settled
                ? 'Settled'
                : null;

    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (selecting)
          SizedBox(
              height: lineH,
              child:
                  Center(child: SelectCheck(checked, size: kMobile ? 20 : 14)))
        else
          SizedBox(
            width: dotSlot,
            height: lineH,
            child: (waiting || working)
                ? Align(
                    alignment: Alignment.centerLeft,
                    child: _StateDot(
                        color: waiting ? AppColors.run : AppColors.accent,
                        pulse: working))
                : null,
          ),
        if (selecting) SizedBox(width: kMobile ? 12 : 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                height: lineH,
                child: Row(children: [
                  Expanded(
                    child: renameField ??
                        Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: titleStyle),
                  ),
                  if (s.keepAwake && renameField == null) ...[
                    const SizedBox(width: 6),
                    AppIcon('lock', size: 11, color: AppColors.fg3),
                  ],
                  if (renameField == null && timeText.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(timeText,
                        maxLines: 1,
                        style: TS.meta(draft && !settled
                            ? AppColors.accent
                            : AppColors.fg3)),
                  ],
                ]),
              ),
              if (hasMeta)
                SizedBox(
                  height: kMobile ? 18 : 16,
                  child: Row(children: [
                    Expanded(
                      child: Row(children: [
                        if (branch.isNotEmpty)
                          Flexible(
                            child:
                                Row(mainAxisSize: MainAxisSize.min, children: [
                              AppIcon('git-branch',
                                  size: kMobile ? 13 : 12,
                                  color: AppColors.fg3),
                              const SizedBox(width: 4),
                              Flexible(
                                child: Text(branch,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TS.meta()),
                              ),
                            ]),
                          ),
                        if (diff != null) ...[
                          if (branch.isNotEmpty) const SizedBox(width: 8),
                          if (diff.added > 0)
                            Text('+${compactCount(diff.added)}',
                                maxLines: 1, style: TS.meta(AppColors.ok)),
                          if (diff.added > 0 && diff.removed > 0)
                            const SizedBox(width: 5),
                          if (diff.removed > 0)
                            Text('-${compactCount(diff.removed)}',
                                maxLines: 1, style: TS.meta(AppColors.danger)),
                        ],
                      ]),
                    ),
                    if (badge != null) ...[
                      const SizedBox(width: 8),
                      badge!,
                    ],
                  ]),
                ),
            ],
          ),
        ),
      ],
    );

    void longPress() {
      HapticFeedback.selectionClick();
      onLongPress?.call();
    }

    final row = kMobile
        ? Material(
            color: checked ? AppColors.accentBg : Colors.transparent,
            child: InkWell(
              onTap: onTap,
              onLongPress: onLongPress == null ? null : longPress,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                ConstrainedBox(
                  constraints: const BoxConstraints(minHeight: 56),
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(4, 8, 4, 8),
                    child:
                        Align(alignment: Alignment.centerLeft, child: content),
                  ),
                ),
                if (divider)
                  Container(
                      height: 1,
                      margin:
                          EdgeInsets.only(left: selecting ? 36 : dotSlot + 4),
                      color: AppColors.line),
              ]),
            ),
          )
        : HoverSurface(
            selected: selecting ? checked : selected,
            radius: 8,
            onTap: onTap,
            onLongPress: onLongPress == null ? null : longPress,
            onSecondaryTapDown: onSecondaryTapDown,
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.centerLeft,
              child: content,
            ),
          );

    return Semantics(
      container: true,
      selected: selected,
      label: stateLabel == null ? null : '$stateLabel. $title',
      child: row,
    );
  }
}

class _StateDot extends StatefulWidget {
  const _StateDot({required this.color, required this.pulse});
  final Color color;
  final bool pulse;

  @override
  State<_StateDot> createState() => _StateDotState();
}

class _StateDotState extends State<_StateDot>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: Motion.pulse);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (widget.pulse && !reduceMotion(context)) {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else {
      _c.stop();
      _c.value = 1;
    }
  }

  @override
  void didUpdateWidget(covariant _StateDot old) {
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
    final dot = Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(color: widget.color, shape: BoxShape.circle),
    );
    if (!widget.pulse) return dot;
    return FadeTransition(
      opacity: Tween<double>(begin: 0.45, end: 1)
          .animate(CurvedAnimation(parent: _c, curve: Curves.easeOut)),
      child: dot,
    );
  }
}
