import 'package:flutter/material.dart';

import '../../widgets.dart';
import '../../mobile_kit.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../tap_detector.dart';

/// Statuses that wait on the user (spec TK-01 "Needs you").
const taskNeedsYou = {
  TaskStatus.inReview,
  TaskStatus.blocked,
  TaskStatus.failed,
};

bool taskWaitsOnUser(TaskStatus s) => taskNeedsYou.contains(s);

/// The daemon stores priority as an integer: 2 and above High, 1 Med, else Low.
String priorityWord(int p) => p >= 2 ? 'High' : (p == 1 ? 'Med' : 'Low');

/// "Review", "Blocked", "Failed" lead the sub line of a needs-you row.
String? needsYouWord(TaskStatus s) => switch (s) {
      TaskStatus.inReview => 'Review',
      TaskStatus.blocked => 'Blocked',
      TaskStatus.failed => 'Failed',
      _ => null,
    };

/// "4m", "3h", "2d".
String shortAgo(String iso, {DateTime? now}) {
  final at = DateTime.tryParse(iso);
  if (at == null) return '';
  final d = (now ?? DateTime.now()).difference(at);
  if (d.inMinutes < 1) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  return '${d.inDays}d';
}

/// The owner is the task's session agent. Nothing is invented: Lead only when
/// Lead created it, otherwise no owner.
({String? id, String name})? taskOwnerAgent(TaskItem t,
    Map<String, SessionInfo> sessions, Map<String, String> agentNames) {
  final s = sessions[t.sessionId];
  for (final id in [s?.agentId, s?.workerAgentId, s?.ownerAgentId]) {
    if (id == null || id.isEmpty) continue;
    final n = agentNames[id];
    if (n != null && n.trim().isNotEmpty) return (id: id, name: shortAgentName(n));
  }
  if (t.createdById.toLowerCase() == 'lead') return (id: 'lead', name: 'Lead');
  return null;
}

String? taskOwner(TaskItem t, Map<String, SessionInfo> sessions,
        Map<String, String> agentNames) =>
    taskOwnerAgent(t, sessions, agentNames)?.name;

/// The state word shown on the detail tag and the board.
String taskStateWord(TaskStatus s) => switch (s) {
      TaskStatus.inProgress => 'Doing',
      TaskStatus.todo => 'Todo',
      TaskStatus.inReview => 'Review',
      TaskStatus.blocked => 'Blocked',
      TaskStatus.failed => 'Failed',
      TaskStatus.done => 'Completed',
      TaskStatus.cancelled => 'Cancelled',
    };

/// Round 28 (or [size]) initial on surface2.
class OwnerAvatar extends StatelessWidget {
  const OwnerAvatar(this.name, {super.key, this.size = 28});
  final String name;
  final double size;
  @override
  Widget build(BuildContext context) {
    final t = name.trim();
    return ExcludeSemantics(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration:
            BoxDecoration(color: AppColors.surface2, shape: BoxShape.circle),
        child: Text(t.isEmpty ? '?' : t.characters.first.toUpperCase(),
            style: sans(size * 0.43,
                weight: W.label, height: 1, color: AppColors.fg2)),
      ),
    );
  }
}

/// The state mark shared with session rows: morph while doing, an empty
/// ring for todo, the amber dot when it waits on the user, a tick when
/// completed and an x ring when failed or cancelled.
class TaskGlyph extends StatelessWidget {
  const TaskGlyph(this.status, {super.key, this.size = 22});
  final TaskStatus status;
  final double size;

  @override
  Widget build(BuildContext context) {
    final state = switch (status) {
      TaskStatus.inReview || TaskStatus.blocked => MkState.needsYou,
      TaskStatus.failed || TaskStatus.cancelled => MkState.failed,
      TaskStatus.inProgress => MkState.working,
      TaskStatus.done => MkState.done,
      TaskStatus.todo => MkState.open,
    };
    return ExcludeSemantics(
        child: SizedBox(
            width: size,
            height: size,
            child: OverflowBox(
                maxWidth: size + 8,
                maxHeight: size + 8,
                child: Center(child: MkStateMark(state, size: size)))));
  }
}

/// A 48 x 48 trailing bar icon (44 on iPhone), in the primary ink.
class BarIcon extends StatelessWidget {
  const BarIcon(this.icon, this.label, this.onTap, {super.key, this.toggled});
  final bool? toggled;
  final String icon;
  final String label;
  final VoidCallback? onTap;
  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        toggled: toggled,
        label: label,
        excludeSemantics: true,
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
              width: kAndroidLook ? 48 : 44,
              height: kAndroidLook ? 48 : 44,
              child: Center(
                  child: AppIcon(icon,
                      size: kAndroidLook ? 22 : 19, color: AppColors.fg1))),
        ),
      );
}
