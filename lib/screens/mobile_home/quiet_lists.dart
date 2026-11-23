import 'package:flutter/material.dart';

import '../../api.dart';
import '../../crew_status.dart';
import '../../menu_widgets.dart' show relativeTime;
import '../../mochi.dart';
import '../../models.dart';
import '../../quiet.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../group_messaging.dart' show openGroupThread;
import '../tasks/task_common.dart' show openTaskDetail, showCreateTask;
import 'home_data.dart';
import 'quiet_home.dart';

int _epoch(String iso) =>
    (DateTime.tryParse(iso)?.millisecondsSinceEpoch ?? 0) ~/ 1000;

/// Quiet Tasks: in progress first, then what finished today. A calm list.
class QuietTasksScreen extends StatefulWidget {
  const QuietTasksScreen({super.key, required this.client});
  final DaemonClient client;

  @override
  State<QuietTasksScreen> createState() => _QuietTasksScreenState();
}

class _QuietTasksScreenState extends State<QuietTasksScreen> {
  List<TaskItem>? _tasks;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final t = await widget.client.tasks();
      if (mounted) setState(() {
        _tasks = t;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks = _tasks;
    final children = <Widget>[
      QuietPlaceHeader(
        title: 'Tasks',
        trailing: Semantics(
          button: true,
          label: 'New task',
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () async {
              if (await showCreateTask(context, widget.client)) _load();
            },
            child: SizedBox(
                width: 48,
                height: 48,
                child: Center(
                    child: AppIcon('plus', size: 22, color: AppColors.fg1))),
          ),
        ),
      ),
    ];
    if (tasks == null) {
      children.add(_error == null
          ? Padding(
              padding: EdgeInsets.all(S.s32),
              child: const Center(child: Spinner(size: 18)))
          : Padding(
              padding: EdgeInsets.all(S.s16),
              child: QuietNeedsYou(
                  title: 'Could not load tasks',
                  detail: _error,
                  action: 'Retry',
                  onAction: _load)));
    } else {
      final dayStart = DateTime.now()
              .copyWith(hour: 0, minute: 0, second: 0, millisecond: 0)
              .millisecondsSinceEpoch ~/
          1000;
      bool live(TaskItem t) =>
          t.status == TaskStatus.inProgress ||
          t.status == TaskStatus.inReview ||
          t.status == TaskStatus.blocked;
      final active = tasks.where(live).toList()
        ..sort((a, b) => _epoch(b.updatedAt).compareTo(_epoch(a.updatedAt)));
      final todo = tasks.where((t) => t.status == TaskStatus.todo).toList();
      final done = tasks
          .where((t) => t.status.isTerminal && _epoch(t.updatedAt) >= dayStart)
          .toList()
        ..sort((a, b) => _epoch(b.updatedAt).compareTo(_epoch(a.updatedAt)));
      Widget row(TaskItem t) => QuietRow(
            title: t.title,
            titleLines: 2,
            sub: t.statusReason?.isNotEmpty == true
                ? '${t.status.label} · ${t.statusReason}'
                : t.status.label,
            meta: relativeTime(_epoch(t.updatedAt)),
            leading: t.status == TaskStatus.blocked
                ? const QuietHand(size: 20)
                : AppIcon(
                    t.status.isTerminal
                        ? 'check-circle'
                        : t.status == TaskStatus.todo
                            ? 'circle'
                            : 'circle',
                    size: 20,
                    color: t.status.isTerminal ? AppColors.fg3 : AppColors.fg1),
            onTap: () => openTaskDetail(context, widget.client, t.id),
          );
      if (active.isNotEmpty) {
        children.add(QuietSectionLabel('In progress', count: active.length));
        children.addAll(active.map(row));
      }
      if (todo.isNotEmpty) {
        children.add(QuietSectionLabel('To do', count: todo.length));
        children.addAll(todo.take(8).map(row));
      }
      if (done.isNotEmpty) {
        children.add(QuietSectionLabel('Done today', count: done.length));
        children.addAll(done.map(row));
      }
      if (active.isEmpty && todo.isEmpty && done.isEmpty) {
        children.add(Padding(
            padding: EdgeInsets.all(S.s32),
            child: Text('No tasks yet.',
                textAlign: TextAlign.center,
                style: sans(14, color: AppColors.fg3))));
      }
    }
    children.add(SizedBox(height: S.s24));
    return RefreshIndicator(onRefresh: _load, child: ListView(children: children));
  }
}

/// Quiet Agents: Lead, groups, then every agent with what it is doing.
class QuietAgentsScreen extends StatefulWidget {
  const QuietAgentsScreen({
    super.key,
    required this.client,
    required this.agents,
    required this.sessions,
    required this.onOpenAgent,
    required this.onOpenLead,
  });
  final DaemonClient client;
  final List<CoordinationAgent> agents;
  final List<SessionInfo> sessions;
  final void Function(CoordinationAgent a) onOpenAgent;
  final VoidCallback onOpenLead;

  @override
  State<QuietAgentsScreen> createState() => _QuietAgentsScreenState();
}

class _QuietAgentsScreenState extends State<QuietAgentsScreen> {
  List<GroupSummary> _groups = const [];
  final _q = TextEditingController();

  @override
  void initState() {
    super.initState();
    widget.client.groups().then((g) {
      if (mounted) setState(() => _groups = g);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim().toLowerCase();
    final rows = agentRows(widget.agents, widget.sessions);
    final all = [...rows.needs, ...rows.working, ...rows.asleep]
        .where((r) =>
            q.isEmpty || r.agent.displayName.toLowerCase().contains(q))
        .toList();
    final groups = sortedGroups(_groups)
        .where((g) => q.isEmpty || g.title.toLowerCase().contains(q))
        .toList();
    Widget leading(AgentRow r) => AgentMochi(r.agent.id, size: 28);
    String line(AgentRow r) => switch (r.state) {
          CrewState.needsYou => 'Needs you',
          CrewState.working => 'Working',
          _ => 'Asleep',
        };
    return ListView(children: [
      const QuietPlaceHeader(title: 'Agents'),
      Padding(
        padding: EdgeInsets.fromLTRB(S.s16, S.s8, S.s16, S.s4),
        child: TextField(
          controller: _q,
          onChanged: (_) => setState(() {}),
          style: sans(15, color: AppColors.fg1),
          cursorColor: AppColors.fg1,
          decoration: InputDecoration(
            isDense: true,
            filled: true,
            fillColor: AppColors.surface2,
            hintText: 'Search agents, groups',
            hintStyle: sans(15, color: AppColors.fg4),
            prefixIcon: Padding(
                padding: EdgeInsets.symmetric(horizontal: S.s12),
                child: AppIcon('search', size: 18, color: AppColors.fg4)),
            prefixIconConstraints:
                const BoxConstraints(minWidth: 0, minHeight: 0),
            contentPadding: EdgeInsets.symmetric(vertical: 12),
            border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(R.of(12)),
                borderSide: BorderSide.none),
          ),
        ),
      ),
      if (q.isEmpty)
        QuietRow(
          title: 'Lead',
          sub: 'Orchestrator',
          leading: AgentMochi('lead', size: 28),
          onTap: widget.onOpenLead,
        ),
      if (groups.isNotEmpty) ...[
        QuietSectionLabel('Groups', count: groups.length),
        for (final g in groups)
          QuietRow(
            title: g.title.isEmpty ? 'Group' : g.title,
            sub: '${g.members.length} members',
            leading: AppIcon('users', size: 22, color: AppColors.fg2),
            onTap: () => openGroupThread(context, client: widget.client, group: g),
          ),
      ],
      QuietSectionLabel('Agents', count: all.length),
      for (final r in all)
        QuietRow(
          title: r.agent.displayName,
          sub: line(r),
          leading: leading(r),
          trailing: r.state == CrewState.needsYou
              ? const QuietHand(size: 16)
              : null,
          onTap: () => widget.onOpenAgent(r.agent),
        ),
      SizedBox(height: S.s24),
    ]);
  }
}
