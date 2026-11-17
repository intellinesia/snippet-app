import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../api.dart';
import '../models.dart';
import '../settings_form.dart';
import '../tool_activity.dart';
import 'file_changes.dart' show sessionChangeSteps;
import 'lanes.dart' show openLaneView;
import '../mochi.dart' show AgentMochi;
import '../platform.dart';
import '../theme.dart';
import '../wake_models.dart';
import '../widgets.dart';

part 'session_rail_pages.dart';

const String kSessionRailCollapsedPref = 'session_rail_collapsed';
const double kSessionRailWidth = 288;

/// Window-bar right padding plus the gap after its last tool, so the panel's
/// right edge lines up with the toggle button above it.
double get kSessionRailEdgeInset => S.of(10) + S.s2;

/// Chat must keep at least this much room beside the rail.
const double kSessionRailMinChat = 520;

/// Narrowest session column that still shows the rail.
const double kSessionRailMinColumn =
    kSessionRailMinChat + kSessionRailWidth + 24;

final ValueNotifier<bool> sessionRailCollapsed = ValueNotifier<bool>(false);

/// The panel as a floating card, for windows too narrow to dock it.
final ValueNotifier<bool> sessionRailFloating = ValueNotifier<bool>(false);

/// Set from outside the panel (the bar's goal icon) to open the goal editor
/// in place once the panel is showing; the panel clears it.
final ValueNotifier<bool> sessionGoalEditRequest = ValueNotifier<bool>(false);
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
    this.handOffPanel,
    this.onForkNow,
    this.onRewindNow,
    this.onCompactNow,
    this.onDeleteNow,
    this.onMemory,
    this.onOpenTask,
    this.onHandOff,
    this.onFork,
    this.onCompact,
    this.onDeliverables,
    this.onRecurring,
    this.onDelete,
    this.onAnswer,
    this.onSubmitGoal,
    this.onResumeGoal,
    this.onEndGoal,
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

  /// Inline bodies for the action strip: each opens under the strip instead
  /// of a dialog. A null one falls back to its plain callback above.
  final Widget Function(VoidCallback close)? handOffPanel;
  final VoidCallback? onForkNow;
  final Future<void> Function(Checkpoint c)? onRewindNow;
  final VoidCallback? onCompactNow;
  final VoidCallback? onDeleteNow;
  final VoidCallback? onMemory;
  final void Function(String taskId)? onOpenTask;
  final VoidCallback? onHandOff;
  final VoidCallback? onFork;
  final VoidCallback? onCompact;
  final VoidCallback? onDeliverables;
  final VoidCallback? onRecurring;
  final VoidCallback? onDelete;

  /// Sends the answer to Mission Control's pending question.
  final void Function(String answer)? onAnswer;

  /// Sets or replaces the goal; the editor lives inside the goal card.
  final ValueChanged<String>? onSubmitGoal;
  final VoidCallback? onResumeGoal;
  final VoidCallback? onEndGoal;

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

/// "Delete session" that asks in place: the row turns into the question.
class _DeleteInPlace extends StatefulWidget {
  const _DeleteInPlace({required this.onDelete});
  final VoidCallback onDelete;

  @override
  State<_DeleteInPlace> createState() => _DeleteInPlaceState();
}

class _DeleteInPlaceState extends State<_DeleteInPlace> {
  bool _asking = false;

  @override
  Widget build(BuildContext context) {
    if (!_asking) {
      return _RailRow(
          icon: 'trash',
          label: 'Delete session',
          danger: true,
          onTap: () => setState(() => _asking = true));
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 6, 2, 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Text('Delete this session?',
            style: sans(13, weight: W.title, color: AppColors.fg1)),
        const SizedBox(height: 2),
        Text('Removes the conversation. Files on disk stay.',
            style: sans(11.5, color: AppColors.fg4)),
        const SizedBox(height: 10),
        Row(children: [
          const Spacer(),
          Btn('Cancel',
              small: true,
              variant: BtnVariant.surface,
              onTap: () => setState(() => _asking = false)),
          const SizedBox(width: 6),
          Btn('Delete',
              small: true, variant: BtnVariant.danger, onTap: widget.onDelete),
        ]),
      ]),
    );
  }
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

  bool _editingGoal = false;

  /// Desktop drill-in page (lanes, jobs, checkpoints, wakes, usage); null is the root.
  String? _page;
  int _laneFilter = 0;
  List<Map<String, dynamic>> _procs = const [];
  List<WakeSchedule> _wakes = const [];
  final _wakeBrief = TextEditingController();
  final _wakeSched = TextEditingController();
  bool _wakeSaving = false;
  String? _wakeError;

  void _set(VoidCallback f) {
    if (mounted) setState(f);
  }

  /// The strip action whose section is open under the strip, if any.
  String? _openAction;

  /// Checkpoint whose Rewind was tapped once and now asks to confirm.
  String? _armedRewind;

  void _closeAction() => setState(() {
        _openAction = null;
        _armedRewind = null;
      });

  void _toggleAction(String key) => setState(() {
        _openAction = _openAction == key ? null : key;
        _armedRewind = null;
      });
  final _goalText = TextEditingController();

  @override
  void initState() {
    super.initState();
    loadSessionRailPref();
    _load();
    sessionGoalEditRequest.addListener(_onGoalEditRequest);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => mounted ? _onGoalEditRequest() : null);
  }

  @override
  void dispose() {
    sessionGoalEditRequest.removeListener(_onGoalEditRequest);
    _goalText.dispose();
    _wakeBrief.dispose();
    _wakeSched.dispose();
    super.dispose();
  }

  void _onGoalEditRequest() {
    if (!sessionGoalEditRequest.value || widget.onSubmitGoal == null) return;
    sessionGoalEditRequest.value = false;
    _startGoalEdit();
  }

  void _startGoalEdit() {
    final g = widget.state?.goal;
    final initial = g != null && g.ongoing ? g.text : '';
    _goalText.text = initial;
    _goalText.selection =
        TextSelection(baseOffset: 0, extentOffset: initial.length);
    setState(() => _editingGoal = true);
  }

  void _cancelGoalEdit() => setState(() => _editingGoal = false);

  void _submitGoal() {
    final t = _goalText.text.trim();
    if (t.isEmpty) return;
    final g = widget.state?.goal;
    final current = g != null && g.ongoing ? g.text.trim() : '';
    if (t != current) widget.onSubmitGoal?.call(t);
    setState(() => _editingGoal = false);
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
    final procs = await _try(c.bgList(id)) as List<Map<String, dynamic>>?;
    if (!mounted || gen != _liveGen) return;
    setState(() {
      _git = git ?? _git;
      _procs = procs ?? _procs;
    });
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
      mc ? Future.value(null) : _try(c.bgList(id)),
      mc ? Future.value(null) : _try(c.wakes()),
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
      _procs = r[5] as List<Map<String, dynamic>>? ?? _procs;
      final wl = r[6] as WakeList?;
      if (wl != null) {
        _wakes = [
          for (final w in wl.wakes)
            if (w.owner == id) w
        ];
      }
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
            padding: EdgeInsets.fromLTRB(24, 10, kSessionRailEdgeInset, S.s12),
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
            // Pages slide in from the side they lead to; root comes back from the left.
            child: AnimatedSwitcher(
              duration: const Duration(milliseconds: 180),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              layoutBuilder: (cur, prev) => Stack(
                  alignment: Alignment.topCenter,
                  children: [...prev, if (cur != null) cur]),
              transitionBuilder: (child, anim) {
                final isRoot = child.key == const ValueKey('rail-root');
                final dx = isRoot ? -0.12 : 0.12;
                return FadeTransition(
                  opacity: anim,
                  child: SlideTransition(
                    position: Tween(begin: Offset(dx, 0), end: Offset.zero)
                        .animate(anim),
                    child: child,
                  ),
                );
              },
              child: Column(
                key: ValueKey(
                    _page == null || kMobile || widget.isMissionControl
                        ? 'rail-root'
                        : 'rail-$_page'),
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: _railBody(),
              ),
            ),
          ),
        ),
      ),
    );
  }

  List<Widget> _railBody() {
    if (kMobile || widget.isMissionControl) return _groups();
    if (_page != null) return _subPage();
    return _desktopRoot([_header()]);
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
      add('In flight', _flightRows(), meta: n == 0 ? null : '$n');
      add('Next', _wakeRows());
      add('Autonomy', _autonomyRows(), open: false);
      final ctx = _contextPct(s);
      add('Model', _modelRows(s),
          open: false,
          meta: ctx == null
              ? widget.profileLabel
              : '${widget.profileLabel} · ${ctx.round()}%');
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
    add('Usage', _usageRows(s), open: false);
    add('Next without you', _nextRows(), open: false);
    return out;
  }

  /// The goal sits at the top of the panel: its text, its state and what you
  /// can do to it. The daemon has no pause; interrupting the run pauses it.
  Widget _goalCard() {
    final g = widget.state?.goal;
    if (_editingGoal && widget.onSubmitGoal != null) {
      return _goalEditor(g != null && g.ongoing);
    }
    if (g == null || !g.ongoing) {
      if (widget.onSubmitGoal == null) return const SizedBox.shrink();
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 0),
        child: InkWell(
          onTap: _startGoalEdit,
          borderRadius: BorderRadius.circular(R.of(14)),
          child: Container(
            padding: const EdgeInsets.fromLTRB(14, 11, 12, 11),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(R.of(14)),
            ),
            child: Row(children: [
              AppIcon('goal', size: 15, color: AppColors.fg4),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Set a goal', style: sans(13, color: AppColors.fg2)),
                      const SizedBox(height: 2),
                      Text('Works toward it without you',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(11.5, color: AppColors.fg4)),
                    ]),
              ),
              AppIcon('chevron-right', size: 12, color: AppColors.fg4),
            ]),
          ),
        ),
      );
    }
    final paused = g.paused;
    final turns = g.autonomousTurns;
    final state = paused ? 'Paused' : 'Active';
    final turnsText = turns > 0 ? '$turns turn${turns == 1 ? '' : 's'}' : null;
    final tone = paused ? AppColors.fg3 : AppColors.accent;
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(R.of(14)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          AppIcon('goal', size: 12, color: AppColors.fg4),
          const SizedBox(width: 6),
          Text('Goal', style: sans(11.5, color: AppColors.fg4)),
          const SizedBox(width: 8),
          Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: tone, shape: BoxShape.circle)),
          const SizedBox(width: 5),
          Text(state, style: sans(11.5, color: tone, tabular: true)),
          if (turnsText != null) ...[
            const Spacer(),
            Text(turnsText, style: mono(11.5, color: AppColors.fg4)),
          ],
        ]),
        const SizedBox(height: 8),
        Text(g.text,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: sans(13.5, height: 1.45, color: AppColors.fg1)),
        const SizedBox(height: 10),
        Row(children: [
          if (paused && widget.onResumeGoal != null) ...[
            _goalBtn('play', 'Resume', widget.onResumeGoal),
            const SizedBox(width: 6),
          ],
          if (widget.onSubmitGoal != null) ...[
            _goalBtn('edit', 'Edit', _startGoalEdit),
            const SizedBox(width: 6),
          ],
          if (widget.onEndGoal != null)
            _goalBtn('check', 'End goal', widget.onEndGoal, quiet: true),
        ]),
      ]),
    );
  }

  /// The goal is written where it will live: the card becomes the editor.
  /// Ctrl or Cmd+Enter sets it, Escape cancels.
  Widget _goalEditor(bool replacing) {
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(R.of(14)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          AppIcon('goal', size: 12, color: AppColors.fg4),
          const SizedBox(width: 6),
          Text(replacing ? 'Edit goal' : 'New goal',
              style: sans(11.5, color: AppColors.fg4)),
        ]),
        const SizedBox(height: 8),
        CallbackShortcuts(
          bindings: {
            const SingleActivator(LogicalKeyboardKey.escape): _cancelGoalEdit,
            const SingleActivator(LogicalKeyboardKey.enter, control: true):
                _submitGoal,
            const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                _submitGoal,
          },
          child: AppField(
            controller: _goalText,
            hint: 'What should the agent work toward?',
            autofocus: true,
            minLines: 3,
            maxLines: 6,
          ),
        ),
        const SizedBox(height: 6),
        Text(
            replacing
                ? 'Replaces the current goal.'
                : 'Works toward it without you until done or ended.',
            style: sans(11.5, color: AppColors.fg4)),
        const SizedBox(height: 10),
        Row(children: [
          const Spacer(),
          Btn('Cancel',
              small: true, variant: BtnVariant.surface, onTap: _cancelGoalEdit),
          const SizedBox(width: 6),
          ValueListenableBuilder<TextEditingValue>(
            valueListenable: _goalText,
            builder: (_, v, __) => Btn(replacing ? 'Save' : 'Start goal',
                small: true,
                disabled: v.text.trim().isEmpty,
                onTap: _submitGoal),
          ),
        ]),
      ]),
    );
  }

  Widget _goalBtn(String icon, String label, VoidCallback? onTap,
      {bool quiet = false}) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(R.of(9)),
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: quiet ? null : AppColors.surface3,
          borderRadius: BorderRadius.circular(R.of(9)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AppIcon(icon, size: 12, color: AppColors.fg3),
          const SizedBox(width: 6),
          Text(label, style: sans(12, color: AppColors.fg2)),
        ]),
      ),
    );
  }

  /// The common session actions one click away; the rest behind More.
  Widget _actionStrip() {
    final w = widget;
    VoidCallback? inline(String key, bool has, VoidCallback? fallback) =>
        has ? () => _toggleAction(key) : fallback;
    final cells = <(String, String, VoidCallback?, String)>[
      if (w.onHandOff != null || w.handOffPanel != null)
        (
          'users',
          'Hand off',
          inline('handoff', w.handOffPanel != null, w.onHandOff),
          'handoff'
        ),
      if (w.onFork != null || w.onForkNow != null)
        (
          'git-branch',
          'Fork',
          inline('fork', w.onForkNow != null, w.onFork),
          'fork'
        ),
      if (w.onCheckpoints != null || w.onRewindNow != null)
        (
          'history',
          'Rewind',
          inline('rewind', w.onRewindNow != null, w.onCheckpoints),
          'rewind'
        ),
      if (w.onCompact != null || w.onCompactNow != null)
        (
          'minimize',
          'Compact',
          inline('compact', w.onCompactNow != null, w.onCompact),
          'compact'
        ),
    ];
    final more = <(String, String, VoidCallback?)>[
      if (w.onMemory != null) ('brain', 'Memory', w.onMemory),
      if (w.onDeliverables != null)
        ('folder', 'Shared files', w.onDeliverables),
      if (w.onProcesses != null) ('activity', 'Processes', w.onProcesses),
      if (w.onRecurring != null) ('repeat', 'Scheduled', w.onRecurring),
      if (w.onPullRequests != null)
        ('pull-request', 'Pull requests', w.onPullRequests),
    ];
    if (cells.isEmpty && more.isEmpty && w.onDelete == null) {
      return const SizedBox.shrink();
    }
    Widget cell(String icon, String label, void Function(BuildContext) tap,
            {bool on = false}) =>
        Expanded(
          child: Builder(
            builder: (ctx) => Material(
              color: on ? AppColors.surface3 : AppColors.surface2,
              child: InkWell(
                onTap: () => tap(ctx),
                hoverColor: AppColors.surface3,
                child: SizedBox(
                  height: 56,
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        AppIcon(icon,
                            size: 15,
                            color: on ? AppColors.fg1 : AppColors.fg3),
                        const SizedBox(height: 5),
                        Text(label,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(11,
                                color: on ? AppColors.fg1 : AppColors.fg3)),
                      ]),
                ),
              ),
            ),
          ),
        );
    final row = <Widget>[];
    for (final c in cells) {
      if (row.isNotEmpty) row.add(const SizedBox(width: 2));
      row.add(cell(c.$1, c.$2, (_) => c.$3?.call(), on: _openAction == c.$4));
    }
    // Desktop has room for the extras as a second row; delete lives in the
    // sidebar and tab menus there.
    final row2 = <Widget>[];
    if (!kMobile) {
      // Desktop lists these as rows under the strip.
    } else if (more.isNotEmpty || w.onDelete != null) {
      if (row.isNotEmpty) row.add(const SizedBox(width: 2));
      row.add(cell('more-horizontal', 'More', (ctx) => _openMore(ctx, more)));
    }
    if (row.isEmpty && row2.isEmpty) return const SizedBox.shrink();
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Padding(
        padding: const EdgeInsets.fromLTRB(12, 8, 12, 0),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(R.of(12)),
          child: Column(children: [
            if (row.isNotEmpty) Row(children: row),
            if (row.isNotEmpty && row2.isNotEmpty) const SizedBox(height: 2),
            if (row2.isNotEmpty) Row(children: row2),
          ]),
        ),
      ),
      AnimatedSize(
        duration: Motion.fast,
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: _actionSection(),
      ),
    ]);
  }

  /// The open strip action, written where it happens: under the strip.
  Widget _actionSection() {
    final k = _openAction;
    if (k == null) return const SizedBox(width: double.infinity);
    final w = widget;
    final (String title, String sub, Widget body) = switch (k) {
      'handoff' => (
          'Hand off to',
          'They take this session after the current turn.',
          w.handOffPanel?.call(_closeAction) ?? const SizedBox.shrink(),
        ),
      'fork' => (
          'Fork this conversation',
          'Copies everything so far into a new session. This one stays as '
              'it is, and files on disk are shared.',
          Row(children: [
            const Spacer(),
            Btn('Cancel',
                small: true, variant: BtnVariant.surface, onTap: _closeAction),
            const SizedBox(width: 6),
            Btn('Fork', small: true, onTap: () {
              _closeAction();
              w.onForkNow?.call();
            }),
          ]),
        ),
      'rewind' => (
          'Rewind to a checkpoint',
          'Files return to that point; later changes are discarded.',
          _rewindBody(),
        ),
      _ => (
          'Compact history',
          'Older history becomes a summary. Recent messages stay. '
              'This cannot be undone.',
          Row(children: [
            const Spacer(),
            Btn('Cancel',
                small: true, variant: BtnVariant.surface, onTap: _closeAction),
            const SizedBox(width: 6),
            Btn('Compact', small: true, onTap: () {
              _closeAction();
              w.onCompactNow?.call();
            }),
          ]),
        ),
    };
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): _closeAction,
      },
      child: Focus(
        autofocus: true,
        child: Container(
          key: ValueKey('rail-action-$k'),
          margin: const EdgeInsets.fromLTRB(12, 2, 12, 0),
          padding: const EdgeInsets.fromLTRB(12, 10, 8, 12),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(R.of(12)),
          ),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Row(children: [
              Expanded(
                child: Text(title,
                    style: sans(13, weight: W.title, color: AppColors.fg1)),
              ),
              IconBtn('x',
                  size: 24,
                  iconSize: 12,
                  tooltip: 'Close',
                  onTap: _closeAction),
            ]),
            Padding(
              padding: const EdgeInsets.only(right: 4),
              child: Text(sub,
                  style: sans(11.5, height: 1.45, color: AppColors.fg4)),
            ),
            const SizedBox(height: 10),
            Padding(padding: const EdgeInsets.only(right: 4), child: body),
          ]),
        ),
      ),
    );
  }

  /// The latest checkpoints; Rewind asks once more in place before it acts.
  Widget _rewindBody() {
    final all = widget.state?.checkpoints ?? const <Checkpoint>[];
    final recent = all.reversed.take(4).toList();
    final more = widget.onCheckpoints;
    if (recent.isEmpty) {
      return Text('No checkpoints yet.',
          style: sans(12.5, color: AppColors.fg3));
    }
    String when(Checkpoint c) {
      final t = DateTime.tryParse(c.createdAt);
      if (t == null) return '';
      final r = relativeTime(t.millisecondsSinceEpoch ~/ 1000);
      return r == 'now' ? 'just now' : '$r ago';
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Column(children: [
          for (var i = 0; i < recent.length; i++) ...[
            if (i > 0) const SizedBox(height: 2),
            Builder(builder: (_) {
              final c = recent[i];
              final armed = _armedRewind == c.id;
              return Container(
                color: AppColors.surface3,
                padding: const EdgeInsets.fromLTRB(10, 6, 6, 6),
                child: Row(children: [
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(c.label.isEmpty ? c.id : c.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(12.5, color: AppColors.fg2)),
                          if (when(c).isNotEmpty)
                            Text(when(c),
                                style: sans(11,
                                    color: AppColors.fg4, tabular: true)),
                        ]),
                  ),
                  const SizedBox(width: 6),
                  Btn(armed ? 'Restore' : 'Rewind',
                      small: true,
                      variant: armed ? BtnVariant.primary : BtnVariant.surface,
                      onTap: () {
                    if (!armed) {
                      setState(() => _armedRewind = c.id);
                      return;
                    }
                    _closeAction();
                    widget.onRewindNow?.call(c);
                  }),
                ]),
              );
            }),
          ],
        ]),
      ),
      if (more != null) ...[
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerRight,
          child: InkWell(
            onTap: () {
              _closeAction();
              more();
            },
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text('All checkpoints \u203a',
                  style: sans(12, color: AppColors.fg4)),
            ),
          ),
        ),
      ],
    ]);
  }

  void _openMore(
      BuildContext anchor, List<(String, String, VoidCallback?)> items) {
    void run(VoidCallback? f) {
      Navigator.of(anchor, rootNavigator: true).pop();
      f?.call();
    }

    showAnchoredPanel<void>(anchor,
        width: 236,
        maxHeight: 360,
        alignRight: true,
        child: Padding(
          padding: const EdgeInsets.all(6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final i in items)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child:
                    _RailRow(icon: i.$1, label: i.$2, onTap: () => run(i.$3)),
              ),
            if (widget.onDelete != null || widget.onDeleteNow != null) ...[
              if (items.isNotEmpty)
                Divider(height: 9, thickness: 1, color: AppColors.line),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: widget.onDeleteNow == null
                    ? _RailRow(
                        icon: 'trash',
                        label: 'Delete session',
                        danger: true,
                        onTap: () => run(widget.onDelete))
                    : _DeleteInPlace(onDelete: () => run(widget.onDeleteNow)),
              ),
            ],
          ]),
        ));
  }

  /// A single pending question, with its options when it has them.
  Widget _needsYouCard() {
    final qs = widget.state?.pendingQuestion?['questions'];
    if (qs is! List || qs.isEmpty || qs.first is! Map) {
      return const SizedBox.shrink();
    }
    final q = qs.first as Map;
    final text = '${q['text'] ?? ''}'.trim();
    if (text.isEmpty) return const SizedBox.shrink();
    final ak = q['answer_kind'] is Map ? q['answer_kind'] as Map : const {};
    final kind = '${ak['kind'] ?? 'free_text'}';
    String label(Object? v) => '${v ?? ''}'.trim();
    final options = qs.length > 1
        ? <String>[]
        : switch (kind) {
            'yes_no' => ['Yes', 'No'],
            'confirm' => [
                label(ak['confirm_label']).isEmpty
                    ? 'Confirm'
                    : label(ak['confirm_label']),
                label(ak['cancel_label']).isEmpty
                    ? 'Cancel'
                    : label(ak['cancel_label']),
              ],
            'single_choice' => [
                for (final c
                    in (ak['choices'] as List? ?? const []).whereType<Map>())
                  if (label(c['label']).isNotEmpty) label(c['label'])
              ],
            _ => <String>[],
          };
    return Container(
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 0),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.run.withValues(alpha: 0.11),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _Dot(AppColors.run),
          const SizedBox(width: 6),
          Text('Needs you', style: sans(11.5, color: AppColors.run)),
        ]),
        const SizedBox(height: 6),
        Text(text,
            maxLines: 4,
            overflow: TextOverflow.ellipsis,
            style: sans(13.5, color: AppColors.fg1)),
        if (options.isNotEmpty && widget.onAnswer != null) ...[
          const SizedBox(height: 10),
          Wrap(spacing: 6, runSpacing: 6, children: [
            for (final o in options)
              InkWell(
                onTap: () => widget.onAnswer!('$text\n→ $o'),
                borderRadius: BorderRadius.circular(9),
                child: Container(
                  height: 28,
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: AppColors.surface3,
                      borderRadius: BorderRadius.circular(9)),
                  child: Text(o, style: sans(12, color: AppColors.fg1)),
                ),
              ),
          ]),
        ],
      ]),
    );
  }

  double? _contextPct(HarnessState? s) => s != null &&
          s.contextWindow > 0 &&
          s.lastPromptTokens > 0
      ? (s.lastPromptTokens / s.contextWindow * 100).clamp(0, 100).toDouble()
      : null;

  String _nextWakeText(WakeSchedule w) {
    if (!w.enabled) return 'Paused';
    if (w.queued) return 'Queued';
    if (w.nextRunAt <= 0) return w.scheduleText;
    final d = DateTime.fromMillisecondsSinceEpoch(w.nextRunAt * 1000);
    final n = DateTime.now();
    final hm =
        '${d.hour.toString().padLeft(2, '0')}:${d.minute.toString().padLeft(2, '0')}';
    return d.year == n.year && d.month == n.month && d.day == n.day
        ? hm
        : '${d.day}/${d.month} $hm';
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
          if (mc && widget.headerActions != null) widget.headerActions!,
          if (!mc && widget.onShell != null)
            IconBtn('terminal',
                size: 30,
                iconSize: 15,
                tooltip: 'Terminal',
                onTap: widget.onShell),
          if (widget.floating)
            IconBtn('x',
                size: 30,
                iconSize: 15,
                tooltip: 'Close',
                onTap: () => sessionRailFloating.value = false),
        ]),
      ),
      if (mc) _needsYouCard(),
      if (!mc) _goalCard(),
      if (!mc) _actionStrip(),
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
                                      : 'Completed',
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

  /// Paths inside the workspace read relative to it.
  String _relPath(String path) {
    var ws = (widget.state?.workspace ?? '').trim();
    if (ws.isEmpty) return path;
    if (!ws.endsWith('/')) ws = '$ws/';
    return path.startsWith(ws) ? path.substring(ws.length) : path;
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
                Expanded(child: _PathText(_relPath(f.path))),
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
    final wake = _wake;
    return [
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
      _RailRow(
        icon: 'scheduled',
        label: wake?.scheduleText.isNotEmpty == true
            ? wake!.scheduleText
            : 'Next wake',
        value: !_wakeKnown
            ? null
            : wake == null
                ? 'None'
                : _nextWakeText(wake),
        onTap: widget.onWakes,
      ),
      if (_autonomous != null)
        _RailRow(
            icon: 'activity',
            label: 'Automated wakes',
            value: _autonomous! ? 'On' : 'Off',
            onTap: widget.onAutonomy),
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
            Expanded(
              child: Text(w.meta!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12, color: AppColors.fg4, tabular: true)),
            ),
          ] else
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
