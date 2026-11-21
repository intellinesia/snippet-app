import 'package:flutter/material.dart';

import '../motion.dart' show WorkingBars;
import '../theme.dart';
import 'chat_style.dart' show AgentDisc;

/// Desktop: who spoke, at the top of their run, in agent and group chats alike.
class ChatRunHead extends StatelessWidget {
  const ChatRunHead({
    super.key,
    required this.agentId,
    required this.name,
    this.time,
    this.lead = false,
    this.working = false,
  });

  final String agentId;
  final String name;
  final String? time;
  final bool lead;
  final bool working;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: S.s4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AgentDisc(id: agentId, size: 20),
          SizedBox(width: S.s8),
          Flexible(
            child: Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(13, weight: FontWeight.w500, color: AppColors.fg1)),
          ),
          if (lead) ...[
            SizedBox(width: S.s6),
            Text('lead', style: sans(11, color: AppColors.fg4)),
          ],
          if (time != null) ...[
            SizedBox(width: S.s8),
            Text(time!, style: mono(11, color: AppColors.fg4)),
          ],
          if (working) ...[
            SizedBox(width: S.s8),
            const WorkingBars(),
          ],
        ]),
      );
}
