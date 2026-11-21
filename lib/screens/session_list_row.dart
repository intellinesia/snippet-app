import 'package:flutter/material.dart';

import '../ambient_loop.dart';
import '../models.dart';
import '../notification_text.dart' show approvalOf;
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

/// Finished while the user was away and not yet opened — the "Came back"
/// section. Needs-you still wins when a session is both.
bool sessionCameBack(SessionInfo s) => s.cameBack && !sessionNeedsYou(s);

({String label, String icon}) sessionAttentionState(SessionInfo s) {
  final type = '${s.attention?['type'] ?? ''}'.toLowerCase();
  if (type == 'question') return (label: 'Question', icon: 'help-circle');
  if (type == 'in_review' || type == 'review' || s.status == 'in_review') {
    return (label: 'In review', icon: 'list');
  }
  return (label: 'Needs input', icon: 'message');
}

String sessionStepLabel(SessionPlan plan) {
  if (plan.current == null && plan.total > 0 && plan.done >= plan.total) {
    return 'plan done';
  }
  final stepNum = plan.current != null
      ? (plan.done + 1).clamp(1, plan.total)
      : plan.done.clamp(0, plan.total);
  return 'plan $stepNum/${plan.total}';
}

/// "Plan 2 of 4 · Integrate lanes · 2 lanes" for a busy session, or null.
String? sessionProgressLabel(SessionInfo s) {
  final parts = <String>[];
  final plan = s.plan;
  if (plan != null && plan.total > 0 && plan.done < plan.total) {
    final step = (plan.done + 1).clamp(1, plan.total);
    parts.add('Plan $step of ${plan.total}');
    final current = plan.current?.trim() ?? '';
    if (current.isNotEmpty) parts.add(current);
  }
  final lanes = s.lanes?.running ?? 0;
  if (lanes > 0) parts.add(lanes == 1 ? '1 lane' : '$lanes lanes');
  return parts.isEmpty ? null : parts.join(' · ');
}

String sessionDuration(int? unixSec) {
  if (unixSec == null || unixSec <= 0) return '';
  final secs = unixSec > 100000000000 ? unixSec ~/ 1000 : unixSec;
  final d = DateTime.now()
      .difference(DateTime.fromMillisecondsSinceEpoch(secs * 1000));
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  return '${d.inHours}h ${d.inMinutes % 60}m';
}

String? sessionLanesLabel(SessionLanes? lanes) {
  if (lanes == null || lanes.running <= 0) return null;
  final n = lanes.running;
  final count = n == 1 ? '1 lane' : '$n lanes';
  final first = lanes.items
      .map((l) => (l.activity ?? l.title).trim())
      .firstWhere((t) => t.isNotEmpty, orElse: () => '');
  return first.isEmpty ? count : '$count · $first';
}

String sessionPrLabel(SessionPr pr) {
  final suffix = switch (pr.state) {
    'merged' => 'merged',
    'closed' => 'closed',
    'draft' => pr.checks == 'none' ? 'draft' : 'draft · checks ${pr.checks}',
    _ => pr.checks == 'none' ? 'open' : 'checks ${pr.checks}',
  };
  return 'PR #${pr.number} · $suffix';
}

Color sessionPrColor(SessionPr pr) => switch (pr.checks) {
      'failing' => AppColors.danger,
      'passing' => AppColors.ok,
      'pending' => AppColors.run,
      _ => AppColors.fg3,
    };

String? sessionWakeLabel(int? nextWakeAt) {
  if (nextWakeAt == null || nextWakeAt <= 0) return null;
  final dt = DateTime.fromMillisecondsSinceEpoch(nextWakeAt * 1000).toLocal();
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final day = days[dt.weekday - 1];
  final hh = dt.hour.toString().padLeft(2, '0');
  final mm = dt.minute.toString().padLeft(2, '0');
  return 'wakes $day $hh:$mm';
}

class SessionPrActionRow extends StatelessWidget {
  const SessionPrActionRow({
    super.key,
    required this.pr,
    this.onReview,
    this.onMerge,
    required this.mobile,
  });

  final SessionPr pr;
  final VoidCallback? onReview;
  final VoidCallback? onMerge;
  final bool mobile;

  @override
  Widget build(BuildContext context) {
    final color = sessionPrColor(pr);
    final showActions =
        pr.state == 'open' && (onReview != null || onMerge != null);
    final btnHeight = mobile ? M.minTarget : 28.0;
    return Row(
      children: [
        AppIcon('pull-request', size: mobile ? 12 : 11, color: color),
        const SizedBox(width: 4),
        Expanded(
          child: Text(
            sessionPrLabel(pr),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: (mobile ? sans(12, color: color) : TS.meta(color)),
          ),
        ),
        if (showActions) ...[
          if (onReview != null) ...[
            const SizedBox(width: 6),
            _PrMiniButton(
              label: 'Review',
              height: btnHeight,
              onTap: onReview!,
              primary: false,
            ),
          ],
          if (onMerge != null) ...[
            const SizedBox(width: 6),
            _PrMiniButton(
              label: 'Merge',
              height: btnHeight,
              onTap: onMerge!,
              primary: true,
            ),
          ],
        ],
      ],
    );
  }
}

class _PrMiniButton extends StatelessWidget {
  const _PrMiniButton({
    required this.label,
    required this.height,
    required this.onTap,
    required this.primary,
  });

  final String label;
  final double height;
  final VoidCallback onTap;
  final bool primary;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: primary ? AppColors.accentBg : AppColors.tint2,
      borderRadius: BorderRadius.circular(6),
      child: InkWell(
        borderRadius: BorderRadius.circular(6),
        onTap: onTap,
        child: Container(
          height: height,
          padding: EdgeInsets.symmetric(horizontal: height >= 40 ? 12 : 8),
          alignment: Alignment.center,
          child: Text(
            label,
            style: sans(height >= 40 ? 13 : 11,
                weight: W.label,
                color: primary ? AppColors.accent : AppColors.fg2),
          ),
        ),
      ),
    );
  }
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
            SizedBox(width: S.s6),
            Text('${widget.count}', maxLines: 1, style: countStyle),
          ],
        ]),
      ),
      if (widget.onToggle != null) ...[
        SizedBox(width: S.s6),
        chevron,
      ],
    ]);

    final row = kMobile
        ? Padding(
            padding: EdgeInsets.fromLTRB(0, S.s16, 0, S.s4),
            child: labelRow,
          )
        : Container(
            height: 30,
            alignment: Alignment.bottomLeft,
            padding: EdgeInsets.fromLTRB(8, 0, 8, S.s4),
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
          child: widget.onToggle == null
              ? row
              : kMobile
                  ? GestureDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: () {
                        pickHaptic();
                        widget.onToggle!();
                      },
                      child: row,
                    )
                  : HoverSurface(
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
    this.joinAbove = false,
    this.joinBelow = false,
    this.draft = false,
    this.divider = false,
    this.showProject = false,
    this.unread = false,
    this.pinned = false,
    this.renameField,
    this.leading,
    this.provider,
    this.machine,
    this.onReviewPr,
    this.onMergePr,
    this.onTogglePin,
    this.onMore,
    this.onDecide,
  });

  final SessionInfo session;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final GestureTapDownCallback? onSecondaryTapDown;
  final bool selected;
  final bool selecting;
  final bool checked;

  /// The neighbour is checked too, so the tints meet without a rounded edge.
  final bool joinAbove;
  final bool joinBelow;
  final bool draft;
  final bool divider;
  final bool showProject;
  final bool unread;
  final bool pinned;

  /// Replaces the title while renaming.
  final Widget? renameField;

  /// Leading agent, provider or neutral mark aligned with the title line.
  final Widget? leading;

  /// Desktop meta line: the profile's provider and the machine it runs on.
  final String? provider;
  final String? machine;

  final VoidCallback? onReviewPr;
  final VoidCallback? onMergePr;

  /// Desktop hover actions: pin and the existing right-click menu.
  final VoidCallback? onTogglePin;
  final void Function(Offset position)? onMore;

  /// Desktop inline Deny / Approve for a pending tool approval.
  final void Function(bool approve)? onDecide;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final settled = s.settled;
    final needsYou = sessionNeedsYou(s);
    final working = !settled && !needsYou && sessionBusy(s);
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
    final attn = needsYou ? sessionAttentionState(s) : null;
    final noRepo = !showProject && branch.isEmpty && !s.isGit;
    final pr = !settled ? s.pr : null;
    final wakeText = !settled && !working && !needsYou
        ? sessionWakeLabel(s.nextWakeAt)
        : null;
    final progressText = working ? sessionProgressLabel(s) : null;
    final hasExtraLine = progressText != null || pr != null || wakeText != null;
    final cameBackSummary =
        sessionCameBack(s) ? (s.resultSummary?.trim() ?? '') : '';
    final hasMeta = showProject ||
        needsYou ||
        branch.isNotEmpty ||
        diff != null ||
        noRepo ||
        cameBackSummary.isNotEmpty;

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
          SizedBox(width: kMobile ? S.s12 : S.of(9)),
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
                  if (pinned && renameField == null) ...[
                    SizedBox(width: S.s6),
                    AppIcon('pin', size: 11, color: AppColors.fg3),
                  ],
                  if (s.keepAwake && renameField == null) ...[
                    SizedBox(width: S.s6),
                    AppIcon('lock', size: 11, color: AppColors.fg3),
                  ],
                  if (renameField == null && working) ...[
                    SizedBox(width: S.s8),
                    const WorkingDots(),
                  ] else if (renameField == null && timeText.isNotEmpty) ...[
                    SizedBox(width: S.s8),
                    Text(timeText,
                        maxLines: 1,
                        style: (kMobile ? TS.meta : TS.caption)(timeColor)),
                  ],
                ]),
              ),
              if (hasMeta) SizedBox(height: S.s2),
              if (hasMeta)
                SizedBox(
                  height: kMobile ? 18 : 16,
                  child: cameBackSummary.isNotEmpty
                      ? Align(
                          alignment: Alignment.centerLeft,
                          child: Text(cameBackSummary,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TS.meta(AppColors.fg2)),
                        )
                      : Row(children: [
                          if (attn != null) ...[
                            _StateLabel(state: attn),
                            if (showProject ||
                                branch.isNotEmpty ||
                                diff != null ||
                                noRepo)
                              SizedBox(width: S.s8),
                          ],
                          if (showProject) ...[
                            _ProjectChip(label: projectLabel(s)),
                            if (branch.isNotEmpty) ...[
                              SizedBox(width: S.s8),
                              AppIcon('git-branch',
                                  size: 11, color: AppColors.fg4),
                              SizedBox(width: S.s4),
                              Flexible(
                                child: Text(branch,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TS.meta()),
                              ),
                            ],
                          ] else ...[
                            if (branch.isNotEmpty)
                              Expanded(
                                child: Row(children: [
                                  AppIcon('git-branch',
                                      size: 11, color: AppColors.fg4),
                                  SizedBox(width: S.s4),
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
                                child: Row(children: [
                                  AppIcon('folder-x',
                                      size: 11, color: AppColors.fg4),
                                  SizedBox(width: S.s4),
                                  Flexible(
                                    child: Text('No git repo',
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: TS.meta(AppColors.fg4)),
                                  ),
                                ]),
                              )
                            else if (diff != null)
                              const Spacer(),
                            if (diff != null) ...[
                              if (branch.isNotEmpty || noRepo)
                                SizedBox(width: S.s8),
                              if (diff.added > 0)
                                Text('+${compactCount(diff.added)}',
                                    maxLines: 1, style: TS.meta(AppColors.ok)),
                              if (diff.added > 0 && diff.removed > 0)
                                SizedBox(width: S.s4),
                              if (diff.removed > 0)
                                Text('-${compactCount(diff.removed)}',
                                    maxLines: 1,
                                    style: TS.meta(AppColors.danger)),
                            ],
                          ],
                        ]),
                ),
              if (hasExtraLine) ...[
                const SizedBox(height: 2),
                // Keep desktop rows compact: at most one extra line below metadata.
                if (progressText != null)
                  Text(progressText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TS.meta(AppColors.fg3)),
                if (progressText != null && pr != null)
                  const SizedBox(height: 2),
                if (pr != null)
                  SessionPrActionRow(
                    pr: pr,
                    onReview: onReviewPr,
                    onMerge: onMergePr,
                    mobile: kMobile,
                  )
                else if (wakeText != null && progressText == null)
                  Text(wakeText,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TS.meta(AppColors.fg4)),
              ],
            ],
          ),
        ),
      ],
    );

    // Desktop: title and time over one quiet meta line; no round avatar.
    final compact = !kMobile;
    final approval = needsYou ? approvalOf(s.attention) : null;
    Widget compactContent(bool hover) {
      // Fixed columns so provider, folder, branch and machine line up
      // down the list; the bouncing agent already reads as working.
      final folder =
          s.projectFolder.trim().isEmpty ? '' : projectLabel(s);
      final metaStyle = sans(12, color: AppColors.fg4);
      Widget metaField(String icon, String text) => text.isEmpty
          ? const SizedBox.shrink()
          : Row(mainAxisSize: MainAxisSize.min, children: [
              AppIcon(icon, size: 12, color: AppColors.fg4),
              const SizedBox(width: 4),
              Flexible(
                child: Text(text,
                    maxLines: 1,
                    softWrap: false,
                    overflow: TextOverflow.ellipsis,
                    style: metaStyle),
              ),
            ]);
      // Natural width of an icon + text field, to share space by priority.
      double fieldWidth(String text) => text.isEmpty
          ? 0
          : 17 +
              (TextPainter(
                      text: TextSpan(text: text, style: metaStyle),
                      maxLines: 1,
                      textDirection: TextDirection.ltr)
                    ..layout())
                  .width
                  .ceilToDouble();
      Widget action(String icon, String tip, VoidCallback? tap) => Tooltip(
            message: tip,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: tap,
              child: SizedBox(
                  width: 24,
                  height: 18,
                  child: Center(
                      child: AppIcon(icon, size: 15, color: AppColors.fg3))),
            ),
          );
      final dim = settled || untitled;
      final titleW = renameField ??
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              // The reference's 14px regular title, grey until selected.
              style: sans(14,
                  color: dim
                      ? AppColors.fg4
                      : (selected || hover)
                          ? AppColors.fg1
                          : AppColors.fg3));
      final machineName = (machine ?? '').trim();
      final showMeta = renameField == null &&
          (provider != null ||
              machineName.isNotEmpty ||
              folder.isNotEmpty ||
              branch.isNotEmpty);
      final line = Row(children: [
        Expanded(child: titleW),
        if (pinned && renameField == null) ...[
          const SizedBox(width: 6),
          AppIcon('pin', size: 11, color: AppColors.fg4),
        ],
        if (s.keepAwake && renameField == null) ...[
          const SizedBox(width: 6),
          AppIcon('lock', size: 11, color: AppColors.fg4),
        ],
        // Fixed slot so hovering swaps the time for actions without reflow.
        if (renameField == null && needsYou && !hover) ...[
          const SizedBox(width: 6),
          Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                  color: AppColors.run, shape: BoxShape.circle)),
        ],
        if (renameField == null)
          SizedBox(
            width: 52,
            height: 18,
            child: Stack(alignment: Alignment.centerRight, children: [
              Visibility.maintain(
                visible: !(hover && !selecting),
                child: Text(timeText,
                    maxLines: 1,
                    overflow: TextOverflow.fade,
                    softWrap: false,
                    style: sans(12, color: timeColor, tabular: true)),
              ),
              if (hover && !selecting)
                Row(mainAxisSize: MainAxisSize.min, children: [
                  if (onTogglePin != null)
                    action('pin', pinned ? 'Unpin' : 'Pin', onTogglePin),
                  if (onMore != null)
                    Builder(
                      builder: (ctx) => action('more-horizontal', 'More', () {
                        final box = ctx.findRenderObject() as RenderBox;
                        onMore!(box.localToGlobal(Offset(0, box.size.height)));
                      }),
                    ),
                ]),
            ]),
          ),
      ]);
      final meta = !showMeta
          ? null
          : SizedBox(
              height: 16,
              child: LayoutBuilder(builder: (_, box) {
                // Machine never truncates; folder gives way before branch.
                final machineW =
                    machineName.isEmpty ? 0.0 : 8 + fieldWidth(machineName);
                final lead = provider == null ? 0.0 : 18.0;
                final gap = folder.isNotEmpty && branch.isNotEmpty ? 8.0 : 0.0;
                final avail = box.maxWidth - machineW - lead - gap;
                final branchNat = fieldWidth(branch);
                final folderNat = fieldWidth(folder);
                final branchW = branchNat <= avail - 40 || folder.isEmpty
                    ? branchNat.clamp(0.0, avail)
                    : (avail - folderNat).clamp(40.0, branchNat);
                final folderW = (avail - branchW).clamp(0.0, folderNat);
                return Row(children: [
                  if (provider != null) ...[
                    SizedBox(
                      width: 12,
                      child: ProviderLogo(provider,
                          size: 11,
                          color: providerLogoIsColour(provider)
                              ? null
                              : AppColors.fg3),
                    ),
                    const SizedBox(width: 6),
                  ],
                  if (folder.isNotEmpty)
                    SizedBox(
                        width: folderW, child: metaField('folder', folder)),
                  if (gap > 0) SizedBox(width: gap),
                  if (branch.isNotEmpty)
                    SizedBox(
                        width: branchW, child: metaField('git-branch', branch)),
                  if (machineName.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    // Desktop pins the machine to the row's right edge.
                    if (!kMobile) const Spacer(),
                    metaField('laptop', machineName),
                  ],
                ]);
              }),
            );
      final body = meta == null
          ? line
          : Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [line, const SizedBox(height: 1), meta]);
      if (approval == null || onDecide == null || renameField != null) {
        return body;
      }
      Widget chip(String label, bool ok) => GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onDecide!(ok),
            child: Container(
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 9),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: ok
                    ? AppColors.accentFill
                    : AppColors.fg1.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(R.of(6)),
              ),
              child: Text(label,
                  style: sans(11.5,
                      weight: W.label,
                      color: ok ? AppColors.accentFg : AppColors.fg2)),
            ),
          );
      return Column(mainAxisSize: MainAxisSize.min, children: [
        body,
        Padding(
          padding: const EdgeInsets.only(top: 4),
          child: Row(children: [
            chip('Deny', false),
            const SizedBox(width: 6),
            chip('Approve', true),
          ]),
        ),
      ]);
    }

    void longPress() {
      holdHaptic();
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
                        borderRadius: BorderRadius.vertical(
                          top: Radius.circular(joinAbove ? 0 : R.md),
                          bottom: Radius.circular(joinBelow ? 0 : R.md),
                        ))),
              ),
            Pressable(
              kind: PressKind.row,
              child: Material(
                color: Colors.transparent,
                child: InkWell(
                  onTap: onTap == null
                      ? null
                      : () {
                          tapHaptic();
                          onTap!();
                        },
                  splashFactory: NoSplash.splashFactory,
                  highlightColor: Colors.transparent,
                  hoverColor: Colors.transparent,
                  focusColor: Colors.transparent,
                  overlayColor:
                      const WidgetStatePropertyAll(Colors.transparent),
                  onLongPress: onLongPress == null ? null : longPress,
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    ConstrainedBox(
                      constraints: BoxConstraints(minHeight: M.minTarget),
                      child: Padding(
                        padding: EdgeInsets.symmetric(vertical: S.s8),
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
        : _HoverBuilder(
            builder: (hover) => HoverSurface(
                  selected: selecting ? checked : selected,
                  radius: R.of(8),
                  selectedColor: AppColors.surface3,
                  hoverColor: AppColors.fg1.withValues(alpha: 0.07),
                  onTap: onTap,
                  onLongPress: onLongPress == null ? null : longPress,
                  onSecondaryTapDown: onSecondaryTapDown,
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(minHeight: 44),
                    child: Padding(
                      // 8 here + 8 list inset = the 16px sidebar edge.
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 4),
                      child: Align(
                          alignment: Alignment.centerLeft,
                          child: !compact ? content : compactContent(hover)),
                    ),
                  ),
                ));

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
      SizedBox(width: S.s4),
      Text(state.label, maxLines: 1, style: TS.meta(color)),
    ]);
  }
}

class _ProjectChip extends StatelessWidget {
  const _ProjectChip({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Flexible(
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        AppIcon('folder', size: 11, color: AppColors.fg4),
        SizedBox(width: S.s4),
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

class _WorkingDotsState extends State<WorkingDots> {
  final _c = AmbientLoop(const Duration(milliseconds: 900));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _c.bind(context);
    if (reduceMotion(context)) {
      _c.stop();
    } else {
      _c.start();
    }
  }

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
    return Semantics(
      label: 'Working',
      excludeSemantics: true,
      child: SizedBox(
        width: 14,
        height: 8,
        child: RepaintBoundary(
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
        )),
      ),
    );
  }
}

/// Hands its builder the hover state of the pointer over the whole row.
class _HoverBuilder extends StatefulWidget {
  const _HoverBuilder({required this.builder});

  final Widget Function(bool hover) builder;

  @override
  State<_HoverBuilder> createState() => _HoverBuilderState();
}

class _HoverBuilderState extends State<_HoverBuilder> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: widget.builder(_hover),
      );
}

/// Two letters of a workspace folder in a 14 px tile, tinted from a hash of
/// the folder name so each project keeps its colour.
class WorkspaceChip extends StatelessWidget {
  const WorkspaceChip({super.key, required this.folder});

  final String folder;

  static String initials(String folder) {
    final parts =
        folder.split(RegExp(r'[-_.\s]+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length >= 2) return (parts[0][0] + parts[1][0]).toUpperCase();
    final p = parts.first;
    return (p.length >= 2 ? p.substring(0, 2) : p).toUpperCase();
  }

  @override
  Widget build(BuildContext context) {
    var h = 7;
    for (final c in folder.codeUnits) {
      h = (h * 31 + c) & 0x7FFFFFFF;
    }
    final hue = (h % 360).toDouble();
    final dark = ThemeData.estimateBrightnessForColor(AppColors.windowBg) ==
        Brightness.dark;
    final tint = HSLColor.fromAHSL(1, hue, 0.55, dark ? 0.72 : 0.38).toColor();
    return Row(mainAxisSize: MainAxisSize.min, children: [
      Container(
        width: 14,
        height: 14,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: tint.withValues(alpha: 0.18),
          borderRadius: BorderRadius.circular(R.of(3)),
        ),
        child: Text(initials(folder),
            style: sans(8, weight: FontWeight.w600, color: tint)),
      ),
      const SizedBox(width: 4),
      Flexible(
        child: Text(folder,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: sans(11, color: AppColors.fg4)),
      ),
    ]);
  }
}
