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

/// The phone New sheet behind the one create button: Session, Agent, Group.
Future<void> showNewSheet(
  BuildContext context, {
  required VoidCallback onNewSession,
  required VoidCallback onNewAgent,
  required VoidCallback onNewGroup,
}) async {
  final picked = await showAppSheet<_NewAction>(
    context,
    title: 'New',
    child: Column(mainAxisSize: MainAxisSize.min, children: [
      _NewSheetRow(
          _NewAction.session, 'edit', 'Session', 'Start work with an agent'),
      _NewSheetRow(
          _NewAction.agent, 'bot', 'Agent', 'Add an agent to your roster'),
      _NewSheetRow(
          _NewAction.group, 'users', 'Group', 'Bring agents into one thread'),
    ]),
  );
  switch (picked) {
    case _NewAction.session:
      onNewSession();
    case _NewAction.agent:
      onNewAgent();
    case _NewAction.group:
      onNewGroup();
    default:
  }
}

class _NewSheetRow extends StatelessWidget {
  const _NewSheetRow(this.value, this.icon, this.label, this.detail);

  final _NewAction value;
  final String icon, label, detail;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: '$label, $detail',
        excludeSemantics: true,
        child: InkWell(
          onTap: () => Navigator.of(context).pop(value),
          borderRadius: BorderRadius.circular(R.of(12)),
          child: SizedBox(
            height: 72,
            child: Row(children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                    color: AppColors.surface2, shape: BoxShape.circle),
                alignment: Alignment.center,
                child: AppIcon(icon, size: 18, color: AppColors.fg2),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style:
                              sans(15, weight: W.label, color: AppColors.fg1)),
                      const SizedBox(height: 2),
                      Text(detail,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(13, color: AppColors.fg3)),
                    ]),
              ),
            ]),
          ),
        ),
      );
}
