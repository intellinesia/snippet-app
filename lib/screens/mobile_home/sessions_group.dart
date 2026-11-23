import 'package:flutter/material.dart';

import '../../mochi.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../../settled_sessions.dart' show settledDaysLeft;
import '../session_list_row.dart' show projectLabel, sessionCameBack;
import '../shell_nav.dart' show sessionBusy;
import 'home_style.dart';

/// Human-managed sessions, newest first, with the Settled fold.
class SessionsGroup extends StatelessWidget {
  const SessionsGroup({
    super.key,
    required this.main,
    required this.settled,
    required this.settledOpen,
    required this.onToggleSettled,
    required this.onOpen,
    this.onLongPress,
  });

  final List<SessionInfo> main;
  final List<SessionInfo> settled;
  final bool settledOpen;
  final VoidCallback onToggleSettled;
  final void Function(SessionInfo s) onOpen;
  final void Function(SessionInfo s)? onLongPress;

  Widget _row(SessionInfo s) => SessionTile(
        key: ValueKey('session-row-${s.id}'),
        session: s,
        onOpen: () => onOpen(s),
        onLongPress: onLongPress == null ? null : () => onLongPress!(s),
      );

  @override
  Widget build(BuildContext context) {
    final reduce = reduceMotion(context);
    return HomeCard(children: [
      ...withDividers([for (final s in main) _row(s)]),
      if (settled.isNotEmpty) ...[
        if (main.isNotEmpty) const HomeDivider(inset: 0),
        FoldRow(
          key: const ValueKey('settled-fold'),
          label: 'Settled',
          count: settled.length,
          open: settledOpen,
          onTap: onToggleSettled,
        ),
        AnimatedSize(
          duration: reduce ? const Duration(milliseconds: 1) : Motion.base,
          curve: Curves.easeOutCubic,
          alignment: Alignment.topCenter,
          child: settledOpen
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const HomeDivider(inset: 0),
                    ...withDividers([for (final s in settled) _row(s)]),
                  ],
                )
              : const SizedBox(width: double.infinity),
        ),
      ],
    ]);
  }
}

class SessionTile extends StatelessWidget {
  const SessionTile({
    super.key,
    required this.session,
    required this.onOpen,
    this.onLongPress,
    this.height = 64,
    this.showAgent = true,
  });

  final SessionInfo session;
  final VoidCallback onOpen;
  final VoidCallback? onLongPress;
  final double height;
  final bool showAgent;

  @override
  Widget build(BuildContext context) {
    final s = session;
    final title = s.title.trim().isEmpty ? 'Untitled session' : s.title.trim();
    final branch = (s.branch ?? '').trim();
    final done = sessionCameBack(s) && !s.settled;
    final charState = sessionBusy(s)
        ? AgentCharacterState.working
        : AgentCharacterState.idle;
    final left = s.settled ? settledDaysLeft(s) : null;
    final age = left != null ? '${left}d left' : homeAge(s.lastActive);
    return Semantics(
      button: true,
      label: '$title, ${done ? 'Completed' : age}',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onOpen,
          onLongPress: onLongPress,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: height),
            child: Padding(
              padding: EdgeInsets.fromLTRB(S.of(14), S.s8, S.of(14), S.s8),
              child: Row(children: [
                if (showAgent) ...[
                  SizedBox(
                    width: 40,
                    child: Center(
                      child: AgentMochi(s.displayAgentId ?? 'snippet',
                          size: rowAvatarSize(height, max: 40), state: charState),
                    ),
                  ),
                  SizedBox(width: S.s12),
                ],
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(17,
                              weight: FontWeight.w500, color: AppColors.fg1)),
                      Row(children: [
                        AppIcon('folder', size: 12, color: AppColors.fg3),
                        SizedBox(width: S.s4),
                        Flexible(
                          child: Text(projectLabel(s),
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
                SizedBox(width: S.s8),
                Text(done ? 'Completed' : age,
                    maxLines: 1,
                    style: sans(13,
                        color: done ? AppColors.ok : AppColors.fg3)),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}
