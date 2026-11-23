import 'package:flutter/material.dart';

import '../api.dart';
import '../chat/signal_row.dart' show prettyProfile;
import '../mochi.dart';
import '../models.dart';
import '../quiet.dart';
import '../theme.dart';
import '../widgets.dart';

/// The group page's right rail: who is in it, with provider mark and state.
class GroupRail extends StatefulWidget {
  const GroupRail({super.key, required this.client, required this.group});

  final DaemonClient client;
  final GroupSummary group;

  @override
  State<GroupRail> createState() => _GroupRailState();
}

class _GroupRailState extends State<GroupRail> {
  List<CoordinationAgent> _agents = const [];

  @override
  void initState() {
    super.initState();
    widget.client.coordinationAgents().then((a) {
      if (mounted) setState(() => _agents = a);
    }).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final ids = widget.group.agentIds;
    final byId = {for (final a in _agents) a.id: a};
    final human = widget.group.members.any((m) => m.kind == 'human');
    return Container(
      decoration: BoxDecoration(
          border: Border(
              left: BorderSide(color: AppColors.fg1.withValues(alpha: 0.06)))),
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 24),
        children: [
          Text('Members ${ids.length + (human ? 1 : 0)}',
              style: sans(12, weight: W.label, color: AppColors.fg2)),
          const SizedBox(height: 8),
          for (final id in ids) _member(id, byId[id]),
          if (human)
            Container(
              constraints: const BoxConstraints(minHeight: 40),
              child: Row(children: [
                SizedBox(
                    width: 24,
                    child: AppIcon('user', size: 16, color: AppColors.fg3)),
                const SizedBox(width: 10),
                Text('You', style: sans(13, color: AppColors.fg1)),
              ]),
            ),
        ],
      ),
    );
  }

  Widget _member(String id, CoordinationAgent? a) {
    final name = a == null || a.displayName.trim().isEmpty
        ? id
        : a.displayName.trim();
    final needs = (a?.needsYou ?? 0) > 0;
    final working = !needs && (a?.presence?.live ?? false);
    final profile = a?.deskProfile ?? a?.profile;
    final state = needs
        ? 'needs you'
        : working
            ? 'working'
            : 'idle';
    return Container(
      constraints: const BoxConstraints(minHeight: 44),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(children: [
        ClipRRect(
            borderRadius: BorderRadius.circular(R.of(6)),
            child: AgentMochi(id, size: 24)),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13, weight: W.label, color: AppColors.fg1)),
              Row(children: [
                if (profile != null && providerLogoAsset(profile) != null) ...[
                  ProviderLogo(profile, size: 12, color: AppColors.fg3),
                  const SizedBox(width: 5),
                ],
                Flexible(
                  child: Text(
                      profile == null
                          ? state
                          : '${prettyProfile(profile)} · $state',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(12, color: AppColors.fg3)),
                ),
              ]),
            ],
          ),
        ),
        if (needs)
          const QuietHand(size: 14)
        else if (working)
          AppIcon('circle', size: 14, color: AppColors.fg2),
      ]),
    );
  }
}
