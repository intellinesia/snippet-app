import 'package:flutter/material.dart';

import '../../models.dart';
import '../../phone_attention_bar.dart';
import '../../platform.dart';
import '../../tap_detector.dart';
import '../../theme.dart';
import '../../toast_avoid.dart';
import '../../widgets.dart';
import '../../mobile_kit.dart';
import '../../mochi.dart';
import 'task_phone.dart';

enum BoardColumn {
  todo('Todo', {TaskStatus.todo}),
  doing('Doing', {TaskStatus.inProgress}),
  review('Review', taskNeedsYou),
  done('Completed', {TaskStatus.done, TaskStatus.cancelled});

  const BoardColumn(this.label, this.statuses);
  final String label;
  final Set<TaskStatus> statuses;
}

/// TK-02: the read-only phone board. Compact bar, the column filter group,
/// one column of cards at a time; swipe changes column. Nothing here moves a
/// task.
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

  List<TaskItem> _of(BoardColumn c) => [
        for (final t in widget.tasks)
          if (c.statuses.contains(t.status)) t
      ];

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
          constraints: const BoxConstraints(minHeight: 56),
          child: Row(children: [
            if (widget.leading != null)
              widget.leading!
            else
              SizedBox(width: kAndroidLook ? 16 : MK.gutter),
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
                          style: kAndroidLook
                              ? sans(22, weight: W.label, color: AppColors.fg1)
                              : sans(16.5,
                                  weight: FontWeight.w600,
                                  color: AppColors.fg1)),
                    ),
                    Text('$n ${n == 1 ? 'card' : 'cards'}',
                        style: sans(12.5, color: AppColors.fg3)),
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
        child: MkFilterGroup<BoardColumn>(
          padding: MK.filterPad.copyWith(bottom: 8),
          options: [
            for (final c in BoardColumn.values)
              MkFilter(c, c.label, count: _of(c).length),
          ],
          selected: BoardColumn.values[_col],
          onSelect: (c) => _select(c.index),
        ),
      );

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
      padding: EdgeInsets.fromLTRB(16, 4, 16, MK.bottomClearance(context)),
      children: [
        for (final t in items)
          Padding(
            padding: EdgeInsets.only(bottom: kAndroidLook ? 4 : 8),
            child: BoardCard(
              key: ValueKey('board-card-${t.id}'),
              task: t,
              owner: taskOwner(t, widget.sessions, widget.agentNames),
              ownerId:
                  taskOwnerAgent(t, widget.sessions, widget.agentNames)?.id,
              onTap: () => widget.onOpen(t),
            ),
          ),
      ],
    );
  }
}

/// A board card on a flat surface: state mark and title, then owner and
/// priority. Needs you shows the amber dot and the words.
class BoardCard extends StatelessWidget {
  const BoardCard(
      {super.key,
      required this.task,
      required this.owner,
      required this.onTap,
      this.ownerId});
  final TaskItem task;
  final String? owner;
  final String? ownerId;
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
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          decoration: BoxDecoration(
              color: AppColors.surface1,
              borderRadius: BorderRadius.circular(MK.groupRadius)),
          child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(task.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: mkRowTitle()),
                const SizedBox(height: 10),
                Row(children: [
                  if (owner != null) ...[
                    if (ownerId != null && ownerId!.isNotEmpty)
                      ExcludeSemantics(child: AgentMochi(ownerId!, size: 22))
                    else
                      OwnerAvatar(owner!, size: 22),
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(owner!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: mkRowSub(color: AppColors.fg2)),
                    ),
                  ],
                  const Spacer(),
                  if (needs) ...[
                    TaskGlyph(task.status, size: 14),
                    const SizedBox(width: 4),
                    Text('Needs you',
                        style: sans(12.5, weight: W.label, color: MK.amber)),
                    const SizedBox(width: 10),
                  ],
                  Text(pri, style: sans(12.5, color: AppColors.fg3)),
                ]),
              ]),
        ),
      ),
    );
  }
}
