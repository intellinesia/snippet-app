import 'package:flutter/material.dart';

import '../mochi.dart';
import '../theme.dart';
import 'agent_cluster.dart';

/// Desktop chat header (XO-03): a bounded s1 bar above the transcript with the
/// chat's identity, its state line and the trailing chat actions.
class ChatHeaderBar extends StatelessWidget {
  const ChatHeaderBar({
    super.key,
    required this.agentIds,
    required this.title,
    this.subtitle = '',
    this.actions = const [],
  });

  static const double height = 48;

  /// One id draws the agent; two or more draw the group cluster.
  final List<String> agentIds;
  final String title;
  final String subtitle;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final avatar = agentIds.length > 1
        ? AgentCluster(ids: agentIds, size: 28)
        : ClipRRect(
            borderRadius: BorderRadius.circular(8),
            child: AgentMochi(
                agentIds.isEmpty ? 'snippet' : agentIds.first,
                size: 28),
          );
    return Container(
      key: const ValueKey('chat-header-bar'),
      // Grows with large text instead of overflowing.
      constraints: BoxConstraints(minHeight: height),
      margin: const EdgeInsets.fromLTRB(12, 8, 12, 0),
      padding: const EdgeInsets.only(left: 12, right: 10, top: 4, bottom: 4),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(children: [
        avatar,
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13.5,
                      weight: FontWeight.w500, color: AppColors.fg1)),
              if (subtitle.isNotEmpty)
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(11, color: AppColors.fg3)),
            ],
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
