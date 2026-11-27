import 'package:flutter/material.dart';

import '../mochi.dart';
import '../theme.dart';
import 'agent_cluster.dart';

/// Desktop pane row above a chat: the chat as a filled tab
/// pill with the pane's + beside it, and its state line plus actions at the
/// right end. A hairline closes it.
class ChatHeaderBar extends StatelessWidget {
  const ChatHeaderBar({
    super.key,
    required this.agentIds,
    required this.title,
    this.subtitle = '',
    this.live = false,
    this.leading = const [],
    this.tabs = const [],
    this.actions = const [],
  });

  static const double height = PaneRow.height;

  /// One id draws the agent; two or more draw the group cluster.
  final List<String> agentIds;
  final String title;
  final String subtitle;

  /// Puts a live dot before [subtitle].
  final bool live;

  /// Sits right after the pill (the pane's "+").
  final List<Widget> leading;

  /// The pane's other tabs, as pills after the chat's own (one row).
  final List<Widget> tabs;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final avatar = agentIds.length > 1
        ? AgentCluster(ids: agentIds, size: 16)
        : ClipOval(
            child: AgentMochi(agentIds.isEmpty ? 'snippet' : agentIds.first,
                size: 16),
          );
    return Container(
      key: const ValueKey('chat-header-bar'),
      height: height,
      padding: const EdgeInsets.fromLTRB(8, 0, 8, 0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.paneLine)),
      ),
      child: Row(children: [
        // The tabs take the free width themselves; a loose Flexible beside a
        // Spacer would leave half of it empty past the actions.
        Expanded(
          child: Row(children: [
            Flexible(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 320),
                child: Container(
                  key: const ValueKey('chat-header-pill'),
                  height: PaneRow.pill,
                  padding: const EdgeInsets.fromLTRB(9, 0, 11, 0),
                  decoration: BoxDecoration(
                    color: PaneRow.plate,
                    borderRadius: BorderRadius.circular(PaneRow.radius),
                  ),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    avatar,
                    const SizedBox(width: 8),
                    Flexible(
                      child: Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(PaneRow.label, color: PaneRow.labelOn)),
                    ),
                  ]),
                ),
              ),
            ),
            for (final w in tabs) ...[
              const SizedBox(width: 4),
              Flexible(
                  child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 180),
                      child: w)),
            ],
            for (final w in leading) ...[const SizedBox(width: 4), w],
          ]),
        ),
        if (subtitle.isNotEmpty)
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 360),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (live) ...[
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                      color: AppColors.ok, shape: BoxShape.circle),
                ),
                const SizedBox(width: 7),
              ],
              Flexible(
                child: Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(12, color: AppColors.fg3)),
              ),
            ]),
          ),
        for (var i = 0; i < actions.length; i++) ...[
          SizedBox(width: i == 0 ? 8 : 2),
          actions[i],
        ],
      ]),
    );
  }
}
