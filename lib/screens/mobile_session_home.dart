import 'dart:typed_data';
import 'dart:ui' show PointMode;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../ambient_loop.dart';
import '../glass.dart';
import '../models.dart';
import '../mochi.dart';
import '../notification_text.dart';
import '../theme.dart';
import '../widgets.dart';
import 'mobile_chrome.dart';
import 'phone_hero.dart' show heroAgentColor;
import 'session_list_row.dart';

/// Phone home top bar: the Sessions / Agents switch with search and settings.
/// Search swaps the row for a field until it is cleared and closed.
class MobileHomeTopBar extends StatefulWidget {
  const MobileHomeTopBar({
    super.key,
    required this.agents,
    required this.controller,
    required this.focusNode,
    required this.onChanged,
    required this.onSessions,
    required this.onAgents,
    this.onSettings,
  });

  final bool agents;
  final TextEditingController controller;
  final FocusNode focusNode;
  final ValueChanged<String> onChanged;
  final VoidCallback onSessions;
  final VoidCallback onAgents;
  final VoidCallback? onSettings;

  @override
  State<MobileHomeTopBar> createState() => _MobileHomeTopBarState();
}

class _MobileHomeTopBarState extends State<MobileHomeTopBar> {
  late bool _searching = widget.controller.text.isNotEmpty;

  void _open() {
    setState(() => _searching = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.focusNode.requestFocus();
    });
  }

  void _close() {
    widget.controller.clear();
    widget.onChanged('');
    widget.focusNode.unfocus();
    setState(() => _searching = false);
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(M.gutter, S.s6, M.gutter, S.of(10)),
        child: SizedBox(
          height: 44,
          child: AnimatedSwitcher(
            duration: Motion.base,
            child: _searching
                ? Row(key: const ValueKey('search'), children: [
                    Expanded(child: _field()),
                    SizedBox(width: S.s8),
                    RoundBtn(
                        icon: 'x', tooltip: 'Close search', onTap: _close),
                  ])
                : Row(key: const ValueKey('tabs'), children: [
                    Expanded(child: _segment()),
                    SizedBox(width: S.s8),
                    RoundBtn(icon: 'search', tooltip: 'Search', onTap: _open),
                    if (widget.onSettings != null) ...[
                      SizedBox(width: S.s8),
                      RoundBtn(
                          icon: 'settings',
                          tooltip: 'Settings',
                          onTap: widget.onSettings),
                    ],
                  ]),
          ),
        ),
      );

  Widget _segment() => Container(
        height: 40,
        padding: EdgeInsets.all(S.of(3)),
        decoration: BoxDecoration(
          color: AppColors.tint2,
          borderRadius: BorderRadius.circular(R.pill),
        ),
        child: Row(children: [
          _seg('Sessions', !widget.agents, widget.onSessions),
          _seg('Agents', widget.agents, widget.onAgents),
        ]),
      );

  Widget _seg(String label, bool on, VoidCallback onTap) => Expanded(
        child: Semantics(
          button: true,
          selected: on,
          label: label,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: on
                ? null
                : () {
                    HapticFeedback.selectionClick();
                    onTap();
                  },
            child: AnimatedContainer(
              duration: Motion.fast,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on ? AppColors.surface3 : Colors.transparent,
                borderRadius: BorderRadius.circular(R.pill),
              ),
              child: Text(label,
                  style: sans(14,
                      weight: on ? W.label : W.body,
                      color: on ? AppColors.fg1 : AppColors.fg3)),
            ),
          ),
        ),
      );

  Widget _field() => Container(
        height: 40,
        padding: EdgeInsets.symmetric(horizontal: S.s12),
        decoration: BoxDecoration(
          color: AppColors.tint2,
          borderRadius: BorderRadius.circular(R.lg),
        ),
        child: Row(children: [
          AppIcon('search', size: 16, color: AppColors.fg4),
          SizedBox(width: S.s8),
          Expanded(
            child: TextField(
              controller: widget.controller,
              focusNode: widget.focusNode,
              onChanged: widget.onChanged,
              textInputAction: TextInputAction.search,
              style: sans(15, color: AppColors.fg1),
              cursorColor: AppColors.accent,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: widget.agents ? 'Search agents' : 'Search sessions',
                hintStyle: sans(15, color: AppColors.fg4),
              ),
            ),
          ),
        ]),
      );
}

/// The phone home's bottom bar: Mission Control as an input, with its badge,
/// a live ring while voice is on, and the call button.
class MissionControlDock extends StatelessWidget {
  const MissionControlDock({
    super.key,
    required this.onOpen,
    this.onCall,
    this.live = false,
    this.badgeCount = 0,
  });

  final VoidCallback onOpen;
  final VoidCallback? onCall;
  final bool live;
  final int badgeCount;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: 'Ask Mission Control',
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            tapHaptic();
            onOpen();
          },
          child: Glass(
            radius: BorderRadius.circular(R.of(28)),
            child: SizedBox(
              height: 56,
              child: Row(children: [
                SizedBox(width: S.s6),
                LiveRing(
                  live: live,
                  child: RoundBtn(
                    tooltip: live ? 'Mission Control, voice on' : 'Mission Control',
                    size: 44,
                    bare: true,
                    badgeCount: badgeCount,
                    onTap: onOpen,
                    child: MochiIcon(
                        color: live ? AppColors.ok : AppColors.fg1, size: 24),
                  ),
                ),
                SizedBox(width: S.s12),
                Expanded(
                  child: Text('Ask Mission Control',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(15, color: AppColors.fg3)),
                ),
                if (onCall != null)
                  RoundBtn(
                    tooltip: live ? 'Voice call' : 'Start voice',
                    size: 44,
                    bare: true,
                    onTap: onCall,
                    child: AppIcon('phone',
                        size: 20, color: live ? AppColors.ok : AppColors.fg2),
                  ),
                SizedBox(width: S.s6),
              ]),
            ),
          ),
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

  static Color _ink(Color c) =>
      c.computeLuminance() > 0.45 ? const Color(0xFF14141A) : Colors.white;

  static String _cap(String v) =>
      v.isEmpty ? v : '${v[0].toUpperCase()}${v.substring(1)}';

  static String _checks(SessionPr pr) => switch (pr.checks) {
        'passing' => 'Checks passed',
        'failing' => 'Checks failing',
        'pending' => 'Checks running',
        _ => pr.state == 'draft' ? 'Draft' : 'Open',
      };

  Widget _statusLine({required Widget lead, required String text, Color? ink}) =>
      Row(children: [
        SizedBox(width: 18, child: Center(child: lead)),
        SizedBox(width: S.s8),
        Expanded(
          child: Text(text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: sans(15, height: 1.35, color: ink ?? AppColors.fg1)),
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
    final isApproval = needsYou && att['type'] == 'approval' && approvalOf(att) != null;
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
        text: LiveSessionCard._attentionText(s) ?? sessionAttentionState(s).label,
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
            decoration: BoxDecoration(color: AppColors.ok, shape: BoxShape.circle)),
        text: plan?.current?.trim().isNotEmpty == true ? plan!.current!.trim() : 'Working',
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
            : SizedBox.square(dimension: 36, child: Center(child: widget.leading)));

    return Padding(
      padding: EdgeInsets.only(bottom: S.of(10)),
      child: Semantics(
        button: true,
        label: '${cameBack ? 'Came back' : footLeft}. $title',
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
                borderRadius: BorderRadius.circular(R.of(20)),
                border: Border.all(color: AppColors.line),
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
                              AppIcon('git-branch', size: 12, color: AppColors.fg3),
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
                            child: AppIcon('layers', size: 11, color: AppColors.fg3)),
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
                          child: _button('Deny', _busy ? null : () => _decide(false))),
                      SizedBox(width: S.s8),
                      Expanded(
                          flex: 2,
                          child: _button('Approve', _busy ? null : () => _decide(true),
                              icon: 'check', color: colour, ink: _ink(colour))),
                    ]),
                  ] else if (cameBack && openPr && widget.onReviewPr != null) ...[
                    SizedBox(height: S.s12),
                    Row(children: [
                      Expanded(
                          child: _button('Review', widget.onReviewPr, icon: 'eye')),
                      if (widget.onMergePr != null) ...[
                        SizedBox(width: S.s8),
                        Expanded(
                            flex: 2,
                            child: _button('Merge', widget.onMergePr,
                                icon: 'pull-request', color: colour, ink: _ink(colour))),
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

/// A breathing ring that marks a control as live, such as Mission Control
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

/// Faint dot grid painted behind the phone home lists.
class DotField extends StatelessWidget {
  const DotField({super.key, required this.child, this.strength = 0.07});

  /// Faint enough to sit behind a chat transcript.
  const DotField.chat({super.key, required this.child}) : strength = 0.06;

  final Widget child;
  final double strength;

  @override
  Widget build(BuildContext context) => CustomPaint(
        painter: _DotGridPainter(AppColors.fg1.withValues(alpha: strength)),
        child: RepaintBoundary(child: child),
      );
}

class _DotGridPainter extends CustomPainter {
  _DotGridPainter(this.color);

  final Color color;

  static Size? _size;
  static Float32List? _points;

  // One point batch instead of thousands of circles; Impeller redraws it every frame.
  static Float32List _grid(Size size) {
    if (size == _size && _points != null) return _points!;
    const step = 12.0;
    int count(double extent) => ((extent - step / 2) / step).ceil().clamp(0, 1 << 16);
    final cols = count(size.width), rows = count(size.height);
    final out = Float32List(cols * rows * 2);
    var i = 0;
    for (var r = 0; r < rows; r++) {
      for (var c = 0; c < cols; c++) {
        out[i++] = step / 2 + c * step;
        out[i++] = step / 2 + r * step;
      }
    }
    _size = size;
    return _points = out;
  }

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRawPoints(
        PointMode.points,
        _grid(size),
        Paint()
          ..color = color
          ..strokeWidth = 1.8
          ..strokeCap = StrokeCap.round);
  }

  @override
  bool shouldRepaint(_DotGridPainter old) => old.color != color;
}
