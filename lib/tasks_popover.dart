import 'package:flutter/material.dart';

import 'api.dart';
import 'models.dart';
import 'theme.dart';
import 'widgets.dart';

/// Opens the open-task list above [anchor]. "Expand" calls [onExpand] to show
/// the full list in the main pane; picking a task calls [onOpenTask], which
/// opens it in a tab.
Future<void> showTasksPopover(
  BuildContext anchor,
  DaemonClient client, {
  required VoidCallback onExpand,
  required void Function(TaskItem task) onOpenTask,
}) =>
    showAnchoredPanel<void>(
      anchor,
      width: 320,
      maxHeight: 440,
      above: true,
      alignRight: true,
      child: _TasksPopover(
          client: client, onExpand: onExpand, onOpenTask: onOpenTask),
    );

class _TasksPopover extends StatefulWidget {
  const _TasksPopover(
      {required this.client, required this.onExpand, required this.onOpenTask});

  final DaemonClient client;
  final VoidCallback onExpand;
  final void Function(TaskItem task) onOpenTask;

  @override
  State<_TasksPopover> createState() => _TasksPopoverState();
}

class _TasksPopoverState extends State<_TasksPopover> {
  late final Future<List<TaskItem>> _tasks = Future.wait([
    for (final s in _open) widget.client.tasks(status: s.wire, limit: 30),
  ]).then((lists) => [for (final l in lists) ...l]);

  static final _open = [
    TaskStatus.inProgress,
    TaskStatus.blocked,
    TaskStatus.failed,
    TaskStatus.todo,
  ];

  Color _dot(TaskStatus s) => switch (s) {
        TaskStatus.inProgress => AppColors.run,
        TaskStatus.inReview => AppColors.accent,
        TaskStatus.blocked || TaskStatus.failed => AppColors.danger,
        _ => AppColors.fg4,
      };

  void _close() => Navigator.of(context, rootNavigator: true).pop();

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(S.s4, S.s2, S.s4, S.s4),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: EdgeInsets.fromLTRB(S.s4, S.s2, 0, S.s6),
              child: Row(children: [
                Expanded(
                  child: Text('Tasks',
                      style: sans(12, color: AppColors.fg4, spacing: 0.4)),
                ),
                Tooltip(
                  message: 'Expand task list',
                  child: InkWell(
                    borderRadius: BorderRadius.circular(R.sm),
                    onTap: () {
                      _close();
                      widget.onExpand();
                    },
                    child: Padding(
                      padding:
                          EdgeInsets.symmetric(horizontal: S.s8, vertical: S.of(5)),
                      child: Row(mainAxisSize: MainAxisSize.min, children: [
                        AppIcon('expand', size: 12, color: AppColors.fg3),
                        SizedBox(width: S.s6),
                        Text('Expand',
                            style: sans(13, color: AppColors.fg2)),
                      ]),
                    ),
                  ),
                ),
              ]),
            ),
            FutureBuilder<List<TaskItem>>(
              future: _tasks,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return Padding(
                    padding: EdgeInsets.symmetric(vertical: S.of(22)),
                    child: Center(child: Spinner(size: 14)),
                  );
                }
                if (snap.hasError) return _note('Could not load tasks.');
                final open = snap.data!.toList()
                  ..sort((a, b) =>
                      _rank(a.status).compareTo(_rank(b.status)));
                if (open.isEmpty) return _note('No open tasks.');
                return Column(children: [
                  for (final t in open.take(12)) _row(t),
                  if (open.length > 12)
                    Padding(
                      padding: EdgeInsets.fromLTRB(S.s8, S.s6, S.s8, S.s2),
                      child: Text('+${open.length - 12} more',
                          style: sans(12, color: AppColors.fg4)),
                    ),
                ]);
              },
            ),
          ],
        ),
      );

  int _rank(TaskStatus s) => switch (s) {
        TaskStatus.inProgress || TaskStatus.inReview => 0,
        TaskStatus.blocked || TaskStatus.failed => 1,
        _ => 2,
      };

  Widget _note(String text) => Padding(
        padding: EdgeInsets.fromLTRB(S.s4, S.of(10), S.s4, S.s12),
        child: Text(text, style: sans(13, color: AppColors.fg4)),
      );

  Widget _row(TaskItem t) => Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(R.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.sm),
          onTap: () {
            _close();
            widget.onOpenTask(t);
          },
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: S.s8, vertical: S.s8),
            child: Row(children: [
              Container(
                width: 6,
                height: 6,
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: _dot(t.status)),
              ),
              SizedBox(width: S.of(10)),
              Expanded(
                child: Text(t.title.trim().isEmpty ? '(untitled)' : t.title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(13, color: AppColors.fg2)),
              ),
              SizedBox(width: S.s8),
              Text(t.status.label, style: sans(12, color: AppColors.fg4)),
            ]),
          ),
        ),
      );
}
