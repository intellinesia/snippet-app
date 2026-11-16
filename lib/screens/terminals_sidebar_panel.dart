import 'package:flutter/material.dart';

import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'shell_nav.dart';
import 'session.dart' show TerminalInfo;

/// Sidebar panel for a session's terminals.
///
/// Rows mirror the file tree and chat list: flat 26px rows at the sidebar's
/// content inset, selection as a surface step, no card fill or border. The
/// previous version drew bordered cards with a two-line body and a hard-coded
/// title list, which is why it read as both broken and fake.
class TerminalsSidebarPanel extends StatelessWidget {
  const TerminalsSidebarPanel({
    super.key,
    required this.workspacePath,
    required this.terminals,
    required this.focus,
    required this.onNewTerminal,
    required this.onOpenTerminal,
    required this.onCloseTerminal,
  });

  final String workspacePath;

  /// Live terminals for the active session, published by `SessionScreen`.
  /// Empty when the session has not opened one yet.
  final List<TerminalInfo> terminals;

  /// Index of the focused terminal, or -1 when the drawer is closed.
  final int focus;

  final VoidCallback onNewTerminal;
  final ValueChanged<int> onOpenTerminal;

  /// Destroy a terminal. This — or the + above — is the ONLY way a shell is
  /// created or destroyed; the pane can only minimize it.
  final ValueChanged<String> onCloseTerminal;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final displayPath =
        workspacePath.trim().isEmpty ? '~/workspace' : workspacePath;

    final folder = lastPathSegment(displayPath, ifEmpty: displayPath);
    final head = <Widget>[
          if (kMobile)
            ShellSectionHeader(
              label: 'Terminals',
              actions: [
                ShellSectionAction(
                  icon: 'plus',
                  tooltip: 'New terminal',
                  onTap: onNewTerminal,
                ),
              ],
            )
          else
            Container(
              height: 38,
              padding: EdgeInsets.fromLTRB(S.of(14), 0, S.s8, 0),
              decoration: BoxDecoration(
                border: Border(bottom: BorderSide(color: AppColors.line)),
              ),
              child: Row(children: [
                Text('Terminals',
                    style: sans(13, weight: W.label, color: AppColors.fg1)),
                SizedBox(width: S.s4),
                ShellSectionAction(
                  icon: 'plus',
                  tooltip: 'New terminal',
                  onTap: onNewTerminal,
                ),
              ]),
            ),
          if (!kMobile) SizedBox(height: S.s6),
          // The session's working directory, same flat 32px row the file tree
          // and git panels use for their context line.
          Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: kSidebarContentInset),
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: kNavPadH),
              child: Row(children: [
                AppIcon('folder-open', size: 14, color: AppColors.fg3),
                SizedBox(width: S.s8),
                Expanded(
                  child: Text(displayPath,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono(11, color: AppColors.fg3)),
                ),
              ]),
            ),
          ),
    ];
    if (terminals.isEmpty) {
      return Container(
        color: kMobile ? AppColors.pageBg : Colors.transparent,
        padding: EdgeInsets.only(top: kMobile ? S.s8 : 0),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          ...head,
          Expanded(
            child: EmptyState(
              icon: 'terminal',
              title: 'No terminals open',
              body:
                  'Shells start in $folder and keep running until you close them here.',
              action: Btn('New terminal',
                  small: true, icon: 'plus', onTap: onNewTerminal),
            ),
          ),
        ]),
      );
    }
    return Container(
      color: kMobile ? AppColors.pageBg : Colors.transparent,
      child: ListView(
        padding: EdgeInsets.only(top: kMobile ? S.s8 : 0, bottom: S.s16),
        children: [
          ...head,
          SizedBox(height: S.s6),
          for (var i = 0; i < terminals.length; i++) _row(i),
        ],
      ),
    );
  }

  Widget _row(int i) {
    final t = terminals[i];
    final selected = i == focus;
    return ShellNavRow(
      id: t.id,
      label: t.title,
      icon: 'terminal',
      tone: ShellTone.neutral,
      selected: selected,
      onTap: () => onOpenTerminal(i),
      // Alive dot on the left of the close affordance, so a running pty reads
      // at a glance while the row stays a single 26px line.
      trailing: Row(mainAxisSize: MainAxisSize.min, children: [
        if (t.alive) ...[
          const StatusDot(status: 'online', size: 7),
          SizedBox(width: S.s6),
        ],
        // Destroying lives here, not in the pane: the pane can only minimize.
        GestureDetector(
          onTap: () => onCloseTerminal(t.id),
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: EdgeInsets.all(S.of(3)),
            child: AppIcon('x', size: 12, color: AppColors.fg4),
          ),
        ),
      ]),
    );
  }
}
