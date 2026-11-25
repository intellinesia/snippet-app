import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../agent_character.dart' show AgentCharacterState;
import '../../api.dart';
import '../../chat/stage_bar.dart';
import '../../chat_scene.dart' show SceneBackdrop;
import '../../glass.dart' show StatusInset;
import '../../chat/stage_header.dart' show StageMember;
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../phone_hero.dart' show heroAgentColor;
import '../mobile_chrome.dart' show RoundBtn;
import 'home_composer.dart';
import 'home_data.dart';
import 'home_style.dart';
import 'sessions_group.dart';

/// One agent's managed sessions: Running, then Idle. Pushed from the Agents
/// card's "n managed" pill.
class ManagedView extends StatelessWidget {
  const ManagedView({
    super.key,
    required this.client,
    required this.agent,
    required this.sessions,
    required this.onOpenSession,
    required this.onPlus,
    required this.onSent,
    required this.onOpenAgent,
  });

  final DaemonClient client;
  final CoordinationAgent agent;

  /// Every session, live; this view picks the agent's managed, non-settled ones.
  final ValueListenable<List<SessionInfo>> sessions;
  final void Function(SessionInfo s) onOpenSession;
  final void Function(BuildContext anchor) onPlus;
  final VoidCallback onSent;

  /// The More button opens the agent's own thread.
  final VoidCallback onOpenAgent;

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
        valueListenable: sessions,
        builder: (context, all, _) => _body(context, all),
      );

  Widget _body(BuildContext context, List<SessionInfo> all) {
    final mine = managedByAgent(all)[agent.id] ?? const <SessionInfo>[];
    final split = managedSplit(mine);
    final n = mine.length;
    final colour = heroAgentColor(agent.id);
    final bottom = MediaQuery.paddingOf(context).bottom;
    return Material(
      color: AppColors.bg,
      child: SceneBackdrop(
        child: StatusInset(
          top: MediaQuery.paddingOf(context).top,
          child: SafeArea(
            bottom: false,
            child: Stack(children: [
        ListView(
          padding: EdgeInsets.fromLTRB(
              M.gutter, StageBar.height + 8, M.gutter, 140 + bottom),
          children: [
            if (split.running.isNotEmpty) ...[
              HomeLabel('Running', count: split.running.length),
              HomeCard(children: withDividers([
                for (final s in split.running)
                  _RunningTile(
                      session: s, colour: colour, onOpen: () => onOpenSession(s)),
              ], inset: 0)),
            ],
            if (split.idle.isNotEmpty) ...[
              HomeLabel('Idle', count: split.idle.length, top: 18),
              HomeCard(children: withDividers([
                for (final s in split.idle)
                  SessionTile(
                      session: s,
                      height: 72,
                      showAgent: false,
                      onOpen: () => onOpenSession(s)),
              ], inset: 0)),
            ],
          ],
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: IgnorePointer(
            child: Container(
              height: 140 + bottom,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    AppColors.bg.withValues(alpha: 0),
                    AppColors.bg.withValues(alpha: 0.94),
                    AppColors.bg,
                  ],
                  stops: const [0, 0.75, 1],
                ),
              ),
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: StageBar(
            members: [StageMember(agent.id, state: AgentCharacterState.idle)],
            title: agent.displayName,
            subtitle: '$n managed session${n == 1 ? '' : 's'}',
          ),
        ),
        Positioned(
          left: M.gutter - 2,
          top: S.s8 - 2,
          child: Hit44(
            label: 'Back',
            onTap: () => Navigator.maybePop(context),
            child: IgnorePointer(
                child: RoundBtn(icon: 'chevron-left', tooltip: 'Back', iconSize: 20)),
          ),
        ),
        Positioned(
          right: M.gutter - 2,
          top: S.s8 - 2,
          child: Hit44(
            label: 'More',
            onTap: onOpenAgent,
            child: IgnorePointer(
                child: RoundBtn(icon: 'more-horizontal', tooltip: 'More')),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: HomeComposer(
            client: client,
            agentId: agent.id,
            agentName: agent.displayName,
            hint: 'Message ${agent.displayName}',
            onPlus: onPlus,
            onSent: onSent,
          ),
        ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _RunningTile extends StatelessWidget {
  const _RunningTile(
      {required this.session, required this.colour, required this.onOpen});

  final SessionInfo session;
  final Color colour;
  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final title = s.title.trim().isEmpty ? 'Untitled session' : s.title.trim();
    final branch = (s.branch ?? '').trim();
    return Semantics(
      button: true,
      label: '$title, running, ${homeAge(s.lastActive)}',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onOpen,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 100),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: S.of(14), vertical: S.s12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Row(children: [
                    Spinner(size: 14, color: AppColors.fg3),
                    SizedBox(width: S.s8),
                    Expanded(
                      child: Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(17,
                              weight: FontWeight.w500, color: AppColors.fg1)),
                    ),
                    SizedBox(width: S.s8),
                    Text(homeAge(s.lastActive),
                        style: sans(13, color: AppColors.fg3)),
                  ]),
                  SizedBox(height: S.s2),
                  Row(children: [
                    AppIcon('folder', size: 12, color: AppColors.fg3),
                    SizedBox(width: S.s4),
                    Flexible(
                      child: Text(s.projectFolder.split('/').last,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(13, color: AppColors.fg3)),
                    ),
                    if (branch.isNotEmpty) ...[
                      SizedBox(width: S.s8),
                      AppIcon('git-branch', size: 12, color: AppColors.fg3),
                      SizedBox(width: S.s4),
                      Flexible(
                        child: Text(branch,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(13, color: AppColors.fg3)),
                      ),
                    ],
                  ]),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

}
