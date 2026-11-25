import 'dart:async';

import 'package:flutter/material.dart';

import '../../api.dart';
import '../../goal_models.dart';
import '../../models.dart';
import '../../motion_routes.dart';
import '../../panel.dart' show presentScreen;
import '../../tap_detector.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../session.dart' show SessionScreen;
import '../spec_bar.dart';
import '../tasks/task_common.dart' show openTaskDetail;
import '../tasks/task_phone.dart';
import '../tasks/task_phone_list.dart' show PhoneTaskCard;

/// A pushed Goal page (TK-04): bar B, progress, contributing sessions, tasks
/// in the TK-01 row shape, and the acceptance text when there is any.
Future<void> openGoalPhonePage(
        BuildContext context, DaemonClient client, String goalId) =>
    Navigator.of(context).push<void>(AppPageRoute<void>(
      builder: (_) => GoalPhonePage(client: client, goalId: goalId),
    ));

class GoalPhonePage extends StatefulWidget {
  const GoalPhonePage({super.key, required this.client, required this.goalId});
  final DaemonClient client;
  final String goalId;

  @override
  State<GoalPhonePage> createState() => _GoalPhonePageState();
}

class _GoalPhonePageState extends State<GoalPhonePage> {
  GoalDetail? _d;
  Map<String, SessionInfo> _sessions = const {};
  Map<String, String> _agents = const {};
  Object? _error;

  @override
  void initState() {
    super.initState();
    unawaited(_load());
  }

  Future<void> _load() async {
    try {
      final d = await widget.client.goal(widget.goalId);
      if (!mounted) return;
      setState(() {
        _d = d;
        _error = null;
      });
    } catch (e) {
      if (mounted) setState(() => _error = e);
      return;
    }
    try {
      final s = await widget.client.sessions();
      if (mounted) setState(() => _sessions = {for (final x in s) x.id: x});
    } catch (_) {}
    try {
      final a = await widget.client.coordinationAgents();
      if (mounted) {
        setState(() => _agents = {
              for (final x in a)
                if (x.displayName.trim().isNotEmpty) x.id: x.displayName.trim()
            });
      }
    } catch (_) {}
  }

  String _agent(String? id) =>
      id == null ? '' : (_agents[id] ?? (id.isEmpty ? '' : id));

  void _openSession(String id, String title) => presentScreen(context,
      builder: (_, close) => SessionScreen(
          client: widget.client, sessionId: id, title: title, onMenu: close));

  @override
  Widget build(BuildContext context) {
    final d = _d;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          SpecBar(title: d?.goal.title.isNotEmpty == true ? d!.goal.title : 'Goal', subtitle: 'Goal'),
          Expanded(child: d == null ? _stub() : _body(d)),
        ]),
      ),
    );
  }

  Widget _stub() => _error != null
      ? EmptyState(
          icon: 'alert-circle',
          title: "Couldn't load this goal",
          body: 'Check the connection and try again.',
          action: StateButton('Retry', onTap: () {
            setState(() => _error = null);
            _load();
          }))
      : const AppLoading(label: 'Loading goal');

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 24, 16, 8),
        child: Semantics(
          header: true,
          child: Text(t, style: sans(12, weight: W.label, color: AppColors.fg3)),
        ),
      );

  Widget _body(GoalDetail d) {
    final p = d.goal.progress;
    final pct = p.total == 0 ? 0 : (p.done * 100 / p.total).round();
    final blocked = d.tasks
        .where((t) => TaskStatus.parse(t.status) == TaskStatus.blocked)
        .length;
    // One row per session that did work on a task, newest first.
    final bySession = <String, String>{};
    for (final t in d.tasks) {
      final s = t.sessionId;
      if (s == null || s.isEmpty) continue;
      final cur = bySession[s];
      if (cur == null || t.updatedAt.compareTo(cur) > 0) bySession[s] = t.updatedAt;
    }
    final sessionIds = bySession.keys.toList()
      ..sort((a, b) => bySession[b]!.compareTo(bySession[a]!));
    final criteria = [
      for (final c in d.acceptance)
        if (c.criterion.trim().isNotEmpty) c.criterion.trim(),
      for (final s in d.plan)
        if (s.title.trim().isNotEmpty) s.title.trim(),
    ];
    return ListView(
      padding: const EdgeInsets.only(bottom: 24),
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
          child: LayoutBuilder(builder: (context, c) {
            final tp = TextPainter(
              text: TextSpan(
                  text: '$pct percent',
                  style: sans(12, weight: W.label, color: AppColors.fg2)),
              textDirection: TextDirection.ltr,
              textScaler: MediaQuery.textScalerOf(context),
            )..layout();
            // 68 leaves the label its 1x room (gap 4); larger text takes more.
            final room = tp.width + 4 > 68 ? tp.width + 4 : 68.0;
            final track = c.maxWidth - room;
            return Row(children: [
              Semantics(
                label: 'Progress',
                value: '$pct percent',
                child: Container(
                  key: const ValueKey('goal-track'),
                  width: track,
                  height: 6,
                  alignment: Alignment.centerLeft,
                  decoration: BoxDecoration(
                      color: AppColors.surface3,
                      borderRadius: BorderRadius.circular(3)),
                  child: FractionallySizedBox(
                    widthFactor: pct / 100,
                    child: DecoratedBox(
                        decoration: BoxDecoration(
                            color: AppColors.fg2,
                            borderRadius: BorderRadius.circular(3))),
                  ),
                ),
              ),
              const Spacer(),
              ExcludeSemantics(
                child: Text('$pct percent',
                    style: sans(12, weight: W.label, color: AppColors.fg2)),
              ),
            ]);
          }),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
              '${p.done} of ${p.total} tasks done   $blocked blocked',
              key: const ValueKey('goal-counts'),
              style: sans(12, color: AppColors.fg3)),
        ),
        if (sessionIds.isNotEmpty) ...[
          _label('Sessions contributing'),
          for (final id in sessionIds) _sessionRow(id, bySession[id]!, d),
        ],
        if (d.tasks.isNotEmpty) ...[
          _label('Tasks'),
          for (final t in d.tasks)
            PhoneTaskCard(
              key: ValueKey('goal-task-${t.id}'),
              task: TaskItem.fromJson({
                'id': t.id,
                'title': t.title,
                'status': t.status,
                'session_id': t.sessionId ?? '',
                'updated_at': t.updatedAt,
              }),
              owner: (t.agent ?? '').isEmpty ? null : _agent(t.agent),
              showPriority: false,
              onTap: () => openTaskDetail(context, widget.client, t.id),
            ),
        ],
        if (criteria.isNotEmpty) ...[
          _label('Acceptance'),
          for (final c in criteria)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: Text(c,
                  style: sans(15, height: 21 / 15, color: AppColors.fg1)),
            ),
        ],
      ],
    );
  }

  Widget _sessionRow(String id, String at, GoalDetail d) {
    final s = _sessions[id];
    final task = d.tasks.firstWhere((t) => t.sessionId == id);
    final title = (s?.title ?? '').trim().isNotEmpty
        ? s!.title.trim()
        : (_agent(task.agent).isNotEmpty ? _agent(task.agent) : 'Session');
    final who = _agent(task.agent);
    final ago = shortAgo(at);
    final sub = [if (who.isNotEmpty) who, if (ago.isNotEmpty) ago].join('   ');
    return Semantics(
      button: true,
      label: '$title, $sub',
      excludeSemantics: true,
      child: TapDetector(
        key: ValueKey('goal-session-$id'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _openSession(id, title),
        child: Column(children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 59),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: sans(15, color: AppColors.fg1)),
                      if (sub.isNotEmpty)
                        Text(sub, style: sans(12, color: AppColors.fg3)),
                    ]),
              ),
            ),
          ),
          Container(
              height: 1,
              margin: const EdgeInsets.symmetric(horizontal: 16),
              color: AppColors.border),
        ]),
      ),
    );
  }
}
