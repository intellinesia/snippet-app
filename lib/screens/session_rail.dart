import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import '../glass.dart';
import '../models.dart';
import '../settings_form.dart';
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

  @override
  void initState() {
    super.initState();
    loadSessionRailPref();
    _load();
  }

  @override
  void didUpdateWidget(SessionRail old) {
    super.didUpdateWidget(old);
    if (old.state?.status != widget.state?.status ||
        old.sessionId != widget.sessionId) {
      _load();
    }
  }

  Future<Object?> _try(Future<Object?> f) async {
    try {
      return await f;
    } catch (_) {
      return null;
    }
  }

  Future<void> _load() async {
    final gen = ++_gen;
    final c = widget.client;
    final id = widget.sessionId;
    final ws = widget.state?.workspace ?? '';
    final mc = widget.isMissionControl;
    final r = await Future.wait<Object?>([
      mc ? Future.value(null) : _try(c.gitStatus(id)),
      mc || ws.isEmpty
          ? Future.value(null)
          : _try(c.sessions(folder: ws)),
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
        if (collapsed) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(0, 52, 10, 0),
            child: Align(
              alignment: Alignment.topCenter,
              child: _RailToggle(
                  tooltip: 'Show session rail',
                  onTap: () => setSessionRailCollapsed(false)),
            ),
          );
        }
        return SizedBox(
          width: kSessionRailWidth + 10,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(0, 52, 10, 12),
            child: Align(
              alignment: Alignment.topCenter,
              child: Glass(
                radius: BorderRadius.circular(14),
                tint: AppColors.surface2.withValues(alpha: 0.6),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 720),
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: S.s6),
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

  List<Widget> _groups() {
    final groups = <List<Widget>>[];
    final labels = <String>[];
    void add(String label, List<Widget> rows) {
      if (rows.isEmpty) return;
      labels.add(label);
      groups.add(rows);
    }

    final mc = widget.isMissionControl;
    final s = widget.state;
    if (!mc) {
      add('Workspace', _workspace());
      add('Running', _running());
    }
    add('Autonomy', _autonomy());
    add('Model', _model());
    if (!mc) {
      add('Task', _taskRows());
      add('History', _history(s));
    }
    return [
      for (var i = 0; i < groups.length; i++)
        _RailGroup(
          label: labels[i],
          trailing: i == 0
              ? _RailToggle(
                  tooltip: 'Hide session rail',
                  small: true,
                  onTap: () => setSessionRailCollapsed(true))
              : null,
          first: i == 0,
          children: groups[i],
        ),
    ];
  }

  List<Widget> _workspace() {
    final info = _info;
    final git = _git;
    final c = info?.shownChanges;
    final branch = (git?.ok ?? false) && git!.branch.isNotEmpty
        ? git.branch
        : info?.branch;
    final ahead = git?.ahead ?? 0;
    final dirty = git == null ? 0 : git.files.length;
    return [
      if (widget.onChanges != null)
        _RailRow(
          icon: 'file-code',
          label: 'Changes',
          valueWidget: c == null || (c.added == 0 && c.removed == 0)
              ? null
              : Row(mainAxisSize: MainAxisSize.min, children: [
                  Text('+${c.added}',
                      style: sans(13, color: AppColors.ok, tabular: true)),
                  const SizedBox(width: 5),
                  Text('-${c.removed}',
                      style:
                          sans(13, color: AppColors.danger, tabular: true)),
                ]),
          onTap: widget.onChanges,
        ),
      if (info != null && info.inWorktree)
        _RailRow(
            icon: 'worktree',
            label: 'Worktree',
            value: lastPathSegment(info.folder)),
      if (branch != null && branch.isNotEmpty)
        _RailRow(
            icon: 'git-branch',
            label: branch,
            chevron: widget.onGit != null,
            onTap: widget.onGit),
      if (widget.onGit != null && git != null)
        _RailRow(
          icon: 'upload',
          label: 'Commit and push',
          value: ahead > 0
              ? '$ahead ahead'
              : dirty > 0
                  ? '$dirty changed'
                  : null,
          onTap: widget.onGit,
        ),
      if (widget.github == true && widget.onPullRequests != null)
        _RailRow(
            icon: 'git-commit',
            label: 'Pull requests',
            chevron: true,
            onTap: widget.onPullRequests),
    ];
  }

  List<Widget> _running() {
    final lanes = widget.state?.lanes ?? const <LaneInfo>[];
    final working = lanes.where((l) => l.running).length;
    return [
      if (lanes.isNotEmpty && widget.onLanes != null)
        _RailRow(
            icon: 'layers',
            label: 'Lanes',
            value: working > 0 ? '$working working' : '${lanes.length}',
            chevron: true,
            onTap: widget.onLanes),
      if (widget.onProcesses != null)
        _RailRow(
            icon: 'processes',
            label: 'Processes',
            value: _procs == null ? null : '$_procs',
            chevron: true,
            onTap: widget.onProcesses),
      if (widget.onShell != null)
        _RailRow(
            icon: 'terminal',
            label: 'Shell',
            chevron: true,
            onTap: widget.onShell),
    ];
  }

  List<Widget> _autonomy() {
    final goal = widget.state?.goal;
    final goalOn = goal?.ongoing ?? false;
    final wake = _wake;
    final mode = widget.resumeMode;
    return [
      if (widget.isMissionControl && widget.onAutonomy != null)
        _RailRow(
            icon: 'activity',
            label: 'Automated wakes',
            chevron: true,
            onTap: widget.onAutonomy),
      if (!widget.isMissionControl)
        _RailRow(
          icon: 'goal',
          label: goalOn ? 'Goal' : 'Set a goal',
          value: goalOn ? (goal!.paused ? 'Paused' : 'Working') : null,
          chevron: !goalOn,
          onTap: widget.onGoal,
        ),
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
      if (!widget.isMissionControl)
        _RailRow(
          icon: 'clock',
          label: 'Cold resume',
          value: switch (mode) {
            'lean' => 'Lean',
            'full' => 'Full',
            _ => 'Ask',
          },
          onTap: widget.onCycleResume,
        ),
    ];
  }

  List<Widget> _model() {
    final s = widget.state;
    final ctx = s != null && s.contextWindow > 0 && s.lastPromptTokens > 0
        ? (s.lastPromptTokens / s.contextWindow * 100).clamp(0, 100).round()
        : null;
    final cached = s != null && s.lastPromptTokens > 0 && s.cacheReadTokens > 0
        ? (s.cacheReadTokens / s.lastPromptTokens * 100).clamp(0, 100).round()
        : null;
    return [
      _RailRow(
        icon: 'cpu',
        label: widget.profileLabel,
        height: ctx != null && cached != null ? 44 : 32,
        trailing: ctx == null
            ? null
            : Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _stat('Context', '$ctx%'),
                  if (cached != null) _stat('Cached', '$cached%'),
                ],
              ),
        chevron: true,
        onTap: widget.onModel,
      ),
    ];
  }

  Widget _stat(String k, String v) => Text.rich(
        TextSpan(children: [
          TextSpan(text: '$k  ', style: sans(11, color: AppColors.fg4)),
          TextSpan(text: v, style: sans(11, color: AppColors.fg2, tabular: true)),
        ]),
        maxLines: 1,
      );

  List<Widget> _taskRows() {
    final t = _task;
    if (t == null || widget.onOpenTask == null) return const [];
    final plan = t.workPlan;
    final done = plan.where((p) => p.done).length;
    return [
      _RailRow(
        icon: 'task',
        label: t.title,
        value: plan.isEmpty ? t.status.label : '$done of ${plan.length}',
        chevron: true,
        onTap: () => widget.onOpenTask!(t.id),
      ),
    ];
  }

  List<Widget> _history(HarnessState? s) => [
        if (widget.onCheckpoints != null)
          _RailRow(
              icon: 'history',
              label: 'Checkpoints',
              value: '${s?.checkpoints.length ?? 0}',
              chevron: true,
              onTap: widget.onCheckpoints),
        if (widget.onMemory != null)
          _RailRow(
              icon: 'brain',
              label: 'Memory',
              chevron: true,
              onTap: widget.onMemory),
      ];
}

class _RailGroup extends StatelessWidget {
  const _RailGroup({
    required this.label,
    required this.children,
    this.trailing,
    this.first = false,
  });
  final String label;
  final List<Widget> children;
  final Widget? trailing;
  final bool first;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 10),
      padding: const EdgeInsets.symmetric(vertical: S.s8),
      decoration: BoxDecoration(
        border: first
            ? null
            : Border(
                top: BorderSide(color: AppColors.fg1.withValues(alpha: 0.06))),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 0, 4),
            child: SizedBox(
              height: 18,
              child: Row(children: [
                Expanded(
                    child: Text(label,
                        style: sans(12, color: AppColors.fg4))),
                if (trailing != null) trailing!,
              ]),
            ),
          ),
          ...children,
        ],
      ),
    );
  }
}

class _RailRow extends StatelessWidget {
  const _RailRow({
    required this.icon,
    required this.label,
    this.value,
    this.valueWidget,
    this.trailing,
    this.chevron = false,
    this.onTap,
    this.height = 32,
  });
  final String icon;
  final String label;
  final String? value;
  final Widget? valueWidget;
  final Widget? trailing;
  final bool chevron;
  final VoidCallback? onTap;
  final double height;

  @override
  Widget build(BuildContext context) {
    final v = valueWidget ??
        (value == null
            ? null
            : Text(value!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(13, color: AppColors.fg4, tabular: true)));
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      hoverColor: AppColors.surface2,
      child: SizedBox(
        height: height,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 2),
          child: Row(children: [
            AppIcon(icon, size: 16, color: AppColors.fg2),
            const SizedBox(width: 10),
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(14, color: AppColors.fg1)),
            ),
            if (v != null) ...[
              const SizedBox(width: 8),
              Flexible(flex: 0, child: v),
            ],
            if (trailing != null) ...[
              const SizedBox(width: 8),
              trailing!,
            ],
            if (chevron) ...[
              const SizedBox(width: 6),
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
    final icon = AppIcon('sidebar', size: small ? 14 : 16, color: AppColors.fg3);
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: small
            ? Padding(padding: const EdgeInsets.all(2), child: icon)
            : Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: AppColors.fg1.withValues(alpha: 0.08)),
                ),
                alignment: Alignment.center,
                child: icon,
              ),
      ),
    );
  }
}
