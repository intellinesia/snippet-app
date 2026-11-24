import 'package:flutter/material.dart';

import '../../api.dart';
import '../../goal_models.dart';
import '../../tap_detector.dart';
import '../../theme.dart';
import 'agents_home.dart';

/// The state words for a plan step, from its task. Words carry the state.
String missionStepState(GoalTask? t) {
  switch (t?.status) {
    case null:
    case 'todo':
      return 'Not started';
    case 'in_progress':
    case 'in_review':
      return 'In progress';
    case 'blocked':
      final r = t!.statusReason;
      return r == null ? 'Blocked' : 'Blocked: $r';
    case 'done':
    case 'completed':
      return 'Done';
    default:
      return t!.status;
  }
}

bool _done(GoalTask? t) => t?.status == 'done' || t?.status == 'completed';

/// Mission bar (HM-13): 48 high minimum, title, "n of m", a 4 high track and
/// the blocked step line. The whole bar opens the board.
class MissionBar extends StatelessWidget {
  const MissionBar({super.key, required this.detail, required this.onTap});
  final GoalDetail detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final steps = detail.plan;
    final done = [for (final s in steps) if (_done(detail.taskFor(s))) s].length;
    final blocked = [
      for (final s in steps)
        if (detail.taskFor(s)?.status == 'blocked') s
    ].firstOrNull;
    final frac = steps.isEmpty ? 0.0 : done / steps.length;
    return Semantics(
      button: true,
      label: 'Mission ${detail.goal.title}, $done of ${steps.length}',
      excludeSemantics: true,
      child: TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          key: const ValueKey('mission-bar'),
          constraints: const BoxConstraints(minHeight: 48),
          padding: const EdgeInsets.symmetric(horizontal: kGutter, vertical: 8),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            border: Border.symmetric(
                horizontal: BorderSide(color: AppColors.border, width: 1)),
          ),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(
                  child: Text(detail.goal.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(13, weight: FontWeight.w500, color: AppColors.fg1))),
              const SizedBox(width: 8),
              Text('$done of ${steps.length}',
                  style: sans(12, color: AppColors.fg3)),
            ]),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: Container(
                key: const ValueKey('mission-track'),
                height: 4,
                color: AppColors.surface3,
                alignment: Alignment.centerLeft,
                child: FractionallySizedBox(
                    widthFactor: frac,
                    child: ColoredBox(color: AppColors.fg2)),
              ),
            ),
            if (blocked != null) ...[
              const SizedBox(height: 6),
              Text('Blocked: ${blocked.title}',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12, weight: FontWeight.w500, color: AppColors.fg1)),
            ],
          ]),
        ),
      ),
    );
  }
}

/// Mission board (HM-13): goal line, progress, numbered step rows.
class MissionPage extends StatelessWidget {
  const MissionPage({super.key, required this.detail});
  final GoalDetail detail;

  @override
  Widget build(BuildContext context) {
    final steps = detail.plan;
    final done = [for (final s in steps) if (_done(detail.taskFor(s))) s].length;
    final pct = steps.isEmpty ? 0 : (done * 100 / steps.length).round();
    return Material(
      color: AppColors.bg,
      child: SafeArea(
        child: Column(children: [
          PushedBar(title: 'Mission', subtitle: detail.goal.title),
          Expanded(
            child: ListView(padding: const EdgeInsets.only(bottom: 24), children: [
              if (detail.goal.outcome.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(kGutter, 16, kGutter, 0),
                  child: Text(detail.goal.outcome,
                      style: sans(13, color: AppColors.fg2)),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(kGutter, 12, kGutter, 8),
                child: LayoutBuilder(builder: (context, c) {
                  final big = bigText(context);
                  final track = ClipRRect(
                    borderRadius: BorderRadius.circular(3),
                    child: Container(
                      key: const ValueKey('board-track'),
                      height: 6,
                      color: AppColors.surface3,
                      alignment: Alignment.centerLeft,
                      child: FractionallySizedBox(
                          widthFactor: pct / 100,
                          child: ColoredBox(color: AppColors.fg2)),
                    ),
                  );
                  final label = Text('$pct percent',
                      maxLines: 1,
                      overflow: TextOverflow.visible,
                      softWrap: false,
                      style: sans(12, weight: FontWeight.w500, color: AppColors.fg2));
                  return big
                      ? Column(crossAxisAlignment: CrossAxisAlignment.start, children: [track, const SizedBox(height: 4), label])
                      : Row(children: [Expanded(child: track), const SizedBox(width: 12), SizedBox(width: 56, child: label)]);
                }),
              ),
              for (final s in steps) _step(context, s),
            ]),
          ),
        ]),
      ),
    );
  }

  Widget _step(BuildContext context, GoalPlanStep s) {
    final t = detail.taskFor(s);
    final state = missionStepState(t);
    final owner = t?.agent;
    return Semantics(
      label: '${s.n}. ${s.title}, ${owner ?? ''} $state',
      excludeSemantics: true,
      child: Container(
        key: ValueKey('step-${s.n}'),
        constraints: const BoxConstraints(minHeight: 72),
        padding: const EdgeInsets.fromLTRB(kGutter + 3, 10, kGutter, 10),
        decoration: BoxDecoration(
            border: Border(
                bottom: BorderSide(color: AppColors.border, width: 1))),
        child: Row(children: [
          Container(
            width: 30,
            height: 30,
            alignment: Alignment.center,
            decoration:
                BoxDecoration(color: AppColors.surface2, shape: BoxShape.circle),
            child: Text('${s.n}', style: sans(13, color: AppColors.fg2)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('${s.n}.  ${s.title}',
                  style: sans(15, color: AppColors.fg1)),
              Text([if (owner != null) owner, state].join('  ·  '),
                  style: sans(13,
                      color: state.startsWith('Blocked')
                          ? AppColors.fg2
                          : AppColors.fg3)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Resolves the goal a group's task room belongs to, or null.
Future<GoalDetail?> missionForGroup(DaemonClient client, String groupId) async {
  try {
    final id = groupId.startsWith('task:') ? groupId.substring(5) : groupId;
    final t = await client.getTask(id);
    final gid = t.goalId;
    if (gid == null || gid.isEmpty) return null;
    return await client.goal(gid);
  } catch (_) {
    return null;
  }
}
