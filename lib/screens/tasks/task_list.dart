import '../../task_reason.dart';
import 'package:flutter/material.dart';

import '../../models.dart';
import '../../platform.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../shell_nav.dart' show kNavPadH, kNavRowHeight;
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

  List<TaskItem> get _visible => tasks
      .where((t) => filter.isEmpty || filter.contains(t.status))
      .where((t) => taskMatches(t, query))
      .toList();

  List<Widget> rows() {
    final visible = _visible;
    final rows = [
      for (final status in TaskStatus.values)
        ..._group(status, visible.where((t) => t.status == status)),
    ];
    return [
      for (var i = 0; i < rows.length; i++)
        Appear(
          key: rows[i].key,
          index: i,
          since: appearSince,
          child: rows[i],
        ),
    ];
  }

  Widget emptyState() => _empty();

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final pad = padding ??
        (kMobile
            ? const EdgeInsets.fromLTRB(M.gutter, 4, M.gutter, 24)
            : const EdgeInsets.fromLTRB(8, 0, 8, 18));
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

  List<Widget> _group(TaskStatus status, Iterable<TaskItem> items) {
    if (items.isEmpty) return const [];
    if (kMobile) {
      final list = items.toList();
      return [
        TaskStatusHeader(
            key: ValueKey('h-${status.name}'),
            status: status,
            count: list.length),
        for (var i = 0; i < list.length; i++)
          TaskRow(
              key: ValueKey('t-${list[i].id}'),
              task: list[i],
              note: noteForTask(list[i], tasks),
              folder: sessionFolders?[list[i].sessionId],
              onTap: () => onOpen(list[i]),
              divider: i < list.length - 1),
        if (hasMore?.call(status) ?? false) _loadMore(status),
      ];
    }
    return [
      TaskStatusHeader(
          key: ValueKey('h-${status.name}'),
          status: status,
          count: items.length),
      for (final task in items)
        TaskRow(
            key: ValueKey('t-${task.id}'),
            task: task,
            note: noteForTask(task, tasks),
            selected: task.id == selectedId,
            onTap: () => onOpen(task)),
      if (hasMore?.call(status) ?? false) _loadMore(status),
    ];
  }

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

class TaskStatusHeader extends StatelessWidget {
  const TaskStatusHeader(
      {super.key, required this.status, required this.count});
  final TaskStatus status;
  final int count;

  @override
  Widget build(BuildContext context) => kMobile
      ? Padding(
          padding: const EdgeInsets.fromLTRB(0, 16, 0, 4),
          child: Text(status.label,
              style: sans(13, weight: W.label, color: AppColors.fg3)),
        )
      : Padding(
        padding: const EdgeInsets.fromLTRB(12, 14, 12, 6),
        child: Row(children: [
          Container(
            width: 6,
            height: 6,
            decoration: BoxDecoration(
                color: statusColor(status), shape: BoxShape.circle),
          ),
          const SizedBox(width: S.s8),
          Text(status.label,
              style: kMobile ? sans(13, color: AppColors.fg2) : TS.label()),
          const SizedBox(width: S.s8),
          if (kMobile)
            Text('$count', style: sans(13, color: AppColors.fg4))
          else
            CountBadge(count),
        ]),
      );
}

/// One task. Desktop gets a single dense line; a phone adds the first line of
/// the description, so a row says what the work is without opening it.
/// "Plan 3/5 · now: <step>" for an open task whose worker has laid out a plan.
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
      this.folder});
  final TaskItem task;
  final TaskNote? note;
  final bool selected;
  final VoidCallback onTap;

  /// A hairline under the row, between rows of one status on a phone.
  final bool divider;

  /// Project folder name for the phone card's meta line.
  final String? folder;

  @override
  Widget build(BuildContext context) {
    final detail = note?.line ??
        workPlanLine(task) ??
        task.description.trim().split('\n').first;
    final age = taskAge(task);
    if (kMobile) {
      // v5 `.pcard`: title, step line, then "agent · folder" with the age.
      final finished = const {TaskStatus.done, TaskStatus.cancelled}
          .contains(task.status);
      final needsYou = const {
        TaskStatus.inReview,
        TaskStatus.blocked,
        TaskStatus.failed,
      }.contains(task.status);
      final agent = task.createdByKind == 'agent' ? task.createdById : '';
      final folderName = (folder ?? '').trim();
      final meta = [agent, folderName].where((s) => s.isNotEmpty).join(' · ');
      return InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Container(
          margin: const EdgeInsets.only(bottom: 10),
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(14),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(task.title,
                  style: sans(15,
                      weight: W.label,
                      height: 1.3,
                      color: finished ? AppColors.fg3 : AppColors.fg1)),
              if (detail.isNotEmpty) ...[
                const SizedBox(height: 5),
                Text(detail,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: sans(14, height: 1.4, color: AppColors.fg3)),
              ],
              if (meta.isNotEmpty || age.isNotEmpty) ...[
                const SizedBox(height: 8),
                Row(children: [
                  if (task.priority > 0) ...[
                    PriorityMark(task.priority),
                    const SizedBox(width: 8),
                  ],
                  if (agent.isNotEmpty) ...[
                    AgentMochi(agent, size: 16),
                    const SizedBox(width: 6),
                  ],
                  Expanded(
                    child: Text(meta,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(13, color: AppColors.fg3)),
                  ),
                  if (age.isNotEmpty)
                    Text(age,
                        style: sans(13,
                            color: needsYou ? AppColors.run : AppColors.fg3,
                            tabular: true)),
                ]),
              ],
            ],
          ),
        ),
      );
    }
    if (!kMobile) {
      final done = task.status == TaskStatus.done ||
          task.status == TaskStatus.cancelled;
      return Material(
        color: selected ? AppColors.accentBg : Colors.transparent,
        borderRadius: BorderRadius.circular(7),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(7),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 7, 8, 7),
            child: Row(
              crossAxisAlignment: detail.isNotEmpty
                  ? CrossAxisAlignment.start
                  : CrossAxisAlignment.center,
              children: [
                Padding(
                  padding: EdgeInsets.only(top: detail.isNotEmpty ? 6 : 0),
                  child: Container(
                    width: 6,
                    height: 6,
                    decoration: BoxDecoration(
                      color: statusColor(task.status),
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                if (task.priority > 0) ...[
                  PriorityMark(task.priority),
                  const SizedBox(width: 6),
                ],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(task.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(13,
                              height: 18 / 13,
                              color: done ? AppColors.fg3 : AppColors.fg1)),
                      if (detail.isNotEmpty) ...[
                        const SizedBox(height: 1),
                        Text(detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(12,
                                height: 15 / 11.5, color: AppColors.fg4)),
                      ],
                    ],
                  ),
                ),
                if (age.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(age,
                      style: mono(11, color: AppColors.fg4)),
                ],
              ],
            ),
          ),
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.only(bottom: 2),
      child: Material(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(kMobile ? R.md : R.sm),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(kMobile ? R.md : R.sm),
          child: ConstrainedBox(
            constraints: BoxConstraints(
                minHeight: kMobile ? M.rowHeight : kNavRowHeight),
            child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: kMobile ? M.rowPadH : kNavPadH,
                  vertical: kMobile ? 8 : 0),
              child: Row(children: [
                if (task.priority > 0) ...[
                  PriorityMark(task.priority),
                  const SizedBox(width: 8),
                ],
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(task.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: kMobile
                              ? TS.rowTitle(AppColors.fg2)
                              : TS.label()),
                      if (kMobile && detail.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Text(detail,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TS.meta()),
                      ],
                    ],
                  ),
                ),
                if (age.isNotEmpty) ...[
                  const SizedBox(width: 8),
                  Text(age, style: TS.meta(AppColors.fg4)),
                ],
              ]),
            ),
          ),
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
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
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
            horizontal: kMobile ? M.gutter : kNavPadH, vertical: 4),
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
