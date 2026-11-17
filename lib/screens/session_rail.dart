import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import '../models.dart';
import '../settings_form.dart';
import '../tool_activity.dart';
import 'file_changes.dart' show sessionChangeSteps;
import 'lanes.dart' show openLaneView;
import '../mochi.dart' show AgentMochi;
import '../theme.dart';
import '../wake_models.dart';
import '../widgets.dart';

const String kSessionRailCollapsedPref = 'session_rail_collapsed';
const double kSessionRailWidth = 288;

/// Chat must keep at least this much room beside the rail.
const double kSessionRailMinChat = 520;

/// Narrowest session column that still shows the rail.
const double kSessionRailMinColumn =
    kSessionRailMinChat + kSessionRailWidth + 24;

final ValueNotifier<bool> sessionRailCollapsed = ValueNotifier<bool>(false);

/// The panel as a floating card, for windows too narrow to dock it.
final ValueNotifier<bool> sessionRailFloating = ValueNotifier<bool>(false);
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

/// The session panel: what the session is doing, with its actions at the top.
/// Reads live state the session already holds and fetches the few counts it
/// does not.
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
    this.floating = false,
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
    this.onHandOff,
    this.onFork,
    this.onCompact,
    this.onDeliverables,
    this.onRecurring,
    this.onDelete,
    this.providers = const {},
    this.ownProfile,
    this.ownAgent,
    this.headerActions,
    this.headerChips,
  });

  final DaemonClient client;
  final String sessionId;
  final HarnessState? state;
  final bool isMissionControl;
  final String profileLabel;
  final String resumeMode;

  /// Shown as a floating card (narrow window) instead of docked beside the chat.
  final bool floating;
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
  final VoidCallback? onHandOff;
  final VoidCallback? onFork;
  final VoidCallback? onCompact;
  final VoidCallback? onDeliverables;
  final VoidCallback? onRecurring;
  final VoidCallback? onDelete;

  /// Profile name to provider, for the lane rows' marks.
  final Map<String, String> providers;
  final String? ownProfile;
  final String? ownAgent;

  /// Session actions (goal, terminal, more) shown beside the panel's title.
  final Widget? headerActions;

  /// Files and git chips shown under the panel's title.
  final Widget? headerChips;

  @override
  State<SessionRail> createState() => _SessionRailState();
}

class _SessionRailState extends State<SessionRail> {
  GitStatus? _git;
  WakeSchedule? _wake;
  bool _wakeKnown = false;
  bool? _warm;
  bool? _autonomous;
  List<TaskItem> _tasks = const [];
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
    final git = await _try(c.gitStatus(id)) as GitStatus?;
    if (!mounted || gen != _liveGen) return;
    setState(() => _git = git ?? _git);
  }

  Future<void> _load() async {
    final gen = ++_gen;
    ++_liveGen;
    final c = widget.client;
    final id = widget.sessionId;
    final mc = widget.isMissionControl;
    final r = await Future.wait<Object?>([
      mc ? Future.value(null) : _try(c.gitStatus(id)),
      _try(c.wake(id)),
      _try(c.keepWarmFor(id)),
      _try(c.tasks(status: 'in_progress')),
      _try(c.mcAutonomy()),
    ]);
    if (!mounted || gen != _gen) return;
    final auto = r[4] as Map<String, dynamic>?;
    setState(() {
      _git = r[0] as GitStatus?;
      _wakeKnown = true;
      _wake = r[1] as WakeSchedule?;
      _warm = (r[2] as KeepWarmEntry?)?.enabled ?? false;
      _tasks = r[3] as List<TaskItem>? ?? const [];
      _autonomous = auto == null ? null : auto['on'] == true;
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

  Future<void> _stopLane(String lane) async {
    try {
      await widget.client.cancelLane(widget.sessionId, lane);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    if (widget.floating) return _card(640);
    return ValueListenableBuilder<bool>(
      valueListenable: sessionRailCollapsed,
      builder: (_, collapsed, __) {
        // Hidden: the chat header carries the actions and the show toggle.
        if (collapsed) return const SizedBox.shrink();
        return LayoutBuilder(
          builder: (_, box) => Padding(
            padding: EdgeInsets.fromLTRB(24, 10, 0, S.s12),
            child: Align(
              alignment: Alignment.topCenter,
              child: _card(box.maxHeight - 10 - S.s12),
            ),
          ),
        );
      },
    );
  }

  Widget _card(double maxHeight) {
    return Container(
      width: kSessionRailWidth,
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(R.of(16)),
        border: Border.all(
            color: widget.floating ? AppColors.lineStrong : AppColors.line),
        boxShadow: widget.floating ? overlayShadow : null,
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: maxHeight),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(R.of(16)),
          child: SingleChildScrollView(
            padding: const EdgeInsets.only(bottom: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _groups(),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _groups() {
    final mc = widget.isMissionControl;
    final s = widget.state;
    final out = <Widget>[_header()];
    var first = true;
    void add(String label, List<Widget> rows,
        {String? meta, String? link, VoidCallback? onLabel, bool open = true}) {
      if (rows.isEmpty) return;
      out.add(_RailGroup(
          key: ValueKey('rail-$label'),
          label: label,
          meta: meta,
          link: link,
          onLabel: onLabel,
          initiallyOpen: open,
          divider: !first || !mc,
          children: rows));
      first = false;
    }

    if (mc) {
      final n = _tasks.length;
      add('In flight', _flightRows(),
          meta: n == 0 ? null : '$n task${n == 1 ? '' : 's'}');
      add('Autonomy', _autonomyRows());
      add('Automated wakes', _wakeRows(),
          link: 'Edit', onLabel: widget.onAutonomy);
      add('Model', _modelRows(s));
      return out;
    }
    final plan = _plan(s);
    if (plan != null) {
      final done = plan.where((p) => _stepState(p) == 2).length;
      add('Plan', _planRows(plan), meta: '$done of ${plan.length} done');
    }
    final lanes = [...?s?.lanes];
    final running = lanes.where((l) => l.running).length;
    add('Lanes', _laneRows(lanes),
        meta: running == 0 ? null : '$running running',
        link: 'All',
        onLabel: widget.onLanes);
    final files = fileChanges(sessionChangeSteps(s?.events ?? const []));
    add('Changes', _changeRows(files),
        meta: files.isEmpty
            ? null
            : '${files.length} file${files.length == 1 ? '' : 's'}',
        link: 'Review',
        onLabel: widget.onChanges);
    add('Usage', _usageRows(s));
    add('Next without you', _nextRows());
    final w = widget;
    add(
        'Actions',
        [
          if (w.onHandOff != null)
            _RailRow(icon: 'users', label: 'Hand off', onTap: w.onHandOff),
          if (w.onFork != null)
            _RailRow(
                icon: 'git-branch', label: 'Fork from here', onTap: w.onFork),
          if (w.onRecurring != null)
            _RailRow(icon: 'repeat', label: 'Scheduled', onTap: w.onRecurring),
        ],
        open: false);
    add(
        'Workspace',
        [
          if (w.onDeliverables != null)
            _RailRow(
                icon: 'folder', label: 'Shared files', onTap: w.onDeliverables),
          if (w.onProcesses != null)
            _RailRow(
                icon: 'activity', label: 'Processes', onTap: w.onProcesses),
          if (w.onShell != null)
            _RailRow(icon: 'terminal', label: 'Terminal', onTap: w.onShell),
        ],
        open: false);
    add(
        'History',
        [
          if (w.onCheckpoints != null)
            _RailRow(
                icon: 'history', label: 'Checkpoints', onTap: w.onCheckpoints),
          if (w.onMemory != null)
            _RailRow(icon: 'brain', label: 'Memory', onTap: w.onMemory),
          if (w.onCompact != null)
            _RailRow(
                icon: 'minimize', label: 'Compact history', onTap: w.onCompact),
        ],
        open: false);
    if (w.onDelete != null) {
      out.add(Padding(
        padding: const EdgeInsets.fromLTRB(14, 4, 14, 8),
        child: _RailRow(
            icon: 'trash',
            label: 'Delete session',
            danger: true,
            onTap: w.onDelete),
      ));
    }
    return out;
  }

  Widget _header() {
    final mc = widget.isMissionControl;
    final t = _tasks.where((t) => t.sessionId == widget.sessionId).firstOrNull;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Container(
        padding: const EdgeInsets.fromLTRB(14, 8, 8, 8),
        decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.line))),
        child: Row(children: [
          Expanded(
            child: Text(mc ? 'Mission Control' : 'Session',
                style: sans(13, weight: W.label, color: AppColors.fg1)),
          ),
          if (widget.headerActions != null) widget.headerActions!,
          IconBtn(widget.floating ? 'x' : 'sidebar',
              size: 30,
              iconSize: 15,
              tooltip: widget.floating ? 'Close' : 'Hide session panel',
              onTap: () => widget.floating
                  ? sessionRailFloating.value = false
                  : setSessionRailCollapsed(true)),
        ]),
      ),
      if (widget.headerChips != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 2),
          child:
              Align(alignment: Alignment.centerLeft, child: widget.headerChips),
        ),
      if (t != null && widget.onOpenTask != null)
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 6, 8, 0),
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
    ]);
  }

  static List<Map>? _plan(HarnessState? s) {
    final events = s?.events ?? const <Map<String, dynamic>>[];
    for (var i = events.length - 1; i >= 0; i--) {
      final e = events[i];
      if (e['kind'] != 'plan_updated') continue;
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
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 26),
            child: Row(children: [
              SizedBox(
                width: 14,
                child: Center(
                  child: switch (_stepState(p)) {
                    2 => AppIcon('check', size: 12, color: AppColors.fg4),
                    1 => Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                            color: AppColors.accent,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                  color: AppColors.accentBg, spreadRadius: 3)
                            ])),
                    _ => Container(
                        width: 9,
                        height: 9,
                        decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: AppColors.fg4, width: 1.3))),
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
                          2 => AppColors.fg4,
                          1 => AppColors.fg1,
                          _ => AppColors.fg3,
                        })),
              ),
            ]),
          ),
      ];

  /// The lane's agent when it runs as another one, else its provider.
  Widget _laneMark(LaneInfo l) {
    final agent = (l.agent ?? '').trim();
    if (agent.isNotEmpty && agent != widget.ownAgent) {
      return AgentMochi(agent, size: 18);
    }
    final provider =
        widget.providers[l.profile] ?? widget.providers[widget.ownProfile];
    if (provider != null) return ProviderLogo(provider, size: 16);
    return AgentMochi(widget.ownAgent ?? 'snippet', size: 18);
  }

  List<Widget> _laneRows(List<LaneInfo> lanes) {
    lanes.sort((a, b) => (b.running ? 1 : 0) - (a.running ? 1 : 0));
    return [
      for (final l in lanes.take(4))
        InkWell(
          onTap: () => openLaneView(context, l,
              client: widget.client,
              sessionId: widget.sessionId,
              liveLanes: () => widget.state?.lanes ?? [l]),
          borderRadius: BorderRadius.circular(R.md),
          hoverColor: AppColors.surface2,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 40),
            child: Row(children: [
              SizedBox.square(
                  dimension: 20, child: Center(child: _laneMark(l))),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l.title.isEmpty ? l.id : l.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(13, color: AppColors.fg2)),
                    Row(children: [
                      _Dot(l.running
                          ? AppColors.accent
                          : l.status == 'failed'
                              ? AppColors.danger
                              : AppColors.ok),
                      const SizedBox(width: 6),
                      Expanded(
                          child: Text(
                              l.running
                                  ? ((l.activity ?? '').trim().isEmpty
                                      ? 'Running'
                                      : 'Running · ${l.activity!.trim()}')
                                  : l.status == 'failed'
                                      ? 'Failed'
                                      : 'Finished',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(11.5, color: AppColors.fg4))),
                    ]),
                  ],
                ),
              ),
              if (l.running) _OutlineButton('Stop', () => _stopLane(l.id)),
            ]),
          ),
        ),
      if (lanes.length > 4)
        _MoreRow('${lanes.length - 4} more', widget.onLanes),
    ];
  }

  List<Widget> _changeRows(List<FileChange> files) => [
        for (final f in files.take(5))
          InkWell(
            onTap: widget.onChanges,
            borderRadius: BorderRadius.circular(R.md),
            hoverColor: AppColors.surface2,
            child: SizedBox(
              height: 26,
              child: Row(children: [
                Expanded(child: _PathText(f.path)),
                if (f.added > 0)
                  Text('+${f.added}', style: mono(11, color: AppColors.ok)),
                SizedBox(
                  width: 30,
                  child: Text('−${f.removed}',
                      textAlign: TextAlign.right,
                      style: mono(11, color: AppColors.danger)),
                ),
              ]),
            ),
          ),
        if (files.length > 5)
          _MoreRow('${files.length - 5} more', widget.onChanges),
      ];

  // Context and limits, moved here from under the composer.
  List<Widget> _usageRows(HarnessState? s) {
    if (s == null) return const [];
    final rows = <Widget>[];
    if (s.contextWindow > 0 && s.lastPromptTokens > 0) {
      final pct = (s.lastPromptTokens / s.contextWindow * 100).clamp(0, 100);
      rows.add(_UsageRow('Context', '${pct.round()}%', pct / 100,
          detail: 'of ${fmtSi(s.contextWindow)}'));
    }
    if (s.totalTokens > 0) {
      rows.add(_UsageRow('Tokens', fmtSi(s.totalTokens), null));
    }
    final r = s.rateSecondary;
    if (r != null && r.isReported && !r.isExpired) {
      final win = limitWindowLabel(r);
      final pct = r.usedPercent.clamp(0, 100);
      rows.add(_UsageRow(win == '7d' ? 'This week' : 'Limit ($win)',
          '${pct.round()}%', pct / 100,
          warn: pct >= 70));
    }
    return rows;
  }

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
      if (_autonomous != null && widget.onAutonomy != null)
        _RailRow(
            icon: 'activity',
            label: 'Automated wakes',
            value: _autonomous! ? 'On' : 'Off',
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
          icon: 'timer',
          label: 'Keep warm',
          trailing: SettingsSwitch(value: _warm!, onChanged: _setWarm),
          onTap: () => _setWarm(!_warm!),
        ),
    ];
  }

  // Mission Control panel.
  List<Widget> _flightRows() => [
        for (final t in _tasks.take(6))
          InkWell(
            onTap: widget.onOpenTask == null
                ? null
                : () => widget.onOpenTask!(t.id),
            borderRadius: BorderRadius.circular(R.md),
            hoverColor: AppColors.surface2,
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 40),
              child: Row(children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(13, color: AppColors.fg2)),
                      Text(
                          [
                            t.status.label,
                            if ((t.currentStep ?? '').isNotEmpty)
                              t.currentStep!,
                          ].join(' · '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(11.5, color: AppColors.fg4)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                _Dot(AppColors.accent),
              ]),
            ),
          ),
      ];

  List<Widget> _autonomyRows() => [
        _RailRow(
          icon: 'repeat',
          label: 'Cold resume',
          value: switch (widget.resumeMode) {
            'lean' => 'Lean',
            'full' => 'Full',
            _ => 'Ask',
          },
          onTap: widget.onCycleResume,
        ),
      ];

  List<Widget> _wakeRows() {
    final wake = _wake;
    return [
      if (_autonomous != null)
        _RailRow(
            icon: 'activity',
            label: 'Automated wakes',
            value: _autonomous! ? 'On' : 'Off',
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
    ];
  }

  List<Widget> _modelRows(HarnessState? s) {
    final rows = <Widget>[
      InkWell(
        onTap: widget.onModel,
        borderRadius: BorderRadius.circular(R.md),
        child: Container(
          height: 30,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(R.md)),
          child: Row(children: [
            Expanded(
              child: Text(widget.profileLabel,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13, color: AppColors.fg1)),
            ),
            AppIcon('chevron-down', size: 12, color: AppColors.fg4),
          ]),
        ),
      ),
      const SizedBox(height: 4),
    ];
    if (s != null && s.contextWindow > 0 && s.lastPromptTokens > 0) {
      final pct = (s.lastPromptTokens / s.contextWindow * 100).clamp(0, 100);
      rows.add(_UsageRow('Context', '${pct.round()}%', pct / 100));
    }
    return rows;
  }
}

/// Section open/closed state, shared by every panel and kept across launches.
final Map<String, bool> _railOpen = {};
const String _railOpenPref = 'session_rail_open_';

class _RailGroup extends StatefulWidget {
  const _RailGroup({
    super.key,
    required this.label,
    required this.children,
    this.meta,
    this.link,
    this.onLabel,
    this.divider = true,
    this.initiallyOpen = true,
  });
  final String label;
  final String? meta;
  final String? link;
  final VoidCallback? onLabel;
  final bool divider;
  final bool initiallyOpen;
  final List<Widget> children;

  @override
  State<_RailGroup> createState() => _RailGroupState();
}

class _RailGroupState extends State<_RailGroup> {
  bool get _open => _railOpen[widget.label] ?? widget.initiallyOpen;

  @override
  void initState() {
    super.initState();
    if (!_railOpen.containsKey(widget.label)) {
      SharedPreferences.getInstance().then((p) {
        final v = p.getBool('$_railOpenPref${widget.label}');
        if (v == null || !mounted) return;
        setState(() => _railOpen[widget.label] = v);
      });
    }
  }

  Future<void> _toggle() async {
    final v = !_open;
    setState(() => _railOpen[widget.label] = v);
    final p = await SharedPreferences.getInstance();
    await p.setBool('$_railOpenPref${widget.label}', v);
  }

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final open = _open;
    final head = InkWell(
      onTap: _toggle,
      borderRadius: BorderRadius.circular(R.sm),
      child: SizedBox(
        height: 24,
        child: Row(children: [
          AnimatedRotation(
            turns: open ? 0.25 : 0,
            duration: Motion.fast,
            child: AppIcon('chevron-right', size: 12, color: AppColors.fg4),
          ),
          const SizedBox(width: 6),
          Text(w.label, style: sans(12, weight: W.label, color: AppColors.fg3)),
          if (w.meta != null) ...[
            const SizedBox(width: 8),
            Flexible(
              child: Text(w.meta!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12, color: AppColors.fg4, tabular: true)),
            ),
          ],
          const Spacer(),
          if (w.link != null && w.onLabel != null)
            InkWell(
              onTap: w.onLabel,
              borderRadius: BorderRadius.circular(R.sm),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(w.link!, style: sans(11.5, color: AppColors.fg4)),
                  AppIcon('chevron-right', size: 12, color: AppColors.fg4),
                ]),
              ),
            ),
        ]),
      ),
    );
    return Container(
      padding: EdgeInsets.fromLTRB(10, 8, 14, open ? 6 : 8),
      decoration: BoxDecoration(
          border: w.divider
              ? Border(top: BorderSide(color: AppColors.line))
              : null),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          head,
          AnimatedSize(
            duration: Motion.fast,
            curve: Motion.enter,
            alignment: Alignment.topCenter,
            child: open
                ? Padding(
                    padding: const EdgeInsets.only(left: 4, top: 4),
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: w.children),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }
}

class _Dot extends StatelessWidget {
  const _Dot(this.color);
  final Color color;

  @override
  Widget build(BuildContext context) => Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle));
}

class _OutlineButton extends StatelessWidget {
  const _OutlineButton(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.sm),
        child: Container(
          height: 24,
          padding: const EdgeInsets.symmetric(horizontal: 9),
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.sm),
            border: Border.all(color: AppColors.lineStrong),
          ),
          child: Text(label, style: sans(12, color: AppColors.fg2)),
        ),
      );
}

/// Directory dimmed, file name bright, one line.
class _PathText extends StatelessWidget {
  const _PathText(this.path);
  final String path;

  @override
  Widget build(BuildContext context) {
    final i = path.lastIndexOf('/');
    return Text.rich(
      TextSpan(children: [
        if (i >= 0)
          TextSpan(
              text: path.substring(0, i + 1),
              style: mono(12, color: AppColors.fg4)),
        TextSpan(
            text: i >= 0 ? path.substring(i + 1) : path,
            style: mono(12, color: AppColors.fg2)),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
    );
  }
}

class _UsageRow extends StatelessWidget {
  const _UsageRow(this.label, this.value, this.fraction,
      {this.detail, this.warn = false});
  final String label;
  final String value;
  final double? fraction;
  final String? detail;
  final bool warn;

  @override
  Widget build(BuildContext context) =>
      Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        SizedBox(
          height: 28,
          child: Row(children: [
            Text(label, style: sans(13, color: AppColors.fg2)),
            const Spacer(),
            Text(value, style: mono(12, color: AppColors.fg3, tabular: true)),
          ]),
        ),
        if (fraction != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: SizedBox(
                height: 4,
                child: Stack(children: [
                  Positioned.fill(child: ColoredBox(color: AppColors.surface3)),
                  FractionallySizedBox(
                    widthFactor: fraction!.clamp(0.0, 1.0),
                    child:
                        ColoredBox(color: warn ? AppColors.run : AppColors.fg3),
                  ),
                ]),
              ),
            ),
          ),
      ]);
}

class _MoreRow extends StatelessWidget {
  const _MoreRow(this.label, this.onTap);
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.sm),
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
    this.danger = false,
    this.onTap,
  });
  final String icon;
  final String label;
  final String? value;
  final Widget? trailing;
  final bool chevron;
  final bool danger;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(R.md),
      hoverColor: AppColors.surface2,
      child: SizedBox(
        height: 30,
        child: Row(children: [
          AppIcon(icon,
              size: 14, color: danger ? AppColors.danger : AppColors.fg4),
          const SizedBox(width: 10),
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    sans(13, color: danger ? AppColors.danger : AppColors.fg2)),
          ),
          if (value != null) ...[
            const SizedBox(width: 8),
            Flexible(
              flex: 0,
              child: Text(value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12, color: AppColors.fg4, tabular: true)),
            ),
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
    );
  }
}
