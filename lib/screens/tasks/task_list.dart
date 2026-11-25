import '../../task_reason.dart';
import '../../phosphor_icons.dart';
import 'package:flutter/material.dart';

import '../../models.dart';
import '../../platform.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../shell_nav.dart' show kNavPadH;
import 'task_common.dart';
import 'task_rows.dart';
import 'task_view.dart';
import '../../pull_refresh.dart';
import '../../mochi.dart';
import '../../tap_detector.dart';

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
    this.phoneTab = TaskTab.active,
    this.onComplete,
    this.sort = TaskSort.updated,
    this.onStatus,
  });

  final TaskSort sort;

  /// Desktop: the status mark opens a quick change from its anchor.
  final void Function(TaskItem task, BuildContext anchor)? onStatus;

  /// Phone: which of the two tabs' statuses to list (a search or filter
  /// looks across all of them).
  final TaskTab phoneTab;

  /// Phone: the checkbox on a row; null leaves the box inert.
  final Future<void> Function(TaskItem task)? onComplete;

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
  /// Phone sections: label, statuses in each, in reading order.
  static const _activeSections = <(String, List<TaskStatus>)>[
    ('Ready for review', [TaskStatus.inReview]),
    ('Needs you', [TaskStatus.blocked]),
    ('Working', [TaskStatus.inProgress]),
    ('Stopped', [TaskStatus.failed]),
  ];
  static const _allSections = <(String, List<TaskStatus>)>[
    ..._activeSections,
    ('Up next', [TaskStatus.todo]),
    ('Done', [TaskStatus.done]),
    ('Cancelled', [TaskStatus.cancelled]),
  ];

  /// Rows in display order, for keyboard movement.
  List<TaskItem> get ordered => flatTasks(groupTasks(_visible, sort));

  bool get _wide => query.trim().isNotEmpty || filter.isNotEmpty;

  List<TaskItem> get _phoneVisible {
    final allowed = _wide
        ? TaskStatus.values.toSet()
        : phoneTab == TaskTab.active
            ? {for (final s in _activeSections) ...s.$2}
            : {TaskStatus.todo};
    return _visible.where((t) => allowed.contains(t.status)).toList();
  }

  List<Widget> _phoneRows() {
    final visible = _phoneVisible;
    if (visible.isEmpty) return const [];
    final sections = _wide
        ? _allSections
        : phoneTab == TaskTab.active
            ? _activeSections
            : const [
                ('Up next', [TaskStatus.todo])
              ];
    DateTime? newest;
    for (final t in visible) {
      final at = DateTime.tryParse(t.updatedAt);
      if (at != null && (newest == null || at.isAfter(newest))) newest = at;
    }
    final out = <Widget>[];
    var first = true;
    for (final (label, statuses) in sections) {
      final items = [
        for (final s in statuses) ...visible.where((t) => t.status == s)
      ];
      if (items.isEmpty) continue;
      out.add(Padding(
        key: ValueKey('section-$label'),
        padding: EdgeInsets.fromLTRB(20, first ? 14 : 22, 20, 6),
        child: Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(label, style: sans(15, color: AppColors.fg2)),
              const SizedBox(width: 6),
              Text('${items.length}', style: sans(15, color: AppColors.fg3)),
              if (first && newest != null) ...[
                const Spacer(),
                Text('Updated ${agoLabel(newest)}',
                    style: sans(14, color: AppColors.fg3)),
              ],
            ]),
      ));
      first = false;
      for (final t in items) {
        out.add(PhoneTaskRow(
          key: ValueKey('t-${t.id}'),
          task: t,
          note: noteForTask(t, tasks),
          agentName: agentNames?[t.createdById],
          onTap: () => onOpen(t),
          onComplete: onComplete == null ? null : () => onComplete!(t),
        ));
      }
      for (final s in statuses) {
        if (hasMore?.call(s) ?? false) out.add(_loadMore(s));
      }
    }
    return out;
  }

  List<Widget> rows() {
    if (kMobile) return _phoneRows();
    final visible = _visible;
    if (visible.isEmpty) return const [];
    final groups = groupTasks(visible, sort);
    final out = <Widget>[];
    for (var g = 0; g < groups.length; g++) {
      final (status, items) = groups[g];
      out.add(TaskGroupHeader(status, items.length,
          key: ValueKey('group-${status.name}'), first: g == 0));
      Widget row(TaskItem t) => DenseTaskRow(
            key: ValueKey('t-${t.id}'),
            task: t,
            selected: t.id == selectedId,
            workspace: sessionFolders?[t.sessionId],
            onTap: () => onOpen(t),
            onStatus:
                onStatus == null ? null : (anchor) => onStatus!(t, anchor),
          );
      if (status == TaskStatus.done && items.length > taskDoneVisible) {
        out.add(FoldedTasks(
            key: const ValueKey('done-fold'),
            visible: [for (final t in items.take(taskDoneVisible)) row(t)],
            hidden: [for (final t in items.skip(taskDoneVisible)) row(t)]));
      } else {
        out.addAll(items.map(row));
      }
      if (hasMore?.call(status) ?? false) out.add(_loadMore(status));
    }
    return out;
  }

  Widget emptyState() => kMobile ? _emptyPhone() : _empty();

  @override
  Widget build(BuildContext context) {
    final visible = kMobile ? _phoneVisible : _visible;
    final pad = padding ??
        (kMobile
            ? EdgeInsets.fromLTRB(M.gutter, S.s4, M.gutter, S.s24)
            : EdgeInsets.fromLTRB(S.s8, 0, S.s8, S.of(18)));
    if (visible.isEmpty) {
      return PullToRefresh(
        onRefresh: onRefresh,
        child: ListView(
            padding: pad, children: [kMobile ? _emptyPhone() : _empty()]),
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

  Widget _emptyPhone() {
    if (tasks.isNotEmpty && !_wide) {
      return EmptyState(
        icon: 'layers',
        title:
            phoneTab == TaskTab.active ? 'Nothing active' : 'Nothing up next',
        body: phoneTab == TaskTab.active
            ? 'Tasks being worked on or waiting on you show here.'
            : 'Tasks that have not started show here.',
      );
    }
    return _empty();
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
        body: 'File a task and Lead routes it to a session.',
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
/// Rows with a "Show N more" fold under them.
class FoldedTasks extends StatefulWidget {
  const FoldedTasks({super.key, required this.visible, required this.hidden});
  final List<Widget> visible;
  final List<Widget> hidden;

  @override
  State<FoldedTasks> createState() => _FoldedTasksState();
}

class _FoldedTasksState extends State<FoldedTasks> {
  bool _open = false;

  @override
  Widget build(BuildContext context) => Column(children: [
        ...widget.visible,
        if (_open) ...widget.hidden,
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _open = !_open),
          child: Container(
            height: 28,
            alignment: Alignment.centerLeft,
            // The title column: row inset + mark column + gap + id column.
            padding: const EdgeInsets.only(
                left: kTaskRowInset + 22 + 4 + kTaskIdWidth),
            child: Text(
                _open ? 'Show less' : 'Show ${widget.hidden.length} more',
                style: sans(12, color: AppColors.fg3)),
          ),
        ),
      ]);
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
    // Agent ids are lowercase handles; show them as names when no display name is known.
    final who = (agentName ?? '').trim().isNotEmpty
        ? agentName!.trim()
        : agent.isEmpty
            ? agent
            : agent[0].toUpperCase() + agent.substring(1);
    final meta =
        [id, who, task.status.label].where((p) => p.isNotEmpty).join(' · ');
    final avatar = rowAvatarSize(kMobile ? 52 : 40);
    return Material(
      color: selected
          ? (kMobile ? AppColors.accentBg : AppColors.surface2)
          : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        child: Container(
          constraints: BoxConstraints(minHeight: kMobile ? 52 : 40),
          padding: EdgeInsets.symmetric(
              horizontal: S.s12, vertical: kMobile ? S.s8 : S.s6),
          decoration: BoxDecoration(
            border: Border(
              left: selected && !kMobile
                  ? BorderSide(color: AppColors.fg1, width: 2)
                  : BorderSide.none,
              bottom:
                  divider ? BorderSide(color: AppColors.line) : BorderSide.none,
            ),
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
                              color: finished ? AppColors.fg3 : AppColors.fg1)),
                    ),
                  ]),
                  Text(meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: codeMono(11, color: AppColors.fg3)),
                  if (line.isNotEmpty)
                    Text(line,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(12, color: AppColors.fg4)),
                ],
              ),
            ),
            if (!kMobile && needsYou) ...[
              SizedBox(width: S.s8),
              Container(
                width: 6,
                height: 6,
                decoration:
                    BoxDecoration(color: AppColors.run, shape: BoxShape.circle),
              ),
              SizedBox(width: S.s6),
              Text('Needs you',
                  style:
                      sans(12, weight: FontWeight.w500, color: AppColors.fg2)),
            ],
            if (!kMobile && age.isNotEmpty) ...[
              SizedBox(width: S.s8),
              Text(age, style: mono(11, color: AppColors.fg4)),
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
                  child: Text('Load more', style: TS.ui(AppColors.accent)),
                ),
        ),
      );
}

enum TaskTab { active, upNext }

/// "5 min ago", "2 h ago", "3 d ago".
String agoLabel(DateTime at) {
  final d = DateTime.now().difference(at);
  if (d.inMinutes < 1) return 'just now';
  if (d.inMinutes < 60) return '${d.inMinutes} min ago';
  if (d.inHours < 24) return '${d.inHours} h ago';
  return '${d.inDays} d ago';
}

/// The phone's task row: a checkbox, the title, and one status line.
class PhoneTaskRow extends StatelessWidget {
  const PhoneTaskRow({
    super.key,
    required this.task,
    required this.onTap,
    this.note,
    this.agentName,
    this.onComplete,
  });
  final TaskItem task;
  final TaskNote? note;
  final String? agentName;
  final VoidCallback onTap;
  final VoidCallback? onComplete;

  static const _warn = Color(0xFFD4923C);

  (String, Color) get _status => !kMobile
      ? (
          switch (task.status) {
            TaskStatus.inReview => 'Ready for review',
            TaskStatus.blocked => 'Blocked',
            TaskStatus.inProgress => 'Working',
            TaskStatus.failed => 'Failed',
            TaskStatus.todo => 'To do',
            TaskStatus.done => 'Done',
            TaskStatus.cancelled => 'Cancelled',
          },
          statusColor(task.status)
        )
      : switch (task.status) {
          TaskStatus.inReview => ('Ready for review', AppColors.ok),
          TaskStatus.blocked => ('Blocked', _warn),
          TaskStatus.inProgress => ('Working', AppColors.accent),
          TaskStatus.failed => ('Failed', AppColors.run),
          TaskStatus.todo => ('To do', AppColors.fg3),
          TaskStatus.done => ('Done', AppColors.ok),
          TaskStatus.cancelled => ('Cancelled', AppColors.fg3),
        };

  String get _note {
    final who = (agentName ?? '').trim().isNotEmpty
        ? agentName!.trim()
        : (task.createdByKind == 'agent' && task.createdById.isNotEmpty
            ? task.createdById[0].toUpperCase() + task.createdById.substring(1)
            : '');
    final line = (note?.line ?? '').trim();
    if (task.status == TaskStatus.inReview) {
      final p = [who, line].where((e) => e.isNotEmpty).join(' · ');
      if (p.isNotEmpty) return p;
    }
    if (line.isNotEmpty) return line;
    if (who.isNotEmpty) return who;
    final at = DateTime.tryParse(task.updatedAt);
    if (at == null) return '';
    final ago = agoLabel(at);
    return ago == 'just now' ? 'Just started' : ago;
  }

  @override
  Widget build(BuildContext context) {
    final (word, colour) = _status;
    final finished =
        const {TaskStatus.done, TaskStatus.cancelled}.contains(task.status);
    final text = _note;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          TapDetector(
            key: ValueKey('check-${task.id}'),
            behavior: HitTestBehavior.opaque,
            onTap: onComplete,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(0, 1, 0, 6),
              child: Container(
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  color: finished ? AppColors.fg3 : null,
                  borderRadius: BorderRadius.circular(6),
                  border: Border.all(
                      color: finished ? AppColors.fg3 : AppColors.fg4,
                      width: 1.5),
                ),
                child: finished
                    ? Icon(PhIcons.check, size: 14, color: AppColors.bg)
                    : null,
              ),
            ),
          ),
          const SizedBox(width: 14),
          Expanded(
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(task.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: sans(17,
                      weight: W.label,
                      height: 23 / 17,
                      color: finished ? AppColors.fg3 : AppColors.fg1)),
              const SizedBox(height: 2),
              Text.rich(
                TextSpan(children: [
                  TextSpan(text: word, style: TextStyle(color: colour)),
                  if (text.isNotEmpty) TextSpan(text: ' · $text'),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(15, height: 21 / 15, color: AppColors.fg3),
              ),
            ]),
          ),
        ]),
      ),
    );
  }
}
