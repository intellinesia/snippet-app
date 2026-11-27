import 'package:flutter/material.dart';

import '../../models.dart';
import '../../pull_refresh.dart';
import '../../tap_detector.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../../mobile_kit.dart';
import '../../mochi.dart';
import '../mobile_home/collapsing_root.dart';
import 'task_phone.dart';
import 'task_phone_board.dart';

enum TaskScope { all, mine, agents }

/// The phone Tasks root (TK-01): large title with the New task split button,
/// the All / Mine / Agents filter group, then Needs you, Open and Completed
/// sections of state-led rows.
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
  bool _searching = false;
  final _q = TextEditingController();

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  bool _hit(TaskItem t) {
    final q = _q.text.trim().toLowerCase();
    if (q.isEmpty) return true;
    final owner =
        taskOwnerAgent(t, widget.sessions, widget.agentNames)?.name ?? '';
    return t.title.toLowerCase().contains(q) ||
        t.id.toLowerCase().contains(q) ||
        owner.toLowerCase().contains(q);
  }

  bool _in(TaskItem t, TaskScope s) => switch (s) {
        TaskScope.all => true,
        TaskScope.mine => t.createdByKind == 'human',
        TaskScope.agents => t.createdByKind == 'agent',
      };

  @override
  Widget build(BuildContext context) {
    final all = widget.tasks;
    final shown = [
      for (final t in all)
        if (_in(t, _scope) && _hit(t)) t
    ];
    List<TaskItem> of(Set<TaskStatus> s) => [
          for (final t in shown)
            if (s.contains(t.status)) t
        ];
    final done = of({TaskStatus.done, TaskStatus.cancelled})
      ..sort((a, b) => b.updatedAt.compareTo(a.updatedAt));
    final groups = <(String, List<TaskItem>)>[
      ('Needs you', of(taskNeedsYou)),
      (
        'Open',
        [
          ...of({TaskStatus.inProgress}),
          ...of({TaskStatus.todo})
        ]
      ),
    ];

    final children = <Widget>[
      _head(),
      if (_searching)
        MkSearchField(
            controller: _q,
            hint: 'Search tasks',
            onChanged: (_) => setState(() {})),
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
            body: _q.text.trim().isNotEmpty
                ? 'No tasks match your search.'
                : _scope == TaskScope.agents
                    ? 'No tasks created by agents.'
                    : 'No tasks created by you.',
          )));
    } else {
      for (final (label, items) in groups) {
        if (items.isEmpty) continue;
        children.add(_label(label, items.length));
        children.add(_rows(items));
      }
      if (done.isNotEmpty) {
        children.add(_label('Completed', done.length));
        final cut = _doneOpen ? done.length : kDoneVisible;
        children.add(_rows(done.take(cut).toList()));
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

    if (_board) {
      final trailing = [
        ...widget.actions,
        BarIcon('list', 'List view', () => setState(() => _board = false),
            toggled: true),
        BarIcon('plus', 'New task', widget.onNew),
      ];
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
      actions: [
        ...widget.actions,
        // Board: Android carries search in the top bar; iPhone has none.
        if (kAndroidLook)
          MkIconTap(
              'search',
              'Search',
              () => setState(() {
                    _searching = !_searching;
                    if (!_searching) _q.clear();
                  })),
      ],
      child: PullToRefresh(
        onRefresh: widget.onRefresh,
        child: ListView(
          padding: EdgeInsets.only(bottom: MK.bottomClearance(context)),
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

  // Title row: the large title with the New task split button beside it.
  Widget _head() => Padding(
        padding: const EdgeInsets.only(right: 16),
        child: Row(children: [
          Expanded(child: LargeTitle(widget.title)),
          // Board: the split button sits 2 off the title centre, below on
          // Android and above on iPhone.
          Padding(
            padding: kAndroidLook
                ? const EdgeInsets.only(top: 4)
                : const EdgeInsets.only(bottom: 4),
            child: MkSplitButton(
              label: 'New task',
              icon: 'plus',
              onTap: widget.onNew,
              onMenu: _menu,
              menuLabel: 'Task options',
            ),
          ),
        ]),
      );

  void _menu() {
    showMkSheet<void>(context,
        title: widget.title,
        builder: (ctx) => Column(mainAxisSize: MainAxisSize.min, children: [
              MkSheetTile(
                icon: 'kanban',
                label: 'Board view',
                onTap: () {
                  Navigator.of(ctx).pop();
                  setState(() => _board = true);
                },
              ),
            ]));
  }

  // Only Completed carries a count on the board.
  Widget _label(String t, int n) => KeyedSubtree(
        key: ValueKey('group-$t'),
        child: MkSection(t, trailing: t == 'Completed' ? '$n' : null),
      );

  Widget _chips(List<TaskItem> all) {
    int n(TaskScope s) => all.where((t) => _in(t, s)).length;
    return MediaQuery.withClampedTextScaling(
      maxScaleFactor: 1.35,
      child: MkFilterGroup<TaskScope>(
        padding: MK.filterPad,
        options: [
          MkFilter(TaskScope.all, 'All', count: n(TaskScope.all)),
          MkFilter(TaskScope.mine, 'Mine', count: n(TaskScope.mine)),
          MkFilter(TaskScope.agents, 'Agents', count: n(TaskScope.agents)),
        ],
        selected: _scope,
        onSelect: (s) => setState(() => _scope = s),
      ),
    );
  }

  Widget _rows(List<TaskItem> items) => MkList(children: [
        for (var i = 0; i < items.length; i++)
          _row(items[i], last: i == items.length - 1),
      ]);

  Widget _row(TaskItem t, {bool last = false}) {
    final o = taskOwnerAgent(t, widget.sessions, widget.agentNames);
    return PhoneTaskCard(
      key: ValueKey('t-${t.id}'),
      task: t,
      owner: o?.name,
      ownerId: o?.id,
      last: last,
      onTap: () => widget.onOpen(t),
    );
  }
}

/// A 48 high fold row: label 14/500 fg2 and a chevron 16.
class _FoldRow extends StatelessWidget {
  const _FoldRow(
      {super.key,
      required this.label,
      required this.open,
      required this.onTap});
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
              padding: EdgeInsets.symmetric(
                  horizontal: kAndroidLook ? 28 : MK.gutter),
              child: Row(children: [
                Flexible(
                  child: Text(label,
                      style: sans(14, weight: W.label, color: AppColors.fg3)),
                ),
                const SizedBox(width: 6),
                AppIcon(open ? 'chevron-up' : 'chevron-down',
                    size: 16, color: AppColors.fg3),
              ]),
            ),
          ),
        ),
      );
}

/// One task row, built like a session row: the state mark leads, title
/// over owner, priority and time, the owner's character on the right.
class PhoneTaskCard extends StatelessWidget {
  const PhoneTaskCard(
      {super.key,
      required this.task,
      required this.owner,
      required this.onTap,
      this.ownerId,
      this.last = false,
      this.showPriority = true});
  final TaskItem task;
  final String? owner;
  final String? ownerId;
  final VoidCallback onTap;

  /// No hairline under the last row of a run (iPhone).
  final bool last;

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
      if (showPriority && !finished) priorityWord(task.priority),
      if (time.isNotEmpty) time,
    ].join(' · ');
    final big = MediaQuery.textScalerOf(context).scale(10) > 13.5;
    final sub = Text.rich(
      TextSpan(children: [
        if (word != null)
          TextSpan(
              text: rest.isEmpty ? word : '$word · ',
              style: sans(13.5, weight: W.label, color: AppColors.fg2)),
        TextSpan(text: rest),
      ]),
      maxLines: big ? 2 : 1,
      overflow: TextOverflow.ellipsis,
      style: mkRowSub(),
    );
    final id = ownerId;
    final a = kAndroidLook;
    final whoSize = a ? 28.0 : 24.0;
    final Widget? who = id != null && id.isNotEmpty
        ? ExcludeSemantics(child: AgentMochi(id, size: whoSize))
        : owner != null
            ? OwnerAvatar(owner!, size: whoSize)
            : null;
    final titleText = Text(task.title,
        maxLines: big ? 2 : 1,
        overflow: TextOverflow.ellipsis,
        style: mkRowTitle().copyWith(fontSize: a ? 15.5 : 15));
    // Android rows sit inside segmented tiles, which own the outer inset.
    final left = a ? 16.0 : MK.gutter;
    final markSlot = a ? 40.0 : 24.0;
    final gap = a ? 14.0 : 12.0;
    final Widget text;
    if (a) {
      text = Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [titleText, const SizedBox(height: 2), sub]);
    } else {
      // iPhone puts the owner's character on the title line.
      text = Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(children: [
              Expanded(child: titleText),
              if (who != null) ...[
                const SizedBox(width: 8),
                SizedBox(width: whoSize, height: whoSize, child: who),
              ],
            ]),
            const SizedBox(height: 2),
            sub,
          ]);
    }
    return Semantics(
      button: true,
      label: '${task.title}, ${word ?? task.status.label}, '
          '${owner == null ? '' : '$owner, '}${showPriority ? '${priorityWord(task.priority)} priority' : ''}',
      excludeSemantics: true,
      child: TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: left),
          child: Row(children: [
            SizedBox(
                width: markSlot, child: Center(child: TaskGlyph(task.status))),
            SizedBox(width: gap),
            Expanded(
              child: Container(
                constraints: BoxConstraints(minHeight: a ? 68 : 64),
                padding: const EdgeInsets.symmetric(vertical: 10),
                decoration: BoxDecoration(
                  border: !a && !last
                      ? Border(
                          bottom: BorderSide(color: MK.hairline, width: 0.5))
                      : null,
                ),
                child: Row(children: [
                  Expanded(child: text),
                  if (a && who != null) ...[
                    const SizedBox(width: 14),
                    SizedBox(width: whoSize, height: whoSize, child: who),
                  ],
                ]),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
