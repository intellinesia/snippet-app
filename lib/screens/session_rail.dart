import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import '../glass.dart';
import '../models.dart';
import '../settings_form.dart';
import '../tool_activity.dart';
import 'file_changes.dart' show sessionChangeSteps;
import '../theme.dart';
import '../wake_models.dart';
import '../widgets.dart';

const String kSessionRailCollapsedPref = 'session_rail_collapsed';
const double kSessionRailWidth = 272;

/// Chat must keep at least this much room beside the rail.
const double kSessionRailMinChat = 520;

/// Narrowest session column that still shows the rail.
const double kSessionRailMinColumn =
    kSessionRailMinChat + kSessionRailWidth + 24;

final ValueNotifier<bool> sessionRailCollapsed = ValueNotifier<bool>(false);
bool _railPrefLoaded = false;

Future<void> loadSessionRailPref() async {
  if (_railPrefLoaded) return;
  _railPrefLoaded = true;
  final p = await SharedPreferences.getInstance();
  sessionRailCollapsed.value = p.getBool(kSessionRailCollapsedPref) ?? false;
}

Future<void> setSessionRailCollapsed(bool v) async {
  sessionRailCollapsed.value = v;
  final p = await SharedPreferences.getInstance();
  await p.setBool(kSessionRailCollapsedPref, v);
}

/// Floating quick-options card beside a session's chat. Reads live state the
/// session already holds and fetches the few counts it does not.
class SessionRail extends StatefulWidget {
  const SessionRail({
    super.key,
    required this.client,
    required this.sessionId,
    required this.state,
    required this.isMissionControl,
    required this.profileLabel,
    required this.resumeMode,
    required this.onModel,
    required this.onWakes,
    required this.onGoal,
    required this.onCycleResume,
    this.github,
    this.onChanges,
    this.onGit,
    this.onPullRequests,
    this.onLanes,
    this.onProcesses,
    this.onShell,
    this.onAutonomy,
    this.onCheckpoints,
    this.onMemory,
    this.onOpenTask,
    this.headerActions,
    this.headerChips,
  });

  final DaemonClient client;
  final String sessionId;
  final HarnessState? state;
  final bool isMissionControl;
  final String profileLabel;
  final String resumeMode;
  final bool? github;
  final VoidCallback onModel;
  final VoidCallback onWakes;
  final VoidCallback onGoal;
  final VoidCallback onCycleResume;
  final VoidCallback? onChanges;
  final VoidCallback? onGit;
  final VoidCallback? onPullRequests;
  final VoidCallback? onLanes;
  final VoidCallback? onProcesses;
  final VoidCallback? onShell;
  final VoidCallback? onAutonomy;
  final VoidCallback? onCheckpoints;
  final VoidCallback? onMemory;
  final void Function(String taskId)? onOpenTask;

  /// Session actions (goal, tools, more) shown beside the panel's title.
  final Widget? headerActions;

  /// Files and git chips shown under the panel's title.
  final Widget? headerChips;

  @override
  State<SessionRail> createState() => _SessionRailState();
}

class _SessionRailState extends State<SessionRail> {
  GitStatus? _git;
  SessionInfo? _info;
  int? _procs;
  WakeSchedule? _wake;
  bool _wakeKnown = false;
  bool? _warm;
  TaskItem? _task;
  int _gen = 0;
  int _liveGen = 0;

  @override
  void initState() {
    super.initState();
    loadSessionRailPref();
    _load();
  }

  @override
  void didUpdateWidget(SessionRail old) {
    super.didUpdateWidget(old);
    if (old.sessionId != widget.sessionId) {
      _load();
    } else if (old.state?.status != widget.state?.status) {
      // A turn changes only the worktree and processes; the rest is per session.
      _loadLive();
    }
  }

  Future<Object?> _try(Future<Object?> f) async {
    try {
      return await f;
    } catch (_) {
      return null;
    }
  }

  Future<void> _loadLive() async {
    if (widget.isMissionControl) return;
    final gen = ++_liveGen;
    final c = widget.client;
    final id = widget.sessionId;
    final r = await Future.wait<Object?>([
      _try(c.gitStatus(id)),
      _try(c.bgList(id)),
    ]);
    if (!mounted || gen != _liveGen) return;
    final procs = r[1] as List<Map<String, dynamic>>?;
    setState(() {
      _git = r[0] as GitStatus? ?? _git;
      _procs = procs?.where((p) => p['running'] == true).length ?? _procs;
    });
  }

  Future<void> _load() async {
    final gen = ++_gen;
    ++_liveGen;
    final c = widget.client;
    final id = widget.sessionId;
    final ws = widget.state?.workspace ?? '';
    final mc = widget.isMissionControl;
    final r = await Future.wait<Object?>([
      mc ? Future.value(null) : _try(c.gitStatus(id)),
      mc || ws.isEmpty ? Future.value(null) : _try(c.sessions(folder: ws)),
      mc ? Future.value(null) : _try(c.bgList(id)),
      _try(c.wake(id)),
      _try(c.keepWarmFor(id)),
      mc ? Future.value(null) : _try(c.tasks(status: 'in_progress')),
    ]);
    if (!mounted || gen != _gen) return;
    final infos = r[1] as List<SessionInfo>?;
    final tasks = r[5] as List<TaskItem>?;
    final procs = r[2] as List<Map<String, dynamic>>?;
    setState(() {
      _git = r[0] as GitStatus?;
      _info = infos?.where((s) => s.id == id).firstOrNull;
      _procs = procs?.where((p) => p['running'] == true).length;
      _wakeKnown = true;
      _wake = r[3] as WakeSchedule?;
      _warm = (r[4] as KeepWarmEntry?)?.enabled ?? false;
      _task = tasks?.where((t) => t.sessionId == id).firstOrNull;
    });
  }

  Future<void> _setWarm(bool on) async {
    final before = _warm;
    setState(() => _warm = on);
    try {
      await widget.client.setKeepWarm(widget.sessionId, enabled: on);
    } catch (_) {
      if (mounted) setState(() => _warm = before);
    }
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: sessionRailCollapsed,
      builder: (_, collapsed, __) {
        // Hidden: the chat header carries the actions and the show toggle.
        if (collapsed) return const SizedBox.shrink();
        return SizedBox(
          width: kSessionRailWidth + 10,
          child: Padding(
            padding: EdgeInsets.fromLTRB(0, S.s8, S.of(10), S.s12),
            child: Align(
              alignment: Alignment.topCenter,
              child: Glass(
                radius: BorderRadius.circular(R.of(14)),
                tint: AppColors.surface2.withValues(alpha: 0.6),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 720),
                  child: SingleChildScrollView(
                    padding: EdgeInsets.symmetric(vertical: S.s6),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: _groups(),
                    ),
                  ),
                ),
              ),
            ),
          ),
        );
      },
    );
  }

  // Round 5 session card: what the session is doing, not what you can do to it.
  // Actions live behind the header's "more" menu.
  List<Widget> _groups() {
    final mc = widget.isMissionControl;
    final s = widget.state;
    final out = <Widget>[_header()];
    void add(String label, List<Widget> rows,
        {String? meta, VoidCallback? onLabel}) {
      if (rows.isEmpty) return;
      out.add(_RailGroup(
          label: label, meta: meta, onLabel: onLabel, children: rows));
    }

    if (!mc) {
      final plan = _plan(s);
      if (plan != null) {
        final done = plan.where((p) => _stepState(p) == 2).length;
        add('Plan', _planRows(plan), meta: '$done of ${plan.length} done');
      }
      add('Lanes', _laneRows(s), onLabel: widget.onLanes);
      final files = fileChanges(sessionChangeSteps(s?.events ?? const []));
      add('Changes', _changeRows(files),
          meta: files.isEmpty ? null : '${files.length}',
          onLabel: widget.onChanges);
    }
    add('Next without you', _nextRows());
    return out;
  }

  Widget _header() {
    final ws = _info?.folder ?? widget.state?.workspace ?? '';
    final git = _git;
    final branch = (git?.ok ?? false) && git!.branch.isNotEmpty
        ? git.branch
        : (_info?.branch ?? '');
    final where = [
      if (ws.isNotEmpty) lastPathSegment(ws),
      if (branch.isNotEmpty) branch,
    ].join(' · ');
    final t = _task;
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 8, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Text(widget.isMissionControl ? 'Mission Control' : 'Session',
              style: sans(13, weight: W.label, color: AppColors.fg1)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(where,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mono(11, color: AppColors.fg4)),
          ),
          if (widget.headerActions != null) widget.headerActions!,
          _RailToggle(
              tooltip: 'Hide session panel',
              small: true,
              onTap: () => setSessionRailCollapsed(true)),
        ]),
        if (widget.headerChips != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Align(
                alignment: Alignment.centerLeft, child: widget.headerChips),
          ),
        if (t != null && widget.onOpenTask != null)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: _RailRow(
              icon: 'task',
              label: t.title,
              value: t.workPlan.isEmpty
                  ? t.status.label
                  : '${t.workPlan.where((p) => p.done).length} of ${t.workPlan.length}',
              chevron: true,
              onTap: () => widget.onOpenTask!(t.id),
            ),
          ),
      ]),
    );
  }

  static List<Map>? _plan(HarnessState? s) {
    final events = s?.events ?? const <Map<String, dynamic>>[];
    for (var i = events.length - 1; i >= 0; i--) {
      final e = events[i];
      if (e['type'] != 'plan_updated') continue;
      final steps = (e['steps'] as List? ?? const []).whereType<Map>().toList();
      return steps.isEmpty ? null : steps;
    }
    return null;
  }

  static int _stepState(Map step) => switch (step['status']?.toString()) {
        'done' || 'completed' => 2,
        'in_progress' => 1,
        _ => 0,
      };

  List<Widget> _planRows(List<Map> plan) => [
        for (final p in plan)
          SizedBox(
            height: 26,
            child: Row(children: [
              SizedBox(
                width: 16,
                child: Center(
                  child: switch (_stepState(p)) {
                    2 => AppIcon('check', size: 13, color: AppColors.ok),
                    1 => Container(
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                            color: AppColors.accent, shape: BoxShape.circle)),
                    _ => Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: AppColors.fg4, width: 1.2))),
                  },
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(p['step']?.toString() ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(13,
                        color: switch (_stepState(p)) {
                          2 => AppColors.fg3,
                          1 => AppColors.fg1,
                          _ => AppColors.fg3,
                        })),
              ),
              if (_stepState(p) == 1)
                Text('now', style: sans(11, color: AppColors.fg4)),
            ]),
          ),
      ];

  List<Widget> _laneRows(HarnessState? s) {
    final lanes = [...?s?.lanes];
    lanes.sort((a, b) => (b.running ? 1 : 0) - (a.running ? 1 : 0));
    return [
      for (final l in lanes.take(4))
        _InfoRow(
          icon: l.running ? 'activity' : (l.status == 'failed' ? 'x' : 'check'),
          title: l.title.isEmpty ? l.id : l.title,
          sub: l.running
              ? ((l.activity ?? '').trim().isEmpty
                  ? 'Running'
                  : 'Running · ${l.activity!.trim()}')
              : l.status == 'failed'
                  ? 'Failed'
                  : 'Finished',
          live: l.running,
          onTap: widget.onLanes,
        ),
      if (lanes.length > 4)
        _MoreRow('${lanes.length - 4} more', widget.onLanes),
    ];
  }

  List<Widget> _changeRows(List<FileChange> files) => [
        for (final f in files.take(5))
          InkWell(
            onTap: widget.onChanges,
            borderRadius: BorderRadius.circular(6),
            hoverColor: AppColors.surface2,
            child: SizedBox(
              height: 26,
              child: Row(children: [
                AppIcon('file', size: 13, color: AppColors.fg4),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(f.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono(12, color: AppColors.fg2)),
                ),
                if (f.added > 0)
                  Text('+${f.added}',
                      style: sans(11, color: AppColors.ok, tabular: true)),
                if (f.removed > 0) ...[
                  const SizedBox(width: 4),
                  Text('-${f.removed}',
                      style: sans(11, color: AppColors.danger, tabular: true)),
                ],
              ]),
            ),
          ),
        if (files.length > 5)
          _MoreRow('${files.length - 5} more', widget.onChanges),
      ];

  List<Widget> _nextRows() {
    final goal = widget.state?.goal;
    final goalOn = goal?.ongoing ?? false;
    final wake = _wake;
    return [
      if (goalOn)
        _RailRow(
          icon: 'goal',
          label: 'Goal',
          value: goal!.paused ? 'Paused' : 'Working',
          onTap: widget.onGoal,
        ),
      if (widget.isMissionControl && widget.onAutonomy != null)
        _RailRow(
            icon: 'repeat',
            label: 'Automated wakes',
            chevron: true,
            onTap: widget.onAutonomy),
      _RailRow(
        icon: 'scheduled',
        label: 'Wakes',
        value: !_wakeKnown
            ? null
            : wake == null
                ? 'None'
                : wake.enabled
                    ? wake.scheduleText
                    : 'Paused',
        onTap: widget.onWakes,
      ),
      if (_warm != null)
        _RailRow(
          icon: 'activity',
          label: 'Keep warm',
          trailing: SettingsSwitch(value: _warm!, onChanged: _setWarm),
          onTap: () => _setWarm(!_warm!),
        ),
    ];
  }
}

class _RailGroup extends StatelessWidget {
  const _RailGroup({
    required this.label,
    required this.children,
    this.meta,
    this.onLabel,
  });
  final String label;
  final String? meta;
  final VoidCallback? onLabel;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final head = SizedBox(
      height: 24,
      child: Row(children: [
        Text(label, style: sans(13, weight: W.label, color: AppColors.fg1)),
        if (meta != null) ...[
          const SizedBox(width: 8),
          Text(meta!, style: sans(12, color: AppColors.fg4, tabular: true)),
        ],
        const Spacer(),
        if (onLabel != null)
          AppIcon('chevron-right', size: 12, color: AppColors.fg4),
      ]),
    );
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 8, 12, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          onLabel == null
              ? head
              : InkWell(
                  onTap: onLabel,
                  borderRadius: BorderRadius.circular(6),
                  child: head),
          const SizedBox(height: 2),
          ...children,
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.icon,
    required this.title,
    required this.sub,
    this.live = false,
    this.onTap,
  });
  final String icon;
  final String title;
  final String sub;
  final bool live;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      hoverColor: AppColors.surface2,
      child: SizedBox(
        height: 40,
        child: Row(children: [
          Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(6),
            ),
            alignment: Alignment.center,
            child: AppIcon(icon,
                size: 13, color: live ? AppColors.accent : AppColors.fg3),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(13, color: AppColors.fg1)),
                Text(sub,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(11, color: AppColors.fg4)),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

class _MoreRow extends StatelessWidget {
  const _MoreRow(this.label, this.onTap);
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(6),
        child: SizedBox(
          height: 24,
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(label, style: sans(12, color: AppColors.fg4)),
          ),
        ),
      );
}

class _RailRow extends StatelessWidget {
  const _RailRow({
    required this.icon,
    required this.label,
    this.value,
    this.trailing,
    this.chevron = false,
    this.onTap,
  });
  final String icon;
  final String label;
  final String? value;
  final Widget? trailing;
  final bool chevron;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final v = (value == null
        ? null
        : Text(value!,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: sans(12, color: AppColors.fg4, tabular: true)));
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(R.md),
      hoverColor: AppColors.surface2,
      child: SizedBox(
        height: 30,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: S.s2),
          child: Row(children: [
            AppIcon(icon, size: 14, color: AppColors.fg3),
            SizedBox(width: S.of(10)),
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13, color: AppColors.fg2)),
            ),
            if (v != null) ...[
              SizedBox(width: S.s8),
              Flexible(flex: 0, child: v),
            ],
            if (trailing != null) ...[
              SizedBox(width: S.s8),
              trailing!,
            ],
            if (chevron) ...[
              SizedBox(width: S.s6),
              AppIcon('chevron-right', size: 12, color: AppColors.fg4),
            ],
          ]),
        ),
      ),
    );
  }
}

class _RailToggle extends StatelessWidget {
  const _RailToggle(
      {required this.tooltip, required this.onTap, this.small = false});
  final String tooltip;
  final VoidCallback onTap;
  final bool small;

  @override
  Widget build(BuildContext context) {
    final icon =
        AppIcon('sidebar', size: small ? 14 : 16, color: AppColors.fg3);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.md),
        child: small
            ? Padding(padding: EdgeInsets.all(S.s2), child: icon)
            : Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(R.md),
                  border:
                      Border.all(color: AppColors.fg1.withValues(alpha: 0.08)),
                ),
                alignment: Alignment.center,
                child: icon,
              ),
      ),
    );
  }
}
