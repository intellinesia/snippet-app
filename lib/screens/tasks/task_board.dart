import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../../api.dart';
import '../../mochi.dart';
import '../../models.dart';
import '../../panel.dart' show presentScreen;
import '../../platform.dart';
import '../../shell_panel.dart' show openSessionInTab;
import '../../theme.dart';
import '../../widgets.dart';
import '../list_search_field.dart';
import '../session.dart' show SessionScreen;
import 'task_common.dart';
import 'task_kanban.dart';
import 'task_view_toggle.dart';
import '../../tap_detector.dart';

/// The desktop Tasks tab: a status board by default, with a list option.
class TaskBoard extends StatefulWidget {
  const TaskBoard({super.key, required this.client});

  final DaemonClient client;

  @override
  State<TaskBoard> createState() => _TaskBoardState();
}

class _TaskBoardState extends State<TaskBoard> {
  // Remembered across tab reopenings within a run.
  static TaskView _last = TaskView.board;
  TaskView _view = _last;

  void _set(TaskView v) => setState(() => _view = _last = v);

  @override
  Widget build(BuildContext context) {
    final toggle = TaskViewToggle(value: _view, onChanged: _set);
    return _view == TaskView.board
        ? TaskKanban(client: widget.client, viewToggle: toggle)
        : TaskListView(client: widget.client, viewToggle: toggle);
  }
}

/// Grouped task rows beside the selected task.
///
/// Reads the same [TaskFeed] as the kanban; only the layout differs.
class TaskListView extends StatefulWidget {
  const TaskListView({super.key, required this.client, this.viewToggle});

  final DaemonClient client;
  final Widget? viewToggle;

  @override
  State<TaskListView> createState() => _TaskListViewState();
}

enum _Tab { active, review, done }

class _TaskListViewState extends State<TaskListView> {
  late TaskFeed _feed = TaskFeed(widget.client, onChange: _sync);
  final _search = TextEditingController();

  _Tab _tab = _Tab.active;
  bool _filtering = false;
  String _query = '';
  String? _selected;
  Map<String, String> _agentNames = const {};
  Map<String, SessionInfo> _sessions = const {};
  List<TaskAgent> _roster = const [];
  String? _rosterFor;

  static const _review = [
    TaskStatus.inReview,
    TaskStatus.blocked,
    TaskStatus.failed
  ];
  static const _flight = [TaskStatus.inProgress, TaskStatus.todo];
  static const _finished = [TaskStatus.done, TaskStatus.cancelled];

  @override
  void initState() {
    super.initState();
    unawaited(_loadContext());
  }

  @override
  void didUpdateWidget(covariant TaskListView old) {
    super.didUpdateWidget(old);
    if (old.client != widget.client) {
      _feed.dispose();
      _feed = TaskFeed(widget.client, onChange: _sync);
      _selected = null;
      unawaited(_loadContext());
    }
  }

  @override
  void dispose() {
    _feed.dispose();
    _search.dispose();
    super.dispose();
  }

  void _sync() {
    if (mounted) setState(() {});
  }

  Future<void> _loadContext() async {
    try {
      final agents = await widget.client.coordinationAgents();
      if (!mounted) return;
      setState(() => _agentNames = {
            for (final a in agents)
              if (a.displayName.trim().isNotEmpty) a.id: a.displayName.trim(),
          });
    } catch (_) {}
    try {
      final sessions = await widget.client.sessions();
      if (!mounted) return;
      setState(() => _sessions = {for (final s in sessions) s.id: s});
    } catch (_) {}
  }

  Future<void> _loadRoster(String id) async {
    _rosterFor = id;
    try {
      final r = await widget.client.taskAgents(id);
      if (!mounted || _rosterFor != id) return;
      setState(() => _roster = r.where((a) => a.active).toList());
    } catch (_) {
      if (mounted && _rosterFor == id) setState(() => _roster = const []);
    }
  }

  void _select(TaskItem t) {
    setState(() {
      _selected = t.id;
      _roster = const [];
    });
    unawaited(_loadRoster(t.id));
  }

  Future<void> _create() async {
    if (await showCreateTask(context, widget.client)) await _feed.refresh();
  }

  String _agent(String id) => _agentNames[id] ?? id;

  bool _isToday(TaskItem t) {
    final at = DateTime.tryParse(t.updatedAt)?.toLocal();
    final now = DateTime.now();
    return at != null &&
        at.year == now.year &&
        at.month == now.month &&
        at.day == now.day;
  }

  List<TaskItem> _in(List<TaskStatus> s, List<TaskItem> all) => [
        for (final t in all)
          if (s.contains(t.status)) t
      ];

  @override
  Widget build(BuildContext context) {
    final all = _feed.tasks.where((t) => taskMatches(t, _query)).toList();
    final review = _in(_review, all);
    final flight = _in(_flight, all);
    final done = _in(_finished, all);
    final today = [
      for (final t in done)
        if (_isToday(t)) t
    ];
    final sections = switch (_tab) {
      _Tab.active => [
          ('Needs review', review),
          ('In flight', flight),
          ('Done today', today),
        ],
      _Tab.review => [('Needs review', review)],
      _Tab.done => [('Done', done)],
    };
    final visible = [for (final s in sections) ...s.$2];
    final selected = visible.where((t) => t.id == _selected).firstOrNull ??
        visible.firstOrNull;
    if (selected != null && selected.id != _rosterFor) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_loadRoster(selected.id));
      });
      _rosterFor = selected.id;
    }
    final showDetail = _selected != null || selected != null;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      _top(),
      if (_filtering)
        Padding(
          padding: EdgeInsets.fromLTRB(S.s20, S.s8, S.s20, 0),
          child: SizedBox(
            height: 32,
            child: ListSearchField(
              controller: _search,
              hint: 'Filter tasks',
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
        ),
      Expanded(
        child: _feed.loading
            ? Center(child: Spinner(size: 20, color: AppColors.fg3))
            : _feed.error != null
                ? Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      Text('Could not load tasks',
                          style: sans(13, color: AppColors.fg2)),
                      SizedBox(height: S.s8),
                      Btn('Retry', small: true, onTap: _feed.refresh),
                    ]),
                  )
                : Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                        Expanded(child: _list(sections, selected)),
                        if (showDetail && selected != null)
                          _detail(selected, all),
                      ]),
      ),
    ]);
  }

  Widget _top() {
    return Container(
      height: 48,
      padding: EdgeInsets.symmetric(horizontal: S.s20),
      decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: AppColors.line))),
      child: Row(children: [
        Text('Tasks',
            style: sans(15, weight: FontWeight.w600, color: AppColors.fg1)),
        SizedBox(width: S.s12 + S.s12),
        _segment(),
        const Spacer(),
        if (widget.viewToggle != null) ...[
          widget.viewToggle!,
          SizedBox(width: S.s8),
        ],
        _SmallBtn(
            label: 'Filter',
            icon: LucideIcons.slidersHorizontal,
            onTap: () => setState(() {
                  _filtering = !_filtering;
                  if (!_filtering) {
                    _query = '';
                    _search.clear();
                  }
                })),
        SizedBox(width: S.s8),
        _SmallBtn(
            label: 'New task',
            icon: LucideIcons.plus,
            primary: true,
            onTap: _create),
      ]),
    );
  }

  Widget _segment() {
    const labels = {
      _Tab.active: 'Active',
      _Tab.review: 'Needs review',
      _Tab.done: 'Done',
    };
    return Container(
      padding: const EdgeInsets.all(2),
      decoration: BoxDecoration(
          color: AppColors.surface2, borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final t in _Tab.values)
          TapDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _tab = t),
            child: Container(
              height: 24,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _tab == t ? AppColors.surface3 : Colors.transparent,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(labels[t]!,
                  style: sans(12,
                      color: _tab == t ? AppColors.fg1 : AppColors.fg3)),
            ),
          ),
      ]),
    );
  }

  Widget _list(List<(String, List<TaskItem>)> sections, TaskItem? selected) {
    return ListView(
      padding: EdgeInsets.fromLTRB(S.s20, S.s12, S.s20, S.s20),
      children: [
        for (final s in sections)
          if (s.$2.isNotEmpty || _tab != _Tab.active) ...[
            Padding(
              padding: EdgeInsets.fromLTRB(S.s8, S.s12, S.s8, S.s6),
              child: Row(children: [
                Text(s.$1, style: sans(12, color: AppColors.fg3)),
                SizedBox(width: S.s6),
                Text('${s.$2.length}', style: mono(11, color: AppColors.fg4)),
              ]),
            ),
            if (s.$2.isEmpty)
              Padding(
                padding: EdgeInsets.symmetric(horizontal: S.s8, vertical: S.s8),
                child:
                    Text('Nothing here', style: sans(12, color: AppColors.fg4)),
              ),
            for (final t in s.$2)
              _TaskRow(
                task: t,
                selected: t.id == selected?.id,
                agentLabel: t.createdById.isEmpty ? '' : _agent(t.createdById),
                sub: _sub(t),
                onTap: () => _select(t),
              ),
          ],
      ],
    );
  }

  String _sub(TaskItem t) {
    final note = t.currentStep ?? t.statusReason;
    if (note != null) return note;
    final s = _sessions[t.sessionId];
    final b = s?.branch;
    if (b != null && b.isNotEmpty) return b;
    return switch (t.status) {
      TaskStatus.done => 'approved',
      TaskStatus.todo => 'waits to start',
      _ => '',
    };
  }

  Widget _detail(TaskItem t, List<TaskItem> all) {
    final session = _sessions[t.sessionId];
    final plan = t.workPlan;
    final lanes = [
      for (final a in _roster)
        if (a.workSessionId != null) a
    ];
    final age = taskAge(t);
    final byline = [
      if (t.createdById.isNotEmpty) _agent(t.createdById),
      if ((session?.branch ?? '').isNotEmpty) session!.branch!,
      if (age.isNotEmpty) 'updated $age ago',
    ].join(' · ');
    return Container(
      width: 340,
      padding: EdgeInsets.all(S.s16),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        border: Border(left: BorderSide(color: AppColors.line)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          _IdChip(t.id),
          SizedBox(width: S.s8),
          _Pill(t),
          const Spacer(),
          TapDetector(
            onTap: () => setState(() => _selected = null),
            child: Icon(LucideIcons.x, size: 16, color: AppColors.fg3),
          ),
        ]),
        SizedBox(height: S.s12),
        Text(t.title,
            style: sans(15,
                weight: FontWeight.w600, height: 1.35, color: AppColors.fg1)),
        SizedBox(height: S.s12),
        Row(children: [
          if (t.createdById.isNotEmpty) ...[
            AgentMochi(t.createdById, size: 14),
            SizedBox(width: S.s6),
          ],
          Expanded(
            child: Text(byline,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(12, color: AppColors.fg3)),
          ),
        ]),
        Expanded(
          child: ListView(padding: EdgeInsets.only(top: S.s12), children: [
            if (plan.isNotEmpty)
              _group('Plan', [
                for (final s in plan) _stepRow(s),
              ]),
            if (lanes.isNotEmpty)
              _group('Lanes', [
                for (final a in lanes)
                  _kv(
                    leading: Icon(LucideIcons.activity,
                        size: 14, color: AppColors.fg3),
                    left: _sessions[a.workSessionId]?.title.isNotEmpty == true
                        ? _sessions[a.workSessionId]!.title
                        : _agent(a.agentId),
                    right: a.status == 'active' ? 'running' : a.status,
                  ),
              ]),
            if (_roster.isNotEmpty)
              _group('People', [
                for (final a in _roster)
                  _kv(
                    leading: AgentMochi(a.agentId, size: 14),
                    left: _agent(a.agentId),
                    right: a.hasSessionLease ? 'holds the turn' : a.role,
                  ),
              ]),
          ]),
        ),
        Row(children: [
          _SmallBtn(
              label: 'Open room',
              onTap: () => openTaskDetail(context, widget.client, t.id)),
          SizedBox(width: S.s8),
          if (t.sessionId.isNotEmpty) ...[
            _SmallBtn(label: 'Open session', onTap: () => _openSession(t)),
            SizedBox(width: S.s8),
          ],
          const Spacer(),
          _SmallBtn(
              label: 'Message',
              primary: true,
              onTap: () => openTaskDetail(context, widget.client, t.id)),
        ]),
      ]),
    );
  }

  void _openSession(TaskItem t) {
    final tab = openSessionInTab;
    if (!kMobile && tab != null) {
      tab(widget.client, t.sessionId, _sessions[t.sessionId]?.title ?? t.title);
      return;
    }
    presentScreen(context,
        builder: (_, close) => SessionScreen(
            client: widget.client,
            sessionId: t.sessionId,
            title: _sessions[t.sessionId]?.title ?? t.title,
            onMenu: close));
  }

  Widget _group(String label, List<Widget> rows) => Padding(
        padding: EdgeInsets.only(bottom: S.s12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(2, 0, 2, 4),
            child: Text(label, style: sans(11, color: AppColors.fg4)),
          ),
          Container(
            padding: const EdgeInsets.symmetric(vertical: 4),
            decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(R.of(10))),
            child: Column(children: rows),
          ),
        ]),
      );

  Widget _stepRow(WorkStep s) => ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 30),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(children: [
            SizedBox(
              width: 14,
              child: Center(
                child: s.done
                    ? Icon(LucideIcons.check, size: 14, color: AppColors.fg3)
                    : Container(
                        width: 6,
                        height: 6,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color:
                              s.current ? AppColors.accent : AppColors.surface3,
                        ),
                      ),
              ),
            ),
            SizedBox(width: S.s8),
            Expanded(
              child: Text(s.step,
                  style: sans(12,
                      color: s.done
                          ? AppColors.fg3
                          : s.current
                              ? AppColors.fg1
                              : AppColors.fg2)),
            ),
          ]),
        ),
      );

  Widget _kv(
          {required Widget leading,
          required String left,
          required String right}) =>
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 30),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
          child: Row(children: [
            SizedBox(width: 14, child: Center(child: leading)),
            SizedBox(width: S.s8),
            Expanded(
              child: Text(left,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12, color: AppColors.fg2)),
            ),
            SizedBox(width: S.s8),
            Text(right, style: sans(12, color: AppColors.fg3)),
          ]),
        ),
      );
}

class _SmallBtn extends StatelessWidget {
  const _SmallBtn(
      {required this.label, this.icon, this.primary = false, this.onTap});
  final String label;
  final IconData? icon;
  final bool primary;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? AppColors.accentFg : AppColors.fg1;
    return TapDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: primary ? AppColors.accentFill : AppColors.surface2,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: fg),
            const SizedBox(width: 6),
          ],
          Text(label,
              style: sans(12,
                  weight: primary ? FontWeight.w600 : null, color: fg)),
        ]),
      ),
    );
  }
}

class _IdChip extends StatelessWidget {
  const _IdChip(this.id);
  final String id;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
        decoration: BoxDecoration(
            color: AppColors.surface3, borderRadius: BorderRadius.circular(5)),
        child: Text(id.length > 6 ? id.substring(0, 6) : id,
            style: codeMono(11, color: AppColors.fg3)),
      );
}

class _Pill extends StatelessWidget {
  const _Pill(this.task);
  final TaskItem task;

  @override
  Widget build(BuildContext context) {
    final t = task;
    final (label, color) = switch (t.status) {
      TaskStatus.inProgress when t.planTotal > 0 => (
          'Step ${(t.planDone + 1).clamp(1, t.planTotal)} of ${t.planTotal}',
          AppColors.accent
        ),
      TaskStatus.inProgress => ('Running', AppColors.accent),
      TaskStatus.todo => ('Queued', AppColors.fg3),
      TaskStatus.inReview => ('In review', AppColors.run),
      TaskStatus.done => ('Done', AppColors.ok),
      _ => (t.status.label, statusColor(t.status)),
    };
    final neutral = t.status == TaskStatus.todo;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 1),
      decoration: BoxDecoration(
        color: neutral ? AppColors.surface3 : color.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(6),
      ),
      child:
          Text(label, maxLines: 1, style: sans(11, color: color, height: 1.4)),
    );
  }
}

class _TaskRow extends StatefulWidget {
  const _TaskRow({
    required this.task,
    required this.selected,
    required this.agentLabel,
    required this.sub,
    required this.onTap,
  });
  final TaskItem task;
  final bool selected;
  final String agentLabel;
  final String sub;
  final VoidCallback onTap;

  @override
  State<_TaskRow> createState() => _TaskRowState();
}

class _TaskRowState extends State<_TaskRow> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.task;
    final who =
        [widget.agentLabel, widget.sub].where((s) => s.isNotEmpty).join(' · ');
    final age = taskAge(t);
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          height: 36,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: widget.selected || _hover
                ? AppColors.surface2
                : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            SizedBox(
                width: 20,
                child: t.createdById.isEmpty
                    ? null
                    : AgentMochi(t.createdById, size: 18)),
            const SizedBox(width: 10),
            _IdChip(t.id),
            const SizedBox(width: 10),
            Expanded(
              child: Text(t.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13, color: AppColors.fg1)),
            ),
            const SizedBox(width: 10),
            SizedBox(
              width: 140,
              child: Text(who,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12, color: AppColors.fg3)),
            ),
            const SizedBox(width: 10),
            SizedBox(
                width: 96,
                child: Align(alignment: Alignment.centerLeft, child: _Pill(t))),
            const SizedBox(width: 10),
            SizedBox(
              width: 56,
              child: Text(age,
                  textAlign: TextAlign.right,
                  style: sans(11, color: AppColors.fg4, tabular: true)),
            ),
          ]),
        ),
      ),
    );
  }
}
