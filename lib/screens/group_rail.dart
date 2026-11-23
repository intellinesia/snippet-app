import 'package:flutter/material.dart';

import '../api.dart';
import '../chat/signal_row.dart' show profileMeta;
import '../mochi.dart';
import '../models.dart';
import '../quiet.dart';
import '../theme.dart';
import '../shell_panel.dart' show openSessionInTab;
import '../widgets.dart';
import 'agent_rail.dart';
import 'sidebar.dart' show SidebarState;

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
  List<SessionInfo> _sessions = const [];
  Map<String, InferenceProfile> _profiles = const {};

  @override
  void initState() {
    super.initState();
    widget.client.coordinationAgents().then((a) {
      if (mounted) setState(() => _agents = a);
    }).catchError((_) {});
    widget.client.getConfig().then((c) {
      if (mounted) {
        setState(() => _profiles = {for (final p in c.profiles) p.name: p});
      }
    }).catchError((_) {});
    widget.client.sessions().then((l) {
      if (mounted) setState(() => _sessions = l);
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
          const SizedBox(height: 20),
          AgentRail(
            embedded: true,
            sessions: [
              for (final s in _sessions)
                if ({s.agentId, s.ownerAgentId, s.workerAgentId}
                    .any((a) => a != null && ids.contains(a)))
                  s
            ],
            onOpenSession: (s) =>
                openSessionInTab?.call(widget.client, s.id, s.title),
            onAllSessions: SidebarState.showAllSessions,
          ),
        ],
      ),
    );
  }

  Widget _member(String id, CoordinationAgent? a) {
    final name =
        a == null || a.displayName.trim().isEmpty ? id : a.displayName.trim();
    final needs = (a?.needsYou ?? 0) > 0;
    final working = !needs && (a?.presence?.live ?? false);
    final profile = a?.deskProfile ?? a?.profile;
    final meta = profileMeta(_profiles, profile);
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
                if (providerLogoAsset(meta.provider) != null) ...[
                  ProviderLogo(meta.provider, size: 12, color: AppColors.fg3),
                  const SizedBox(width: 5),
                ],
                Flexible(
                  child: Text(
                      meta.label.isEmpty ? state : '${meta.label} · $state',
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
