import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../theme.dart';
import 'agents_sidebar_panel.dart';

/// Desktop roster tab: every agent and group, with the same live state rows
/// the sidebar shows.
class AllAgentsView extends StatelessWidget {
  const AllAgentsView({
    super.key,
    required this.client,
    required this.sessions,
    required this.onOpenAgent,
    required this.onOpenSession,
  });

  final DaemonClient client;
  final List<SessionInfo> sessions;
  final void Function(CoordinationAgent agent) onOpenAgent;
  final void Function(SessionInfo session) onOpenSession;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.panelBg,
      child: Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 640),
          child: ListView(
            padding: EdgeInsets.fromLTRB(S.s16, S.s24, S.s16, S.s24),
            children: [
              Padding(
                padding: EdgeInsets.only(left: S.s8, bottom: S.s16),
                child: Text('All agents and groups',
                    style: sans(20,
                        height: 28 / 20,
                        weight: W.strong,
                        color: AppColors.fg1)),
              ),
              AgentsSidebarPanel(
                key: const ValueKey('all-agents-list'),
                embedded: true,
                client: client,
                groupsKey: 'groups-all-agents',
                sessions: sessions,
                onOpenAgent: onOpenAgent,
                onOpenSession: onOpenSession,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
