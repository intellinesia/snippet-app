import 'package:flutter/material.dart';

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

/// The phone New sheet behind the one create button: five one-line rows.
Future<void> showNewSheet(
  BuildContext context, {
  required VoidCallback onNewSession,
  required VoidCallback onNewAgent,
  required VoidCallback onNewGroup,
  VoidCallback? onNewShell,
  VoidCallback? onNewTask,
}) async {
  final dark = AppColors.bg.computeLuminance() < 0.5;
  final reduced = reduceMotion(context);
  final rows = <(_NewAction, String, String, String)>[
    (_NewAction.session, 'chat', 'New session', 'Start work with an agent'),
    (_NewAction.agent, 'bot', 'New agent', 'Add an agent to your roster'),
    (_NewAction.group, 'users', 'New group', 'Bring agents into one thread'),
    if (onNewShell != null)
      (_NewAction.shell, 'terminal', 'New shell', 'Open a terminal here'),
    if (onNewTask != null)
      (_NewAction.task, 'kanban', 'New task', 'Add work to the task list'),
  ];
  final picked = await showModalBottomSheet<_NewAction>(
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    backgroundColor: AppColors.surface1,
    barrierColor: Colors.black.withValues(alpha: dark ? 0.58 : 0.32),
    shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
    clipBehavior: Clip.antiAlias,
    constraints: BoxConstraints(
        maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        maxWidth: double.infinity),
    sheetAnimationStyle: AnimationStyle(
      duration: Duration(milliseconds: reduced ? 1 : 200),
      reverseDuration: Duration(milliseconds: reduced ? 1 : 200),
      curve: Curves.easeOut,
      reverseCurve: Curves.easeOut,
    ),
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
  final List<(_NewAction, String, String, String)> rows;

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.paddingOf(context).bottom;
    final screenH = MediaQuery.sizeOf(context).height;
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: (screenH * 0.45).clamp(0, screenH * 0.85)),
      child: FocusScope(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  margin: const EdgeInsets.only(top: 8),
                  width: 36,
                  height: 4,
                  decoration: BoxDecoration(
                      color: AppColors.surface3,
                      borderRadius: BorderRadius.circular(2)),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 13, 20, 8),
                child: Text('New',
                    style: sans(13, weight: W.label, color: AppColors.fg3)),
              ),
              for (var i = 0; i < rows.length; i++)
                _NewSheetRow(
                  rows[i].$1,
                  rows[i].$2,
                  rows[i].$3,
                  rows[i].$4,
                  autofocus: i == 0,
                  last: i == rows.length - 1,
                ),
              SizedBox(height: bottom + 8),
            ],
          ),
        ),
      ),
    );
  }
}

class _NewSheetRow extends StatelessWidget {
  const _NewSheetRow(this.value, this.icon, this.label, this.hint,
      {required this.autofocus, required this.last});

  final _NewAction value;
  final String icon, label, hint;
  final bool autofocus, last;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        hint: hint,
        excludeSemantics: true,
        child: InkWell(
          autofocus: autofocus,
          onTap: () => Navigator.of(context).pop(value),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Stack(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(26, 8, 16, 8),
                child: Row(children: [
                  AppIcon(icon, size: 20, color: AppColors.fg1),
                  const SizedBox(width: 18),
                  Expanded(
                    child: Text(label,
                        style: sans(15, color: AppColors.fg1)),
                  ),
                ]),
              ),
              if (!last)
                Positioned(
                  left: 64,
                  right: 16,
                  bottom: 0,
                  child: Container(height: 1, color: AppColors.border),
                ),
            ]),
          ),
        ),
      );
}
