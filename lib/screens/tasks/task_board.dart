import 'package:flutter/material.dart';
import '../../api.dart';
import 'task_list_view.dart';

/// The desktop Tasks tab: the grouped list with the selected task beside it.
class TaskBoard extends StatelessWidget {
  const TaskBoard({super.key, required this.client});

  final DaemonClient client;

  @override
  Widget build(BuildContext context) => TaskListView(client: client);
}
