import 'package:flutter/material.dart';

import '../../api.dart';
import '../../models.dart';
import '../../motion.dart';
import '../../platform.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../../desktop_layout.dart';
import '../list_search_field.dart';
import '../mobile_chrome.dart' show MobileBackBar;
import '../shell_nav.dart';
import 'create_task_form.dart';
import 'task_common.dart';
import 'task_detail_screen.dart';
import 'task_list.dart';

/// A pushed Tasks page, optionally limited to the tasks [agentIds] are on.
Future<void> openTasksPage(BuildContext context, DaemonClient client,
    {Set<String>? agentIds}) {
  return Navigator.of(context).push<void>(MaterialPageRoute(
    builder: (page) => Material(
      color: AppColors.bg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MobileBackBar(
              title: 'Tasks',
              onBack: () => Navigator.of(page).pop(),
            ),
            Expanded(
              child: TasksPanel(
                client: client,
                phoneHeader: false,
                agentIds: agentIds,
              ),
            ),
          ],
        ),
      ),
    ),
  ));
}

/// Open tasks the given agents are on, counted once each.
Future<int> openTaskCountFor(DaemonClient client, Iterable<String> agentIds) async {
  const open = {
    TaskStatus.todo,
    TaskStatus.inProgress,
    TaskStatus.inReview,
    TaskStatus.blocked,
  };
  final lists = await Future.wait(
      [for (final a in agentIds) client.tasks(agentId: a, limit: 500)]);
  return {
    for (final l in lists)
      for (final t in l)
        if (open.contains(t.status)) t.id,
  }.length;
}

class TasksPanel extends StatefulWidget {
  const TasksPanel({
    super.key,
    required this.client,
    this.trailing = const [],
    this.phoneHeader = true,
    this.onOpenTask,
    this.agentIds,
  });

  final DaemonClient client;

  /// Only tasks these agents are on; null shows every task.
  final Set<String>? agentIds;
  final List<Widget> trailing;
  final bool phoneHeader;

  /// Desktop: open a picked task elsewhere (a tab) instead of in the panel.
  final void Function(TaskItem task)? onOpenTask;

  @override
  State<TasksPanel> createState() => TasksPanelState();
}

class TasksPanelState extends State<TasksPanel> {
  late TaskFeed _feed = TaskFeed(widget.client, onChange: _sync);

  final _search = TextEditingController();
  bool _searchOpen = kMobile;
  DateTime? _shownAt;
  String _query = '';
  Set<TaskStatus> _filter = {};
  String? _selectedTaskId;
  bool _creatingTask = false;
  Map<String, String> _sessionFolders = const {};
  Set<String>? _agentTaskIds;

  List<TaskItem> get _tasks {
    if (widget.agentIds == null) return _feed.tasks;
    final ids = _agentTaskIds;
    if (ids == null) return const [];
    return _feed.tasks.where((t) => ids.contains(t.id)).toList();
  }

  @override
  void initState() {
    super.initState();
    _loadFolders();
    _loadAgentTasks();
  }

  Future<void> _loadAgentTasks() async {
    final agents = widget.agentIds;
    if (agents == null) return;
    try {
      final lists = await Future.wait(
          [for (final a in agents) widget.client.tasks(agentId: a, limit: 500)]);
      if (!mounted) return;
      setState(() => _agentTaskIds = {
            for (final l in lists)
              for (final t in l) t.id,
          });
    } catch (_) {
      if (mounted) setState(() => _agentTaskIds = const {});
    }
  }

  @override
  void didUpdateWidget(covariant TasksPanel oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) {
      _feed.dispose();
      _feed = TaskFeed(widget.client, onChange: _sync);
      _selectedTaskId = null;
      _creatingTask = false;
    }
  }

  void _sync() {
    if (mounted) setState(() {});
  }

  /// session id → last path segment, for the phone card meta line. Best
  /// effort: an unreachable daemon just leaves the line shorter.
  Future<void> _loadFolders() async {
    try {
      final sessions = await widget.client.sessions();
      if (!mounted) return;
      setState(() => _sessionFolders = {
            for (final s in sessions)
              s.id: s.projectFolder.split('/').where((p) => p.isNotEmpty).last,
          });
    } catch (_) {}
  }

  @override
  void dispose() {
    _feed.dispose();
    _search.dispose();
    super.dispose();
  }

  Future<void> create() async {
    if (!kMobile) {
      setState(() {
        _creatingTask = true;
        _selectedTaskId = null;
      });
      return;
    }
    if (await showCreateTask(context, widget.client)) await _feed.refresh();
  }

  Future<void> _open(TaskItem task) async {
    if (!kMobile && widget.onOpenTask != null) {
      widget.onOpenTask!(task);
      return;
    }
    if (!kMobile) {
      setState(() {
        _selectedTaskId = task.id;
        _creatingTask = false;
      });
      return;
    }
    await openTaskDetail(context, widget.client, task.id);
    if (mounted) await _feed.refresh();
  }

  static const _active = {TaskStatus.todo, TaskStatus.inProgress};
  static const _stuck = {TaskStatus.blocked, TaskStatus.failed};

  Widget _statusStrip() {
    final tasks = _tasks;
    int count(Set<TaskStatus> s) =>
        tasks.where((t) => s.contains(t.status)).length;
    final tabs = <(String, Set<TaskStatus>)>[
      ('All', const {}),
      ('Active', _active),
      ('Blocked', _stuck),
      ('Done', const {TaskStatus.done}),
      if (count(const {TaskStatus.cancelled}) > 0)
        ('Cancelled', const {TaskStatus.cancelled}),
    ];
    bool same(Set<TaskStatus> a, Set<TaskStatus> b) =>
        a.length == b.length && a.containsAll(b);
    if (kMobile) {
      // v5 `.pseg`:Needs you / Working / Queued / Done. Tapping the lit chip
      // again clears back to all.
      const needsYou = {
        TaskStatus.inReview,
        TaskStatus.blocked,
        TaskStatus.failed,
      };
      final chips = <(String, Set<TaskStatus>)>[
        ('Needs you', needsYou),
        ('Working', const {TaskStatus.inProgress}),
        ('Queued', const {TaskStatus.todo}),
        ('Done', const {TaskStatus.done}),
      ];
      return SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
        child: Row(children: [
          for (final (label, set) in chips) ...[
            _FilterChip(
              label: label,
              count: count(set),
              on: same(_filter, set),
              onTap: () => setState(() {
                _filter = same(_filter, set) ? const {} : {...set};
                _shownAt = null;
              }),
            ),
            const SizedBox(width: 6),
          ],
        ]),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (final (label, set) in tabs) ...[
          Material(
            color: same(_filter, set) ? AppColors.surface2 : Colors.transparent,
            borderRadius: BorderRadius.circular(6),
            child: InkWell(
              borderRadius: BorderRadius.circular(6),
              onTap: () => setState(() {
                _filter = {...set};
                _shownAt = null;
              }),
              child: Container(
                height: 26,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(label,
                      style: sans(12,
                          weight: same(_filter, set) ? W.label : W.body,
                          color: same(_filter, set)
                              ? AppColors.fg1
                              : AppColors.fg3)),
                  const SizedBox(width: 5),
                  Text('${set.isEmpty ? tasks.length : count(set)}',
                      style: mono(11, color: AppColors.fg4)),
                ]),
              ),
            ),
          ),
          const SizedBox(width: 2),
        ],
      ]),
    );
  }

  void _toggleSearch() {
    setState(() {
      _searchOpen = !_searchOpen;
      if (!_searchOpen) {
        _search.clear();
        _query = '';
      }
    });
  }

  Widget _desktopBackHeader(String title, VoidCallback onBack) => Padding(
        padding: const EdgeInsets.fromLTRB(6, 8, 10, 4),
        child: Row(children: [
          IconBtn(
            'chevron-left',
            size: 28,
            iconSize: 15,
            tooltip: 'Back',
            onTap: onBack,
          ),
          const SizedBox(width: 4),
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(13, weight: W.label, color: AppColors.fg1)),
          ),
        ]),
      );

  static const _wideMin = 900.0;

  @override
  Widget build(BuildContext context) {
    if (kMobile) return _stacked();
    return LayoutBuilder(
      builder: (context, c) => c.maxWidth >= _wideMin ? _wide() : _stacked(),
    );
  }

  Widget _desktopSearch() => Container(
        height: 32,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(children: [
          AppIcon('search', size: 14, color: AppColors.fg4),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: _search,
              autofocus: true,
              onChanged: (v) => setState(() => _query = v),
              style: sans(13, color: AppColors.fg1),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: 'Search tasks',
                hintStyle: sans(13, color: AppColors.fg4),
              ),
            ),
          ),
          if (_query.isNotEmpty)
            IconBtn('x',
                size: 20,
                iconSize: 10,
                tooltip: 'Clear',
                onTap: () {
                  _search.clear();
                  setState(() => _query = '');
                }),
        ]),
      );

  Widget _wide() {
    final list = TaskList(
      appearSince: _shownAt,
      tasks: _tasks,
      query: _query,
      filter: _filter,
      selectedId: _selectedTaskId,
      onOpen: _open,
      onRefresh: _feed.refresh,
      hasMore: _feed.hasMore,
      onLoadMore: _feed.loadMore,
    );
    final error = _feed.error;
    Widget? empty;
    var rows = const <Widget>[];
    if (_feed.loading) {
      empty = Center(child: Spinner(size: 20, color: AppColors.fg3));
    } else if (error != null) {
      empty = Column(mainAxisSize: MainAxisSize.min, children: [
        Text('Could not load tasks', style: sans(13, color: AppColors.fg2)),
        const SizedBox(height: 10),
        Btn('Retry', small: true, onTap: _feed.refresh),
      ]);
    } else {
      _shownAt ??= _tasks.isNotEmpty ? DateTime.now() : null;
      rows = list.rows();
      empty = list.emptyState();
    }
    final Widget detail;
    if (_creatingTask) {
      detail = Align(
        alignment: Alignment.topLeft,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 680),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(
                    S.s40, S.s32, S.s40, S.s16),
                child: Text('New task',
                    style: sans(20,
                        weight: W.strong,
                        spacing: -0.2,
                        color: AppColors.fg1)),
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 28),
                  child: CreateTaskForm(
                    client: widget.client,
                    onCreated: () {
                      setState(() => _creatingTask = false);
                      _feed.refresh();
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    } else if (_selectedTaskId != null) {
      detail = TaskDetailScreen(
        key: ValueKey('pane-task-$_selectedTaskId'),
        client: widget.client,
        taskId: _selectedTaskId!,
        pane: true,
      );
    } else {
      detail = const DetailEmpty('Select a task');
    }
    final master = MasterPane(
          title: 'Tasks',
          actions: [
            IconBtn('search',
                size: 28,
                iconSize: 15,
                active: _searchOpen,
                tooltip: 'Search tasks',
                onTap: _toggleSearch),
            const SizedBox(width: S.s4),
            HeaderAction('New task', onTap: create),
            ...widget.trailing,
          ],
          search: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_searchOpen) _desktopSearch(),
              if (_tasks.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: S.s4),
                  child: _statusStrip(),
                ),
            ],
          ),
          empty: empty,
          children: rows,
        );
    // Tasks open in their own tab, so a detail pane would stay empty: give
    // the list the room instead.
    if (widget.onOpenTask != null) {
      return ColoredBox(
        color: kMobile ? AppColors.bg : Colors.transparent,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040), child: master),
        ),
      );
    }
    return ColoredBox(
      color: kMobile ? AppColors.bg : Colors.transparent,
      child: MasterDetail(masterWidth: 380, master: master, detail: detail),
    );
  }

  Widget _stacked() {
    if (!kMobile && _selectedTaskId != null) {
      return ColoredBox(
        color: kMobile ? AppColors.bg : Colors.transparent,
        child: TaskDetailScreen(
          key: ValueKey('sidebar-task-$_selectedTaskId'),
          client: widget.client,
          taskId: _selectedTaskId!,
          embedded: true,
          onClose: () {
            setState(() => _selectedTaskId = null);
            _feed.refresh();
          },
        ),
      );
    }
    if (!kMobile && _creatingTask) {
      return ColoredBox(
        color: kMobile ? AppColors.bg : Colors.transparent,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _desktopBackHeader(
                'New task', () => setState(() => _creatingTask = false)),
            Expanded(
              child: CreateTaskForm(
                client: widget.client,
                onCreated: () {
                  setState(() => _creatingTask = false);
                  _feed.refresh();
                },
              ),
            ),
          ],
        ),
      );
    }
    return ColoredBox(
      color: kMobile ? AppColors.bg : Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (kMobile && widget.phoneHeader) _phoneHeader(),
          if (!kMobile) _desktopHeader(),
          if (_searchOpen)
            kMobile
                ? Padding(
                    padding: const EdgeInsets.fromLTRB(
                        M.gutter, 2, M.gutter, 4),
                    child: ListSearchField(
                      controller: _search,
                      hint: 'Search tasks',
                      onChanged: (v) => setState(() => _query = v),
                    ),
                  )
                : Padding(
                    padding: const EdgeInsets.fromLTRB(10, 4, 10, 6),
                    child: Container(
                      height: 32,
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      decoration: BoxDecoration(
                        color: AppColors.surface1,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: Row(children: [
                        AppIcon('search', size: 14, color: AppColors.fg4),
                        const SizedBox(width: 8),
                        Expanded(
                          child: TextField(
                            controller: _search,
                            autofocus: true,
                            onChanged: (v) => setState(() => _query = v),
                            style: sans(13, color: AppColors.fg1),
                            decoration: InputDecoration(
                              isCollapsed: true,
                              border: InputBorder.none,
                              hintText: 'Search tasks',
                              hintStyle: sans(13, color: AppColors.fg4),
                            ),
                          ),
                        ),
                        if (_query.isNotEmpty)
                          IconBtn('x',
                              size: 20,
                              iconSize: 10,
                              tooltip: 'Clear',
                              onTap: () {
                                _search.clear();
                                setState(() => _query = '');
                              }),
                      ]),
                    ),
                  ),
          if (_tasks.isNotEmpty)
            Padding(
              padding: kMobile
                  ? const EdgeInsets.fromLTRB(M.gutter, 0, M.gutter, 0)
                  : const EdgeInsets.fromLTRB(10, 2, 10, 4),
              child: _statusStrip(),
            ),
          Expanded(
            child: Swap(
              stateKey: _feed.loading
                  ? 'loading'
                  : (_feed.error != null ? 'error' : 'list'),
              child: _body(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _phoneHeader() => Padding(
        padding: const EdgeInsets.fromLTRB(M.gutter, 16, M.gutter, 6),
        child: Row(children: [
          Text('Tasks', style: TS.pageTitle()),
          const Spacer(),
          ...widget.trailing,
        ]),
      );

  Widget _desktopHeader() => ShellSectionHeader(
        label: 'Tasks',
        actions: [
          ShellSectionAction(
              icon: 'search',
              tooltip: 'Search tasks',
              active: _searchOpen,
              onTap: _toggleSearch),
          ShellSectionAction(icon: 'plus', tooltip: 'New task', onTap: create),
        ],
      );

  Widget _body() {
    if (_feed.loading) {
      return Center(
        child: kMobile
            ? const AppLoading(label: 'Loading tasks')
            : Spinner(size: 20, color: AppColors.fg3),
      );
    }
    final error = _feed.error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Could not load tasks',
                textAlign: TextAlign.center,
                style: sans(13, color: AppColors.fg2)),
            const SizedBox(height: 10),
            Btn('Retry', small: true, onTap: _feed.refresh),
          ]),
        ),
      );
    }
    if (_tasks.isNotEmpty) _shownAt ??= DateTime.now();
    return TaskList(
      appearSince: _shownAt,
      tasks: _tasks,
      query: _query,
      filter: _filter,
      onOpen: _open,
      onRefresh: _feed.refresh,
      hasMore: _feed.hasMore,
      onLoadMore: _feed.loadMore,
      sessionFolders: _sessionFolders,
      padding: kMobile
          ? const EdgeInsets.fromLTRB(M.gutter, 4, M.gutter, 16)
          : const EdgeInsets.fromLTRB(10, 2, 10, 16),
    );
  }
}

/// One v5 `.pseg` filter chip: 32px pill, surface fill, lit when [on].
class _FilterChip extends StatelessWidget {
  const _FilterChip({
    required this.label,
    required this.count,
    required this.on,
    required this.onTap,
  });

  final String label;
  final int count;
  final bool on;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion.fast,
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: on ? AppColors.surface3 : AppColors.surface2,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Text('$label $count',
                style: sans(14, color: on ? AppColors.fg1 : AppColors.fg3)),
          ]),
        ),
      );
}
