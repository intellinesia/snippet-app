import 'package:flutter/material.dart';

import '../../api.dart';
import '../../goal_models.dart';
import '../../panel.dart';
import '../../platform.dart';
import '../../theme.dart';
import '../../widgets.dart';
import 'goal_detail_screen.dart';
import 'goal_phone_page.dart';

Tone attentionTone(GoalAttention a) => switch (a) {
      GoalAttention.stalled => Tone.danger,
      GoalAttention.readyToClose => Tone.ok,
    };

class AttentionChip extends StatelessWidget {
  const AttentionChip(this.attention, {super.key});
  final GoalAttention attention;

  @override
  Widget build(BuildContext context) =>
      Tag(attention.label, tone: attentionTone(attention), dot: true);
}

class GoalProgressBar extends StatelessWidget {
  const GoalProgressBar(this.progress, {super.key, this.colour});
  final GoalProgress progress;
  final Color? colour;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(R.pill),
      child: Stack(children: [
        Container(height: 4, color: AppColors.surface3),
        FractionallySizedBox(
          widthFactor: progress.fraction,
          child: Container(height: 4, color: colour ?? AppColors.accent),
        ),
      ]),
    );
  }
}

/// A goal in a list: title, slice progress, evidence and anything needing a look.
class GoalRow extends StatelessWidget {
  const GoalRow({super.key, required this.goal, required this.onTap});
  final Goal goal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final p = goal.progress;
    return HoverSurface(
      onTap: onTap,
      radius: 10,
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: kMobile ? S.s12 : S.s8, vertical: kMobile ? S.s12 : S.of(9)),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(
              child: Text(goal.title.isEmpty ? '(untitled goal)' : goal.title,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: sans(kMobile ? 14 : 13,
                      weight: W.label, color: AppColors.fg1)),
            ),
            if (goal.attention != null) ...[
              SizedBox(width: S.s8),
              AttentionChip(goal.attention!),
            ],
          ]),
          SizedBox(height: S.s8),
          GoalProgressBar(p,
              colour: goal.attention == GoalAttention.readyToClose
                  ? AppColors.ok
                  : null),
          SizedBox(height: S.s6),
          Row(children: [
            Text('${p.done} of ${p.total} slices',
                style: sans(12, color: AppColors.fg3, tabular: true)),
            const Spacer(),
            AppIcon('check', size: 11, color: AppColors.fg4),
            SizedBox(width: S.s4),
            Text('${goal.evidence.done} of ${goal.evidence.total} evidenced',
                style: sans(12, color: AppColors.fg3, tabular: true)),
          ]),
        ]),
      ),
    );
  }
}

/// Open a goal: a sheet on a phone, a drawer panel on desktop.
Future<void> openGoalDetail(
    BuildContext context, DaemonClient client, String goalId) {
  if (kMobile) return openGoalPhonePage(context, client, goalId);
  return presentScreen<void>(
    context,
    style: PanelStyle.drawer,
    purpose: ShellPanelPurpose.generic,
    panelId: 'goal-$goalId',
    originClient: client,
    maxWidth: 640,
    maxHeight: 820,
    builder: (_, close) =>
        GoalDetailScreen(client: client, goalId: goalId, onClose: close),
  );
}
