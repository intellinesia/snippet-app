import 'package:flutter/material.dart';

import '../menu_widgets.dart';
import '../theme.dart';
import 'shell_components.dart';
import 'shell_models.dart';
import 'shell_rail.dart' show RailIcon;

/// Builds the activity rail action tools for the active tab.
List<Widget> buildShellRailTools({
  required ShellTab? activeTab,
  required MacSessionStatus? macSessionStatus,
  required void Function(String action, [String? extra]) onSessionAction,
  void Function(String action)? onAgentAction,
}) {
  final tab = activeTab;
  // Agent options live in the docked info panel, opened from the title.
  if (tab != null && tab.readout?.isAgent == true) return const [];
  final mc = tab?.isLead ?? false;
  // Lead's options live in its docked details panel.
  if (mc) return const [];
  final s = macSessionStatus?.state;
  if (tab != null && tab.isDraft) return const [];
  final lanes = s?.lanes.where((l) => l.running).length ?? 0;

  Widget railTool(
    String icon, {
    required String tooltip,
    required VoidCallback? onTap,
    bool active = false,
    String? badge,
  }) =>
      RailIcon(
        icon: icon,
        tooltip: tooltip,
        active: active,
        badge: badge,
        onTap: onTap,
      );

  final win = s?.contextWindow ?? 0;
  final used = s?.lastPromptTokens ?? 0;
  final frac = win > 0 ? (used / win).clamp(0.0, 1.0) : 0.0;
  String k(int v) => v >= 1000 ? '${(v / 1000).round()}k' : '$v';

  Future<void> openMenu(BuildContext ctx) async {
    PopupMenuItem<VoidCallback> item(String icon, String label, VoidCallback fn,
            {String? detail}) =>
        appMenuItem(value: fn, icon: icon, label: label, detail: detail);
    final fn = await showAppMenu<VoidCallback>(
      ctx,
      anchor: ctx,
      below: true,
      alignEnd: true,
      minWidth: 260,
      maxWidth: 280,
      items: [
        if (win > 0 && used > 0) ...[
          PopupMenuItem<VoidCallback>(
            enabled: false,
            height: 64,
            child: Padding(
              padding: EdgeInsets.symmetric(vertical: S.s6),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(child: Text('Context', style: TS.ui())),
                      Text('${k(used)} / ${k(win)}', style: TS.meta()),
                    ]),
                    SizedBox(height: S.of(10)),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        for (var i = 0; i < 26; i++)
                          Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: i < (frac * 26).round()
                                  ? (frac > 0.8
                                      ? AppColors.danger
                                      : AppColors.fg3)
                                  : AppColors.line,
                            ),
                          ),
                      ],
                    ),
                  ]),
            ),
          ),
          PopupMenuItem<VoidCallback>(
            enabled: false,
            height: 40,
            child: Builder(
              builder: (ctx) => Align(
                alignment: Alignment.centerLeft,
                child: Material(
                  color: AppColors.surface3,
                  borderRadius: BorderRadius.circular(R.sm),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(R.sm),
                    onTap: () => Navigator.of(ctx)
                        .pop<VoidCallback>(() => onSessionAction('compact')),
                    child: Container(
                      height: 30,
                      padding: EdgeInsets.symmetric(horizontal: S.s12),
                      alignment: Alignment.center,
                      child: Text('Compact now', style: TS.ui(AppColors.fg1)),
                    ),
                  ),
                ),
              ),
            ),
          ),
          const PopupMenuDivider(),
        ],
        if (mc)
          item('activity', 'Automated wakes', () => onSessionAction('autonomy'))
        else ...[
          item('git-fork', 'Fork from here', () => onSessionAction('fork')),
          item('send', 'Hand off', () => onSessionAction('handoff')),
          item('history', 'Rewind', () => onSessionAction('checkpoints')),
          const PopupMenuDivider(height: 9),
          item('file-diff', 'File changes',
              () => onSessionAction('file_changes')),
          item('clipboard', 'Artifacts', () => onSessionAction('artifacts')),
          item('book-marked', 'Memory', () => onSessionAction('memory')),
          item('pull-request', 'Pull requests',
              () => onSessionAction('pull_requests')),
        ],
        if (win <= 0 || used <= 0)
          item('wrap', 'Compact history', () => onSessionAction('compact')),
        if (!mc) ...[
          const PopupMenuDivider(),
          appMenuItem(
              value: () => onSessionAction('delete'),
              icon: 'trash',
              label: 'Delete session',
              danger: true),
        ],
      ],
    );
    fn?.call();
  }

  return [
    Builder(
      builder: (ctx) => railTool(
        'more-horizontal',
        tooltip: 'Session actions',
        badge: lanes > 0 ? '$lanes' : null,
        onTap: tab == null ? null : () => openMenu(ctx),
      ),
    ),
  ];
}
