import 'dart:async';

import 'package:flutter/material.dart';
import '../../empty_art.dart';
import '../../platform.dart';
import 'package:flutter/services.dart';

import '../../api.dart';
import '../../models.dart';
import '../../phosphor_icons.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../../tap_detector.dart';
import '../list_search_field.dart';
import 'create_task_form.dart';
import 'task_common.dart';
import 'task_detail_screen.dart';
import 'task_list.dart' show FoldedTasks;
import 'task_rows.dart';
import 'task_view.dart';

/// The desktop Tasks list: grouped dense rows on the left, the selected task
/// in a 470pt pane on the right. Keys: J/K move, Enter opens in a tab, X
/// selects, S status, A assign, C new, / search, Esc clears.
class TaskListView extends StatefulWidget {
  const TaskListView({super.key, required this.client, this.viewToggle});

  final DaemonClient client;
  final Widget? viewToggle;

  @override
  State<TaskListView> createState() => _TaskListViewState();
}

class _TaskListViewState extends State<TaskListView> {
  late final TaskFeed _feed = TaskFeed(widget.client, onChange: _sync);
  final _search = TextEditingController();
  final _searchFocus = FocusNode(debugLabel: 'tasks-search');
  final _keys = FocusNode(debugLabel: 'tasks-keys');
  final _rowKeys = <String, GlobalKey>{};
  final _bulkKey = GlobalKey();

  bool _searching = false;
  String _query = '';
  TaskFilter _filter = const TaskFilter();
  TaskSort _sort = TaskSort.updated;
  String? _selected;
  final Set<String> _checked = {};
  bool _creating = false;
  Map<String, String> _agentNames = const {};
  Map<String, SessionInfo> _sessions = const {};

  @override
  void initState() {
    super.initState();
    unawaited(_loadContext());
  }

  @override
  void dispose() {
    _feed.dispose();
    _search.dispose();
    _searchFocus.dispose();
    _keys.dispose();
    super.dispose();
  }

  void _sync() {
    if (mounted) setState(() {});
  }

  Future<void> _loadContext() async {
    try {
      final agents = await widget.client.coordinationAgents();
      if (!mounted) return;
      setState(() => _agentNames = {
            for (final a in agents)
              if (a.displayName.trim().isNotEmpty) a.id: a.displayName.trim(),
          });
    } catch (_) {}
    try {
      final sessions = await widget.client.sessions();
      if (!mounted) return;
      setState(() => _sessions = {for (final s in sessions) s.id: s});
    } catch (_) {}
  }

  String _agent(String id) => _agentNames[id] ?? id;

  String _workspace(TaskItem t) {
    final f = _sessions[t.sessionId]?.projectFolder ?? '';
    return lastPathSegment(f);
  }

  List<TaskItem> get _visible => [
        for (final t in _feed.tasks)
          if (taskMatches(t, _query) && _filter.matches(t, _workspace)) t
      ];

  GlobalKey _rowKey(String id) => _rowKeys.putIfAbsent(id, GlobalKey.new);

  // Menus ---------------------------------------------------------------

  Future<void> _setStatus(Iterable<TaskItem> tasks, BuildContext anchor,
      {TaskStatus? current}) async {
    final picked = await showAppMenu<TaskStatus>(context,
        anchor: anchor,
        below: true,
        minWidth: 180,
        maxWidth: 220,
        items: [
          for (final s in taskGroupOrder.take(5))
            appMenuItem<TaskStatus>(
                value: s, label: s.label, selected: s == current),
        ]);
    if (picked == null || !mounted) return;
    try {
      for (final t in tasks) {
        if (t.status != picked) await widget.client.setTaskStatus(t.id, picked);
      }
      setState(_checked.clear);
      await _feed.refresh();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    }
  }

  Future<void> _filterMenu(BuildContext anchor) async {
    final agents = {for (final t in _feed.tasks) t.createdById}..remove('');
    final spaces = {for (final t in _feed.tasks) _workspace(t)}..remove('');
    final picked = await showAppMenu<String>(context,
        anchor: anchor,
        below: true,
        minWidth: 220,
        maxWidth: 280,
        items: [
          appMenuHeading<String>('Status'),
          for (final s in taskGroupOrder.take(5))
            appMenuItem<String>(
                value: 's:${s.name}',
                label: s.label,
                selected: _filter.statuses.contains(s)),
          if (agents.isNotEmpty) appMenuHeading<String>('Agent'),
          for (final a in agents)
            appMenuItem<String>(
                value: 'a:$a', label: _agent(a), selected: _filter.agent == a),
          if (spaces.isNotEmpty) appMenuHeading<String>('Workspace'),
          for (final w in spaces)
            appMenuItem<String>(
                value: 'w:$w', label: w, selected: _filter.workspace == w),
        ]);
    if (picked == null || !mounted) return;
    final key = picked.substring(2);
    setState(() {
      switch (picked[0]) {
        case 's':
          final s = TaskStatus.values.byName(key);
          final next = {..._filter.statuses};
          next.contains(s) ? next.remove(s) : next.add(s);
          _filter = _filter.copyWith(statuses: next);
        case 'a':
          _filter = _filter.agent == key
              ? _filter.copyWith(clearAgent: true)
              : _filter.copyWith(agent: key);
        case 'w':
          _filter = _filter.workspace == key
              ? _filter.copyWith(clearWorkspace: true)
              : _filter.copyWith(workspace: key);
      }
    });
  }

  Future<void> _sortMenu(BuildContext anchor) async {
    final picked = await showAppMenu<TaskSort>(context,
        anchor: anchor,
        below: true,
        alignEnd: true,
        minWidth: 150,
        maxWidth: 200,
        items: [
          for (final s in TaskSort.values)
            appMenuItem<TaskSort>(
                value: s, label: s.label, selected: s == _sort),
        ]);
    if (picked != null && mounted) setState(() => _sort = picked);
  }

  Future<void> _assign(TaskItem t, BuildContext anchor) async {
    final ids = _agentNames.keys.toList();
    if (ids.isEmpty) return;
    final picked = await showAppMenu<String>(context,
        anchor: anchor,
        below: true,
        minWidth: 200,
        maxWidth: 260,
        items: [
          appMenuHeading<String>('Assign to'),
          for (final id in ids)
            appMenuItem<String>(value: id, label: _agent(id)),
        ]);
    if (picked == null || !mounted) return;
    try {
      await widget.client.addTaskAgent(t.id, picked);
      if (mounted) toast(context, 'Assigned to ${_agent(picked)}');
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    }
  }

  // Keys ----------------------------------------------------------------

  List<TaskItem> get _ordered => flatTasks(groupTasks(_visible, _sort));

  TaskItem? get _current =>
      _ordered.where((t) => t.id == _selected).firstOrNull;

  void _openSearch() {
    setState(() => _searching = true);
    WidgetsBinding.instance
        .addPostFrameCallback((_) => _searchFocus.requestFocus());
  }

  void _closeSearch() {
    _search.clear();
    setState(() {
      _searching = false;
      _query = '';
    });
    _keys.requestFocus();
  }

  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent) return KeyEventResult.ignored;
    if (HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isAltPressed) {
      return KeyEventResult.ignored;
    }
    final k = e.logicalKey;
    final list = _ordered;
    void move(int d) {
      final cur = list.indexWhere((t) => t.id == _selected);
      final next = moveSelection(cur, d, list.length);
      if (next >= 0) {
        setState(() {
          _selected = list[next].id;
          _creating = false;
        });
      }
    }

    if (k == LogicalKeyboardKey.keyJ || k == LogicalKeyboardKey.arrowDown) {
      move(1);
    } else if (k == LogicalKeyboardKey.keyK ||
        k == LogicalKeyboardKey.arrowUp) {
      move(-1);
    } else if (k == LogicalKeyboardKey.enter) {
      final t = _current;
      if (t == null) return KeyEventResult.ignored;
      openTaskInTab?.call(widget.client, t.id);
    } else if (k == LogicalKeyboardKey.keyX) {
      final t = _current;
      if (t == null) return KeyEventResult.ignored;
      setState(() =>
          _checked.contains(t.id) ? _checked.remove(t.id) : _checked.add(t.id));
    } else if (k == LogicalKeyboardKey.keyS) {
      final t = _current;
      final ctx = (_checked.isNotEmpty ? _bulkKey : _rowKey(t?.id ?? ''))
          .currentContext;
      if (ctx == null) return KeyEventResult.ignored;
      final targets = _checked.isNotEmpty
          ? list.where((x) => _checked.contains(x.id))
          : [t!];
      unawaited(_setStatus(targets, ctx, current: t?.status));
    } else if (k == LogicalKeyboardKey.keyA) {
      final t = _current;
      final ctx = _rowKey(t?.id ?? '').currentContext;
      if (t == null || ctx == null) return KeyEventResult.ignored;
      unawaited(_assign(t, ctx));
    } else if (k == LogicalKeyboardKey.keyC) {
      setState(() => _creating = true);
    } else if (k == LogicalKeyboardKey.slash) {
      _openSearch();
    } else if (k == LogicalKeyboardKey.escape) {
      if (_checked.isNotEmpty) {
        setState(_checked.clear);
      } else if (_creating) {
        setState(() => _creating = false);
      } else if (_selected != null) {
        setState(() => _selected = null);
      } else {
        return KeyEventResult.ignored;
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  // Build ---------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final visible = _visible;
    final groups = groupTasks(visible, _sort);
    return Focus(
      focusNode: _keys,
      autofocus: true,
      onKeyEvent: _onKey,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        _top(),
        if (!_filter.isEmpty || _searching) _appliedBar(),
        Container(height: AppColors.hairline, color: AppColors.paneLine),
        Expanded(
          child: _feed.loading
              ? Center(child: Spinner(size: 20, color: AppColors.fg3))
              : _feed.error != null
                  ? Center(
                      child: Column(mainAxisSize: MainAxisSize.min, children: [
                        Text('Could not load tasks',
                            style: sans(13, color: AppColors.fg2)),
                        SizedBox(height: S.s8),
                        Btn('Retry', small: true, onTap: _feed.refresh),
                      ]),
                    )
                  : LayoutBuilder(builder: (context, c) {
                      final pane = c.maxWidth > 900 ? 470.0 : c.maxWidth * 0.45;
                      return Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(child: _list(groups)),
                            Container(width: AppColors.hairline, color: AppColors.paneLine),
                            SizedBox(width: pane, child: _pane()),
                          ]);
                    }),
        ),
      ]),
    );
  }

  Widget _top() => Container(
        height: PaneRow.height,
        padding: const EdgeInsets.fromLTRB(20, 0, 12, 0),
        child: Row(children: [
          Text('Tasks',
              style: sans(13, weight: W.label, color: taskTitleInk)),
          const SizedBox(width: 8),
          Text('${openTaskCount(_feed.tasks)} open',
              style: sans(12, color: AppColors.fg4)),
          const Spacer(),
          if (widget.viewToggle != null) ...[
            widget.viewToggle!,
            const SizedBox(width: 8),
          ],
          Builder(
              builder: (a) => _BarBtn(
                  label: 'Filter',
                  icon: PhIcons.slidersHorizontal,
                  onTap: () => _filterMenu(a))),
          const SizedBox(width: 6),
          Builder(
              builder: (a) => _BarBtn(
                  label: _sort.label,
                  icon: PhIcons.caretUpDown,
                  onTap: () => _sortMenu(a))),
          const SizedBox(width: 6),
          _BarBtn(
              label: 'New task',
              icon: PhIcons.plus,
              onTap: () => setState(() => _creating = true)),
        ]),
      );

  Widget _appliedBar() {
    Widget chip(String label, VoidCallback clear) => Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Container(
            height: 24,
            padding: const EdgeInsets.only(left: 10, right: 4),
            decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(kMobile ? 12 : R.of(6)),
                border: Border.all(color: taskHairline)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(label, style: sans(12, color: AppColors.fg2)),
              TapDetector(
                behavior: HitTestBehavior.opaque,
                onTap: clear,
                child: Padding(
                  padding: const EdgeInsets.all(4),
                  child: AppIcon('x', size: 10, color: AppColors.fg3),
                ),
              ),
            ]),
          ),
        );
    return Padding(
      padding: EdgeInsets.fromLTRB(S.s20, 0, S.s20, 8),
      child: Row(children: [
        if (_searching)
          SizedBox(
            width: 220,
            height: 28,
            child: ListSearchField(
              controller: _search,
              focusNode: _searchFocus,
              hint: 'Search tasks',
              onChanged: (v) => setState(() => _query = v),
            ),
          ),
        if (_searching) ...[
          const SizedBox(width: 4),
          IconBtn('x',
              size: 24,
              iconSize: 11,
              tooltip: 'Close search',
              onTap: _closeSearch),
          const SizedBox(width: 8),
        ],
        for (final s in _filter.statuses)
          chip(
              s.label,
              () => setState(() => _filter = _filter.copyWith(
                  statuses: {..._filter.statuses}..remove(s)))),
        if (_filter.agent != null)
          chip(
              'Agent: ${_agent(_filter.agent!)}',
              () =>
                  setState(() => _filter = _filter.copyWith(clearAgent: true))),
        if (_filter.workspace != null)
          chip(
              'Workspace: ${_filter.workspace}',
              () => setState(
                  () => _filter = _filter.copyWith(clearWorkspace: true))),
      ]),
    );
  }

  Widget _list(List<(TaskStatus, List<TaskItem>)> groups) {
    if (groups.isEmpty) {
      return TaskEmptyNote(
        title: _feed.tasks.isEmpty ? 'No tasks yet' : 'No tasks match',
        art: _feed.tasks.isEmpty ? EmptyArtKind.tasks : EmptyArtKind.search,
        body: _feed.tasks.isEmpty
            ? 'File a task and Lead routes it to a session.'
            : 'Try another search or clear the filter.',
      );
    }
    final out = <Widget>[];
    for (var g = 0; g < groups.length; g++) {
      final (status, items) = groups[g];
      out.add(TaskGroupHeader(status, items.length, first: g == 0));
      Widget row(TaskItem t) => KeyedSubtree(
            key: _rowKey(t.id),
            child: DenseTaskRow(
              task: t,
              selected: t.id == _selected,
              checked: _checked.contains(t.id),
              onTap: () => setState(() {
                _selected = t.id;
                _creating = false;
                _keys.requestFocus();
              }),
              onStatus: (a) => _setStatus([t], a, current: t.status),
            ),
          );
      if (status == TaskStatus.done && items.length > taskDoneVisible) {
        out.add(FoldedTasks(
            visible: [for (final t in items.take(taskDoneVisible)) row(t)],
            hidden: [for (final t in items.skip(taskDoneVisible)) row(t)]));
      } else {
        out.addAll(items.map(row));
      }
    }
    return Column(children: [
      Expanded(
        child: ListView(
            padding: EdgeInsets.fromLTRB(S.s8, 0, S.s8, S.s16), children: out),
      ),
      if (_checked.isNotEmpty) _bulkBar() else _hints(),
    ]);
  }

  Widget _bulkBar() => Container(
        key: _bulkKey,
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration:
            BoxDecoration(border: Border(top: BorderSide(color: AppColors.paneLine, width: AppColors.hairline))),
        child: Row(children: [
          Text('${_checked.length} selected',
              style: sans(12.5, weight: W.label, color: AppColors.fg1)),
          const Spacer(),
          Builder(
            builder: (a) => Btn('Set status',
                small: true,
                variant: BtnVariant.secondary,
                onTap: () => _setStatus(
                    _feed.tasks.where((t) => _checked.contains(t.id)), a)),
          ),
          const SizedBox(width: 8),
          Btn('Clear',
              small: true,
              variant: BtnVariant.ghost,
              onTap: () => setState(_checked.clear)),
        ]),
      );

  Widget _hints() => Container(
        height: 32,
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.symmetric(horizontal: 20),
        decoration:
            BoxDecoration(border: Border(top: BorderSide(color: AppColors.paneLine, width: AppColors.hairline))),
        child: Text(
            'J / K move   Enter open   X select   S status   A assign   C new   / search',
            style: sans(11.5, color: AppColors.fg4)),
      );

  Widget _pane() {
    if (_creating) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Padding(
          padding: EdgeInsets.fromLTRB(S.s20, S.s20, S.s20, 0),
          child: Text('New task',
              style: sans(13.5, weight: W.label, color: taskTitleInk)),
        ),
        SizedBox(height: S.s12),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: CreateTaskForm(
              client: widget.client,
              onCreated: () {
                setState(() => _creating = false);
                _feed.refresh();
              },
            ),
          ),
        ),
      ]);
    }
    final id = _selected;
    if (id == null) return const TaskEmptyNote(title: 'Select a task');
    return TaskDetailScreen(
      key: ValueKey('pane-task-$id'),
      client: widget.client,
      taskId: id,
      pane: true,
    );
  }
}

class _BarBtn extends StatelessWidget {
  const _BarBtn({required this.label, required this.icon, this.onTap});
  final String label;
  final IconData icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fg = AppColors.fg2;
    return TapDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: Container(
        height: 28,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(PaneRow.radius),
          border: Border.all(color: AppColors.paneLine, width: AppColors.hairline),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 12.5, color: fg),
          const SizedBox(width: 6),
          Text(label, style: sans(12.5, weight: W.label, color: fg)),
        ]),
      ),
    );
  }
}
