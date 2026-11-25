import 'package:flutter/material.dart';

import 'dart:async';

import '../api.dart';
import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import '../transcript.dart'
    show LaneControlButton, LaneWho, RunSpinner, laneFirstSentence;
import '../tap_detector.dart';
import 'compact_btn.dart';
import 'spec_bar.dart';
import 'lanes.dart' show laneSections, openLaneView;

/// Human-readable checkpoint timestamp ('Today · 3:04 PM').
///
/// Lives here rather than in session.dart so this shared module has no
/// dependency back on the session screen — the direction is session -> panels.
/// session.dart imports it from here.
String formatCheckpointDate(String raw) {
  final parsed = DateTime.tryParse(raw)?.toLocal();
  if (parsed == null) return raw;

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final day = DateTime(parsed.year, parsed.month, parsed.day);
  final daysAgo = today.difference(day).inDays;
  final hour = parsed.hour == 0
      ? 12
      : (parsed.hour > 12 ? parsed.hour - 12 : parsed.hour);
  final minute = parsed.minute.toString().padLeft(2, '0');
  final meridiem = parsed.hour >= 12 ? 'PM' : 'AM';
  final time = '$hour:$minute $meridiem';

  if (daysAgo == 0) return 'Today · $time';
  if (daysAgo == 1) return 'Yesterday · $time';
  if (daysAgo >= 0 && daysAgo < 7) {
    const weekdays = <String>['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return '${weekdays[parsed.weekday - 1]} · $time';
  }
  const months = <String>[
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];
  final date = '${months[parsed.month - 1]} ${parsed.day}, ${parsed.year}';
  return '$date · $time';
}

/// Session panels that render in a host.
///
/// Scaffold-free on purpose: the shell's right pane hosts them directly, and the
/// session's own drawer hosts the same widgets, so the two can never show a
/// different Checkpoints and Lanes view. Before this each had its own
/// copy and they were already drifting.

/// Checkpoint history. `onRewind`/`onFork` are supplied by the host so the shell
/// and the session route the action back through the same session handler.
class SessionCheckpointsPanel extends StatefulWidget {
  const SessionCheckpointsPanel({
    super.key,
    required this.checkpoints,
    required this.onRewind,
    required this.onFork,
    this.client,
    this.sessionId,
    this.below,
    this.embedded = false,
  });

  final DaemonClient? client;
  final String? sessionId;

  final List<Checkpoint> checkpoints;
  final void Function(Checkpoint) onRewind;
  final void Function(Checkpoint) onFork;

  /// Shown under the list, e.g. the session's file changes on desktop.
  final Widget? below;

  /// Sized to its content and without its own side padding, for a host that scrolls.
  final bool embedded;

  @override
  State<SessionCheckpointsPanel> createState() =>
      _SessionCheckpointsPanelState();
}

class _SessionCheckpointsPanelState extends State<SessionCheckpointsPanel> {
  Map<String, ({int files, int add, int del})> _stats = const {};
  String _statsFor = '';

  @override
  void initState() {
    super.initState();
    _loadStats();
  }

  @override
  void didUpdateWidget(SessionCheckpointsPanel old) {
    super.didUpdateWidget(old);
    _loadStats();
  }

  Future<void> _loadStats() async {
    final c = widget.client;
    final sid = widget.sessionId;
    if (c == null || sid == null) return;
    final ids = [for (final cp in widget.checkpoints.reversed) cp.id];
    final sig = ids.join(',');
    if (sig == _statsFor || ids.isEmpty) return;
    _statsFor = sig;
    try {
      final s = await c.checkpointStats(sid, ids);
      if (mounted) setState(() => _stats = s);
    } catch (_) {}
  }

  String _stat(String id) {
    final s = _stats[id];
    if (s == null) return '';
    if (s.files == 0) return 'no changes';
    return '${s.files} file${s.files == 1 ? '' : 's'}';
  }

  Widget _row(Checkpoint c, bool latest) {
    final stat = _stat(c.id);
    final sub = [formatCheckpointDate(c.createdAt), if (stat.isNotEmpty) stat]
        .join(' \u00b7 ');
    final title = c.label.trim().isEmpty
        ? 'Checkpoint'
        : c.label.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (kMobile) return _phoneRow(c, latest, title, sub);
    final text = Row(children: [
      Text(title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: sans(13, weight: W.label, color: AppColors.fg1)),
      SizedBox(width: S.s8),
      Flexible(
          child: Text(sub,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(12, color: AppColors.fg4))),
    ]);
    return Container(
      constraints: const BoxConstraints(minHeight: 36),
      padding: EdgeInsets.fromLTRB(S.s8, S.s2, S.s8, S.s2),
      child: Row(children: [
        Container(
          width: 22,
          height: 22,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surface3,
            borderRadius: BorderRadius.circular(R.sm),
          ),
          child: AppIcon('history', size: 13, color: AppColors.fg3),
        ),
        SizedBox(width: S.s8),
        Expanded(child: text),
        // The newest checkpoint is the present state: nothing to restore, and
        // forking the present lives on the actions sheet's Fork tile.
        if (!latest) ...[
          SizedBox(width: S.s8),
          CompactBtn('Restore', onTap: () => widget.onRewind(c)),
          SizedBox(width: S.s4),
          CompactBtn('Fork', onTap: () => widget.onFork(c)),
        ],
      ]),
    );
  }

  /// SE-07 phone row: min 62, title at x16, Restore 88 x 48, hairline x16 to
  /// the right gutter. Restore asks first (the host confirms before rewinding).
  Widget _phoneRow(Checkpoint c, bool latest, String title, String sub) =>
      Container(
        constraints: const BoxConstraints(minHeight: 62),
        padding: const EdgeInsets.only(left: 16, right: 16),
        decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(color: AppColors.border, width: 1))),
        child: Row(children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(15, color: AppColors.fg1)),
                    Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(12, color: AppColors.fg3)),
                  ]),
            ),
          ),
          if (!latest) ...[
            const SizedBox(width: 8),
            Semantics(
              button: true,
              label: 'Restore $title',
              child: ExcludeSemantics(
                child: TapDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => widget.onRewind(c),
                  child: Container(
                    width: 88,
                    height: 48,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: AppColors.border)),
                    child: Text('Restore',
                        style:
                            sans(13, weight: W.label, color: AppColors.fg1)),
                  ),
                ),
              ),
            ),
          ],
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final cps = widget.checkpoints;
    if (cps.isEmpty) {
      final below = widget.below;
      final empty = Padding(
        padding: EdgeInsets.all(S.s20),
        child: Text('No checkpoints yet.', style: TS.meta()),
      );
      if (below == null) return empty;
      // File changes exist without checkpoints, so keep them reachable.
      return ListView(
        shrinkWrap: widget.embedded,
        physics: widget.embedded ? const NeverScrollableScrollPhysics() : null,
        padding: EdgeInsets.symmetric(
            horizontal: widget.embedded ? 0 : (kMobile ? M.gutter : S.s12)),
        children: [empty, below],
      );
    }
    final side = widget.embedded || kMobile ? 0.0 : S.s12;
    return ListView(
      shrinkWrap: widget.embedded,
      physics: widget.embedded ? const NeverScrollableScrollPhysics() : null,
      padding: EdgeInsets.fromLTRB(side, S.s12, side, S.s24),
      children: [
        Padding(
          padding: kMobile
              ? const EdgeInsets.fromLTRB(16, 0, 16, 8)
              : EdgeInsets.fromLTRB(S.s4, 0, S.s4, S.s8),
          child: Row(children: [
            Expanded(
              child: Text('Checkpoints \u00b7 ${cps.length}',
                  style: sans(13, color: AppColors.fg3)),
            ),
            Text('Files roll back too', style: sans(12, color: AppColors.fg4)),
          ]),
        ),
        if (kMobile)
          for (var i = 0; i < cps.length; i++) _row(cps[i], i == 0)
        else
          CardGroupScope(
            child: ListGroup(children: [
              for (var i = 0; i < cps.length; i++) _row(cps[i], i == 0),
            ]),
          ),
        if (widget.below != null) widget.below!,
      ],
    );
  }
}

/// Delegated lanes, reusing the public `LaneDetailCard` so the pane and the
/// full Lanes screen cannot diverge.
class SessionLanesPanel extends StatefulWidget {
  const SessionLanesPanel(
      {super.key, required this.lanes, this.client, this.sessionId});
  final List<LaneInfo> lanes;
  final DaemonClient? client;
  final String? sessionId;

  @override
  State<SessionLanesPanel> createState() => _SessionLanesPanelState();
}

class _SessionLanesPanelState extends State<SessionLanesPanel> {
  String? _sessionProfile;

  @override
  void initState() {
    super.initState();
    _loadProfile();
  }

  @override
  void didUpdateWidget(SessionLanesPanel old) {
    super.didUpdateWidget(old);
    if (old.sessionId != widget.sessionId) _loadProfile();
  }

  Future<void> _loadProfile() async {
    final c = widget.client;
    final id = widget.sessionId;
    if (c == null || id == null) return;
    try {
      final all = await c.sessions();
      if (!mounted || widget.sessionId != id) return;
      String? hit;
      for (final s in all) {
        if (s.id == id) hit = s.profile;
      }
      setState(() => _sessionProfile = hit);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final lanes = widget.lanes;
    final client = widget.client;
    if (!kMobile) {
      return _DeskLanes(
          lanes: lanes,
          client: client,
          sessionId: widget.sessionId,
          sessionProfile: _sessionProfile);
    }
    if (lanes.isEmpty) {
      return const EmptyState(
          icon: 'layers',
          title: 'No delegated lanes',
          body: 'Parallel agent work will appear here when started.');
    }
    final side = kMobile ? M.gutter : S.s12;
    return ListView(
      padding: EdgeInsets.fromLTRB(side, S.s12, side, S.s24),
      children: laneSections(lanes,
          client: client,
          sessionId: widget.sessionId,
          sessionProfile: _sessionProfile),
    );
  }
}

Widget _paneLabel(String text, {Widget? trailing}) => Padding(
      padding: EdgeInsets.fromLTRB(S.s2, S.of(14), S.s2, S.s8),
      child: Row(children: [
        Expanded(
          child: Text(text.toUpperCase(),
              style: sans(11, spacing: 0.9, color: AppColors.fg4)),
        ),
        if (trailing != null) trailing,
      ]),
    );

String _elapsed(String iso) {
  final t = DateTime.tryParse(iso);
  if (t == null) return '';
  final d = DateTime.now().difference(t.toLocal());
  if (d.inMinutes < 1) return 'now';
  if (d.inHours < 1) return '${d.inMinutes}m';
  if (d.inDays < 1) return '${d.inHours}h';
  return '${d.inDays}d';
}

class _DeskLanes extends StatefulWidget {
  const _DeskLanes(
      {required this.lanes, this.client, this.sessionId, this.sessionProfile});
  final List<LaneInfo> lanes;
  final DaemonClient? client;
  final String? sessionId;
  final String? sessionProfile;

  @override
  State<_DeskLanes> createState() => _DeskLanesState();
}

class _DeskLanesState extends State<_DeskLanes> {
  List<RecurringJob> _jobs = const [];

  @override
  void initState() {
    super.initState();
    _loadJobs();
  }

  Future<void> _loadJobs() async {
    final c = widget.client;
    if (c == null) return;
    try {
      final all = await c.recurringJobs();
      if (!mounted) return;
      setState(() => _jobs = [
            for (final j in all)
              if (j.enabled &&
                  (widget.sessionId == null || j.sessionId == widget.sessionId))
                j
          ]..sort((a, b) => a.nextRunAt.compareTo(b.nextRunAt)));
    } catch (_) {}
  }

  String _at(int secs) {
    if (secs <= 0) return '';
    final t = DateTime.fromMillisecondsSinceEpoch(secs * 1000);
    final now = DateTime.now();
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[t.weekday - 1];
  }

  Widget _lane(LaneInfo l) {
    final running = l.running;
    final failed = l.status == 'failed';
    final stopped = l.status == 'cancelled' || l.status == 'paused';
    final detail = (l.activity ?? '').trim().isNotEmpty
        ? l.activity!.trim()
        : laneFirstSentence((l.summary ?? l.handoff ?? '').trim(), 60);
    final elapsed = _elapsed(l.startedAt);
    final (word, fg, bg) = running
        ? (
            elapsed.isEmpty ? 'Running' : elapsed,
            AppColors.fg2,
            AppColors.surface2
          )
        : failed
            ? ('Failed', AppColors.fg1, AppColors.surface2)
            : stopped
                ? (
                    l.status == 'paused' ? 'Paused' : 'Cancelled',
                    AppColors.fg3,
                    AppColors.fg1.withValues(alpha: 0.07)
                  )
                : ('Completed', AppColors.ok, AppColors.okBg);
    return InkWell(
      splashFactory: NoSplash.splashFactory,
      hoverColor: AppColors.surface3,
      onTap: () => openLaneView(context, l,
          client: widget.client,
          sessionId: widget.sessionId,
          liveLanes: () => widget.lanes),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          border: Border(
              top: BorderSide(color: AppColors.fg1.withValues(alpha: 0.07))),
        ),
        child: Row(children: [
          SizedBox.square(
            dimension: 16,
            child: Center(
              child: running
                  ? const RunSpinner(size: 12)
                  : AppIcon(
                      failed
                          ? 'x'
                          : stopped
                              ? 'minus'
                              : 'check',
                      size: 14,
                      color: failed
                          ? AppColors.danger
                          : stopped
                              ? AppColors.fg4
                              : AppColors.ok),
            ),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: l.title.isEmpty ? 'Lane' : l.title,
                    style: sans(13,
                        weight: FontWeight.w500, color: AppColors.fg1)),
                if (detail.isNotEmpty)
                  TextSpan(
                      text: ' \u00b7 $detail',
                      style: sans(13, color: AppColors.fg3)),
              ]),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          const SizedBox(width: 10),
          Flexible(
            flex: 0,
            child: LaneWho(
                client: widget.client,
                agent: (l.profile ?? '').isNotEmpty
                    ? l.profile
                    : widget.sessionProfile,
                profile: (l.profile ?? '').isNotEmpty
                    ? l.profile
                    : widget.sessionProfile,
                textSize: 11.5,
                color: AppColors.fg4,
                maxTextWidth: 96),
          ),
          const SizedBox(width: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
            decoration: BoxDecoration(
                color: bg, borderRadius: BorderRadius.circular(R.of(3))),
            child:
                Text(word, style: sans(11, weight: FontWeight.w500, color: fg)),
          ),
          if (widget.client != null &&
              widget.sessionId != null &&
              (running || l.retryable)) ...[
            const SizedBox(width: 6),
            LaneControlButton(
              client: widget.client!,
              sessionId: widget.sessionId!,
              lane: l,
              quiet: true,
            ),
          ],
        ]),
      ),
    );
  }

  Widget _card(List<LaneInfo> lanes) {
    final running = lanes.where((l) => l.running).length;
    final done = lanes.where((l) => l.status == 'completed').length;
    final parts = [
      if (running > 0) '$running running',
      if (done > 0) '$done completed',
      if (running + done < lanes.length)
        '${lanes.length - running - done} other',
    ];
    return ClipRRect(
      borderRadius: BorderRadius.circular(R.of(8)),
      child: ColoredBox(
        color: AppColors.surface2,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(children: [
                AppIcon('layers', size: 14, color: AppColors.fg3),
                const SizedBox(width: 8),
                Text('Lanes',
                    style: sans(13, weight: W.label, color: AppColors.fg1)),
                const SizedBox(width: 8),
                Flexible(
                  child: Text(parts.join(', '),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(12, color: AppColors.fg3)),
                ),
              ]),
            ),
            for (final l in lanes) _lane(l),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lanes = widget.lanes;
    return ListView(
      padding: EdgeInsets.fromLTRB(S.of(14), 0, S.of(14), S.s24),
      children: [
        if (lanes.isEmpty) ...[
          _paneLabel('Lanes'),
          Padding(
            padding: EdgeInsets.fromLTRB(S.s2, 0, S.s2, S.s4),
            child: Text('Parallel work this session hands off shows up here.',
                style: sans(13, height: 1.5, color: AppColors.fg4)),
          ),
        ] else
          _card(lanes),
        if (_jobs.isNotEmpty) ...[
          _paneLabel('Scheduled'),
          for (final j in _jobs.take(8))
            SizedBox(
              height: 32,
              child: Row(children: [
                SizedBox(
                  width: 46,
                  child: Text(_at(j.nextRunAt),
                      style: mono(12, color: AppColors.accent)),
                ),
                Expanded(
                  child: Text(j.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(13, color: AppColors.fg2)),
                ),
                Text(j.scheduleLabel, style: sans(12, color: AppColors.fg4)),
              ]),
            ),
        ],
      ],
    );
  }
}

/// SE-07 "Session panels" page: bar B, then Checkpoints, Lanes and Activity
/// chips over the matching body. Bodies are supplied by the host so each
/// panel keeps its own data wiring.
class SessionPanelsPage extends StatefulWidget {
  const SessionPanelsPage({
    super.key,
    required this.sessionTitle,
    required this.checkpoints,
    required this.lanes,
    required this.activity,
    this.initial = 0,
  });
  final String sessionTitle;
  final Widget checkpoints, lanes, activity;
  final int initial;

  @override
  State<SessionPanelsPage> createState() => _SessionPanelsPageState();
}

class _SessionPanelsPageState extends State<SessionPanelsPage> {
  late int _i = widget.initial;

  @override
  Widget build(BuildContext context) {
    const names = ['Checkpoints', 'Lanes', 'Activity'];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SpecBar(title: 'Session panels', subtitle: widget.sessionTitle),
      const SizedBox(height: 12),
      SizedBox(
        height: 44,
        child: ListView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          children: [
            for (var i = 0; i < 3; i++) ...[
              if (i > 0) const SizedBox(width: 8),
              SpecChip(names[i], _i == i, () => setState(() => _i = i)),
            ],
          ],
        ),
      ),
      Expanded(
          child: [widget.checkpoints, widget.lanes, widget.activity][_i]),
    ]);
  }
}
