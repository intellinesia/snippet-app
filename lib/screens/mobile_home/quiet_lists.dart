import 'package:flutter/material.dart';

import '../../api.dart';
import '../../models.dart';
import '../../quiet.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../tasks/task_common.dart' show openTaskDetail, showCreateTask;
import 'collapsing_root.dart';
export 'all_agents_phone.dart';

int _epoch(String iso) =>
    (DateTime.tryParse(iso)?.millisecondsSinceEpoch ?? 0) ~/ 1000;

/// Quiet Tasks: in progress first, then what finished today. A calm list.
class QuietTasksScreen extends StatefulWidget {
  const QuietTasksScreen({super.key, required this.client});
  final DaemonClient client;

  @override
  State<QuietTasksScreen> createState() => _QuietTasksScreenState();
}

class _QuietTasksScreenState extends State<QuietTasksScreen> {
  List<TaskItem>? _tasks;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final t = await widget.client.tasks();
      if (mounted) {
        setState(() {
          _tasks = t;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = '$e');
    }
  }

  @override
  Widget build(BuildContext context) {
    final tasks = _tasks;
    final children = <Widget>[
      const LargeTitle('Tasks'),
    ];
    if (tasks == null) {
      children.add(_error == null
          ? Padding(
              padding: EdgeInsets.all(S.s32),
              child: const Center(child: Spinner(size: 18)))
          : Padding(
              padding: EdgeInsets.all(S.s16),
              child: QuietNeedsYou(
                  title: 'Could not load tasks',
                  detail: _error,
                  action: 'Retry',
                  onAction: _load)));
    } else {
      final dayStart = DateTime.now()
              .copyWith(hour: 0, minute: 0, second: 0, millisecond: 0)
              .millisecondsSinceEpoch ~/
          1000;
      bool live(TaskItem t) =>
          t.status == TaskStatus.inProgress ||
          t.status == TaskStatus.inReview ||
          t.status == TaskStatus.blocked;
      final active = tasks.where(live).toList()
        ..sort((a, b) => _epoch(b.updatedAt).compareTo(_epoch(a.updatedAt)));
      final todo = tasks.where((t) => t.status == TaskStatus.todo).toList();
      final done = tasks
          .where((t) => t.status.isTerminal && _epoch(t.updatedAt) >= dayStart)
          .toList()
        ..sort((a, b) => _epoch(b.updatedAt).compareTo(_epoch(a.updatedAt)));
      Widget row(TaskItem t) => QuietRow(
            title: t.title,
            titleLines: 2,
            sub: t.statusReason?.isNotEmpty == true
                ? '${t.status.label} · ${t.statusReason}'
                : t.status.label,
            meta: relativeTime(_epoch(t.updatedAt)),
            leading: t.status == TaskStatus.blocked
                ? const QuietHand(size: 20)
                : AppIcon(
                    t.status.isTerminal
                        ? 'check-circle'
                        : t.status == TaskStatus.todo
                            ? 'circle'
                            : 'circle',
                    size: 20,
                    color: t.status.isTerminal ? AppColors.fg3 : AppColors.fg1),
            onTap: () => openTaskDetail(context, widget.client, t.id),
          );
      if (active.isNotEmpty) {
        children.add(QuietSectionLabel('In progress', count: active.length));
        children.addAll(active.map(row));
      }
      if (todo.isNotEmpty) {
        children.add(QuietSectionLabel('To do', count: todo.length));
        children.addAll(todo.take(8).map(row));
      }
      if (done.isNotEmpty) {
        children.add(QuietSectionLabel('Done today', count: done.length));
        children.addAll(done.map(row));
      }
      if (active.isEmpty && todo.isEmpty && done.isEmpty) {
        children.add(Padding(
            padding: EdgeInsets.all(S.s32),
            child: Text('No tasks yet.',
                textAlign: TextAlign.center,
                style: sans(14, color: AppColors.fg3))));
      }
    }
    children.add(SizedBox(height: S.s24));
    return CollapsingRoot(
        title: 'Tasks',
        actions: [
          Semantics(
            button: true,
            label: 'New task',
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () async {
                if (await showCreateTask(context, widget.client)) _load();
              },
              child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(
                      child: AppIcon('plus', size: 20, color: AppColors.fg2))),
            ),
          ),
        ],
        child: RefreshIndicator(
            onRefresh: _load, child: ListView(children: children)));
  }
}
