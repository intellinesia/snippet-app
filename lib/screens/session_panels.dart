import 'package:flutter/material.dart';

import 'dart:async';

import '../api.dart';
import '../mochi.dart';
import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import '../transcript.dart' show LaneControlButton, LaneWho;
import 'compact_btn.dart';
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
    return Padding(
      padding: EdgeInsets.fromLTRB(S.s12, S.s8, S.s12, S.s8),
      child: Row(children: [
        Container(
          width: 32,
          height: 32,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: AppColors.surface3,
            borderRadius: BorderRadius.circular(R.sm),
          ),
          child: AppIcon('history', size: 16, color: AppColors.fg3),
        ),
        SizedBox(width: S.s12),
        Expanded(
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    c.label.trim().isEmpty
                        ? 'Checkpoint'
                        : c.label.trim().replaceAll(RegExp(r'\s+'), ' '),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(15, color: AppColors.fg1)),
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(12, color: AppColors.fg4)),
              ]),
        ),
        // The newest checkpoint is the present state, so only Fork applies.
        if (!latest) ...[
          SizedBox(width: S.s8),
          CompactBtn('Restore', onTap: () => widget.onRewind(c)),
        ],
        SizedBox(width: S.s4),
        CompactBtn('Fork', onTap: () => widget.onFork(c)),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cps = widget.checkpoints;
    if (cps.isEmpty) {
      return Padding(
        padding: EdgeInsets.all(S.s20),
        child: Text('No checkpoints yet.', style: TS.meta()),
      );
    }
    final side = widget.embedded ? 0.0 : (kMobile ? M.gutter : S.s12);
    return ListView(
      shrinkWrap: widget.embedded,
      physics: widget.embedded ? const NeverScrollableScrollPhysics() : null,
      padding: EdgeInsets.fromLTRB(side, S.s12, side, S.s24),
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(S.s4, 0, S.s4, S.s8),
          child: Row(children: [
            Expanded(
              child: Text('Checkpoints \u00b7 ${cps.length}',
                  style: sans(13, color: AppColors.fg3)),
            ),
            Text('Files roll back too',
                style: sans(12, color: AppColors.fg4)),
          ]),
        ),
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
    final color = switch (l.status) {
      'running' => AppColors.accent,
      'failed' => AppColors.danger,
      'cancelled' || 'paused' => AppColors.fg4,
      _ => AppColors.ok,
    };
    final status = switch (l.status) {
      'running' => 'working',
      'failed' => 'failed',
      'cancelled' => 'cancelled',
      'paused' => 'paused',
      _ => 'done',
    };
    final task = (l.activity ?? '').trim().isNotEmpty
        ? l.activity!.trim()
        : (l.summary ?? l.handoff ?? '').trim();
    final steps = l.activityLog.length.clamp(0, 14);
    return Padding(
      padding: EdgeInsets.only(bottom: S.s8),
      child: Material(
        color: AppColors.tint1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(R.lg),
          side: BorderSide(color: AppColors.line),
        ),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.lg),
          onTap: () => openLaneView(context, l,
              client: widget.client,
              sessionId: widget.sessionId,
              liveLanes: () => widget.lanes),
          child: Padding(
            padding: EdgeInsets.fromLTRB(S.s12, S.of(11), S.s12, S.of(11)),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                AgentMochi(l.agent ?? l.id, size: 18),
                SizedBox(width: S.of(9)),
                Expanded(
                  child: Text(l.title.isEmpty ? 'Lane' : l.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(13, color: AppColors.fg1)),
                ),
                Text(status, style: sans(12, color: color)),
                if (widget.client != null &&
                    widget.sessionId != null &&
                    (l.running || l.retryable)) ...[
                  SizedBox(width: S.s8),
                  LaneControlButton(
                    client: widget.client!,
                    sessionId: widget.sessionId!,
                    lane: l,
                  ),
                ],
              ]),
              if (task.isNotEmpty) ...[
                SizedBox(height: S.of(7)),
                Text(task,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: sans(13, height: 1.45, color: AppColors.fg3)),
              ],
              SizedBox(height: S.s8),
              Row(children: [
                for (var i = 0; i < 14; i++)
                  Container(
                    width: 5,
                    height: 5,
                    margin: EdgeInsets.only(right: S.of(3)),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: i < steps
                          ? color
                          : AppColors.fg1.withValues(alpha: 0.10),
                    ),
                  ),
                const Spacer(),
                SizedBox(width: S.s8),
                Flexible(
                  child: LaneWho(
                      client: widget.client,
                      agent: l.agent,
                      profile: (l.profile ?? '').isNotEmpty
                          ? l.profile
                          : widget.sessionProfile,
                      maxTextWidth: 96),
                ),
                if (_elapsed(l.startedAt).isNotEmpty) ...[
                  SizedBox(width: S.s8),
                  Text(_elapsed(l.startedAt),
                      style: mono(11, color: AppColors.fg4)),
                ],
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final lanes = widget.lanes;
    final running = lanes.where((l) => l.running).length;
    return ListView(
      padding: EdgeInsets.fromLTRB(S.of(14), 0, S.of(14), S.s24),
      children: [
        _paneLabel(running > 0
            ? 'Lanes · $running running'
            : 'Lanes${lanes.isEmpty ? '' : ' · ${lanes.length}'}'),
        if (lanes.isEmpty)
          Padding(
            padding: EdgeInsets.fromLTRB(S.s2, 0, S.s2, S.s4),
            child: Text(
                'Parallel work this session hands off shows up here.',
                style: sans(13, height: 1.5, color: AppColors.fg4)),
          )
        else
          for (final l in lanes) _lane(l),
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
