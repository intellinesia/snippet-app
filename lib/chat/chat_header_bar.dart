import 'package:flutter/material.dart';

import '../mochi.dart';
import '../composer/chat_composer.dart' show kChatMeasure;
import '../theme.dart';
import 'agent_cluster.dart';

/// Desktop chat header: one flat bounded row above the transcript with the
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
        : ClipOval(
            child: AgentMochi(
                agentIds.isEmpty ? 'snippet' : agentIds.first,
                size: 28),
          );
    // Flat and bounded to the transcript column plus 24 each side, so the
    // avatar lines up with the posts below; a hairline closes it.
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: kChatMeasure + 48),
        child: Container(
          key: const ValueKey('chat-header-bar'),
          // Grows with large text instead of overflowing.
          constraints: BoxConstraints(minHeight: height),
          padding: const EdgeInsets.fromLTRB(24, 4, 24, 4),
          decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.line)),
          ),
          child: Row(children: [
            avatar,
            const SizedBox(width: 14),
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
                        style: sans(12, color: AppColors.fg3)),
                ],
              ),
            ),
            for (var i = 0; i < actions.length; i++) ...[
              SizedBox(width: i == 0 ? 8 : 2),
              actions[i],
            ],
          ]),
        ),
      ),
    );
  }
}
