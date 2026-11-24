import '../../chat/agent_cluster.dart';
import 'package:flutter/material.dart';

import '../../api.dart';
import '../../crew_status.dart';
import '../../mochi.dart';
import '../../models.dart';
import '../../quiet.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../../tap_detector.dart';
import '../group_messaging.dart' show openGroupThread;
import '../shell_nav.dart' show sessionBusy;
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
      if (mounted) {
        setState(() {
          _tasks = t;
          _error = null;
        });
      }
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
    return RefreshIndicator(
        onRefresh: _load, child: ListView(children: children));
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
    this.onOpenSession,
  });

  /// Opens one of the agent's sessions from its expanded row.
  final void Function(SessionInfo s)? onOpenSession;
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
        .where(
            (r) => q.isEmpty || r.agent.displayName.toLowerCase().contains(q))
        .toList();
    final groups = sortedGroups(_groups)
        .where((g) => q.isEmpty || g.title.toLowerCase().contains(q))
        .toList();
    List<SessionInfo> sessionsOf(CoordinationAgent ag) => [
          for (final x in widget.sessions)
            if (x.displayAgentId == ag.id) x
        ]..sort((x, y) => y.lastActive.compareTo(x.lastActive));
    String names(GroupSummary g) {
      final byId = {for (final ag in widget.agents) ag.id: ag.displayName};
      final n = [
        for (final m in g.members)
          if (!m.isHuman) (byId[m.id] ?? m.id)
      ];
      if (n.isEmpty) return '${g.members.length} members';
      return g.members.any((m) => m.isHuman)
          ? '${n.join(', ')} and you'
          : n.join(', ');
    }

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
            hintText: 'Search agents and groups',
            hintStyle: sans(15, color: AppColors.fg3),
            prefixIcon: Padding(
                padding: EdgeInsets.symmetric(horizontal: S.s12),
                child: AppIcon('search', size: 18, color: AppColors.fg3)),
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
        AgentListLine(
          id: 'lead',
          title: 'Lead',
          sub: 'Orchestrator',
          onTap: widget.onOpenLead,
        ),
      if (groups.isNotEmpty) ...[
        QuietSectionLabel('Groups', count: groups.length),
        for (final g in groups)
          AgentListLine(
            title: g.title.isEmpty ? 'Group' : g.title,
            sub: names(g),
            face: g.agentIds.isEmpty
                ? AppIcon('users', size: 22, color: AppColors.fg2)
                : GroupGlyph(
                    size: 40, ids: g.agentIds, count: g.members.length),
            onTap: () =>
                openGroupThread(context, client: widget.client, group: g),
          ),
      ],
      QuietSectionLabel('Agents', count: all.length),
      for (final r in all) _agentLine(r, sessionsOf(r.agent)),
      SizedBox(height: S.s24),
    ]);
  }

  String? _open;

  Widget _agentLine(AgentRow r, List<SessionInfo> mine) {
    final latest = mine.firstOrNull;
    final busy = [
      for (final x in mine)
        if (!x.settled && sessionBusy(x)) x
    ];
    final (Widget? mark, String sub) = switch (r.state) {
      CrewState.needsYou => (
          const QuietHand(size: 12),
          'Needs you · ${latest?.title ?? ''}'
        ),
      CrewState.working => (
          _dot(),
          'Working · ${(busy.firstOrNull ?? latest)?.title ?? ''}'
        ),
      _ => (
          null,
          latest == null
              ? 'Asleep'
              : 'Asleep · last active ${relativeTime(latest.lastActive) == 'now' ? 'just now' : '${relativeTime(latest.lastActive)} ago'}'
        ),
    };
    final open = _open == r.agent.id;
    final shown = [
      ...busy.take(1),
      ...mine.where((x) => !busy.contains(x)).take(busy.isEmpty ? 2 : 1),
    ];
    final line = AgentListLine(
      id: r.agent.id,
      title: r.agent.displayName,
      sub: sub.endsWith(' · ') ? sub.substring(0, sub.length - 3) : sub,
      mark: mark,
      meta: r.state == CrewState.working && latest != null
          ? relativeTime(latest.lastActive)
          : null,
      onTap: open || shown.isEmpty
          ? () => widget.onOpenAgent(r.agent)
          : () => setState(() => _open = r.agent.id),
    );
    if (!open || shown.isEmpty) return line;
    // Tapped: the row lifts onto s1 and shows its live and latest session.
    return Padding(
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
      child: Container(
        padding: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(R.of(16))),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          MediaQuery.removePadding(
              context: context, removeLeft: true, child: line),
          const SizedBox(height: 8),
          for (final x in shown)
            Semantics(
              button: true,
              label: '${x.title}, ${x.settled ? 'done' : 'working'}',
              excludeSemantics: true,
              child: TapDetector(
                behavior: HitTestBehavior.opaque,
                onTap: widget.onOpenSession == null
                    ? () => widget.onOpenAgent(r.agent)
                    : () => widget.onOpenSession!(x),
                child: SizedBox(
                  height: 44,
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(40, 0, 12, 0),
                    child: Row(children: [
                      if (!x.settled && sessionBusy(x))
                        _dot()
                      else
                        AppIcon('check', size: 12, color: AppColors.fg3),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                            x.title.isEmpty ? 'Untitled session' : x.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(14, color: AppColors.fg1)),
                      ),
                      Text(relativeTime(x.lastActive),
                          style: sans(13, color: AppColors.fg3)),
                    ]),
                  ),
                ),
              ),
            ),
        ]),
      ),
    );
  }

  Widget _dot() => SizedBox.square(
      dimension: 12,
      child: Center(
          child: Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(
                  color: AppColors.fg2, shape: BoxShape.circle))));
}

/// A 64pt list line: 40pt face, title, a quiet status line, trailing meta.
class AgentListLine extends StatelessWidget {
  const AgentListLine({
    super.key,
    this.id,
    this.face,
    required this.title,
    required this.sub,
    this.mark,
    this.meta,
    this.onTap,
  });

  final String? id;
  final Widget? face;
  final String title, sub;
  final Widget? mark;
  final String? meta;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: onTap != null,
        label: [title, sub, if (meta != null) meta!].join(', '),
        excludeSemantics: true,
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            height: 64,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                SizedBox.square(
                  dimension: 40,
                  child: Center(
                      child: face ??
                          ClipOval(child: AgentMochi(id ?? '', size: 40))),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(15,
                                weight: W.label, color: AppColors.fg1)),
                        const SizedBox(height: 2),
                        Row(children: [
                          if (mark != null) ...[
                            mark!,
                            const SizedBox(width: 4)
                          ],
                          Flexible(
                            child: Text(sub,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: sans(13, color: AppColors.fg2)),
                          ),
                        ]),
                      ]),
                ),
                if (meta != null && meta!.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(meta!, style: sans(12, color: AppColors.fg3)),
                ],
              ]),
            ),
          ),
        ),
      );
}
