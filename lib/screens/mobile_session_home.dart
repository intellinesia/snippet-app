import 'package:flutter/material.dart';

import '../ambient_loop.dart';
import '../ink.dart';
import '../models.dart';
import '../mochi.dart';
import '../notification_text.dart';
import '../theme.dart';
import '../widgets.dart';
import 'phone_hero.dart' show heroAgentColor;
import 'session_list_row.dart';

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
      padding: EdgeInsets.fromLTRB(S.s4, top, S.s4, S.s8),
      child: Row(children: [
        if (icon != null) ...[
          AppIcon(icon!, size: 14, color: c),
          SizedBox(width: S.s6),
        ],
        Flexible(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(13, weight: W.label, color: c)),
        ),
        if (count != null) ...[
          SizedBox(width: S.s6),
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
        borderRadius: BorderRadius.circular(R.of(14)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: S.of(14)),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: children,
          ),
        ),
      );
}

/// A needs-you, running or came-back session, shown as a card on the phone list.
class LiveSessionCard extends StatefulWidget {
  const LiveSessionCard({
    super.key,
    required this.session,
    required this.onTap,
    this.onLongPress,
    this.leading,
    this.pinned = false,
    this.onReviewPr,
    this.onMergePr,
    this.onDecide,
  });

  final SessionInfo session;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Widget? leading;
  final bool pinned;
  final VoidCallback? onReviewPr;
  final VoidCallback? onMergePr;

  /// Approve (true) or deny (false) the pending approval; null hides the buttons.
  final Future<void> Function(SessionInfo session, bool approve)? onDecide;

  static String? _attentionText(SessionInfo s) {
    final a = s.attention;
    if (a == null) return null;
    final approval = approvalPreview(a);
    if (approval != null) return approval;
    for (final k in const ['summary', 'text', 'question', 'message']) {
      final v = a[k];
      if (v is String && v.trim().isNotEmpty) return v.trim();
    }
    return null;
  }

  @override
  State<LiveSessionCard> createState() => _LiveSessionCardState();
}

class _LiveSessionCardState extends State<LiveSessionCard> {
  bool _busy = false;

  Future<void> _decide(bool ok) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onDecide!(widget.session, ok);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  static String _cap(String v) =>
      v.isEmpty ? v : '${v[0].toUpperCase()}${v.substring(1)}';

  static String _checks(SessionPr pr) => switch (pr.checks) {
        'passing' => 'Checks passed',
        'failing' => 'Checks failing',
        'pending' => 'Checks running',
        _ => pr.state == 'draft' ? 'Draft' : 'Open',
      };

  Widget _statusLine(
          {required Widget lead, required String text, Color? ink}) =>
      Row(children: [
        SizedBox(width: 18, child: Center(child: lead)),
        SizedBox(width: S.s8),
        Expanded(
          child: Text(text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: sans(14, height: 1.35, color: ink ?? AppColors.fg1)),
        ),
      ]);

  Widget _button(String label, VoidCallback? onTap,
      {String? icon, Color? color, Color? ink}) {
    final fg = ink ?? AppColors.fg1;
    return Opacity(
      opacity: onTap == null ? 0.5 : 1,
      child: Material(
        color: color ?? AppColors.surface3,
        borderRadius: BorderRadius.circular(R.of(12)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap == null
              ? null
              : () {
                  tapHaptic();
                  onTap();
                },
          child: SizedBox(
            height: M.minTarget,
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (icon != null) ...[
                AppIcon(icon, size: 16, color: fg),
                SizedBox(width: S.s6),
              ],
              Text(label, style: sans(15, weight: W.label, color: fg)),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final needsYou = sessionNeedsYou(s);
    final cameBack = sessionCameBack(s);
    final agent = s.displayAgentId?.trim() ?? '';
    final colour = agent.isEmpty ? AppColors.accent : heroAgentColor(agent);
    final plan = !needsYou && !cameBack && s.plan != null && s.plan!.total > 0
        ? s.plan
        : null;
    final att = s.attention ?? const <String, dynamic>{};
    final isApproval =
        needsYou && att['type'] == 'approval' && approvalOf(att) != null;
    final isQuestion = '${att['type'] ?? ''}'.toLowerCase() == 'question';
    final canDecide = isApproval && widget.onDecide != null;
    final pr = s.pr;
    final openPr = pr != null && pr.state == 'open';
    final branch = s.branch?.trim() ?? '';
    final title = s.title.trim().isEmpty ? '(untitled)' : s.title.trim();
    final lanesText = sessionLanesLabel(s.lanes);
    final sub = lanesText;

    final String age;
    if (needsYou || cameBack) {
      age = relativeTime(s.lastActive);
    } else {
      age = sessionDuration(plan != null
          ? (plan.stepStartedAt ?? s.runningSince)
          : s.runningSince);
    }
    final name = agent.isEmpty ? '' : _cap(agent);
    final String footLeft;
    if (cameBack) {
      footLeft = name.isEmpty ? 'Finished' : '$name · finished';
    } else if (plan != null) {
      final step = _cap(sessionStepLabel(plan));
      footLeft = name.isEmpty ? step : '$step · $name';
    } else {
      final base = needsYou ? sessionAttentionState(s).label : 'Working';
      footLeft = name.isEmpty ? base : '$base · $name';
    }

    final Widget status;
    if (needsYou) {
      status = _statusLine(
        lead: AppIcon(isApproval || isQuestion ? 'key' : 'message',
            size: 16, color: AppColors.fg3),
        text:
            LiveSessionCard._attentionText(s) ?? sessionAttentionState(s).label,
      );
    } else if (cameBack) {
      final files = s.shownChanges?.files ?? 0;
      final summary = s.resultSummary?.trim() ?? '';
      status = _statusLine(
        lead: AppIcon('pull-request',
            size: 16, color: pr == null ? AppColors.fg3 : sessionPrColor(pr)),
        text: pr != null
            ? 'PR #${pr.number} · ${_checks(pr)}${files > 0 ? ' · $files file${files == 1 ? '' : 's'}' : ''}'
            : (summary.isEmpty ? 'Finished' : summary),
      );
    } else {
      status = _statusLine(
        lead: Container(
            width: 8,
            height: 8,
            decoration:
                BoxDecoration(color: AppColors.fg2, shape: BoxShape.circle)),
        text: plan?.current?.trim().isNotEmpty == true
            ? plan!.current!.trim()
            : 'Working',
      );
    }

    final avatar = agent.isNotEmpty
        ? AgentMochi(agent,
            size: 36,
            state: needsYou
                ? AgentCharacterState.needs
                : cameBack
                    ? AgentCharacterState.done
                    : AgentCharacterState.working,
            badge: needsYou ? '?' : null)
        : (widget.leading == null
            ? null
            : SizedBox.square(
                dimension: 36, child: Center(child: widget.leading)));

    return Padding(
      padding: EdgeInsets.only(bottom: S.of(10)),
      child: Semantics(
        button: true,
        label: '${cameBack ? 'Completed' : footLeft}. $title',
        child: Material(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(R.of(20)),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            overlayColor: const WidgetStatePropertyAll(Colors.transparent),
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
            hoverColor: Colors.transparent,
            focusColor: Colors.transparent,
            onTap: widget.onTap == null
                ? null
                : () {
                    tapHaptic();
                    widget.onTap!();
                  },
            onLongPress: widget.onLongPress == null
                ? null
                : () {
                    holdHaptic();
                    widget.onLongPress!();
                  },
            child: Container(
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(R.of(20)),
              ),
              padding: EdgeInsets.fromLTRB(S.s16, S.of(14), S.s16, S.of(14)),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [
                            if (widget.pinned) ...[
                              AppIcon('pin', size: 12, color: AppColors.fg3),
                              SizedBox(width: S.s6),
                            ],
                            Expanded(
                              child: Text(title,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: sans(17,
                                      weight: W.label,
                                      height: 1.3,
                                      color: AppColors.fg1)),
                            ),
                          ]),
                          SizedBox(height: S.s2),
                          Row(children: [
                            Flexible(
                              child: Text(projectLabel(s),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: sans(13, color: AppColors.fg3)),
                            ),
                            if (branch.isNotEmpty) ...[
                              SizedBox(width: S.s8),
                              AppIcon('git-branch',
                                  size: 12, color: AppColors.fg3),
                              SizedBox(width: S.s4),
                              Flexible(
                                child: Text(branch,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: mono(12, color: AppColors.fg3)),
                              ),
                            ],
                          ]),
                        ],
                      ),
                    ),
                    if (avatar != null) ...[SizedBox(width: S.s12), avatar],
                  ]),
                  SizedBox(height: S.s12),
                  status,
                  if (sub != null) ...[
                    SizedBox(height: S.s8),
                    Row(children: [
                      Container(
                        width: 18,
                        height: 18,
                        decoration: BoxDecoration(
                            color: AppColors.surface3, shape: BoxShape.circle),
                        child: Center(
                            child: AppIcon('layers',
                                size: 11, color: AppColors.fg3)),
                      ),
                      SizedBox(width: S.s8),
                      Expanded(
                        child: Text(sub,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(13, color: AppColors.fg3)),
                      ),
                    ]),
                  ],
                  if (plan != null) ...[
                    SizedBox(height: S.s12),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        key: const Key('card-progress'),
                        value: (plan.done / plan.total).clamp(0.0, 1.0),
                        minHeight: 6,
                        backgroundColor: AppColors.surface3,
                        valueColor: AlwaysStoppedAnimation(colour),
                      ),
                    ),
                  ],
                  if (canDecide) ...[
                    SizedBox(height: S.s12),
                    Row(children: [
                      Expanded(
                          child: _button(
                              'Deny', _busy ? null : () => _decide(false))),
                      SizedBox(width: S.s8),
                      Expanded(
                          flex: 2,
                          child: _button(
                              'Approve', _busy ? null : () => _decide(true),
                              icon: 'check', color: colour, ink: inkOn(colour))),
                    ]),
                  ] else if (cameBack &&
                      openPr &&
                      widget.onReviewPr != null) ...[
                    SizedBox(height: S.s12),
                    Row(children: [
                      Expanded(
                          child: _button('Review', widget.onReviewPr,
                              icon: 'eye')),
                      if (widget.onMergePr != null) ...[
                        SizedBox(width: S.s8),
                        Expanded(
                            flex: 2,
                            child: _button('Merge', widget.onMergePr,
                                icon: 'pull-request',
                                color: colour,
                                ink: inkOn(colour))),
                      ],
                    ]),
                  ] else if (!needsYou && !cameBack && pr != null) ...[
                    SizedBox(height: S.s8),
                    SessionPrActionRow(
                      pr: pr,
                      onReview: widget.onReviewPr,
                      onMerge: widget.onMergePr,
                      mobile: true,
                    ),
                  ],
                  SizedBox(height: S.s12),
                  Row(children: [
                    Expanded(
                      child: Text(footLeft,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(12, color: AppColors.fg3)),
                    ),
                    if (age.isNotEmpty)
                      Text(age, style: sans(12, color: AppColors.fg3)),
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// A breathing ring that marks a control as live, such as Lead
/// while ambient voice is on.
class LiveRing extends StatefulWidget {
  const LiveRing({super.key, required this.live, required this.child});

  final bool live;
  final Widget child;

  @override
  State<LiveRing> createState() => _LiveRingState();
}

class _LiveRingState extends State<LiveRing> {
  final _c = AmbientLoop(const Duration(milliseconds: 1600), reverse: true);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _c.bind(context);
    _sync();
  }

  @override
  void didUpdateWidget(covariant LiveRing oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  void _sync() {
    if (widget.live && !reduceMotion(context)) {
      _c.start();
    } else {
      _c.stop(at: widget.live ? 1 : 0);
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
