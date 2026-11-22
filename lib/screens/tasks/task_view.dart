import '../../models.dart';

/// Pure list logic for the desktop tasks view: order, sort and fold rules.

/// Board order of the status groups; failed and cancelled close the list.
const taskGroupOrder = <TaskStatus>[
  TaskStatus.inReview,
  TaskStatus.blocked,
  TaskStatus.inProgress,
  TaskStatus.todo,
  TaskStatus.done,
  TaskStatus.failed,
  TaskStatus.cancelled,
];

enum TaskSort {
  updated('Updated'),
  created('Created'),
  priority('Priority');

  const TaskSort(this.label);
  final String label;
}

/// Done shows this many rows before a "Show N more" fold.
const taskDoneVisible = 5;

int _at(String iso) => DateTime.tryParse(iso)?.millisecondsSinceEpoch ?? 0;

List<TaskItem> sortTasks(Iterable<TaskItem> tasks, TaskSort sort) {
  final out = [...tasks];
  int newest(String a, String b) => _at(b).compareTo(_at(a));
  out.sort(switch (sort) {
    TaskSort.updated => (a, b) => newest(a.updatedAt, b.updatedAt),
    TaskSort.created => (a, b) => newest(a.createdAt, b.createdAt),
    TaskSort.priority => (a, b) {
        final p = b.priority.compareTo(a.priority);
        return p != 0 ? p : newest(a.updatedAt, b.updatedAt);
      },
  });
  return out;
}

/// Tasks per status in board order, empty groups dropped, each group sorted.
List<(TaskStatus, List<TaskItem>)> groupTasks(
    Iterable<TaskItem> tasks, TaskSort sort) {
  final sorted = sortTasks(tasks, sort);
  return [
    for (final s in taskGroupOrder)
      if (sorted.any((t) => t.status == s))
        (
          s,
          [
            for (final t in sorted)
              if (t.status == s) t
          ]
        ),
  ];
}

/// The rows in the order the list shows them, for keyboard movement.
List<TaskItem> flatTasks(List<(TaskStatus, List<TaskItem>)> groups) =>
    [for (final g in groups) ...g.$2];

/// Branch and Changes describe the task's own worktree. Before the task starts,
/// or in a shared checkout, the session's repo-wide numbers are not the task's.
bool showWorktreeFacts(TaskItem task, SessionInfo? session) =>
    session != null &&
    session.inWorktree &&
    task.status != TaskStatus.todo &&
    task.status != TaskStatus.cancelled;

/// Index after moving [delta] from [current], clamped; -1 start picks the ends.
int moveSelection(int current, int delta, int length) {
  if (length == 0) return -1;
  if (current < 0) return delta >= 0 ? 0 : length - 1;
  return (current + delta).clamp(0, length - 1);
}

/// What the desktop filter bar narrows the list by; empty means no narrowing.
class TaskFilter {
  const TaskFilter({this.statuses = const {}, this.agent, this.workspace});
  final Set<TaskStatus> statuses;
  final String? agent;
  final String? workspace;

  bool get isEmpty => statuses.isEmpty && agent == null && workspace == null;

  TaskFilter copyWith(
          {Set<TaskStatus>? statuses,
          String? agent,
          String? workspace,
          bool clearAgent = false,
          bool clearWorkspace = false}) =>
      TaskFilter(
        statuses: statuses ?? this.statuses,
        agent: clearAgent ? null : (agent ?? this.agent),
        workspace: clearWorkspace ? null : (workspace ?? this.workspace),
      );

  bool matches(TaskItem t, String Function(TaskItem) workspaceOf) =>
      (statuses.isEmpty || statuses.contains(t.status)) &&
      (agent == null || t.createdById == agent) &&
      (workspace == null || workspaceOf(t) == workspace);
}

/// Tasks that are not finished, for the header's "N open".
int openTaskCount(Iterable<TaskItem> tasks) =>
    tasks.where((t) => !t.status.isTerminal).length;
