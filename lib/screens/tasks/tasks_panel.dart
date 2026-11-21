import 'package:flutter/material.dart';

import '../../api.dart';
import '../../models.dart';
import '../../motion.dart';
import '../../motion_routes.dart';
import '../../platform.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../../desktop_layout.dart';
import '../mobile_chrome.dart' show MobileBackBar;
import '../shell_nav.dart';
import 'create_task_form.dart';
import 'task_common.dart';
import 'task_detail_screen.dart';
import 'task_list.dart';
import '../../tap_detector.dart';

/// A pushed Tasks page, optionally limited to the tasks [agentIds] are on.
Future<void> openTasksPage(BuildContext context, DaemonClient client,
    {Set<String>? agentIds}) {
  final panel = GlobalKey<TasksPanelState>();
  return Navigator.of(context).push<void>(AppPageRoute<void>(
    builder: (page) => Material(
      color: AppColors.paneBg,
      child: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MobileBackBar(
              title: 'Tasks',
              onBack: () => Navigator.of(page).pop(),
              trailing: [
                newTaskPill(() => panel.currentState?.create()),
              ],
            ),
            Expanded(
              child: TasksPanel(
                key: panel,
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

/// The "New task" pill on a pushed Tasks page's back bar.
Widget newTaskPill(VoidCallback onTap) => TapDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: 44,
        child: Center(
          child: Container(
            height: 32,
            padding: EdgeInsets.symmetric(horizontal: S.s12),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(R.of(16)),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AppIcon('plus', size: 14, color: AppColors.fg1),
              SizedBox(width: S.s6),
              Text('New task', style: sans(13, color: AppColors.fg1)),
            ]),
          ),
        ),
      ),
    );

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
  bool _searchOpen = !kMobile;
  TaskTab _tab = TaskTab.active;
  DateTime? _shownAt;
  String _query = '';
  Set<TaskStatus> _filter = {};
  String? _selectedTaskId;
  bool _creatingTask = false;
  Map<String, String> _sessionFolders = const {};
  Map<String, String> _agentNames = const {};
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
    _loadAgentNames();
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

  Future<void> _loadAgentNames() async {
    try {
      final agents = await widget.client.coordinationAgents();
      if (!mounted) return;
      setState(() => _agentNames = {
            for (final a in agents)
              if (a.displayName.trim().isNotEmpty) a.id: a.displayName.trim(),
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

  Widget _statusStrip() {
    final tasks = _tasks;
    int count(Set<TaskStatus> s) =>
        tasks.where((t) => s.contains(t.status)).length;
    bool same(Set<TaskStatus> a, Set<TaskStatus> b) =>
        a.length == b.length && a.containsAll(b);
    // Tapping the lit chip again clears back to all.
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
      if (count(const {TaskStatus.cancelled}) > 0)
        ('Cancelled', const {TaskStatus.cancelled}),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: EdgeInsets.fromLTRB(0, S.s4, 0, S.s8),
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
          SizedBox(width: S.s6),
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
        padding: EdgeInsets.fromLTRB(S.s6, S.s8, S.of(10), S.s4),
        child: Row(children: [
          IconBtn(
            'chevron-left',
            size: 28,
            iconSize: 15,
            tooltip: 'Back',
            onTap: onBack,
          ),
          SizedBox(width: S.s4),
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

  /// 36px field inside a 44px hit area.
  Widget _phoneSearch() => SizedBox(
        height: 44,
        child: Center(
          child: Container(
            height: 36,
            padding: EdgeInsets.symmetric(horizontal: S.s12),
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(R.md),
              border: Border.all(color: AppColors.line),
            ),
            child: Row(children: [
              AppIcon('search', size: 14, color: AppColors.fg4),
              SizedBox(width: S.s8),
              Expanded(
                child: TextField(
                  controller: _search,
                  onChanged: (v) => setState(() => _query = v),
                  textInputAction: TextInputAction.search,
                  cursorColor: AppColors.accent,
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
                TapDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    _search.clear();
                    setState(() => _query = '');
                  },
                  child: AppIcon('x', size: 14, color: AppColors.fg3),
                ),
            ]),
          ),
        ),
      );

  Widget _desktopSearch() => Container(
        height: 32,
        padding: EdgeInsets.symmetric(horizontal: S.s8),
        decoration: BoxDecoration(
          color: AppColors.tint1,
          borderRadius: BorderRadius.circular(R.md),
          border: Border.all(color: AppColors.line),
        ),
        child: Row(children: [
          AppIcon('search', size: 14, color: AppColors.fg4),
          SizedBox(width: S.s8),
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
        SizedBox(height: S.of(10)),
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
                padding: EdgeInsets.fromLTRB(
                    S.s40, S.s32, S.s40, S.s16),
                child: Text('New task',
                    style: sans(kMobile ? 20 : 16,
                        weight: W.strong,
                        spacing: -0.2,
                        color: AppColors.fg1)),
              ),
              Expanded(
                child: Padding(
                  padding: EdgeInsets.symmetric(horizontal: S.of(28)),
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
            SizedBox(width: S.s4),
            HeaderAction('New task', onTap: create),
            ...widget.trailing,
          ],
          search: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_searchOpen) _desktopSearch(),
              if (_tasks.isNotEmpty)
                Padding(
                  padding: EdgeInsets.only(top: S.s4),
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
        color: kMobile ? AppColors.pageBg : Colors.transparent,
        child: Align(
          alignment: Alignment.topCenter,
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 1040), child: master),
        ),
      );
    }
    return ColoredBox(
      color: kMobile ? AppColors.pageBg : Colors.transparent,
      child: MasterDetail(masterWidth: 380, master: master, detail: detail),
    );
  }

  Widget _stacked() {
    if (!kMobile && _selectedTaskId != null) {
      return ColoredBox(
        color: kMobile ? AppColors.pageBg : Colors.transparent,
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
        color: kMobile ? AppColors.pageBg : Colors.transparent,
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
      color: kMobile ? AppColors.pageBg : Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (kMobile && widget.phoneHeader) _phoneHeader(),
          if (!kMobile) _desktopHeader(),
          if (kMobile) _phoneTabs(),
          if (_searchOpen)
            kMobile
                ? Padding(
                    padding: EdgeInsets.fromLTRB(
                        M.gutter, S.s2, M.gutter, S.s4),
                    child: _phoneSearch(),
                  )
                : Padding(
                    padding: EdgeInsets.fromLTRB(S.of(10), S.s4, S.of(10), S.s6),
                    child: Container(
                      height: 32,
                      padding: EdgeInsets.symmetric(horizontal: S.s8),
                      decoration: BoxDecoration(
                        color: AppColors.tint1,
                        borderRadius: BorderRadius.circular(R.md),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: Row(children: [
                        AppIcon('search', size: 14, color: AppColors.fg4),
                        SizedBox(width: S.s8),
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
          if (_tasks.isNotEmpty && !kMobile)
            Padding(
              padding: kMobile
                  ? EdgeInsets.fromLTRB(M.gutter, 0, M.gutter, 0)
                  : EdgeInsets.fromLTRB(S.of(10), S.s2, S.of(10), S.s4),
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

  Future<void> _complete(TaskItem task) async {
    final ok = await confirmAction(context,
        title: 'Mark as done?',
        body: task.title,
        confirmLabel: 'Mark done',
        danger: false);
    if (!ok || !mounted) return;
    try {
      await widget.client.setTaskStatus(task.id, TaskStatus.done);
      await _feed.refresh();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    }
  }

  Widget _phoneTabs() {
    Widget tab(String label, TaskTab t) {
      final on = _tab == t;
      return TapDetector(
        key: ValueKey('tab-${t.name}'),
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() {
          _tab = t;
          _shownAt = null;
        }),
        child: Text(label,
            style: sans(kMobile ? 26 : 18,
                weight: on ? W.label : W.body,
                spacing: -0.3,
                color: on ? AppColors.fg1 : AppColors.fg3)),
      );
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 12, 0),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        tab('Active', TaskTab.active),
        const SizedBox(width: 20),
        tab('Up next', TaskTab.upNext),
        const Spacer(),
        IconBtn('search',
            size: 44,
            iconSize: 20,
            tooltip: 'Search tasks',
            active: _searchOpen,
            onTap: _toggleSearch),
      ]),
    );
  }

  /// A pushed page (from a session's tools) gets the back bar and New task;
  /// the Tasks tab keeps its large title.
  Widget _phoneHeader() {
    final nav = Navigator.maybeOf(context);
    if (nav != null && nav.canPop()) {
      return MobileBackBar(
        title: 'Tasks',
        onBack: () => nav.maybePop(),
        trailing: [newTaskPill(create), ...widget.trailing],
      );
    }
    return Padding(
      padding: EdgeInsets.fromLTRB(M.gutter, S.s16, M.gutter, S.s6),
      child: Row(children: [
        Text('Tasks', style: TS.pageTitle()),
        const Spacer(),
        ...widget.trailing,
      ]),
    );
  }

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
          padding: EdgeInsets.all(S.s24),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text('Could not load tasks',
                textAlign: TextAlign.center,
                style: sans(13, color: AppColors.fg2)),
            SizedBox(height: S.of(10)),
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
      agentNames: _agentNames,
      phoneTab: _tab,
      onComplete: _complete,
      padding: kMobile
          ? EdgeInsets.fromLTRB(M.gutter, S.s4, M.gutter, S.s16)
          : EdgeInsets.fromLTRB(S.of(10), S.s2, S.of(10), S.s16),
    );
  }
}

/// One filter chip: pill on a surface, lit when [on], the count muted.
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
  Widget build(BuildContext context) {
    final h = kMobile ? 32.0 : 26.0;
    return TapDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: SizedBox(
        height: kMobile ? 44 : h,
        child: Center(child: AnimatedContainer(
        duration: Motion.fast,
        height: h,
        padding: EdgeInsets.symmetric(horizontal: kMobile ? S.s12 : S.s8),
        decoration: BoxDecoration(
          color: on
              ? (kMobile ? AppColors.surface3 : AppColors.tint2)
              : (kMobile ? AppColors.surface2 : AppColors.tint1),
          borderRadius: BorderRadius.circular(h / 2),
          border: Border.all(color: on ? AppColors.accent : AppColors.line),
        ),
        alignment: Alignment.center,
        child: Text.rich(TextSpan(children: [
          TextSpan(
              text: '$label ',
              style: sans(kMobile ? 13 : 12,
                  color: on ? AppColors.fg1 : AppColors.fg2)),
          TextSpan(
              text: '$count',
              style: sans(kMobile ? 13 : 12, color: AppColors.fg3)),
        ])),
      ))),
    );
  }
}
