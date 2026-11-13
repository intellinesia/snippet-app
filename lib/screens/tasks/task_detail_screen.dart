import '../../task_reason.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import '../../api.dart';
import '../../swr.dart';
import '../../coordination/coordination_thread_state.dart';
import '../../glass.dart';
import '../../models.dart';
import '../../platform.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../../mochi.dart';
import '../../panel.dart' show presentScreen;
import '../mobile_chrome.dart';
import '../agent_records.dart' show BoardLog;
import '../session.dart' show SessionScreen;
import 'task_common.dart' show statusColor, TaskNoteLines, taskAge;

/// One task: its state, its roster, its links, and its own message room.
///
/// The room is the whole point of a task owning a thread. Agents assigned to
/// this task — and the human — read and post here, and nobody on a DIFFERENT
/// task is woken by it, which is what a single global board could not give.
class TaskDetailScreen extends StatefulWidget {
  const TaskDetailScreen({
    super.key,
    required this.client,
    required this.taskId,
    this.onClose,
    this.embedded = false,
    this.pane = false,
  });

  final DaemonClient client;
  final String taskId;
  final VoidCallback? onClose;
  final bool embedded;
  final bool pane;

  @override
  State<TaskDetailScreen> createState() => _TaskDetailScreenState();
}

class _TaskDetailScreenState extends State<TaskDetailScreen> {
  TaskItem? task;
  List<TaskAgent> roster = const [];
  TaskLinks links = const TaskLinks();
  bool loading = true;
  String? error;
  bool busy = false;

  CoordinationThreadState? room;
  final _composer = TextEditingController();
  List<TaskTurn> turns = const [];
  List<BoardEntry> log = const [];
  bool logExpanded = false;
  int _tab = 0;
  SessionInfo? session;
  String? addressee;
  int _lastSequence = -1;
  Timer? _crewDebounce;
  Revalidator? _crewLive;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    room?.removeListener(_onRoomChanged);
    room?.dispose();
    _composer.dispose();
    _crewDebounce?.cancel();
    _crewLive?.dispose();
    super.dispose();
  }

  void _onRoomChanged() {
    if (!mounted) return;
    setState(() {});
    final newest = room?.events.lastOrNull?.sequence ?? -1;
    if (newest != _lastSequence) {
      _lastSequence = newest;
      _crewDebounce?.cancel();
      _crewDebounce =
          Timer(const Duration(milliseconds: 800), _refreshCrew);
    }
  }

  Future<void> _refreshCrew() async {
    try {
      final roster = await widget.client.taskAgents(widget.taskId);
      final turns = await widget.client.taskTurns(widget.taskId);
      final log = await widget.client.taskLog(widget.taskId);
      if (!mounted) return;
      setState(() {
        this.roster = roster;
        this.turns = turns;
        this.log = log;
      });
    } catch (_) {}
  }

  bool get _closed => const {
        TaskStatus.done,
        TaskStatus.failed,
        TaskStatus.cancelled,
      }.contains(task?.status);

  bool _holdsTurn(TaskAgent a) => !_closed && a.active && a.hasSessionLease;

  String _memberLabel(TaskAgent a) {
    if (_closed) return '';
    if (!a.active) return 'left';
    if (a.hasSessionLease) return 'has the turn';
    return (a.workSessionId ?? '').isEmpty ? 'waiting' : 'in the session';
  }

  Future<void> _load() async {
    try {
      final task = await widget.client.getTask(widget.taskId);
      final roster = await widget.client.taskAgents(widget.taskId);
      final links = await widget.client.taskLinks(widget.taskId);
      Map<String, String> titles = const {};
      try {
        titles = {for (final x in await widget.client.tasks()) x.id: x.title};
      } catch (_) {}
      SessionInfo? routed;
      try {
        if (task.sessionId.isNotEmpty) {
          final all = await widget.client.sessions();
          routed = all.where((s) => s.id == task.sessionId).firstOrNull;
        }
      } catch (_) {}
      if (!mounted) return;
      this.titles = titles;
      // The room is keyed by the task's own thread id, which the daemon derives
      // from the task — so a client never invents one, and reconnecting lands in
      // the same conversation.
      final room = CoordinationThreadState(
          client: widget.client, threadId: task.threadId)
        ..addListener(_onRoomChanged);
      room.attachLive();
      unawaited(room.refresh());
      unawaited(_refreshCrew());
      _crewLive?.dispose();
      _crewLive = Revalidator(
          client: widget.client,
          on: (e) => e['kind'] == 'agent_board',
          debounce: const Duration(seconds: 2),
          onRevalidate: ({required bool force}) {
            if (turns.lastOrNull?.open ?? false) unawaited(_refreshCrew());
          });
      setState(() {
        this.task = task;
        this.roster = roster;
        this.links = links;
        this.room = room;
        session = routed;
        error = null;
      });
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _publish(TaskItem t) {
    final feed = widget.client.swr.entry<List<TaskItem>>('coordination:tasks');
    final data = feed.data;
    if (data == null) return;
    feed.mutate([for (final x in data) x.id == t.id ? t : x]);
  }

  Future<void> _setStatus(TaskStatus status) async {
    final before = task;
    if (before == null) return;
    final moved = before.movedTo(status);
    setState(() => task = moved);
    _publish(moved);
    try {
      final updated = await widget.client.setTaskStatus(widget.taskId, status);
      if (!mounted) return;
      setState(() => task = updated);
      _publish(updated);
    } catch (e) {
      if (!mounted) return;
      setState(() => task = before);
      _publish(before);
      toast(context, '$e', danger: true);
    }
  }

  Future<void> _addAgent() async {
    final agents = await widget.client.coordinationAgents();
    if (!mounted) return;
    final onTask = roster.where((r) => r.active).map((r) => r.agentId).toSet();
    // Mission Control is not a task agent — it coordinates — so it is not
    // offered for membership either.
    final candidates = agents
        .where((a) => !onTask.contains(a.id) && !a.isMissionControl)
        .toList();
    if (candidates.isEmpty) {
      toast(context, 'Every agent is already on this task');
      return;
    }
    final picked = await showAppSheet<String>(
      context,
      title: 'Add an agent',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final a in candidates)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => Navigator.of(context).pop(a.id),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                  child: Row(children: [
                    AppIcon('agent', size: 16, color: AppColors.fg3),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                          a.displayName.trim().isEmpty ? a.id : a.displayName,
                          style: sans(13, color: AppColors.fg1)),
                    ),
                  ]),
                ),
              ),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    final before = roster;
    setState(() => roster = [
          ...roster,
          TaskAgent.fromJson({
            'task_id': widget.taskId,
            'agent_id': picked,
            'role': 'implementer',
            'status': roster.any((r) => r.active) ? 'waiting' : 'active',
            'added_at': DateTime.now().toUtc().toIso8601String(),
          }),
        ]);
    try {
      await widget.client.addTaskAgent(widget.taskId, picked);
      final updated = await widget.client.taskAgents(widget.taskId);
      if (!mounted) return;
      setState(() => roster = updated);
    } catch (e) {
      if (!mounted) return;
      setState(() => roster = before);
      toast(context, '$e', danger: true);
    }
  }

  Future<void> _transferLeaseTo(TaskAgent target) async {
    final currentActive = roster.firstWhere(
      (a) => a.hasSessionLease && a.active,
      orElse: () => roster.first,
    );
    final confirm = await showAppSheet<bool>(
      context,
      title: 'Pass the turn',
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Pass the turn to ${target.agentId}?\nThey carry on in the same workspace. ${currentActive.agentId} stays in the room and can still talk.',
              style: sans(13, color: AppColors.fg2, height: 1.4),
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text('Cancel', style: sans(13, color: AppColors.fg3)),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text('Pass the turn', style: sans(13)),
                ),
              ],
            ),
          ],
        ),
      ),
    );
    if (confirm != true || !mounted) return;
    final before = roster;
    TaskAgent withStatus(TaskAgent a, String status) => TaskAgent.fromJson({
          'task_id': a.taskId,
          'agent_id': a.agentId,
          'role': a.role,
          'work_session_id': a.workSessionId,
          'scope': a.scope,
          'status': status,
          'added_at': a.addedAt,
          'removed_at': a.removedAt,
        });
    setState(() => roster = [
          for (final a in roster)
            a.agentId == target.agentId
                ? withStatus(a, 'active')
                : a.agentId == currentActive.agentId
                    ? withStatus(a, 'waiting')
                    : a
        ]);
    try {
      await widget.client.transferTaskLease(
        widget.taskId,
        currentActive.agentId,
        target.agentId,
      );
      await _refreshCrew();
    } catch (e) {
      if (!mounted) return;
      setState(() => roster = before);
      toast(context, '$e', danger: true);
    }
  }

  Future<void> _pickAddressee() async {
    final members = roster.where((a) => a.active).map((a) => a.agentId);
    final choice = await showAppSheet<String>(
      context,
      title: 'Who is this for?',
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final (value, label) in [
          ('', _defaultAddressee),
          for (final m in members) (m, m),
          ('mission-control', 'Mission Control'),
        ])
          InkWell(
            onTap: () => Navigator.of(context).pop(value),
            child: SizedBox(
              height: 44,
              child: Row(children: [
                if (value.isNotEmpty) ...[
                  AgentMochi(value, size: 18),
                  const SizedBox(width: 10),
                ],
                Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(14, color: AppColors.fg1)),
                ),
              ]),
            ),
          ),
      ]),
    );
    if (choice == null || !mounted) return;
    setState(() => addressee = choice.isEmpty ? null : choice);
  }

  String get _defaultAddressee {
    final holder =
        roster.where((a) => a.active && a.hasSessionLease).firstOrNull;
    return holder == null || _closed
        ? 'The room'
        : '${holder.agentId} (has the turn)';
  }

  Widget _addresseeBar() {
    if (!roster.any((a) => a.active)) return const SizedBox.shrink();
    return Align(
      alignment: Alignment.centerLeft,
      child: InkWell(
        onTap: _pickAddressee,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: kMobile ? 40 : 28),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: Text('To ${addressee ?? _defaultAddressee}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(kMobile ? 13 : 12, color: AppColors.fg3)),
              ),
              const SizedBox(width: 4),
              AppIcon('chevron-down', size: 12, color: AppColors.fg4),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _turnsSection() {
    if (turns.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text('TURNS',
                style: kMobile
                    ? sans(12,
                        weight: W.label, spacing: 0.7, color: AppColors.fg4)
                    : caps(11, color: AppColors.fg3)),
          ),
          for (final turn in turns.reversed) _turnRow(turn),
        ],
      ),
    );
  }

  Widget _logSection() {
    if (log.isEmpty) return const SizedBox.shrink();
    const collapsed = 4;
    final shown =
        logExpanded || log.length <= collapsed ? log : log.sublist(0, collapsed);
    return Padding(
      padding: const EdgeInsets.only(top: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('LOG',
              style: kMobile
                  ? sans(12, weight: W.label, spacing: 0.7, color: AppColors.fg4)
                  : caps(11, color: AppColors.fg3)),
          const SizedBox(height: 4),
          BoardLog(entries: shown, showAgent: true),
          if (log.length > collapsed)
            TextButton(
              onPressed: () => setState(() => logExpanded = !logExpanded),
              child: Text(logExpanded ? 'Show less' : 'Show all ${log.length}',
                  style: sans(kMobile ? 13 : 12, color: AppColors.accent)),
            ),
        ],
      ),
    );
  }

  String _turnSummary(TaskTurn t) {
    if (t.open) return 'working now';
    String count(int n, String one) =>
        n == 0 ? '' : (n == 1 ? '1 $one' : '$n ${one}s');
    final parts = [count(t.files.length, 'file'), count(t.commits.length, 'commit')]
        .where((p) => p.isNotEmpty);
    return parts.isEmpty ? 'no changes' : parts.join(' · ');
  }

  Widget _turnRow(TaskTurn t) {
    return InkWell(
      onTap: () => _showTurn(t),
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: kMobile ? 44 : 32),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(children: [
                AgentMochi(t.agentId, size: kMobile ? 20 : 16),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(t.agentId,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(kMobile ? 14 : 13, color: AppColors.fg1)),
                ),
                const SizedBox(width: 8),
                Text(_turnSummary(t),
                    style: sans(kMobile ? 13 : 12,
                        color: t.open ? AppColors.accent : AppColors.fg4)),
              ]),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _showTurn(TaskTurn t) => showAppSheet<void>(
        context,
        title: '${t.agentId}: ${_turnSummary(t)}',
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (t.open)
              Text('Files and commits are measured when the turn ends.',
                  style: sans(13, color: AppColors.fg3, height: 1.4)),
            for (final line in [...t.commits, ...t.files])
              Padding(
                padding: const EdgeInsets.only(bottom: 6),
                child: Text(line, style: codeMono(12, color: AppColors.fg2)),
              ),
            if (t.sessionId.isNotEmpty)
              Align(
                alignment: Alignment.centerRight,
                child: TextButton(
                  onPressed: () {
                    Navigator.of(context).pop();
                    presentScreen(context,
                        builder: (_, close) => SessionScreen(
                            client: widget.client,
                            sessionId: t.sessionId,
                            title: t.agentId,
                            onMenu: close));
                  },
                  child: Text('Open session',
                      style: sans(13, color: AppColors.accent)),
                ),
              ),
          ],
        ),
      );

  String _speakerId(CoordinationEvent e) => e.eventType == 'task.lease_transferred'
      ? (e.payload['from_agent_id']?.toString() ?? e.actorId)
      : e.actorId;

  /// The speaker's name and what the post is doing: who it names, whose turn
  /// it passes, or that it needs an answer.
  Widget _speaker(CoordinationEvent e, double size) {
    final passing = e.eventType == 'task.lease_transferred';
    final name = _speakerId(e);
    final kind = e.payload['kind']?.toString();
    final to = e.addressedTo;
    return Expanded(
      child: Text.rich(
        TextSpan(children: [
          TextSpan(
              text: name,
              style: sans(size, weight: W.label, color: AppColors.fg2)),
          if (passing)
            TextSpan(
                text: ' passed the turn to ${e.payload['to_agent_id'] ?? ''}',
                style: sans(size, color: AppColors.accent))
          else if (to.isNotEmpty)
            TextSpan(
                text: ' to ${to.join(', ')}',
                style: sans(size, color: AppColors.fg3)),
          if (kind == 'question' || kind == 'blocker')
            TextSpan(
                text: ' · $kind',
                style: sans(size,
                    color: kind == 'blocker'
                        ? AppColors.danger
                        : AppColors.fg3)),
        ]),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
    );
  }

  Widget _addressed(CoordinationEvent e, Widget message) {
    if (e.addressedTo.isEmpty) return message;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('To ${e.addressedTo.join(', ')}',
            style: sans(12, color: AppColors.fg3)),
        const SizedBox(height: 4),
        message,
      ],
    );
  }

  Future<void> _linkTask() async {
    final cached =
        widget.client.swr.entry<List<TaskItem>>('coordination:tasks').data;
    final all = cached ?? await widget.client.tasks();
    if (!mounted) return;
    final other = all.where((t) => t.id != widget.taskId).toList();
    if (other.isEmpty) {
      toast(context, 'No other task to link to');
      return;
    }
    final picked = await showAppSheet<String>(
      context,
      title: 'Blocks which task?',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final t in other)
            Material(
              color: Colors.transparent,
              child: InkWell(
                onTap: () => Navigator.of(context).pop(t.id),
                child: Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
                  child: Text(t.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(13, color: AppColors.fg1)),
                ),
              ),
            ),
        ],
      ),
    );
    if (picked == null || !mounted) return;
    try {
      await widget.client.linkTasks(widget.taskId, picked);
      final updated = await widget.client.taskLinks(widget.taskId);
      if (!mounted) return;
      setState(() => links = updated);
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    }
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    final room = this.room;
    if (text.isEmpty || room == null) return;
    _composer.clear();
    final to = addressee;
    final sent = await room.send(
      to: to == null ? const [] : [to],
      actorKind: 'human',
      actorId: 'local',
      body: text,
      // Stable per attempt so a retried send cannot double-post.
      idempotencyKey:
          'task-${widget.taskId}-${DateTime.now().microsecondsSinceEpoch}',
    );
    if (!mounted) return;
    if (sent == null) {
      _composer.text = text;
      if (room.error != null) toast(context, room.error!, danger: true);
    } else {
      setState(() => addressee = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = task;
    return Scaffold(
      backgroundColor: AppColors.paneBg,
      body: SafeArea(
        bottom: false,
        child: Column(children: [
          if (!kMobile && widget.pane)
            Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 652),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                      S.s16, S.s24, S.s16, S.s8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(t?.title ?? 'Task',
                          style: sans(18,
                              weight: W.strong,
                              spacing: -0.2,
                              color: AppColors.fg1)),
                      if (t != null) ...[
                        const SizedBox(height: S.s6),
                        _byline(t),
                        if (t.goalTitle != null) _goalLine(t),
                      ],
                    ],
                  ),
                ),
              ),
            )
          else if (kMobile) _mobileTopBar(t)
          else if (widget.embedded)
            Padding(
              padding: const EdgeInsets.fromLTRB(6, 8, 10, 4),
              child: Row(children: [
                IconBtn(
                  'chevron-left',
                  size: 28,
                  iconSize: 15,
                  tooltip: 'Back',
                  onTap:
                      widget.onClose ?? () => Navigator.of(context).pop(),
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(t?.title ?? 'Task',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(13,
                          weight: W.label, color: AppColors.fg1)),
                ),
              ]),
            )
          else
            SnAppBar(
              title: t?.title ?? 'Task',
              compact: true,
              bordered: false,
            ),
          Expanded(
            child: !kMobile && widget.pane
                ? Align(
                    alignment: Alignment.topLeft,
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: double.infinity),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: S.s24),
                        child: _body(t),
                      ),
                    ),
                  )
                : _body(t),
          ),
        ]),
      ),
    );
  }

  Map<String, String> titles = const {};

  Widget _goalLine(TaskItem t) => Padding(
        padding: const EdgeInsets.only(top: 2),
        child: Text('Goal: ${t.goalTitle}',
            key: const ValueKey('task-goal'),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: sans(13, color: AppColors.fg3)),
      );

  TaskNote _note(TaskItem t) => taskNote(
        status: t.status.wire,
        statusReason: t.statusReason,
        waitingOn: t.waitingOn,
        currentStep: t.currentStep,
        supersededBy: t.supersededBy,
        titleOf: (id) => titles[id],
      );

  Widget _body(TaskItem? t) {
    return loading
        ? const Center(child: DelayedSpinner(size: 22))
        : error != null
            ? Center(
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Text(error!,
                      textAlign: TextAlign.center,
                      style: sans(12, color: AppColors.danger)),
                ),
              )
            : t == null
                ? const EmptyState(icon: 'layers', title: 'Task not found')
                : kMobile
                    ? _mobileBody(t)
                    : Column(children: [
                        Expanded(
                          child: Stack(children: [
                            CustomScrollView(slivers: [
                              SliverToBoxAdapter(child: _tabBody(t)),
                              SliverToBoxAdapter(
                                  child: Divider(height: 1, color: AppColors.line)),
                              ..._roomSlivers(),
                              const SliverToBoxAdapter(
                                  child: SizedBox(height: 64)),
                            ]),
                            Positioned(
                              left: 0,
                              right: 0,
                              bottom: 16,
                              child: Center(child: _fseg(t)),
                            ),
                          ]),
                        ),
                        _addresseeBar(),
                        _composerBar(),
                      ]);
  }

  // ---- phone v5 layout ----

  Widget _mobileTopBar(TaskItem? t) => MobileHomeHeader(
        title: t?.title ?? 'Task',
        onBack: widget.onClose ?? () => Navigator.of(context).maybePop(),
        trailing: [
          RoundBtn(
            icon: 'more-horizontal',
            size: 40,
            iconSize: 19,
            tooltip: 'Task actions',
            onTap: t == null ? null : _statusMenu,
          ),
        ],
      );

  /// The status moves the old column picker offered, behind the ⋯ button.
  void _statusMenu() {
    final t = task;
    if (t == null || busy) return;
    final allowed = [
      for (final s in TaskStatus.values)
        if (s == t.status ||
            (s != TaskStatus.inProgress &&
                (s == TaskStatus.todo ||
                    !{
                      TaskStatus.done,
                      TaskStatus.failed,
                      TaskStatus.cancelled
                    }.contains(t.status))))
          s,
    ];
    final size = MediaQuery.sizeOf(context);
    showMenu<TaskStatus>(
      context: context,
      position: RelativeRect.fromLTRB(
          size.width - 56, M.appBarHeight + 8, 16, 0),
      items: [
        for (final s in allowed)
          PopupMenuItem(
            value: s,
            enabled: s != t.status,
            child: Text(s.label,
                style: sans(15, color: s == t.status ? AppColors.fg3 : AppColors.fg1)),
          ),
      ],
    ).then((s) {
      if (s != null && s != t.status) _setStatus(s);
    });
  }

  Widget _mobileBody(TaskItem t) => Column(children: [
        Expanded(
          child: CustomScrollView(slivers: [
            SliverToBoxAdapter(child: _mobileV5Head(t)),
            SliverToBoxAdapter(child: _mobileV5Groups(t)),
            ..._roomSlivers(),
            const SliverToBoxAdapter(child: SizedBox(height: 24)),
          ]),
        ),
        _addresseeBar(),
        _composerBar(),
      ]);

  Widget _mobileV5Head(TaskItem t) {
    final age = taskAge(t);
    final inReview = t.status == TaskStatus.inReview;
    return Padding(
      padding: const EdgeInsets.fromLTRB(M.gutter, 4, M.gutter, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          _v5Pill(
            '${t.status.label}${age.isEmpty ? '' : ' · $age'}',
            lit: inReview,
          ),
          const SizedBox(width: S.s8),
          _v5Pill(t.id.length > 8 ? t.id.substring(0, 8) : t.id,
              code: true),
        ]),
        if (t.goalTitle != null) ...[
          const SizedBox(height: S.s4),
          Text('Goal: ${t.goalTitle}',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(14, color: AppColors.fg3)),
        ],
        if (inReview) ...[
          const SizedBox(height: 14),
          Row(children: [
            Expanded(child: _v5Action('Approve', primary: true,
                onTap: busy ? null : () => _setStatus(TaskStatus.done))),
            const SizedBox(width: S.s8),
            Expanded(child: _v5Action('Send back',
                onTap: busy ? null : () => _setStatus(TaskStatus.inProgress))),
          ]),
        ],
      ]),
    );
  }

  Widget _v5Pill(String text, {bool lit = false, bool code = false}) => Container(
        height: 22,
        padding: const EdgeInsets.symmetric(horizontal: S.s8),
        decoration: BoxDecoration(
          color: lit ? AppColors.runBg : AppColors.tint2,
          borderRadius: BorderRadius.circular(11),
        ),
        alignment: Alignment.center,
        child: Text(text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: code
                ? mono(11, color: AppColors.fg3)
                : sans(12,
                    color: lit ? AppColors.run : AppColors.fg2)),
      );

  Widget _v5Action(String label,
          {bool primary = false, VoidCallback? onTap}) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          height: 40,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: primary ? AppColors.accentFill : AppColors.tint2,
            borderRadius: BorderRadius.circular(12),
            border: primary ? null : Border.all(color: AppColors.line),
          ),
          child: Text(label,
              style: sans(15,
                  weight: W.label,
                  color: primary ? AppColors.accentFg : AppColors.fg1)),
        ),
      );

  Widget _v5Label(String text) => Padding(
        padding: const EdgeInsets.fromLTRB(S.s16, 14, 0, S.s6),
        child: Text(text, style: sans(13, color: AppColors.fg3)),
      );

  Widget _v5Card({required Widget child, EdgeInsets? padding}) => Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: AppColors.tint1,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.line),
        ),
        padding: padding ?? const EdgeInsets.symmetric(horizontal: 14),
        child: child,
      );

  Widget _mobileV5Groups(TaskItem t) {
    final brief = t.description.trim().isNotEmpty ? t.description : t.plan;
    return Padding(
      padding: const EdgeInsets.fromLTRB(M.gutter, 0, M.gutter, 0),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        _v5Label('Brief'),
        _v5Card(
          padding: const EdgeInsets.fromLTRB(14, S.s12, 14, S.s12),
          child: brief.trim().isEmpty
              ? Text('No brief yet.', style: sans(15, color: AppColors.fg4))
              : _Description(markdown: brief),
        ),
        if (t.workPlan.isNotEmpty) ...[
          _v5Label('Plan'),
          _v5Card(
            padding: const EdgeInsets.fromLTRB(14, S.s12, 14, S.s12),
            child: _WorkPlan(steps: t.workPlan),
          ),
        ],
        _v5Label('Details'),
        _v5Card(child: Column(children: _detailRows(t))),
        _v5Label('Log'),
        _v5Card(
          padding: const EdgeInsets.fromLTRB(14, S.s8, 14, S.s8),
          child: log.isEmpty
              ? Text('No log entries yet.', style: sans(15, color: AppColors.fg4))
              : Column(children: [
                  BoardLog(
                      entries: logExpanded || log.length <= 4
                          ? log
                          : log.sublist(0, 4),
                      showAgent: true),
                  if (log.length > 4)
                    Align(
                      alignment: Alignment.centerLeft,
                      child: TextAction(
                          logExpanded ? 'Show less' : 'Show all ${log.length}',
                          onTap: () =>
                              setState(() => logExpanded = !logExpanded)),
                    ),
                ]),
        ),
      ]),
    );
  }

  List<Widget> _detailRows(TaskItem t) {
    final holder = roster
            .where((a) => a.active && a.hasSessionLease)
            .firstOrNull ??
        roster.where((a) => a.active).firstOrNull;
    final agentId = holder?.agentId ??
        (t.createdByKind == 'agent' ? t.createdById : '');
    final reviewers = roster
        .where((a) =>
            a.active && a.role.toLowerCase().contains('review'))
        .map((a) => a.agentId)
        .toList();
    final workspace = session?.projectFolder.split('/').last ?? '';
    final seat = [workspace, taskAge(t)].where((s) => s.isNotEmpty).join(' · ');
    final branch = session?.branch ?? '';
    final changes = session?.shownChanges;
    final files = _changedFiles();
    final changesText = changes != null
        ? '+${changes.added} −${changes.removed}'
            '${changes.files > 0 ? ' · ${changes.files} ${changes.files == 1 ? 'file' : 'files'}' : ''}'
        : files.isEmpty
            ? ''
            : '${files.length} ${files.length == 1 ? 'file' : 'files'}';
    final paths = roster
        .where((a) => a.active && a.scope.trim().isNotEmpty)
        .map((a) => a.scope.trim())
        .toSet()
        .toList();
    final rows = <(String, String)>[
      ('Holder', agentId),
      ('Review', reviewers.isEmpty ? '' : reviewers.join(', ')),
      ('Seat', seat),
      ('Branch', branch.trim()),
      ('Changes', changesText),
      ('Owned paths', paths.join(', ')),
    ];
    return [
      for (var i = 0; i < rows.length; i++)
        _detailRow(rows[i].$1, rows[i].$2, last: i == rows.length - 1),
    ];
  }

  /// v5 `.pgi`: bright label left, dim value right, hairline between rows.
  Widget _detailRow(String label, String value, {bool last = false}) => Container(
        constraints: const BoxConstraints(minHeight: 44),
        padding: const EdgeInsets.symmetric(vertical: S.s8),
        decoration: BoxDecoration(
          border: last
              ? null
              : Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: Row(children: [
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(15, color: AppColors.fg1)),
          ),
          const SizedBox(width: S.s12),
          Flexible(
            child: Text(value.isEmpty ? '—' : value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(15, color: AppColors.fg3)),
          ),
        ]),
      );

  Widget _tabBody(TaskItem t) => _tabScroll(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: SizedBox(
              width: double.infinity,
              child: switch (_tab) {
                1 => _planTab(t),
                2 => _logTab(),
                3 => _changesTab(),
                _ => _summarySheet(t),
              },
            ),
          ),
        ),
      );

  Widget _tabScroll({required Widget child}) => Padding(
        padding: kMobile
            ? const EdgeInsets.fromLTRB(20, 8, 20, 16)
            : const EdgeInsets.fromLTRB(S.s16, S.s12, S.s16, S.s12),
        child: child,
      );

  Widget _summarySheet(TaskItem t) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (kMobile || !widget.pane) ...[
            Text(t.title, style: TS.sectionTitle()),
            const SizedBox(height: 6),
            _byline(t),
            const SizedBox(height: 16),
          ],
          if (t.goalTitle != null && !kMobile && !widget.pane) ...[
            _goalLine(t),
            const SizedBox(height: S.s8),
          ],
          _keyCard(_keyRows(t)),
          if (!kMobile)
            if (_standsCard(t) case final stands?) ...[
              const SizedBox(height: 10),
              stands,
            ],
          if (!kMobile && t.status == TaskStatus.inReview) ...[
            const SizedBox(height: 10),
            _verdictCard(),
          ],
          if (_latestReport() case final report?) ...[
            const SizedBox(height: 10),
            _reportCard(report),
          ],
          if (!kMobile) const SizedBox(height: 10),
          _briefCard(t),
          const SizedBox(height: 14),
          if (kMobile) ...[
          // Column picker. The current state is always shown, so the row
          // reads as the task's position; In progress is never offered, as
          // only a dispatch starts work.
          Container(
            height: kMobile ? 44 : 32,
            padding: kMobile ? const EdgeInsets.all(4) : EdgeInsets.zero,
            decoration: kMobile
                ? BoxDecoration(
                    color: AppColors.surface1,
                    borderRadius: BorderRadius.circular(22),
                    boxShadow: [
                      BoxShadow(
                          color: AppColors.fg1.withValues(alpha: 0.08),
                          spreadRadius: 1),
                    ],
                  )
                : null,
            child: ListView(
              scrollDirection: Axis.horizontal,
              children: [
                for (final s in TaskStatus.values)
                  if (s == t.status ||
                      (s != TaskStatus.inProgress &&
                          (s == TaskStatus.todo ||
                              !{
                                TaskStatus.done,
                                TaskStatus.failed,
                                TaskStatus.cancelled
                              }.contains(t.status))))
                  Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: busy || s == t.status
                            ? null
                            : () => _setStatus(s),
                        borderRadius:
                            BorderRadius.circular(kMobile ? 18 : R.chip),
                        child: Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: kMobile ? 13 : 10),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            // Same chip rule as the board's filter bar: the
                            // surface STEP separates, never a hairline.
                            color: s == t.status
                                ? (kMobile
                                    ? AppColors.surface3
                                    : AppColors.tint2)
                                : (kMobile
                                    ? Colors.transparent
                                    : AppColors.tint1),
                            borderRadius:
                                BorderRadius.circular(kMobile ? 18 : R.chip),
                          ),
                          child: Row(mainAxisSize: MainAxisSize.min, children: [
                            if (s == t.status) ...[
                              Container(
                                width: 6,
                                height: 6,
                                decoration: BoxDecoration(
                                    color: statusColor(s),
                                    shape: BoxShape.circle),
                              ),
                              const SizedBox(width: S.s6),
                            ],
                            Text(s.label,
                                style: sans(kMobile ? 14 : 12,
                                    weight: s == t.status ? W.label : W.body,
                                    color: s == t.status
                                        ? AppColors.fg1
                                        : AppColors.fg3)),
                          ]),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 14),
          ],
          _section('Agents', onAdd: _addAgent),
          if (roster.isEmpty)
            Text('Nobody assigned yet.', style: TS.meta())
          else if (kMobile)
            Column(children: [
              for (final a in roster)
                InkWell(
                  onTap: (!_closed && a.active && !a.hasSessionLease)
                      ? () => _transferLeaseTo(a)
                      : null,
                  child: SizedBox(
                    height: 48,
                    child: Row(children: [
                      _holdsTurn(a)
                          ? WorkingMochi(size: 22, color: mochiColorFor(a.agentId))
                          : AgentMochi(a.agentId, size: 22),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(a.agentId,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(15,
                                color: a.active
                                    ? AppColors.fg1
                                    : AppColors.fg3)),
                      ),
                      Text(
                          _memberLabel(a),
                          style: sans(13,
                              color: _holdsTurn(a)
                                  ? AppColors.accent
                                  : AppColors.fg4)),
                    ]),
                  ),
                ),
            ])
          else
            Container(
              decoration: BoxDecoration(
                color: AppColors.tint1,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.line),
              ),
              child: Column(children: [
                for (var i = 0; i < roster.length; i++) ...[
                  if (i > 0)
                    Divider(height: 1, thickness: 1, color: AppColors.line),
                  InkWell(
                    borderRadius: BorderRadius.vertical(
                      top: i == 0 ? const Radius.circular(10) : Radius.zero,
                      bottom: i == roster.length - 1
                          ? const Radius.circular(10)
                          : Radius.zero,
                    ),
                    onTap: (!_closed && roster[i].active && !roster[i].hasSessionLease)
                        ? () => _transferLeaseTo(roster[i])
                        : null,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 10, vertical: 8),
                      child: Row(children: [
                        _holdsTurn(roster[i])
                            ? WorkingMochi(
                                size: 18,
                                color: mochiColorFor(roster[i].agentId))
                            : AgentMochi(roster[i].agentId, size: 18),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(roster[i].agentId,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(13,
                                  color: roster[i].active
                                      ? AppColors.fg1
                                      : AppColors.fg3)),
                        ),
                        Text(
                          _memberLabel(roster[i]),
                          style: sans(12,
                              color: _holdsTurn(roster[i])
                                  ? AppColors.accent
                                  : AppColors.fg4),
                        ),
                      ]),
                    ),
                  ),
                ],
              ]),
            ),
          const SizedBox(height: 14),
          _section('Related', onAdd: _linkTask),
          if (links.links.isEmpty && links.blockedBy.isEmpty)
            Text('No linked tasks.', style: TS.meta())
          else ...[
            // Blockers first: "what is holding this up" is the question the
            // links exist to answer.
            for (final blocker in links.blockedBy)
              _linkRow('Blocked by', blocker, AppColors.danger),
            for (final l in links.links)
              if (l.kind == TaskLinkKind.relatesTo)
                _linkRow(
                    'Relates to',
                    l.toTaskId == t.id ? l.fromTaskId : l.toTaskId,
                    AppColors.fg3),
          ],
        ],
      );

  List<String> _changedFiles() {
    final seen = <String>{};
    final out = <String>[];
    for (final turn in turns) {
      for (final f in turn.files) {
        if (seen.add(f)) out.add(f);
      }
    }
    return out;
  }

  BoardEntry? _latestReport() {
    for (final e in log) {
      if (e.kind == 'reported' && e.summary.trim().isNotEmpty) return e;
    }
    return null;
  }

  Widget _byline(TaskItem t) {
    final holder = roster
            .where((a) => a.active && a.hasSessionLease)
            .firstOrNull ??
        roster.where((a) => a.active).firstOrNull;
    final agentId = holder?.agentId ??
        (t.createdByKind == 'agent' ? t.createdById : '');
    final age = taskAge(t);
    final workspace = session?.projectFolder.split('/').last ?? '';
    return Wrap(
      spacing: 12,
      runSpacing: 6,
      crossAxisAlignment: WrapCrossAlignment.center,
      children: [
        if (agentId.isNotEmpty)
          Row(mainAxisSize: MainAxisSize.min, children: [
            AgentMochi(agentId, size: 14),
            const SizedBox(width: 5),
            Text(agentId, style: TS.meta()),
          ]),
        if (kMobile) Text(t.status.label, style: TS.meta()),
        if (!kMobile && workspace.isNotEmpty)
          Row(mainAxisSize: MainAxisSize.min, children: [
            AppIcon('folder', size: 12, color: AppColors.fg4),
            const SizedBox(width: 4),
            Text(workspace, style: TS.meta()),
          ]),
        if (!kMobile)
          Text(t.id.length > 8 ? t.id.substring(0, 8) : t.id,
              style: mono(11, color: AppColors.fg4)),
        if (age.isNotEmpty)
          Text(age == 'now' ? 'Updated just now' : 'Updated $age ago',
              style: TS.meta()),
        if (kMobile && workspace.isNotEmpty) Text(workspace, style: TS.meta()),
      ],
    );
  }

  BoxDecoration get _sheetCardDecoration => BoxDecoration(
        color: AppColors.tint1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      );

  Widget _keyRow(String key, Widget value, {bool last = false}) => Container(
        constraints: const BoxConstraints(minHeight: 40),
        padding: const EdgeInsets.symmetric(vertical: 6),
        decoration: BoxDecoration(
          border: last
              ? null
              : Border(bottom: BorderSide(color: AppColors.line)),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 90,
              child: Text(
                key,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TS.label(AppColors.fg3),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(child: value),
          ],
        ),
      );

  Widget _agentNames(List<TaskAgent> list) => list.isEmpty
      ? Text('—', style: TS.ui(AppColors.fg4))
      : Wrap(
          spacing: 10,
          runSpacing: 4,
          children: [
            for (final a in list)
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  AgentMochi(a.agentId, size: 16),
                  const SizedBox(width: 5),
                  Text(
                    a.agentId,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TS.ui(AppColors.fg1),
                  ),
                ],
              ),
          ],
        );

  List<Widget> _deskKeyRows(TaskItem t) {
    final active = roster.where((a) => a.active).toList();
    final reviewers =
        active.where((a) => a.role.toLowerCase().contains('review')).toList();
    final holder = active.where((a) => a.hasSessionLease).firstOrNull;
    final branch = (session?.branch ?? '').trim();
    final age = taskAge(t);
    final c = statusColor(t.status);
    final rows = <(String, Widget)>[
      (
        'Status',
        Align(
          alignment: Alignment.centerLeft,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
            decoration: BoxDecoration(
              color: c.withValues(alpha: 0.13),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
                age.isEmpty || age == 'now'
                    ? t.status.label
                    : '${t.status.label} · $age',
                style: sans(12, color: c, tabular: true)),
          ),
        )
      ),
      if (reviewers.isNotEmpty) ('Reviewer', _agentNames(reviewers)),
      if (holder != null)
        (
          'Holder',
          Row(children: [
            _agentNames([holder]),
            if (branch.isNotEmpty) ...[
              const SizedBox(width: 10),
              Flexible(
                child: Text(branch,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono(11, color: AppColors.fg4)),
              ),
            ],
          ])
        ),
    ];
    return [
      for (var i = 0; i < rows.length; i++)
        _keyRow(rows[i].$1, rows[i].$2, last: i == rows.length - 1),
    ];
  }

  Widget? _standsCard(TaskItem t) {
    final note = _note(t);
    final status = t.status.label.toLowerCase();
    final lines = [
      if (note.reason != null && note.reason!.trim().toLowerCase() != status)
        note.reason!,
      if (note.step != null) note.step!,
      if (note.replacedBy != null) note.replacedBy!,
    ];
    if (lines.isEmpty) return null;
    return Container(
      decoration: _sheetCardDecoration,
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text('Where it stands', style: TS.label(AppColors.fg1)),
          const SizedBox(height: 4),
          for (final l in lines) Text(l, style: TS.ui(AppColors.fg2)),
        ],
      ),
    );
  }

  Widget _verdictCard() => Container(
        decoration: _sheetCardDecoration,
        padding: const EdgeInsets.fromLTRB(14, 10, 10, 10),
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Your verdict', style: TS.label(AppColors.fg1)),
                const SizedBox(height: 2),
                Text(
                    'Approving closes the task; sending back requeues it with your notes.',
                    style: TS.meta()),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Btn('Send back',
              small: true,
              variant: BtnVariant.secondary,
              onTap: busy ? null : () => _setStatus(TaskStatus.todo)),
          const SizedBox(width: 6),
          Btn('Approve',
              small: true,
              onTap: busy ? null : () => _setStatus(TaskStatus.done)),
        ]),
      );

  List<Widget> _keyRows(TaskItem t) {
    if (!kMobile) return _deskKeyRows(t);
    final members = roster.where((a) => a.active).toList();
    final display = members.isEmpty ? roster : members;
    final reviewers = display
        .where((a) => a.role.toLowerCase().contains('review'))
        .toList();
    final branch = session?.branch ?? '';
    final changes = session?.shownChanges;
    final files = _changedFiles();
    final paths = roster
        .where((a) => a.active && a.scope.trim().isNotEmpty)
        .map((a) => a.scope.trim())
        .toSet()
        .toList();
    final changesText = changes != null
        ? '+${changes.added} −${changes.removed}'
            '${changes.files > 0 ? ' · ${changes.files} ${changes.files == 1 ? 'file' : 'files'}' : ''}'
        : files.isEmpty
            ? ''
            : '${files.length} ${files.length == 1 ? 'file' : 'files'}';
    final rows = <(String, Widget)>[
      (
        'Status',
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.status.label, style: TS.ui(AppColors.fg1)),
            TaskNoteLines(note: _note(t)),
          ],
        )
      ),
      ('Agents', _agentNames(display)),
      ('Reviewer', _agentNames(reviewers)),
      (
        'Branch',
        branch.trim().isNotEmpty
            ? Text(branch, style: TS.code())
            : Text('—', style: TS.ui(AppColors.fg4))
      ),
      (
        'Changes',
        changesText.isEmpty
            ? Text('—', style: TS.ui(AppColors.fg4))
            : Text(changesText, style: TS.ui(AppColors.fg1))
      ),
      (
        'Owned paths',
        paths.isEmpty
            ? Text('—', style: TS.ui(AppColors.fg4))
            : Text(
                paths.join(', '),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: TS.ui(AppColors.fg1),
              )
      ),
    ];
    return [
      for (var i = 0; i < rows.length; i++)
        _keyRow(rows[i].$1, rows[i].$2, last: i == rows.length - 1),
    ];
  }

  Widget _keyCard(List<Widget> rows) => Container(
        decoration: _sheetCardDecoration,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        child: Column(children: rows),
      );

  Widget _reportCard(BoardEntry e) => Container(
        decoration: _sheetCardDecoration,
        padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 10, bottom: 4),
              child: Text('Report', style: TS.label(AppColors.fg1)),
            ),
            BoardLog(entries: [e], showAgent: true),
          ],
        ),
      );

  Widget _briefCard(TaskItem t) {
    final brief = t.description.trim().isNotEmpty ? t.description : t.plan;
    return Container(
      decoration: _sheetCardDecoration,
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 10, bottom: 4),
            child: Text('Brief', style: TS.label(AppColors.fg1)),
          ),
          if (brief.trim().isEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: Text('No brief yet.', style: TS.ui(AppColors.fg4)),
            )
          else
            _Description(markdown: brief),
        ],
      ),
    );
  }

  Widget _planTab(TaskItem t) {
    if (t.workPlan.isEmpty && turns.isEmpty) {
      return const EmptyState(
        icon: 'task',
        title: 'No plan yet',
        body: 'The agent’s plan and its turns show up here.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (t.workPlan.isNotEmpty) ...[
          _WorkPlan(steps: t.workPlan),
          if (turns.isNotEmpty) const SizedBox(height: 14),
        ],
        _turnsSection(),
      ],
    );
  }

  Widget _logTab() => log.isEmpty
      ? const EmptyState(
          icon: 'history',
          title: 'No log entries yet',
          body: 'What agents report and note lands here.',
        )
      : _logSection();

  Widget _changesTab() {
    final files = _changedFiles();
    final commits = [for (final turn in turns) ...turn.commits];
    if (files.isEmpty && commits.isEmpty) {
      return const EmptyState(
        icon: 'file-diff',
        title: 'No changes yet',
        body: 'Files and commits appear here as agents finish their turns.',
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          '${files.length} ${files.length == 1 ? 'file' : 'files'}'
          '${commits.isEmpty ? '' : ' · ${commits.length} ${commits.length == 1 ? 'commit' : 'commits'}'}',
          style: TS.meta(),
        ),
        const SizedBox(height: 8),
        for (final f in files)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                AppIcon('file', size: 13, color: AppColors.fg4),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    f,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: codeMono(12, color: AppColors.fg2),
                  ),
                ),
              ],
            ),
          ),
        for (final c in commits)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(
              children: [
                AppIcon('git-branch', size: 13, color: AppColors.fg4),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    c,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: codeMono(12, color: AppColors.fg3),
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _fseg(TaskItem t) => Glass(
        radius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.all(3),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < 4; i++) _fsegButton(i, t),
            ],
          ),
        ),
      );

  Widget _fsegButton(int i, TaskItem t) {
    final on = _tab == i;
    final color = on ? AppColors.fg1 : AppColors.fg3;
    final (icon, label) = switch (i) {
      0 => ('layers', 'Summary'),
      1 => ('task', 'Plan'),
      2 => ('history', 'Log'),
      _ => ('file-diff', 'Changes'),
    };
    final count = switch (i) {
      1 => t.workPlan.isEmpty ? turns.length : t.workPlan.length,
      2 => log.length,
      3 => _changedFiles().length,
      _ => null,
    };
    return Semantics(
      button: true,
      selected: on,
      label: label,
      child: InkWell(
        excludeFromSemantics: true,
        onTap: () => setState(() => _tab = i),
        borderRadius: BorderRadius.circular(9),
        child: Container(
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: on
                ? (kMobile ? AppColors.surface3 : AppColors.tint2)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(9),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon(icon, size: 13, color: color),
              const SizedBox(width: 6),
              Text(label, style: TS.label(color)),
              if (count != null) ...[
                const SizedBox(width: 6),
                Text('$count', style: TS.codeSmall(AppColors.fg4)),
              ],
            ],
          ),
        ),
      ),
    );
  }

  Widget _section(String label, {required VoidCallback onAdd}) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(children: [
          Text(label.toUpperCase(),
              style: kMobile
                  ? sans(12, weight: W.label, spacing: 0.7, color: AppColors.fg4)
                  : caps(11, color: AppColors.fg3)),
          const Spacer(),
          GestureDetector(
            onTap: onAdd,
            behavior: HitTestBehavior.opaque,
            child: Padding(
              padding: kMobile
                  ? const EdgeInsets.fromLTRB(12, 8, 0, 8)
                  : const EdgeInsets.all(2),
              child: AppIcon('plus',
                  size: kMobile ? 16 : 14, color: AppColors.fg3),
            ),
          ),
        ]),
      );

  Widget _linkRow(String prefix, String id, Color color) => Padding(
        padding: const EdgeInsets.only(bottom: 4),
        child: Row(children: [
          Text('$prefix  ', style: sans(11, color: color)),
          Expanded(
            child: Text(id,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mono(11, color: AppColors.fg3)),
          ),
        ]),
      );

  List<Widget> _roomSlivers() {
    final room = this.room;
    if (room == null) return const [];
    if (room.events.isEmpty) {
      return const [
        SliverToBoxAdapter(
          child: Padding(
            padding: EdgeInsets.only(top: S.s16),
            child: EmptyState(
              icon: 'message-text',
              title: 'No messages yet',
              body: 'Agents on this task talk here. You can add a note too.',
            ),
          ),
        ),
      ];
    }
    return [
      SliverPadding(
        padding: kMobile
            ? const EdgeInsets.fromLTRB(20, 18, 20, 12)
            : const EdgeInsets.all(S.s12),
        sliver: SliverList.builder(
          itemCount: room.events.length,
          itemBuilder: (_, i) {
            final e = room.events[i];
            final mine = e.actorKind == 'human';
            final body = e.payload['body']?.toString() ?? '';
            if (body.trim().isEmpty) return const SizedBox.shrink();
            if (kMobile) {
              final md = MarkdownBody(
                data: body,
                selectable: true,
                styleSheet: mine ? markdownStyle(context) : agentMarkdownStyle(context),
                builders: {'pre': PreBlockBuilder()},
                onTapLink: (txt, href, title) => openMarkdownLink(href, context),
              );
              if (mine) {
                return Padding(
                  padding: const EdgeInsets.only(left: 48, bottom: 14),
                  child: Align(
                    alignment: Alignment.centerRight,
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(15, 10, 15, 11),
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        borderRadius: kMobile
                            ? const BorderRadius.only(
                                topLeft: Radius.circular(20),
                                topRight: Radius.circular(20),
                                bottomLeft: Radius.circular(20),
                                bottomRight: Radius.circular(6),
                              )
                            : BorderRadius.circular(20),
                      ),
                      child: _addressed(e, md),
                    ),
                  ),
                );
              }
              return Padding(
                padding: const EdgeInsets.only(bottom: 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      AgentMochi(_speakerId(e), size: 18),
                      const SizedBox(width: 8),
                      _speaker(e, 13),
                    ]),
                    const SizedBox(height: 6),
                    md,
                  ],
                ),
              );
            }
            if (mine) {
              return Align(
                alignment: Alignment.centerRight,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Container(
                    margin: const EdgeInsets.only(bottom: 10),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: AppColors.tint2,
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: AppColors.line),
                    ),
                    child: _addressed(
                      e,
                      MarkdownBody(
                        data: body,
                        selectable: true,
                        styleSheet: markdownStyle(context),
                        builders: {'pre': PreBlockBuilder()},
                        onTapLink: (txt, href, title) =>
                            openMarkdownLink(href, context),
                      ),
                    ),
                  ),
                ),
              );
            }
            return Padding(
              padding: const EdgeInsets.only(bottom: 14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    AgentMochi(_speakerId(e), size: 16),
                    const SizedBox(width: 6),
                    _speaker(e, 12),
                  ]),
                  const SizedBox(height: 5),
                  MarkdownBody(
                    data: body,
                    selectable: true,
                    styleSheet: markdownStyle(context),
                    builders: {'pre': PreBlockBuilder()},
                    onTapLink: (txt, href, title) =>
                        openMarkdownLink(href, context),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    ];
  }

  Widget _composerBar() => kMobile
      ? SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 4, 12, 10),
            child: Container(
              padding: const EdgeInsets.fromLTRB(18, 4, 6, 4),
              decoration: BoxDecoration(
                color: AppColors.surface1,
                borderRadius: BorderRadius.circular(26),
                boxShadow: [
                  BoxShadow(
                      color: AppColors.fg1.withValues(alpha: 0.08),
                      spreadRadius: 1),
                ],
              ),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _composer,
                    minLines: 1,
                    maxLines: 4,
                    onSubmitted: (_) => _send(),
                    style: sans(16, color: AppColors.fg1),
                    cursorColor: AppColors.accent,
                    decoration: InputDecoration(
                      border: InputBorder.none,
                      hintText: 'Add a note…',
                      hintStyle: sans(16, color: AppColors.fg4),
                    ),
                  ),
                ),
                GestureDetector(
                  onTap: (room?.sending ?? false) ? null : _send,
                  child: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                        color: AppColors.accentFill, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: AppIcon('arrow-up',
                        size: 16, color: AppColors.accentFg),
                  ),
                ),
              ]),
            ),
          ),
        )
      : SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(10, 6, 10, 10),
            child: Container(
              constraints: const BoxConstraints(minHeight: 36),
              padding: const EdgeInsets.fromLTRB(12, 4, 6, 4),
              decoration: BoxDecoration(
                color: AppColors.tint1,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.line),
              ),
              child: Row(children: [
                Expanded(
                  child: TextField(
                    controller: _composer,
                    minLines: 1,
                    maxLines: 4,
                    onSubmitted: (_) => _send(),
                    style: sans(13, color: AppColors.fg1),
                    cursorColor: AppColors.accent,
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: 'Add a note…',
                      hintStyle: sans(13, color: AppColors.fg4),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                GestureDetector(
                  onTap: (room?.sending ?? false) ? null : _send,
                  child: Container(
                    width: 26,
                    height: 26,
                    decoration: BoxDecoration(
                        color: AppColors.accentFill, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: AppIcon('arrow-up',
                        size: 13, color: AppColors.accentFg),
                  ),
                ),
              ]),
            ),
          ),
        );
}

/// The worker's plan for the task, as it ticks steps off.
class _WorkPlan extends StatelessWidget {
  const _WorkPlan({required this.steps});
  final List<WorkStep> steps;

  @override
  Widget build(BuildContext context) {
    final done = steps.where((s) => s.done).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('Plan · $done/${steps.length}',
            style: sans(13, weight: FontWeight.w500, color: AppColors.fg3)),
        const SizedBox(height: 8),
        for (final s in steps)
          Padding(
            padding: const EdgeInsets.only(bottom: 6),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: s.done
                    ? AppIcon('check', size: 14, color: AppColors.ok)
                    : Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: s.current ? AppColors.accent : null,
                          border: Border.all(
                              color: s.current ? AppColors.accent : AppColors.fg4,
                              width: 1.5),
                        ),
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Text(s.step,
                    style: sans(14,
                        height: 19 / 14,
                        color: s.done
                            ? AppColors.fg4
                            : s.current
                                ? AppColors.fg1
                                : AppColors.fg2)),
              ),
            ]),
          ),
      ],
    );
  }
}

class _Description extends StatefulWidget {
  const _Description({required this.markdown});

  final String markdown;

  @override
  State<_Description> createState() => _DescriptionState();
}

class _DescriptionState extends State<_Description> {
  static const _foldHeight = 260.0;
  bool _expanded = false;

  bool get _long =>
      widget.markdown.length > 700 ||
      '\n'.allMatches(widget.markdown).length > 14;

  @override
  Widget build(BuildContext context) {
    final body = MarkdownBody(
      data: widget.markdown,
      selectable: true,
      styleSheet: markdownStyle(context),
      builders: {'pre': PreBlockBuilder()},
      onTapLink: (txt, href, title) => openMarkdownLink(href, context),
    );
    if (!_long) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSize(
          duration: Motion.base,
          curve: Motion.enter,
          alignment: Alignment.topCenter,
          child: _expanded
              ? body
              : SizedBox(
                  height: _foldHeight,
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (r) => const LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      stops: [0.7, 1],
                      colors: [Colors.white, Colors.transparent],
                    ).createShader(r),
                    child: ClipRect(
                      child: OverflowBox(
                        alignment: Alignment.topLeft,
                        minHeight: 0,
                        maxHeight: double.infinity,
                        child: body,
                      ),
                    ),
                  ),
                ),
        ),
        TextAction(_expanded ? 'Show less' : 'Show more',
            icon: _expanded ? 'chevron-up' : 'chevron-down',
            onTap: () => setState(() => _expanded = !_expanded)),
      ],
    );
  }
}
