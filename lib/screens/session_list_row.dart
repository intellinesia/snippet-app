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

bool sessionNeedsYou(SessionInfo s) =>
    !s.settled &&
    (s.status == 'waiting_for_input' ||
        s.status == 'in_review' ||
        s.attention != null);

({String label, String icon}) _attentionState(SessionInfo s) {
  final type = '${s.attention?['type'] ?? ''}'.toLowerCase();
  if (type == 'question') return (label: 'Question', icon: 'help-circle');
  if (type == 'in_review' || type == 'review' || s.status == 'in_review') {
    return (label: 'In review', icon: 'list');
  }
  return (label: 'Needs input', icon: 'message');
}

/// Project name as a collapsible list section header.
class SessionGroupHeader extends StatefulWidget {
  const SessionGroupHeader(
    this.label, {
    super.key,
    this.count,
    this.collapsed = false,
    this.onToggle,
    this.needsYou = false,
    this.chevronRight = false,
  });

  final String label;
  final int? count;
  final bool collapsed;
  final VoidCallback? onToggle;
  final bool needsYou;
  final bool chevronRight;

  @override
  State<SessionGroupHeader> createState() => _SessionGroupHeaderState();
}

class _SessionGroupHeaderState extends State<SessionGroupHeader> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final labelColor = widget.needsYou ? AppColors.run : AppColors.fg4;
    final countStyle = TS.caption(labelColor).copyWith(
        fontFamily: monoFamily,
        fontSize: 11,
        fontWeight: W.body,
        fontFeatures: const [FontFeature.tabularFigures()]);
    final still = reduceMotion(context);
    final turns = widget.chevronRight
        ? (widget.collapsed ? 0.0 : 0.25)
        : (widget.collapsed ? -0.25 : 0.0);
    final chevron = AnimatedOpacity(
      opacity: kMobile || _hover ? 1 : 0,
      duration: still ? Duration.zero : Motion.quick,
      child: AnimatedRotation(
        turns: turns,
        duration: still ? Duration.zero : Motion.base,
        curve: Curves.easeOutCubic,
        child: AppIcon(
          widget.chevronRight ? 'chevron-right' : 'chevron-down',
          size: 11,
          color: AppColors.fg4,
        ),
      ),
    );

    final labelRow = Row(children: [
      Expanded(
        child: Row(children: [
          Flexible(
            child: Text(widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TS.label(labelColor)),
          ),
          if (widget.count != null) ...[
            const SizedBox(width: 6),
            Text('${widget.count}', maxLines: 1, style: countStyle),
          ],
        ]),
      ),
      const SizedBox(width: 6),
      chevron,
    ]);

    final row = kMobile
        ? Padding(
            padding: const EdgeInsets.fromLTRB(0, 16, 0, 4),
            child: labelRow,
          )
        : Container(
            height: 30,
            alignment: Alignment.bottomLeft,
            padding: const EdgeInsets.fromLTRB(10, 0, 10, 4),
            child: labelRow,
          );

    final countPart = widget.count == null
        ? ''
        : ', ${widget.count} ${widget.count == 1 ? 'session' : 'sessions'}';
    final statePart = widget.onToggle == null
        ? ''
        : ', ${widget.collapsed ? 'collapsed' : 'expanded'}';

    return Semantics(
      container: true,
      header: true,
      button: widget.onToggle != null,
      expanded: widget.onToggle != null ? !widget.collapsed : null,
      label: '${widget.label}$countPart$statePart',
      child: ExcludeSemantics(
        child: MouseRegion(
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: HoverSurface(
            radius: 8,
            onTap: widget.onToggle,
            child: row,
          ),
        ),
      ),
    );
  }
}

/// A session as a two-line list row: leading mark + title + time/working,
/// then status, branch and diff.
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
    this.showProject = false,
    this.unread = false,
    this.renameField,
    this.leading,
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
  final bool showProject;
  final bool unread;

  /// Replaces the title while renaming.
  final Widget? renameField;

  /// Leading agent, provider or neutral mark aligned with the title line.
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final settled = s.settled;
    final needsYou = sessionNeedsYou(s);
    final working = !settled && !needsYou && sessionIsActive(s.status);
    final untitled = s.title.trim().isEmpty;
    final title = untitled ? '(untitled)' : s.title;
    final left = settled ? settledDaysLeft(s) : null;
    final timeText = settled
        ? (left == null ? 'Settled' : '${left}d left')
        : draft
            ? 'Draft'
            : relativeTime(s.lastActive);
    final titleStyle = settled || untitled
        ? TS.rowTitle(AppColors.fg3).copyWith(fontWeight: W.body)
        : TS.rowTitle(AppColors.fg1).copyWith(fontWeight: W.label);
    final timeColor = draft && !settled
        ? AppColors.accent
        : unread
            ? AppColors.fg1
            : AppColors.fg4;
    final lineH = kMobile ? 22.0 : 18.0;
    final diff = sessionDiff(s);
    final branch = s.branch?.trim() ?? '';
    final attn = needsYou ? _attentionState(s) : null;
    final noRepo = !showProject && branch.isEmpty && diff == null;
    final hasMeta = showProject || needsYou || branch.isNotEmpty || diff != null || noRepo;

    final stateLabel = attn?.label ??
        (working
            ? 'Working'
            : settled
                ? 'Settled'
                : null);

    final content = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (leading != null) ...[
          SizedBox(
            width: kMobile ? 20 : 16,
            height: lineH,
            child: Center(child: leading),
          ),
          SizedBox(width: kMobile ? 12 : 9),
        ],
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
                  if (renameField == null && working) ...[
                    const SizedBox(width: 8),
                    const WorkingDots(),
                    const SizedBox(width: 5),
                    Text('Working',
                        maxLines: 1,
                        style: (kMobile ? TS.meta : TS.caption)(AppColors.accent)),
                  ] else if (renameField == null && timeText.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(timeText,
                        maxLines: 1,
                        style: (kMobile ? TS.meta : TS.caption)(timeColor)),
                  ],
                ]),
              ),
              if (hasMeta) const SizedBox(height: 2),
              if (hasMeta)
                SizedBox(
                  height: kMobile ? 18 : 16,
                  child: Row(children: [
                    if (attn != null) ...[
                      _StateLabel(state: attn),
                      if (showProject || branch.isNotEmpty || diff != null || noRepo)
                        const SizedBox(width: 8),
                    ],
                    if (showProject)
                      _ProjectChip(label: projectLabel(s))
                    else ...[
                      if (branch.isNotEmpty)
                        Expanded(
                          child: Row(children: [
                            AppIcon('git-branch',
                                size: 11, color: AppColors.fg4),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(branch,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TS.meta()),
                            ),
                          ]),
                        )
                      else if (noRepo)
                        Expanded(
                          child: Text('No git repo',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TS.meta(AppColors.fg4)),
                        )
                      else if (diff != null)
                        const Spacer(),
                      if (diff != null) ...[
                        if (branch.isNotEmpty) const SizedBox(width: 8),
                        if (diff.added > 0)
                          Text('+${compactCount(diff.added)}',
                              maxLines: 1, style: TS.meta(AppColors.ok)),
                        if (diff.added > 0 && diff.removed > 0)
                          const SizedBox(width: 4),
                        if (diff.removed > 0)
                          Text('-${compactCount(diff.removed)}',
                              maxLines: 1, style: TS.meta(AppColors.danger)),
                      ],
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
        ? Stack(clipBehavior: Clip.none, children: [
            // Tint bleeds into the gutter so selection adds no inset.
            if (checked)
              Positioned(
                left: -12,
                right: -12,
                top: 0,
                bottom: 0,
                child: DecoratedBox(
                    decoration: BoxDecoration(
                        color: AppColors.accentBg,
                        borderRadius: BorderRadius.circular(R.md))),
              ),
            Pressable(
              kind: PressKind.row,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap,
                  splashFactory: NoSplash.splashFactory,
                  highlightColor: Colors.transparent,
                  onLongPress: onLongPress == null ? null : longPress,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: M.minTarget),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Align(
                            alignment: Alignment.centerLeft, child: content),
                      ),
                    ),
                    if (divider)
                      Container(
                          height: 1,
                          color: checked ? Colors.transparent : AppColors.line),
                  ]),
                ),
              ),
            ),
          ])
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
      selected: selecting ? checked : selected,
      label: stateLabel == null ? null : '$stateLabel. $title',
      child: row,
    );
  }
}

class _StateLabel extends StatelessWidget {
  const _StateLabel({required this.state});

  final ({String label, String icon}) state;

  @override
  Widget build(BuildContext context) {
    final color = AppColors.run;
    return Row(mainAxisSize: MainAxisSize.min, children: [
      AppIcon(state.icon, size: 11, color: color),
      const SizedBox(width: 4),
      Text(state.label, maxLines: 1, style: TS.meta(color)),
    ]);
  }
}

class _ProjectChip extends StatelessWidget {
  const _ProjectChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final trimmed = label.trim();
    final letter =
        trimmed.isEmpty ? '?' : trimmed.characters.first.toUpperCase();
    return Flexible(
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Container(
          width: 13,
          height: 13,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surface3,
            borderRadius: BorderRadius.circular(3),
          ),
          child: Text(
            letter,
            style: codeMono(9, color: AppColors.fg3, height: 1.0),
          ),
        ),
        const SizedBox(width: 5),
        Flexible(
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TS.meta(),
          ),
        ),
      ]),
    );
  }
}

/// Three accent dots rising in sequence, a typing-indicator read of "working".
/// Takes the time label's slot; static under reduced motion.
class WorkingDots extends StatefulWidget {
  const WorkingDots({super.key});

  @override
  State<WorkingDots> createState() => _WorkingDotsState();
}

class _WorkingDotsState extends State<WorkingDots>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 900));
  bool _running = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  double _wave(double t, int i) {
    final p = (t - i * 0.16) % 1.0;
    final up = p < 0.5 ? p * 2 : 2 - p * 2;
    return Curves.easeInOut.transform(up);
  }

  @override
  Widget build(BuildContext context) {
    final still = reduceMotion(context);
    if (still && _running) {
      _c.stop();
      _running = false;
    } else if (!still && !_running) {
      _c.repeat();
      _running = true;
    }
    return Semantics(
      label: 'Working',
      excludeSemantics: true,
      child: SizedBox(
        width: 14,
        height: 8,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, __) => Stack(clipBehavior: Clip.none, children: [
            for (var i = 0; i < 3; i++)
              Positioned(
                left: i * 5.5,
                bottom: still ? 2 : 0.5 + 4 * _wave(_c.value, i),
                child: Container(
                  width: 3,
                  height: 3,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: AppColors.accent.withValues(
                        alpha: still ? 0.8 : 0.45 + 0.55 * _wave(_c.value, i)),
                  ),
                ),
              ),
          ]),
        ),
      ),
    );
  }
}
