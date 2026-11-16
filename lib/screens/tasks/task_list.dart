import '../../task_reason.dart';
import 'package:flutter/material.dart';

import '../../models.dart';
import '../../platform.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../shell_nav.dart' show kNavPadH;
import 'task_common.dart';
import '../../pull_refresh.dart';
import '../../motion.dart';
import '../../mochi.dart';

/// Tasks grouped by status, in board order, narrowed by a search and a status
/// filter. The phone tab, the desktop sidebar and the standalone screen all
/// render this, so the three cannot disagree about order or grouping.
class TaskList extends StatelessWidget {
  const TaskList({
    super.key,
    required this.tasks,
    required this.onOpen,
    required this.onRefresh,
    this.query = '',
    this.filter = const {},
    this.padding,
    this.appearSince,
    this.selectedId,
    this.hasMore,
    this.onLoadMore,
    this.sessionFolders,
    this.agentNames,
  });

  final bool Function(TaskStatus status)? hasMore;
  final Future<void> Function(TaskStatus status)? onLoadMore;

  final List<TaskItem> tasks;
  final ValueChanged<TaskItem> onOpen;
  final Future<void> Function() onRefresh;
  final String query;

  /// Statuses to show; empty means all of them.
  final Set<TaskStatus> filter;
  final EdgeInsets? padding;

  /// When the list first showed these tasks; rows mounted long after it show
  /// at rest instead of animating in.
  final DateTime? appearSince;
  final String? selectedId;

  /// session id → folder name, for the phone card's "agent · folder" line.
  final Map<String, String>? sessionFolders;

  /// agent id → display name, for the row's meta line.
  final Map<String, String>? agentNames;

  List<TaskItem> get _visible => tasks
      .where((t) => filter.isEmpty || filter.contains(t.status))
      .where((t) => taskMatches(t, query))
      .toList();

  /// One grouped surface in board order (no per-status headers: the meta line
  /// carries the status), with each status's "Load more" under it.
  List<Widget> rows() {
    final visible = _visible;
    if (visible.isEmpty) return const [];
    final ordered = [
      for (final status in TaskStatus.values)
        ...visible.where((t) => t.status == status),
    ];
    return [
      Appear(
        key: const ValueKey('task-card'),
        since: appearSince,
        child: Container(
          decoration: BoxDecoration(
            color: kMobile ? AppColors.surface2 : AppColors.tint1,
            borderRadius: BorderRadius.circular(R.of(14)),
            border: Border.all(color: AppColors.line),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(children: [
            for (var i = 0; i < ordered.length; i++)
              TaskRow(
                  key: ValueKey('t-${ordered[i].id}'),
                  task: ordered[i],
                  note: noteForTask(ordered[i], tasks),
                  folder: sessionFolders?[ordered[i].sessionId],
                  agentName: agentNames?[ordered[i].createdById],
                  selected: ordered[i].id == selectedId,
                  onTap: () => onOpen(ordered[i]),
                  divider: i < ordered.length - 1),
          ]),
        ),
      ),
      for (final status in TaskStatus.values)
        if (visible.any((t) => t.status == status) &&
            (hasMore?.call(status) ?? false))
          _loadMore(status),
    ];
  }

  Widget emptyState() => _empty();

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final pad = padding ??
        (kMobile
            ? EdgeInsets.fromLTRB(M.gutter, S.s4, M.gutter, S.s24)
            : EdgeInsets.fromLTRB(S.s8, 0, S.s8, S.of(18)));
    if (visible.isEmpty) {
      return PullToRefresh(
        onRefresh: onRefresh,
        child: ListView(padding: pad, children: [_empty()]),
      );
    }
    return PullToRefresh(
      onRefresh: onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: pad,
        children: rows(),
      ),
    );
  }

  Widget _loadMore(TaskStatus status) => TaskLoadMore(
      key: ValueKey('more-${status.name}'),
      onTap: () => onLoadMore?.call(status) ?? Future.value());

  // Three different empties: nothing filed, nothing matching the search, and
  // nothing in the chosen columns.
  Widget _empty() {
    if (tasks.isEmpty) {
      return const EmptyState(
        icon: 'layers',
        title: 'No tasks yet',
        body: 'File a task and Mission Control routes it to a session.',
      );
    }
    if (query.trim().isNotEmpty) {
      return EmptyState(
        icon: 'search',
        title: 'No matching tasks',
        body: 'Nothing matches “${query.trim()}”.',
      );
    }
    return EmptyState(
      icon: 'layers',
      title: filter.length == 1
          ? 'Nothing in ${filter.first.label}'
          : 'Nothing in ${filter.length} columns',
      body: 'Try another column, or clear the filter.',
    );
  }
}

/// One task. Desktop gets a single dense line; a phone adds the first line of
/// the description, so a row says what the work is without opening it.
/// "Plan 3/5 · now: `step`" for an open task whose worker has laid out a plan.
String? workPlanLine(TaskItem task) {
  if (task.workPlan.isEmpty ||
      const {TaskStatus.done, TaskStatus.failed, TaskStatus.cancelled}
          .contains(task.status)) {
    return null;
  }
  final done = task.workPlan.where((s) => s.done).length;
  final now = task.workPlan.where((s) => s.current).map((s) => s.step).firstOrNull;
  return 'Plan $done/${task.workPlan.length}${now == null ? '' : ' · now: $now'}';
}

class TaskRow extends StatelessWidget {
  const TaskRow(
      {super.key,
      required this.task,
      required this.onTap,
      this.note,
      this.selected = false,
      this.divider = false,
      this.folder,
      this.agentName});
  final TaskItem task;
  final TaskNote? note;
  final bool selected;
  final VoidCallback onTap;

  /// A hairline under the row, between rows of one status on a phone.
  final bool divider;

  /// Project folder name for the phone card's meta line.
  final String? folder;

  /// Display name of the creating agent; the id when unknown.
  final String? agentName;

  @override
  Widget build(BuildContext context) {
    final line = note?.line ?? '';
    final finished =
        const {TaskStatus.done, TaskStatus.cancelled}.contains(task.status);
    final needsYou = const {
      TaskStatus.inReview,
      TaskStatus.blocked,
      TaskStatus.failed,
    }.contains(task.status);
    final agent = task.createdByKind == 'agent' ? task.createdById : '';
    final age = taskAge(task);
    final num = RegExp(r'^t-?(\d+)$', caseSensitive: false).firstMatch(task.id);
    final id = num != null
        ? 'T-${num.group(1)}'
        : (task.id.length > 8 ? task.id.substring(0, 8) : task.id)
            .toUpperCase();
    final who = (agentName ?? '').trim().isEmpty ? agent : agentName!.trim();
    final meta =
        [id, who, task.status.label].where((p) => p.isNotEmpty).join(' · ');
    final avatar = kMobile ? 24.0 : 22.0;
    return Material(
      color: selected ? AppColors.accentBg : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: kMobile ? 52 : 40),
          padding: EdgeInsets.symmetric(
              horizontal: S.s12, vertical: kMobile ? S.s8 : S.s6),
          decoration: BoxDecoration(
            border: divider
                ? Border(bottom: BorderSide(color: AppColors.line))
                : null,
          ),
          child: Row(children: [
            SizedBox(
              width: avatar,
              height: avatar,
              child: agent.isNotEmpty
                  ? AgentMochi(agent, size: avatar)
                  : Center(
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: BoxDecoration(
                            color: statusColor(task.status),
                            shape: BoxShape.circle),
                      ),
                    ),
            ),
            SizedBox(width: S.of(10)),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(children: [
                    if (task.priority > 0) ...[
                      PriorityMark(task.priority),
                      SizedBox(width: S.s6),
                    ],
                    Expanded(
                      child: Text(task.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(kMobile ? 15 : 13,
                              weight: W.label,
                              height: 1.3,
                              color:
                                  finished ? AppColors.fg3 : AppColors.fg1)),
                    ),
                  ]),
                  Text(meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono(11, color: AppColors.fg3)),
                  if (line.isNotEmpty)
                    Text(line,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(12, color: AppColors.fg4)),
                  if (!kMobile && task.planTotal > 0) ...[
                    SizedBox(height: S.s4),
                    TaskPlanProgress(
                        done: task.planDone,
                        total: task.planTotal,
                        compact: true),
                  ],
                ],
              ),
            ),
            if (!kMobile && age.isNotEmpty) ...[
              SizedBox(width: S.s8),
              Text(age,
                  style: mono(11,
                      color: needsYou ? AppColors.run : AppColors.fg4)),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Priority as a mark: nothing at the default, a small chip when raised.
class PriorityMark extends StatelessWidget {
  const PriorityMark(this.priority, {super.key});
  final int priority;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: S.of(5), vertical: S.of(1)),
        decoration: BoxDecoration(
            color: AppColors.accentBg,
            borderRadius: BorderRadius.circular(R.xs)),
        child: Text('P$priority',
            style: sans(11, weight: W.label, color: AppColors.accent)),
      );
}

/// The row under a status group that loads its next page of older tasks.
class TaskLoadMore extends StatefulWidget {
  const TaskLoadMore({super.key, required this.onTap});
  final Future<void> Function() onTap;

  @override
  State<TaskLoadMore> createState() => _TaskLoadMoreState();
}

class _TaskLoadMoreState extends State<TaskLoadMore> {
  bool _busy = false;

  Future<void> _run() async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await widget.onTap();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.symmetric(
            horizontal: kMobile ? M.gutter : kNavPadH, vertical: S.s4),
        child: Align(
          alignment: Alignment.centerLeft,
          child: _busy
              ? const SizedBox(
                  height: 32, child: Center(child: Spinner(size: 14)))
              : TextButton(
                  onPressed: _run,
                  child: Text('Load more',
                      style: TS.ui(AppColors.accent)),
                ),
        ),
      );
}
