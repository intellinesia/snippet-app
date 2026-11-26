import 'package:flutter/material.dart';

import '../mochi.dart';
import '../theme.dart';
import 'agent_cluster.dart';

/// Desktop pane row above a chat (Capy layout): the chat as a filled tab
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

  static const double height = 44;

  /// One id draws the agent; two or more draw the group cluster.
  final List<String> agentIds;
  final String title;
  final String subtitle;

  /// Puts a live dot before [subtitle].
  final bool live;

  /// Sits right after the pill (the pane's "+").
  final List<Widget> leading;

  /// The pane's other tabs, as pills after the chat's own (one row, as Capy).
  final List<Widget> tabs;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final avatar = agentIds.length > 1
        ? AgentCluster(ids: agentIds, size: 16)
        : ClipOval(
            child: AgentMochi(
                agentIds.isEmpty ? 'snippet' : agentIds.first,
                size: 16),
          );
    return Container(
      key: const ValueKey('chat-header-bar'),
      constraints: BoxConstraints(minHeight: height),
      padding: const EdgeInsets.fromLTRB(10, 4, 8, 4),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(children: [
        Flexible(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 320),
            child: Container(
              key: const ValueKey('chat-header-pill'),
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 10),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(R.of(7)),
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                avatar,
                const SizedBox(width: 8),
                Flexible(
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(12.5, color: AppColors.fg1)),
                ),
              ]),
            ),
          ),
        ),
        for (final w in tabs) ...[
          const SizedBox(width: 4),
          Flexible(child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 180), child: w)),
        ],
        for (final w in leading) ...[const SizedBox(width: 4), w],
        const Spacer(),
        if (subtitle.isNotEmpty)
          Flexible(
            flex: 0,
            child: ConstrainedBox(
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
          ),
        for (var i = 0; i < actions.length; i++) ...[
          SizedBox(width: i == 0 ? 8 : 2),
          actions[i],
        ],
      ]),
    );
  }
}
