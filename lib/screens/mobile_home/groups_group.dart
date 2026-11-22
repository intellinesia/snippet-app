import 'package:flutter/material.dart';

import '../../chat/agent_cluster.dart';
import '../../markdown_preview.dart' show markdownPreviewSpan, plainPreview;
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../group_messaging.dart' show groupActivityStatus;
import 'home_data.dart';
import 'home_style.dart';

/// Subtitle for a group row: live replying/turn status, else last preview, else
/// member count. Returns whether the line represents live activity.
({String text, bool live}) groupRowLine(
  GroupSummary group,
  String Function(String id) nameOf,
) {
  final status = groupActivityStatus(group, nameOf);
  if (status != null) return (text: status, live: true);
  final preview = group.preview?.trim() ?? '';
  if (preview.isNotEmpty) return (text: preview, live: false);
  return (text: groupMemberSummary(group, nameOf), live: false);
}

/// Relative age string for a group's last activity (empty when unknown).
String groupRelativeAge(GroupSummary group, {DateTime? now}) {
  final at = groupActivityAt(group);
  if (at == null) return '';
  return homeAge(at.millisecondsSinceEpoch ~/ 1000, now: now);
}

/// Search-overlay card for group chats, matching AgentsGroup and SessionsGroup.
class GroupsGroup extends StatelessWidget {
  const GroupsGroup({
    super.key,
    required this.groups,
    required this.nameOf,
    required this.onOpen,
    this.onLongPress,
    this.mutedIds = const {},
  });

  final List<GroupSummary> groups;
  final String Function(String id) nameOf;
  final void Function(GroupSummary g) onOpen;
  final void Function(GroupSummary g)? onLongPress;
  final Set<String> mutedIds;

  @override
  Widget build(BuildContext context) => HomeCard(
        children: withDividers([
          for (final g in groups)
            GroupTile(
              key: ValueKey('group-row-${g.id}'),
              group: g,
              nameOf: nameOf,
              muted: mutedIds.contains(g.id),
              onOpen: () => onOpen(g),
              onLongPress: onLongPress == null ? null : () => onLongPress!(g),
            ),
        ]),
      );
}

class GroupTile extends StatelessWidget {
  const GroupTile({
    super.key,
    required this.group,
    required this.nameOf,
    required this.onOpen,
    this.onLongPress,
    this.muted = false,
  });

  final GroupSummary group;
  final String Function(String id) nameOf;
  final VoidCallback onOpen;
  final VoidCallback? onLongPress;
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final title = group.title.trim().isEmpty ? 'Group' : group.title.trim();
    final line = groupRowLine(group, nameOf);
    final age = groupRelativeAge(group);
    final unread = group.unread;
    final agents = group.agentIds;
    final subColor = (line.live || unread > 0) ? AppColors.fg2 : AppColors.fg3;

    return Semantics(
      button: true,
      label:
          '$title, ${plainPreview(line.text)}${unread > 0 ? ', $unread unread' : ''}',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onOpen,
          onLongPress: onLongPress,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: S.of(14), vertical: S.of(10)),
              child: Row(children: [
                SizedBox.square(
                  dimension: 40,
                  child: agents.isEmpty
                      ? Center(
                          child: AppIcon('users',
                              size: 20, color: AppColors.fg3))
                      : AgentCluster(ids: agents, size: 40),
                ),
                SizedBox(width: S.s12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(children: [
                        Flexible(
                          child: Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(16,
                                  weight: unread > 0
                                      ? FontWeight.w600
                                      : FontWeight.w500,
                                  color: AppColors.fg1)),
                        ),
                        if (muted) ...[
                          SizedBox(width: S.s6),
                          AppIcon('bell-off', size: 13, color: AppColors.fg3),
                        ],
                      ]),
                      Row(children: [
                        if (line.live) ...[
                          Container(
                            width: 7,
                            height: 7,
                            decoration: BoxDecoration(
                                color: AppColors.ok, shape: BoxShape.circle),
                          ),
                          SizedBox(width: S.s6),
                        ],
                        Expanded(
                          child: Text.rich(
                            markdownPreviewSpan(
                                line.text, sans(13, color: subColor)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ]),
                    ],
                  ),
                ),
                if (age.isNotEmpty || unread > 0) ...[
                  SizedBox(width: S.s8),
                  Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (age.isNotEmpty)
                        Text(age,
                            maxLines: 1,
                            style: mono(12,
                                color: unread > 0
                                    ? AppColors.fg2
                                    : AppColors.fg3)),
                      if (unread > 0) ...[
                        if (age.isNotEmpty) const SizedBox(height: 4),
                        GroupUnreadBadge(id: group.id, count: unread),
                      ],
                    ],
                  ),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

class GroupUnreadBadge extends StatelessWidget {
  const GroupUnreadBadge({super.key, required this.id, required this.count});

  final String id;
  final int count;

  @override
  Widget build(BuildContext context) => Container(
        key: ValueKey('group-unread-$id'),
        constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(R.pill),
        ),
        child: Text(
          count > 99 ? '99+' : '$count',
          maxLines: 1,
          style: mono(11, weight: FontWeight.w600, color: AppColors.accentFg),
        ),
      );
}
