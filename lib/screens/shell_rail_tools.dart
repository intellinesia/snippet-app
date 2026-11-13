import 'package:flutter/material.dart';

import '../menu_widgets.dart';
import '../theme.dart';
import 'shell_components.dart';
import 'shell_models.dart';
import 'shell_rail.dart' show RailIcon;

/// Shows an anchored goal popup beneath [anchorContext].
Future<void> showGoalPopover({
  required BuildContext context,
  required BuildContext anchorContext,
  required ValueChanged<String> onSetGoal,
}) async {
  final box = anchorContext.findRenderObject() as RenderBox?;
  if (box == null) return;
  final origin = box.localToGlobal(Offset.zero);
  const width = 320.0;
  final screen = MediaQuery.sizeOf(context).width;
  final left =
      (origin.dx + box.size.width - width).clamp(8.0, screen - width - 8);
  await showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'goal',
    barrierColor: Colors.transparent,
    transitionDuration: Motion.press,
    pageBuilder: (_, __, ___) => Stack(children: [
      Positioned(
        left: left,
        top: origin.dy + box.size.height + 6,
        width: width,
        child: Material(
          color: AppColors.overlay,
          shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(R.lg),
              side: BorderSide(color: AppColors.line)),
          elevation: 4,
          shadowColor: Colors.black.withValues(alpha: 0.4),
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: GoalPopover(
              onSet: (text) {
                Navigator.pop(context);
                onSetGoal(text);
              },
            ),
          ),
        ),
      ),
    ]),
  );
}

/// Builds the activity rail action tools for the active tab.
List<Widget> buildShellRailTools({
  required ShellTab? activeTab,
  required MacSessionStatus? macSessionStatus,
  required bool Function(RightPanel panel) isRightPanelActive,
  required void Function(RightPanel panel) onToggleRightPanel,
  required void Function(String action, [String? extra]) onSessionAction,
  required void Function(BuildContext ctx) onOpenGoalPopover,
  void Function(String action)? onAgentAction,
}) {
  final tab = activeTab;
  // Agent options live in the docked info panel, opened from the title.
  if (tab != null && tab.readout?.isAgent == true) return const [];
  final mc = tab?.isMissionControl ?? false;
  final s = macSessionStatus?.state;
  final goalRunning = s?.goal?.ongoing ?? false;
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
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(children: [
                      Expanded(
                          child: Text('Context', style: TS.ui())),
                      Text('${k(used)} / ${k(win)}', style: TS.meta()),
                    ]),
                    const SizedBox(height: 10),
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
                    onTap: () => Navigator.of(ctx).pop<VoidCallback>(
                        () => onSessionAction('compact')),
                    child: Container(
                      height: 30,
                      padding: const EdgeInsets.symmetric(horizontal: 12),
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
          const PopupMenuDivider(height: 9),
          item('file-diff', 'File changes', () => onSessionAction('file_changes')),
          item('clipboard', 'Artifacts', () => onSessionAction('artifacts')),
          item('book-marked', 'Memory', () => onSessionAction('memory')),
          item('pull-request', 'Pull requests',
              () => onSessionAction('pull_requests')),
          const PopupMenuDivider(),
          goalRunning
              ? item('goal', 'Cancel goal', () => onSessionAction('goal'))
              : item('goal', 'Set goal', () => onOpenGoalPopover(ctx)),
          item('layers', 'Lanes', () => onToggleRightPanel(RightPanel.lanes),
              detail: lanes > 0 ? '$lanes running' : null),
          item('history', 'Checkpoints',
              () => onToggleRightPanel(RightPanel.checkpoints)),
        ],
        item('scheduled', 'Scheduled',
            () => onToggleRightPanel(RightPanel.recurring)),
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
        active: goalRunning ||
            isRightPanelActive(RightPanel.lanes) ||
            isRightPanelActive(RightPanel.checkpoints) ||
            isRightPanelActive(RightPanel.recurring),
        onTap: tab == null ? null : () => openMenu(ctx),
      ),
    ),
  ];
}
