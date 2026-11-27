import 'package:flutter/material.dart';

import '../api.dart';
import '../chat/agent_cluster.dart';
import '../models.dart';
import '../presence.dart';
import '../theme.dart';

/// Desktop group panel hero: stacked members, the title, and a count line.
class GroupPanelHero extends StatelessWidget {
  const GroupPanelHero({
    super.key,
    required this.group,
    required this.title,
    this.trailing,
  });

  final GroupSummary group;
  final String title;
  final Widget? trailing;

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec'
  ];

  String get _sub {
    final n = group.members.length;
    final count = '$n ${n == 1 ? 'member' : 'members'}';
    final t = DateTime.tryParse(group.createdAt)?.toLocal();
    return t == null
        ? count
        : '$count · since ${t.day} ${_months[t.month - 1]}';
  }

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(S.s12, S.s4, S.s12, S.s12),
        child: Row(children: [
          AgentCluster(ids: group.agentIds, size: 52),
          SizedBox(width: S.s12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(17,
                        weight: W.strong,
                        color: Color.lerp(
                            AppColors.fg1, AppColors.fg2, 0.3))),
                SizedBox(height: S.s2),
                Text(_sub, style: sans(12.5, color: AppColors.fg3)),
              ],
            ),
          ),
          if (trailing != null) ...[SizedBox(width: S.s8), trailing!],
        ]),
      );
}

/// A member's live state: a dot and one word, from presence.
class GroupMemberStatus extends StatelessWidget {
  const GroupMemberStatus(
      {super.key, required this.client, required this.member});

  final DaemonClient client;
  final GroupMember member;

  @override
  Widget build(BuildContext context) {
    if (member.isHuman) return _chip('Online', AppColors.ok);
    final store = client.presence;
    return ListenableBuilder(
      listenable: store,
      builder: (_, __) {
        final p = store.presenceForAgentId(member.id);
        final word = p == null ? '' : PresenceStore.chatWord(p);
        if (word.isEmpty) return _chip('Idle', AppColors.fg4);
        return _chip(
            word == 'working'
                ? 'Working'
                : word[0].toUpperCase() + word.substring(1),
            word == 'working' ? AppColors.accent : AppColors.run);
      },
    );
  }

  Widget _chip(String text, Color dot) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
          SizedBox(width: S.s6),
          Text(text, style: sans(12, color: AppColors.fg3)),
        ],
      );
}
