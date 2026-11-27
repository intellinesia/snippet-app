import 'package:flutter/material.dart';

import '../mobile_kit.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';

enum _NewAction { session, agent, group, shell, task }

/// Opens the desktop "New" popover below [anchor] and runs the chosen callback.
/// [recentProjects] are folder paths; picking one calls [onNewSessionIn].
Future<void> showNewMenu(
  BuildContext anchor, {
  required VoidCallback onNewSession,
  required VoidCallback onNewAgent,
  required VoidCallback onNewGroup,
  VoidCallback? onNewShell,
  VoidCallback? onNewTask,
  List<String> recentProjects = const [],
  ValueChanged<String>? onNewSessionIn,
}) async {
  Widget key(String text) => Text(text, style: mono(11, color: AppColors.fg4));
  final projects = recentProjects.take(5).toList();
  final picked = await showAppMenu<Object>(
    anchor,
    anchor: anchor,
    below: true,
    minWidth: 330,
    maxWidth: 330,
    items: [
      appMenuRow<Object>(
        value: _NewAction.session,
        icon: 'chat',
        label: 'New session',
        description: 'Pick a project, agent and model',
        trailingWidget: kMobile ? null : key(kMacOS ? '⌘ N' : 'Ctrl N'),
        height: 50,
      ),
      appMenuRow<Object>(
        value: _NewAction.agent,
        icon: 'bot',
        label: 'New agent',
        description: 'A specialist with its own model and memory',
        height: 50,
      ),
      appMenuRow<Object>(
        value: _NewAction.group,
        icon: 'users',
        label: 'New group',
        description: 'Several agents in one conversation',
        height: 50,
      ),
      if (onNewShell != null || onNewTask != null)
        const PopupMenuDivider(height: 9),
      if (onNewShell != null)
        appMenuRow<Object>(
            value: _NewAction.shell, icon: 'terminal', label: 'New shell'),
      if (onNewTask != null)
        appMenuRow<Object>(
            value: _NewAction.task, icon: 'kanban', label: 'New task'),
      if (projects.isNotEmpty && onNewSessionIn != null) ...[
        appMenuHeading<Object>('New session in'),
        for (final p in projects)
          appMenuRow<Object>(
            value: p,
            icon: 'folder',
            label: lastPathSegment(p, ifEmpty: p),
            trailingWidget: key(_parentOf(p)),
          ),
      ],
    ],
  );
  switch (picked) {
    case _NewAction.session:
      onNewSession();
    case _NewAction.agent:
      onNewAgent();
    case _NewAction.group:
      onNewGroup();
    case _NewAction.shell:
      onNewShell?.call();
    case _NewAction.task:
      onNewTask?.call();
    case final String folder:
      onNewSessionIn?.call(folder);
    default:
  }
}

String _parentOf(String path) {
  final i = path.lastIndexOf('/');
  var parent = i > 0 ? path.substring(0, i) : '/';
  parent = parent.replaceFirst(RegExp(r'^/(home|Users)/[^/]+'), '~');
  return parent.isEmpty ? '~' : parent;
}

/// The phone New sheet behind the one create button: New session across
/// the top, the other kinds as a grid of pills.
Future<void> showNewSheet(
  BuildContext context, {
  required VoidCallback onNewSession,
  required VoidCallback onNewAgent,
  required VoidCallback onNewGroup,
  VoidCallback? onNewShell,
  VoidCallback? onNewTask,
}) async {
  final rows = <(_NewAction, String, String)>[
    (_NewAction.agent, 'bot', 'New agent'),
    (_NewAction.group, 'users', 'New group'),
    if (onNewTask != null) (_NewAction.task, 'kanban', 'New task'),
    if (onNewShell != null) (_NewAction.shell, 'terminal', 'New shell'),
  ];
  final picked = await showMkSheet<_NewAction>(
    context,
    title: 'New',
    builder: (ctx) => _NewSheetBody(rows: rows),
  );
  switch (picked) {
    case _NewAction.session:
      onNewSession();
    case _NewAction.agent:
      onNewAgent();
    case _NewAction.group:
      onNewGroup();
    case _NewAction.shell:
      onNewShell?.call();
    case _NewAction.task:
      onNewTask?.call();
    default:
  }
}

class _NewSheetBody extends StatelessWidget {
  const _NewSheetBody({required this.rows});
  final List<(_NewAction, String, String)> rows;

  @override
  Widget build(BuildContext context) {
    void pick(_NewAction v) => Navigator.of(context).pop(v);
    Widget tile((_NewAction, String, String) r) =>
        MkSheetTile(icon: r.$2, label: r.$3, onTap: () => pick(r.$1));
    final pairs = <Widget>[];
    for (var i = 0; i < rows.length; i += 2) {
      pairs.add(Padding(
        padding: const EdgeInsets.only(top: 8),
        child: Row(children: [
          Expanded(child: tile(rows[i])),
          const SizedBox(width: 8),
          Expanded(
              child: i + 1 < rows.length
                  ? tile(rows[i + 1])
                  : const SizedBox()),
        ]),
      ));
    }
    return SingleChildScrollView(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          MkBigButton('New session',
              icon: 'chat', onTap: () => pick(_NewAction.session)),
          const SizedBox(height: 4),
          ...pairs,
        ],
      ),
    );
  }
}
