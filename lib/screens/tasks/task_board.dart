import 'package:flutter/material.dart';
import '../../api.dart';
import 'task_kanban.dart';
import 'task_view_toggle.dart';
import 'task_list_view.dart';

/// The desktop Tasks tab: a status board by default, with a list option.
class TaskBoard extends StatefulWidget {
  const TaskBoard({super.key, required this.client});

  final DaemonClient client;

  @override
  State<TaskBoard> createState() => _TaskBoardState();
}

class _TaskBoardState extends State<TaskBoard> {
  // Remembered across tab reopenings within a run.
  static TaskView _last = TaskView.board;
  TaskView _view = _last;

  void _set(TaskView v) => setState(() => _view = _last = v);

  @override
  Widget build(BuildContext context) {
    final toggle = TaskViewToggle(value: _view, onChanged: _set);
    return _view == TaskView.board
        ? TaskKanban(client: widget.client, viewToggle: toggle)
        : TaskListView(client: widget.client, viewToggle: toggle);
  }
}
