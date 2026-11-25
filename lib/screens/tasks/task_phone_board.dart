import 'package:flutter/material.dart';

import '../../models.dart';
import '../../phone_attention_bar.dart';
import '../../platform.dart';
import '../../tap_detector.dart';
import '../../theme.dart';
import '../../toast_avoid.dart';
import '../../widgets.dart';
import 'task_phone.dart';

enum BoardColumn {
  todo('Todo', {TaskStatus.todo}),
  doing('Doing', {TaskStatus.inProgress}),
  review('Review', taskNeedsYou),
  done('Done', {TaskStatus.done, TaskStatus.cancelled});

  const BoardColumn(this.label, this.statuses);
  final String label;
  final Set<TaskStatus> statuses;
}

/// TK-02: the read-only phone board. Bar B, four column chips, one column of
/// cards at a time; swipe changes column. Nothing here moves a task.
class PhoneTaskBoard extends StatefulWidget {
  const PhoneTaskBoard({
    super.key,
    required this.title,
    required this.tasks,
    required this.sessions,
    required this.agentNames,
    required this.onOpen,
    required this.actions,
    this.leading,
    this.stateBody,
  });

  final String title;
  final List<TaskItem> tasks;
  final Map<String, SessionInfo> sessions;
  final Map<String, String> agentNames;
  final ValueChanged<TaskItem> onOpen;
  final List<Widget> actions;
  final Widget? leading;
  final Widget? stateBody;

  @override
  State<PhoneTaskBoard> createState() => _PhoneTaskBoardState();
}

class _PhoneTaskBoardState extends State<PhoneTaskBoard> {
  final _pages = PageController();
  int _col = 0;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  List<TaskItem> _of(BoardColumn c) =>
      [for (final t in widget.tasks) if (c.statuses.contains(t.status)) t];

  void _select(int i) {
    setState(() => _col = i);
    final d = reduceMotion(context)
        ? Duration.zero
        : const Duration(milliseconds: 200);
    if (d == Duration.zero) {
      _pages.jumpToPage(i);
    } else {
      _pages.animateToPage(i, duration: d, curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.tasks.length;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ToastAvoid(
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Row(children: [
            if (widget.leading != null) widget.leading! else const SizedBox(width: 16),
            Expanded(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Semantics(
                      header: true,
                      child: Text(widget.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(16, weight: W.label, color: AppColors.fg1)),
                    ),
                    Text('$n ${n == 1 ? 'card' : 'cards'}',
                        style: sans(12, color: AppColors.fg3)),
                  ]),
            ),
            ...widget.actions,
            const SizedBox(width: 4),
          ]),
        ),
      ),
      if (kMobile) const PhoneAttentionLayer(),
      if (widget.stateBody == null) _chips(),
      Expanded(
        child: widget.stateBody ??
            PageView(
              key: const ValueKey('board-pages'),
              controller: _pages,
              onPageChanged: (i) => setState(() => _col = i),
              children: [
                for (final c in BoardColumn.values) _column(c),
              ],
            ),
      ),
    ]);
  }

  Widget _chips() => MediaQuery.withClampedTextScaling(
        maxScaleFactor: 1.35,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
          child: Row(children: [
            for (final c in BoardColumn.values) ...[
              if (c != BoardColumn.todo) const SizedBox(width: 8),
              _chip(c),
            ]
          ]),
        ),
      );

  Widget _chip(BoardColumn c) {
    final on = BoardColumn.values[_col] == c;
    final count = _of(c).length;
    return Semantics(
      button: true,
      selected: on,
      label: '${c.label} $count',
      excludeSemantics: true,
      child: TapDetector(
        key: ValueKey('board-chip-${c.name}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => _select(c.index),
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: on ? AppColors.surface3 : AppColors.surface2,
              borderRadius: BorderRadius.circular(22)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text(c.label,
                style: sans(13,
                    weight: on ? W.label : W.body,
                    color: on ? AppColors.fg1 : AppColors.fg2)),
            const SizedBox(width: 6),
            Text('$count', style: sans(13, color: AppColors.fg3)),
          ]),
        ),
      ),
    );
  }

  Widget _column(BoardColumn c) {
    final items = _of(c);
    if (items.isEmpty) {
      return ListView(children: [
        SizedBox(
            height: 300,
            child: EmptyState(icon: 'list', title: 'Nothing here')),
      ]);
    }
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
      children: [
        for (final t in items)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: BoardCard(
              key: ValueKey('board-card-${t.id}'),
              task: t,
              owner: taskOwner(t, widget.sessions, widget.agentNames),
              onTap: () => widget.onOpen(t),
            ),
          ),
      ],
    );
  }
}

/// A board card: title 14/500, then owner and priority. Needs you shows the
/// amber hand and the words.
class BoardCard extends StatelessWidget {
  const BoardCard(
      {super.key, required this.task, required this.owner, required this.onTap});
  final TaskItem task;
  final String? owner;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final needs = taskWaitsOnUser(task.status);
    final pri = priorityWord(task.priority);
    return Semantics(
      button: true,
      label: '${task.title}, ${owner == null ? '' : '$owner, '}$pri'
          '${needs ? ', needs you' : ''}',
      excludeSemantics: true,
      child: TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 80),
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 12),
          decoration: BoxDecoration(
              color: AppColors.surface1,
              borderRadius: BorderRadius.circular(10)),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(task.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: sans(14, weight: W.label, color: AppColors.fg1)),
                const SizedBox(height: 10),
                Row(children: [
                  if (owner != null) ...[
                    const SizedBox(width: 2),
                    OwnerAvatar(owner!, size: 20),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(owner!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(12, color: AppColors.fg2)),
                    ),
                  ],
                  const Spacer(),
                  if (needs) ...[
                    TaskGlyph(task.status, size: 14),
                    const SizedBox(width: 4),
                    Text('Needs you',
                        style: sans(11.5, weight: W.label, color: AppColors.run)),
                    const SizedBox(width: 8),
                  ],
                  Text(pri, style: sans(11.5, color: AppColors.fg3)),
                ]),
              ]),
        ),
      ),
    );
  }
}
