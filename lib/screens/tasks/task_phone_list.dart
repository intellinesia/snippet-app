import 'package:flutter/material.dart';

import '../../models.dart';
import '../../pull_refresh.dart';
import '../../tap_detector.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../mobile_home/collapsing_root.dart';
import 'task_phone.dart';
import 'task_phone_board.dart';

enum TaskScope { all, mine, agents }

/// The phone Tasks root (TK-01): collapsing large title, All / Mine / Agents
/// chips, then Needs you, Doing, Todo and Done groups of 56-high rows.
class PhoneTasksRoot extends StatefulWidget {
  const PhoneTasksRoot({
    super.key,
    required this.tasks,
    required this.sessions,
    required this.agentNames,
    required this.onOpen,
    required this.onNew,
    required this.onRefresh,
    this.leading,
    this.actions = const [],
    this.stateBody,
    this.hasMore,
    this.onLoadMore,
    this.title = 'Tasks',
  });

  final List<TaskItem> tasks;
  final Map<String, SessionInfo> sessions;
  final Map<String, String> agentNames;
  final ValueChanged<TaskItem> onOpen;
  final VoidCallback onNew;
  final Future<void> Function() onRefresh;
  final Widget? leading;
  final List<Widget> actions;
  final String title;

  /// Loading or error block shown under the title instead of the groups.
  final Widget? stateBody;
  final bool Function(TaskStatus)? hasMore;
  final Future<void> Function(TaskStatus)? onLoadMore;

  @override
  State<PhoneTasksRoot> createState() => _PhoneTasksRootState();
}

const kDoneVisible = 5;

class _PhoneTasksRootState extends State<PhoneTasksRoot> {
  TaskScope _scope = TaskScope.all;
  bool _doneOpen = false;
  bool _board = false;

  bool _in(TaskItem t, TaskScope s) => switch (s) {
        TaskScope.all => true,
        TaskScope.mine => t.createdByKind == 'human',
        TaskScope.agents => t.createdByKind == 'agent',
      };

  @override
  Widget build(BuildContext context) {
    final all = widget.tasks;
    final shown = [for (final t in all) if (_in(t, _scope)) t];
    List<TaskItem> of(Set<TaskStatus> s) =>
        [for (final t in shown) if (s.contains(t.status)) t];
    final done = of({TaskStatus.done, TaskStatus.cancelled})
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final groups = <(String, List<TaskItem>)>[
      ('Needs you', of(taskNeedsYou)),
      ('Doing', of({TaskStatus.inProgress})),
      ('Todo', of({TaskStatus.todo})),
    ];

    final children = <Widget>[
      LargeTitle(widget.title),
      if (widget.stateBody == null && all.isNotEmpty) _chips(all),
    ];
    if (widget.stateBody != null) {
      children.add(SizedBox(height: 320, child: widget.stateBody));
    } else if (all.isEmpty) {
      children.add(SizedBox(
          height: 360,
          child: EmptyState(
            icon: 'list',
            title: 'No tasks yet',
            body: 'Ask an agent to create one, or add your own.',
            action: StateButton('New task', onTap: widget.onNew),
          )));
    } else if (shown.isEmpty) {
      children.add(SizedBox(
          height: 320,
          child: EmptyState(
            icon: 'list',
            title: 'Nothing here',
            body: _scope == TaskScope.agents
                ? 'No tasks created by agents.'
                : 'No tasks created by you.',
          )));
    } else {
      for (final (label, items) in groups) {
        if (items.isEmpty) continue;
        children.add(_label(label, items.length));
        children.addAll(items.map(_row));
      }
      if (done.isNotEmpty) {
        children.add(_label('Done', done.length));
        final cut = _doneOpen ? done.length : kDoneVisible;
        children.addAll(done.take(cut).map(_row));
        if (done.length > kDoneVisible) {
          children.add(_fold(done.length - kDoneVisible));
        }
      }
      final more = [
        for (final s in TaskStatus.values)
          if (widget.hasMore?.call(s) ?? false) s
      ];
      if (more.isNotEmpty) {
        children.add(_FoldRow(
            key: const ValueKey('load-more'),
            label: 'Load more',
            open: false,
            onTap: () {
              for (final s in more) {
                widget.onLoadMore?.call(s);
              }
            }));
      }
    }

    final trailing = [
      ...widget.actions,
      BarIcon(_board ? 'list' : 'kanban', _board ? 'List view' : 'Board view',
          () => setState(() => _board = !_board),
          toggled: _board),
      BarIcon('plus', 'New task', widget.onNew),
    ];
    if (_board) {
      return PhoneTaskBoard(
        title: widget.title,
        tasks: [for (final t in all) t],
        sessions: widget.sessions,
        agentNames: widget.agentNames,
        onOpen: widget.onOpen,
        leading: widget.leading,
        actions: trailing,
        stateBody: widget.stateBody,
      );
    }
    return CollapsingRoot(
      title: widget.title,
      leading: widget.leading,
      actions: trailing,
      child: PullToRefresh(
        onRefresh: widget.onRefresh,
        child: ListView(
          padding: EdgeInsets.only(bottom: S.s24),
          children: children,
        ),
      ),
    );
  }

  Widget _fold(int hidden) => _FoldRow(
        key: const ValueKey('done-fold'),
        label: _doneOpen ? 'Show fewer' : 'Show $hidden more',
        open: _doneOpen,
        onTap: () => setState(() => _doneOpen = !_doneOpen),
      );

  Widget _label(String t, int n) => Padding(
        key: ValueKey('group-$t'),
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Semantics(
          header: true,
          child: Row(children: [
            Text(t, style: sans(12, weight: W.label, color: AppColors.fg3)),
            const SizedBox(width: 12),
            Text('$n', style: sans(12, color: AppColors.fg3)),
          ]),
        ),
      );

  Widget _chips(List<TaskItem> all) {
    int n(TaskScope s) => all.where((t) => _in(t, s)).length;
    Widget chip(String label, TaskScope s) {
      final on = _scope == s;
      return Semantics(
        button: true,
        selected: on,
        label: '$label ${n(s)}',
        excludeSemantics: true,
        child: TapDetector(
          key: ValueKey('chip-${s.name}'),
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _scope = s),
          child: Container(
            height: 44,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: on ? AppColors.fg1 : AppColors.surface2,
                borderRadius: BorderRadius.circular(22)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(label,
                  style: sans(13,
                      weight: on ? W.label : W.body,
                      color: on ? AppColors.bg : AppColors.fg2)),
              const SizedBox(width: 6),
              Text('${n(s)}',
                  style: sans(13, color: on ? AppColors.bg : AppColors.fg3)),
            ]),
          ),
        ),
      );
    }

    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.35,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
        child: Row(children: [
          chip('All', TaskScope.all),
          const SizedBox(width: 8),
          chip('Mine', TaskScope.mine),
          const SizedBox(width: 8),
          chip('Agents', TaskScope.agents),
        ]),
      ),
    );
  }

  Widget _row(TaskItem t) => PhoneTaskCard(
        key: ValueKey('t-${t.id}'),
        task: t,
        owner: taskOwner(t, widget.sessions, widget.agentNames),
        onTap: () => widget.onOpen(t),
      );
}

/// A 48 high fold row: label 14/500 fg2 and a chevron 16.
class _FoldRow extends StatelessWidget {
  const _FoldRow(
      {super.key, required this.label, required this.open, required this.onTap});
  final String label;
  final bool open;
  final VoidCallback onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Flexible(
                  child: Text(label,
                      style: sans(14, weight: W.label, color: AppColors.fg2)),
                ),
                const SizedBox(width: 6),
                AppIcon(open ? 'chevron-up' : 'chevron-down',
                    size: 16, color: AppColors.fg2),
              ]),
            ),
          ),
        ),
      );
}

/// One task row: glyph column x16..36, text at x52, owner avatar at the end.
class PhoneTaskCard extends StatelessWidget {
  const PhoneTaskCard(
      {super.key,
      required this.task,
      required this.owner,
      required this.onTap,
      this.showPriority = true});
  final TaskItem task;
  final String? owner;
  final VoidCallback onTap;

  /// False where the source has no priority (a goal's task list).
  final bool showPriority;

  @override
  Widget build(BuildContext context) {
    final finished =
        task.status == TaskStatus.done || task.status == TaskStatus.cancelled;
    final word = needsYouWord(task.status);
    final time = shortAgo(task.updatedAt);
    final rest = [
      if (owner != null) owner!,
      if (showPriority) priorityWord(task.priority),
      if (time.isNotEmpty) time,
    ].join(' - ');
    final big = MediaQuery.textScalerOf(context).scale(10) > 13.5;
    final sub = Text.rich(
      TextSpan(children: [
        if (word != null)
          TextSpan(
              text: rest.isEmpty ? word : '$word - ',
              style: sans(12.5, weight: W.label, color: AppColors.fg2)),
        TextSpan(text: rest),
      ]),
      maxLines: big ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      style: sans(12.5, color: AppColors.fg3),
    );
    return Semantics(
      button: true,
      label: '${task.title}, ${word ?? task.status.label}, '
          '${owner == null ? '' : '$owner, '}${showPriority ? '${priorityWord(task.priority)} priority' : ''}',
      excludeSemantics: true,
      child: TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 55),
            child: Padding(
              padding:
                  const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                SizedBox(
                    width: 36,
                    child: Align(
                        alignment: Alignment.centerLeft,
                        child: TaskGlyph(task.status))),
                Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(task.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: sans(15,
                                color: finished
                                    ? AppColors.fg3
                                    : AppColors.fg1)),
                        const SizedBox(height: 2),
                        sub,
                      ]),
                ),
                if (owner != null) ...[
                  const SizedBox(width: 12),
                  OwnerAvatar(owner!),
                ],
              ]),
            ),
          ),
          Container(
              height: 1,
              margin: const EdgeInsets.only(left: 52, right: 16),
              color: AppColors.border),
        ]),
      ),
    );
  }
}
