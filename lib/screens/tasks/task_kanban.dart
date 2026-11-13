import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../api.dart';
import '../../mochi.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../list_search_field.dart';
import 'task_common.dart';
import 'task_list.dart' show TaskLoadMore;

/// Desktop task board: four status columns with filter chips and drag/drop.
///
/// Working takes no drops because only a dispatch binds the session allowed to
/// report progress. Moves show at once and revert if the daemon refuses them.
class TaskKanban extends StatefulWidget {
  const TaskKanban({super.key, required this.client});

  final DaemonClient client;

  @override
  State<TaskKanban> createState() => _TaskKanbanState();
}

enum _KanbanColumn {
  needsYou(
    'Needs you',
    [TaskStatus.inReview, TaskStatus.blocked, TaskStatus.failed],
    TaskStatus.inReview,
  ),
  working('Working', [TaskStatus.inProgress], null),
  queued('Queued', [TaskStatus.todo], TaskStatus.todo),
  done('Done', [TaskStatus.done, TaskStatus.cancelled], TaskStatus.done);

  const _KanbanColumn(this.label, this.statuses, this.dropStatus);

  final String label;
  final List<TaskStatus> statuses;
  final TaskStatus? dropStatus;

  Color get dotColor => switch (this) {
        _KanbanColumn.needsYou => AppColors.run,
        _KanbanColumn.working => AppColors.fg2,
        _KanbanColumn.queued => AppColors.fg4,
        _KanbanColumn.done => AppColors.ok,
      };
}

class _TaskKanbanState extends State<TaskKanban> {
  late TaskFeed _feed = TaskFeed(widget.client, onChange: _sync);
  final _search = TextEditingController();
  final _scroll = ScrollController();

  String _query = '';
  Map<String, String> _sessionFolders = const {};
  Map<String, String> _agentNames = const {};
  TaskItem? _dragging;
  double _columnWidth = 200;

  @override
  void initState() {
    super.initState();
    _loadContext();
  }

  @override
  void didUpdateWidget(covariant TaskKanban oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) {
      _feed.dispose();
      _feed = TaskFeed(widget.client, onChange: _sync);
      _sessionFolders = const {};
      _agentNames = const {};
      _loadContext();
    }
  }

  void _loadContext() {
    unawaited(_loadFolders());
    unawaited(_loadAgents());
  }

  Future<void> _loadFolders() async {
    try {
      final sessions = await widget.client.sessions();
      if (!mounted) return;
      final map = <String, String>{};
      for (final s in sessions) {
        final name = _folderName(s.projectFolder);
        if (name.isNotEmpty) map[s.id] = name;
      }
      setState(() => _sessionFolders = map);
    } catch (_) {}
  }

  Future<void> _loadAgents() async {
    try {
      final agents = await widget.client.coordinationAgents();
      if (!mounted) return;
      final map = <String, String>{};
      for (final a in agents) {
        final name = a.displayName.trim();
        if (name.isNotEmpty) map[a.id] = name;
      }
      setState(() => _agentNames = map);
    } catch (_) {}
  }

  static final _hashSeg = RegExp(r'^[0-9a-f]{8,}$');

  static String _folderName(String path) {
    // Worktree checkouts end in a hash segment; name them by the parent.
    final parts = path
        .split('/')
        .where((p) => p.isNotEmpty && !_hashSeg.hasMatch(p))
        .toList();
    return parts.isEmpty ? '' : parts.last;
  }

  void _sync() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _feed.dispose();
    _search.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (await showCreateTask(context, widget.client)) await _feed.refresh();
  }

  Future<void> _open(TaskItem task) async {
    await openTaskDetail(context, widget.client, task.id);
    if (mounted) await _feed.refresh();
  }

  static bool _finished(TaskStatus s) =>
      s == TaskStatus.done || s == TaskStatus.failed || s == TaskStatus.cancelled;

  static bool _accepts(_KanbanColumn column, TaskItem task) {
    final target = column.dropStatus;
    if (target == null) return false;
    if (column.statuses.contains(task.status)) return false;
    return !_finished(task.status) || target == TaskStatus.todo;
  }

  Future<void> _move(TaskItem task, TaskStatus to) async {
    HapticFeedback.selectionClick();
    _feed.replace(task.movedTo(to));
    try {
      _feed.replace(await widget.client.setTaskStatus(task.id, to));
    } catch (e) {
      if (!mounted) return;
      toast(context, 'Could not move “${task.title}”: $e', danger: true);
      await _feed.refresh();
    }
  }

  List<TaskItem> _filteredTasks() {
    return _feed.tasks.where((t) => taskMatches(t, _query)).toList();
  }

  List<TaskItem> _itemsFor(_KanbanColumn column, List<TaskItem> visible) {
    if (column == _KanbanColumn.done) {
      return [
        for (final t in visible)
          if (t.status == TaskStatus.done) t,
        for (final t in visible)
          if (t.status == TaskStatus.cancelled) t,
      ];
    }
    return [
      for (final t in visible)
        if (column.statuses.contains(t.status)) t,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final showBoard = !_feed.loading && _feed.error == null;
    return ColoredBox(
      color: readingBg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _header(showCounts: showBoard),
          Expanded(child: _board()),
        ],
      ),
    );
  }

  Widget _header({required bool showCounts}) {
    final active = _feed.tasks
        .where((t) =>
            t.status == TaskStatus.todo || t.status == TaskStatus.inProgress)
        .length;
    final needsYou = _feed.tasks
        .where((t) =>
            t.status == TaskStatus.inReview ||
            t.status == TaskStatus.blocked ||
            t.status == TaskStatus.failed)
        .length;
    final sub = needsYou > 0
        ? '$active active · $needsYou needs you'
        : '$active active';
    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 14),
      child: Row(children: [
        Text('Tasks',
            style: sans(16, weight: W.label, color: AppColors.fg1)),
        const SizedBox(width: 10),
        if (showCounts)
          Text(sub, style: sans(12, color: AppColors.fg4, tabular: true)),
        const Spacer(),
        SizedBox(
          width: 220,
          child: ListSearchField(
            controller: _search,
            hint: 'Search tasks',
            onChanged: (v) => setState(() => _query = v),
          ),
        ),
        const SizedBox(width: 10),
        Btn('New task',
            small: true, variant: BtnVariant.secondary, onTap: _create),
      ]),
    );
  }

  Widget _board() {
    if (_feed.loading) {
      return Center(child: Spinner(size: 20, color: AppColors.fg3));
    }
    if (_feed.error != null) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Could not load tasks', style: sans(13, color: AppColors.fg2)),
          const SizedBox(height: 10),
          Btn('Retry', small: true, onTap: _feed.refresh),
        ]),
      );
    }
    final visible = _filteredTasks();
    return LayoutBuilder(builder: (context, constraints) {
      const hPad = 24.0;
      const gap = 12.0;
      final available = constraints.maxWidth - hPad * 2 - gap * 3;
      final colWidth = math.max(200.0, available / 4);
      _columnWidth = colWidth;
      final needsScroll =
          colWidth * 4 + gap * 3 + hPad * 2 > constraints.maxWidth + 0.5;
      final row = Padding(
        padding: const EdgeInsets.fromLTRB(hPad, 0, hPad, 20),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (var i = 0; i < _KanbanColumn.values.length; i++) ...[
              if (i > 0) const SizedBox(width: gap),
              _column(_KanbanColumn.values[i],
                  _itemsFor(_KanbanColumn.values[i], visible)),
            ],
          ],
        ),
      );
      if (!needsScroll) return row;
      return Scrollbar(
        controller: _scroll,
        child: SingleChildScrollView(
          controller: _scroll,
          scrollDirection: Axis.horizontal,
          child: row,
        ),
      );
    });
  }

  Widget _column(_KanbanColumn column, List<TaskItem> items) {
    final hasMore = column.statuses.any(_feed.hasMore);
    return DragTarget<TaskItem>(
      onWillAcceptWithDetails: (d) => _accepts(column, d.data),
      onAcceptWithDetails: (d) {
        final target = column.dropStatus;
        if (target != null) _move(d.data, target);
      },
      builder: (context, candidates, _) {
        final dragging = _dragging;
        final hovering = candidates.isNotEmpty;
        final refuses = dragging != null &&
            !column.statuses.contains(dragging.status) &&
            !_accepts(column, dragging);
        return AnimatedContainer(
          duration: Motion.fast,
          width: _columnWidth,
          decoration: BoxDecoration(
            color: hovering
                ? AppColors.surface2.withValues(alpha: 0.45)
                : Colors.transparent,
            borderRadius: BorderRadius.circular(R.lg),
          ),
          child: Opacity(
            opacity: refuses ? 0.5 : 1,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _columnHeader(column, items.length),
                Expanded(
                  child: items.isEmpty
                      ? _emptyColumn(column, refuses)
                      : ListView.builder(
                          padding: EdgeInsets.zero,
                          itemCount: items.length + (hasMore ? 1 : 0),
                          itemBuilder: (_, i) => i < items.length
                              ? _draggableCard(column, items[i])
                              : TaskLoadMore(
                                  onTap: () => Future.wait([
                                    for (final s in column.statuses)
                                      if (_feed.hasMore(s)) _feed.loadMore(s),
                                  ]),
                                ),
                        ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _columnHeader(_KanbanColumn column, int count) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 0, 4, 8),
        child: Row(children: [
          Container(
            width: 7,
            height: 7,
            decoration:
                BoxDecoration(color: column.dotColor, shape: BoxShape.circle),
          ),
          const SizedBox(width: 6),
          Text(column.label,
              style: sans(12, weight: W.label, color: AppColors.fg3)),
          const SizedBox(width: 6),
          Text('$count', style: mono(11, color: AppColors.fg4)),
        ]),
      );

  Widget _emptyColumn(_KanbanColumn column, bool refuses) => Align(
        alignment: Alignment.topCenter,
        child: Container(
          height: 64,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(color: AppColors.line),
          ),
          child: Text(
              column == _KanbanColumn.working
                  ? (refuses ? 'Only a dispatch starts work' : 'Nothing running')
                  : 'No tasks',
              style: TS.meta(AppColors.fg4)),
        ),
      );

  String _stepLine(TaskItem task) {
    final note = noteForTask(task, _feed.tasks).line?.trim();
    if (note != null && note.isNotEmpty) return note;
    final step = task.currentStep?.trim();
    if (step != null && step.isNotEmpty) return step;
    final desc = task.description.trim();
    if (desc.isEmpty) return '';
    return desc.split('\n').first.trim();
  }

  Widget _draggableCard(_KanbanColumn column, TaskItem task) {
    final step = _stepLine(task);
    final folder = _sessionFolders[task.sessionId];
    final agentName =
        task.createdByKind == 'agent' ? _agentNames[task.createdById] : null;
    final needsYou = column == _KanbanColumn.needsYou;
    final card = _TaskCard(
      task: task,
      step: step,
      folder: folder,
      agentName: agentName,
      needsYou: needsYou,
      onTap: () => _open(task),
      onApprove: task.status == TaskStatus.inReview
          ? () => _move(task, TaskStatus.done)
          : null,
      onSendBack: task.status == TaskStatus.inReview
          ? () => _move(task, TaskStatus.inProgress)
          : null,
    );
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Draggable<TaskItem>(
        data: task,
        onDragStarted: () => setState(() => _dragging = task),
        onDragEnd: (_) => setState(() => _dragging = null),
        feedback: Material(
          color: Colors.transparent,
          child: SizedBox(
            width: _columnWidth,
            child: Transform.rotate(
              angle: -0.02,
              child: _TaskCard(
                task: task,
                step: step,
                folder: folder,
                agentName: agentName,
                needsYou: needsYou,
                lifted: true,
              ),
            ),
          ),
        ),
        childWhenDragging: Opacity(opacity: 0.3, child: card),
        child: card,
      ),
    );
  }
}

class _TaskCard extends StatefulWidget {
  const _TaskCard({
    required this.task,
    required this.step,
    required this.needsYou,
    this.folder,
    this.agentName,
    this.onTap,
    this.onApprove,
    this.onSendBack,
    this.lifted = false,
  });

  final TaskItem task;
  final String step;
  final bool needsYou;
  final String? folder;
  final String? agentName;
  final VoidCallback? onTap;
  final VoidCallback? onApprove;
  final VoidCallback? onSendBack;
  final bool lifted;

  @override
  State<_TaskCard> createState() => _TaskCardState();
}

class _TaskCardState extends State<_TaskCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final t = widget.task;
    final isAgent = t.createdByKind == 'agent' && t.createdById.isNotEmpty;
    final agentLabel = isAgent ? (widget.agentName ?? t.createdById) : '';
    final metaText = [agentLabel, widget.folder ?? '']
        .where((s) => s.trim().isNotEmpty)
        .join(' · ');
    final age = taskAge(t);
    final showReviewActions =
        widget.needsYou && t.status == TaskStatus.inReview;

    return MouseRegion(
      cursor: SystemMouseCursors.grab,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
          decoration: BoxDecoration(
            color: _hover || widget.lifted
                ? AppColors.surface2
                : AppColors.surface1,
            borderRadius: BorderRadius.circular(R.md),
            border: Border.all(
              color: _hover || widget.lifted
                  ? AppColors.border2
                  : AppColors.border,
            ),
            boxShadow: widget.lifted
                ? const [
                    BoxShadow(
                        color: Color(0x66000000),
                        blurRadius: 18,
                        offset: Offset(0, 8)),
                  ]
                : null,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                t.title,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: sans(13,
                    weight: W.label, height: 1.35, color: AppColors.fg1),
              ),
              if (widget.step.isNotEmpty) ...[
                const SizedBox(height: 6),
                Text(
                  widget.step,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12, color: AppColors.fg3),
                ),
              ],
              if (isAgent || metaText.isNotEmpty || age.isNotEmpty) ...[
                const SizedBox(height: 6),
                Row(children: [
                  if (isAgent) ...[
                    AgentMochi(t.createdById, size: 14),
                    const SizedBox(width: 6),
                  ],
                  if (metaText.isNotEmpty)
                    Expanded(
                      child: Text(
                        metaText,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(12, color: AppColors.fg4),
                      ),
                    )
                  else
                    const Spacer(),
                  if (age.isNotEmpty) ...[
                    const SizedBox(width: 8),
                    Text(
                      age,
                      style: sans(12,
                          color: widget.needsYou
                              ? AppColors.run
                              : AppColors.fg4,
                          tabular: true),
                    ),
                  ],
                ]),
              ],
              if (showReviewActions) ...[
                const SizedBox(height: 10),
                Row(children: [
                  Btn(
                    'Approve',
                    small: true,
                    variant: BtnVariant.secondary,
                    onTap: widget.onApprove,
                  ),
                  const SizedBox(width: 8),
                  Btn(
                    'Send back',
                    small: true,
                    variant: BtnVariant.ghost,
                    onTap: widget.onSendBack,
                  ),
                ]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
