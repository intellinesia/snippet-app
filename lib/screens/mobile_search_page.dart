import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import '../widgets.dart';
import 'agent_card.dart';
import 'session_list_row.dart';
import 'tasks/task_common.dart';

/// Phone v5 search: one field filtering sessions, tasks and agents, opened
/// full-screen from the bottom bar's search circle.
class MobileSearchPage extends StatefulWidget {
  const MobileSearchPage({
    super.key,
    required this.client,
    required this.sessions,
    required this.onOpenSession,
    required this.onOpenAgent,
  });

  final DaemonClient? client;
  final List<SessionInfo> sessions;
  final void Function(String id, String title, String? profile) onOpenSession;
  final ValueChanged<CoordinationAgent> onOpenAgent;

  @override
  State<MobileSearchPage> createState() => _MobileSearchPageState();
}

class _MobileSearchPageState extends State<MobileSearchPage> {
  final TextEditingController _ctl = TextEditingController();
  String _query = '';
  List<TaskItem>? _tasks;
  List<CoordinationAgent>? _agents;

  @override
  void initState() {
    super.initState();
    final client = widget.client;
    if (client == null) return;
    client.tasks(limit: 200).then((v) {
      if (mounted) setState(() => _tasks = v);
    }).catchError((_) {});
    client.coordinationAgents().then((v) {
      if (mounted) setState(() => _agents = v);
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _ctl.dispose();
    super.dispose();
  }

  List<SessionInfo> _sessionHits(String q) => widget.sessions
      .where((s) =>
          s.title.toLowerCase().contains(q) ||
          s.projectFolder.toLowerCase().contains(q) ||
          (s.branch ?? '').toLowerCase().contains(q))
      .take(8)
      .toList();

  List<TaskItem> _taskHits(String q) => (_tasks ?? const <TaskItem>[])
      .where((t) =>
          t.title.toLowerCase().contains(q) ||
          t.id.toLowerCase().startsWith(q))
      .take(6)
      .toList();

  List<CoordinationAgent> _agentHits(String q) =>
      (_agents ?? const <CoordinationAgent>[])
          .where((a) =>
              a.displayName.toLowerCase().contains(q) ||
              a.id.toLowerCase().contains(q))
          .take(6)
          .toList();

  void _openSession(SessionInfo s) {
    Navigator.of(context).pop();
    widget.onOpenSession(s.id, s.title, s.profile);
  }

  void _openTask(TaskItem t) {
    final client = widget.client;
    if (client == null) return;
    final nav = Navigator.of(context);
    nav.pop();
    openTaskDetail(nav.context, client, t.id);
  }

  void _openAgent(CoordinationAgent a) {
    Navigator.of(context).pop();
    widget.onOpenAgent(a);
  }

  @override
  Widget build(BuildContext context) {
    final q = _query.trim().toLowerCase();
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(M.gutter, 8, M.gutter, 0),
            child: Row(children: [
              Expanded(child: _field()),
              const SizedBox(width: 12),
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => Navigator.of(context).maybePop(),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                      horizontal: 4, vertical: 11),
                  child: Text('Cancel',
                      style: sans(15, color: AppColors.fg1)),
                ),
              ),
            ]),
          ),
          Expanded(child: _results(q)),
        ]),
      ),
    );
  }

  Widget _field() {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(22),
      ),
      padding: const EdgeInsets.only(left: 16, right: 4),
      child: Row(children: [
        AppIcon('search', size: 16, color: AppColors.fg3),
        const SizedBox(width: 10),
        Expanded(
          child: TextField(
            controller: _ctl,
            autofocus: true,
            onChanged: (v) => setState(() => _query = v),
            style: TS.body(),
            cursorColor: AppColors.accent,
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              hintText: 'Search',
              hintStyle: TS.body(AppColors.fg3),
            ),
          ),
        ),
        ListenableBuilder(
          listenable: _ctl,
          builder: (_, __) => _ctl.text.isEmpty
              ? const SizedBox(width: 4)
              : IconBtn('x',
                  size: 36,
                  iconSize: 16,
                  tooltip: 'Clear',
                  onTap: () {
                    _ctl.clear();
                    setState(() => _query = '');
                  }),
        ),
      ]),
    );
  }

  Widget _results(String q) {
    if (q.isEmpty) return const SizedBox.shrink();
    final sessions = _sessionHits(q);
    final tasks = _taskHits(q);
    final agents = _agentHits(q);
    if (sessions.isEmpty && tasks.isEmpty && agents.isEmpty) {
      return Align(
        alignment: Alignment.topCenter,
        child: Padding(
          padding: const EdgeInsets.only(top: 72),
          child: Text('No results',
              style: sans(14, color: AppColors.fg3)),
        ),
      );
    }
    return ListView(children: [
      if (sessions.isNotEmpty)
        ..._section('Sessions', [
          for (final s in sessions)
            _row(
              title: s.title,
              meta: projectLabel(s),
              onTap: () => _openSession(s),
            ),
        ]),
      if (tasks.isNotEmpty)
        ..._section('Tasks', [
          for (final t in tasks)
            _row(
              title: t.title,
              meta: t.status.label,
              onTap: () => _openTask(t),
            ),
        ]),
      if (agents.isNotEmpty)
        ..._section('Agents', [
          for (final a in agents)
            _row(
              title: a.displayName,
              meta: agentStatusLine(a,
                  presence: widget.client?.presence.presenceForAgentId(a.id)),
              onTap: () => _openAgent(a),
            ),
        ]),
    ]);
  }

  List<Widget> _section(String label, List<Widget> rows) => [
        Padding(
          padding: const EdgeInsets.fromLTRB(M.gutter, 16, M.gutter, 4),
          child: Text(label, style: sans(13, color: AppColors.fg3)),
        ),
        for (var i = 0; i < rows.length; i++) ...[
          rows[i],
          if (i < rows.length - 1)
            Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: M.gutter),
              color: AppColors.border,
            ),
        ],
      ];

  Widget _row(
      {required String title,
      required String meta,
      required VoidCallback onTap}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: M.gutter, vertical: 10),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TS.rowTitle(AppColors.fg1)),
          const SizedBox(height: 2),
          Text(meta,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(13, color: AppColors.fg3)),
        ]),
      ),
    );
  }
}
