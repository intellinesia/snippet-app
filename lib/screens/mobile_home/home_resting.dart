import 'package:flutter/material.dart';

import '../../mochi.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../phone_hero.dart' show heroAgentColor;
import '../shell_nav.dart' show sessionBusy;
import 'agents_group.dart' show ManagedPill;
import 'home_data.dart';
import 'home_style.dart';

const int _maxWorking = 3;

/// The working session of [agentId] that has plan progress, else any busy one.
SessionInfo? workingSessionOf(String agentId, Iterable<SessionInfo> sessions) {
  SessionInfo? busy;
  for (final s in sessions) {
    if (!sessionBusy(s)) continue;
    final owner = managedOwner(s) ?? s.displayAgentId;
    if (owner != agentId) continue;
    if (s.plan != null && s.plan!.total > 0) return s;
    busy ??= s;
  }
  return busy;
}

/// Round 7 resting screen when nothing needs the user: Mission Control and one
/// line, plus who is working. Never an empty centre.
class HomeResting extends StatelessWidget {
  const HomeResting({
    super.key,
    required this.working,
    required this.sessions,
    required this.managed,
    required this.asleepCount,
    required this.settledCount,
    required this.onOpenSession,
    required this.onOpenAgent,
    required this.onOpenManaged,
    required this.onOpenEveryone,
  });

  final List<AgentRow> working;
  final List<SessionInfo> sessions;
  final Map<String, List<SessionInfo>> managed;
  final int asleepCount;
  final int settledCount;
  final void Function(SessionInfo s) onOpenSession;
  final void Function(CoordinationAgent a) onOpenAgent;
  final void Function(CoordinationAgent a) onOpenManaged;
  final VoidCallback onOpenEveryone;

  @override
  Widget build(BuildContext context) {
    final reduce = reduceMotion(context);
    final isWorking = working.isNotEmpty;
    return AnimatedSwitcher(
      duration: reduce ? const Duration(milliseconds: 120) : Motion.base,
      child: isWorking
          ? _workingView(context)
          : _quietView(context),
    );
  }

  Widget _quietView(BuildContext context) {
    final reduce = reduceMotion(context);
    final parts = <String>[
      if (asleepCount > 0) '$asleepCount agent${asleepCount == 1 ? '' : 's'} asleep',
      if (settledCount > 0)
        '$settledCount session${settledCount == 1 ? '' : 's'} settled',
    ];
    return Column(
      key: const ValueKey('home-quiet'),
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        SizedBox(
          width: 160,
          height: 128,
          child: Stack(alignment: Alignment.center, children: [
            if (!reduce)
              Container(
                width: 128,
                height: 128,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  gradient: RadialGradient(colors: [
                    AppColors.ok.withValues(alpha: 0.16),
                    AppColors.ok.withValues(alpha: 0),
                  ]),
                ),
              ),
            const AgentMochi('mission-control', size: 88),
          ]),
        ),
        const SizedBox(height: 16),
        Text('Nothing needs you.',
            textAlign: TextAlign.center,
            style: sans(24, weight: FontWeight.w500, color: AppColors.fg1)),
        if (parts.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(parts.join(', '),
              textAlign: TextAlign.center,
              style: sans(13, color: AppColors.fg3)),
        ],
      ],
    );
  }

  Widget _workingView(BuildContext context) {
    final shown = working.take(_maxWorking).toList();
    final more = working.length - shown.length;
    // Centred in the free space, so a short list does not hang from the top.
    return Center(
      key: const ValueKey('home-working'),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Center(child: AgentMochi('mission-control', size: 52)),
            const SizedBox(height: 14),
            Text('All on track.',
                textAlign: TextAlign.center,
                style: sans(22, weight: FontWeight.w500, color: AppColors.fg1)),
            const SizedBox(height: 4),
            Text('Nothing needs you.',
                textAlign: TextAlign.center,
                style: sans(13, color: AppColors.fg3)),
            const HomeLabel('In progress', top: 28),
            for (final r in shown) _workingBlock(r),
            if (more > 0)
              Align(
                alignment: Alignment.centerLeft,
                child: Hit44(
                  label: '$more more working, open Everyone',
                  onTap: onOpenEveryone,
                  width: 160,
                  child: Text('+$more working',
                      style: sans(15,
                          weight: FontWeight.w500, color: AppColors.fg2)),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _workingBlock(AgentRow r) {
    final s = workingSessionOf(r.agent.id, sessions);
    final plan = s?.plan;
    final count = managed[r.agent.id]?.length ?? 0;
    final task = plan?.current ?? s?.title ?? r.line;
    return Semantics(
      button: true,
      label: '${r.agent.displayName}, $task',
      child: ExcludeSemantics(
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            tapHaptic();
            onOpenAgent(r.agent);
          },
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 72),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
                SizedBox(
                  width: 40,
                  height: 40,
                  child: Stack(clipBehavior: Clip.none, children: [
                    Positioned.fill(
                        child: AgentMochi(r.agent.id, size: 40)),
                    Positioned(
                      right: -3,
                      bottom: -3,
                      child: Container(
                        width: 14,
                        height: 14,
                        decoration: BoxDecoration(
                          color: AppColors.ok,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.bg, width: 2),
                        ),
                      ),
                    ),
                  ]),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(children: [
                        Expanded(
                          child: Text(r.agent.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(17,
                                  weight: FontWeight.w600,
                                  color: AppColors.fg1)),
                        ),
                        if (count > 0)
                          ManagedPill(
                            name: r.agent.displayName,
                            count: count,
                            tone: pillTone(heroAgentColor(r.agent.id)),
                            onTap: () => onOpenManaged(r.agent),
                          ),
                      ]),
                      Text(task,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(14, color: AppColors.fg2)),
                      if (plan != null && plan.total > 0) ...[
                        const SizedBox(height: 8),
                        Row(children: [
                          Flexible(
                              child: ConstrainedBox(
                                  constraints:
                                      const BoxConstraints(maxWidth: 150),
                                  child: _SegBar(
                                      done: plan.done, total: plan.total))),
                          const SizedBox(width: 10),
                          Text('${plan.done} of ${plan.total} steps',
                              style: sans(12, color: AppColors.fg3)),
                        ]),
                      ],
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Segmented plan progress, 4 pt high and 150 pt wide.
class _SegBar extends StatelessWidget {
  const _SegBar({required this.done, required this.total});

  final int done;
  final int total;

  @override
  Widget build(BuildContext context) {
    final n = total.clamp(1, 12);
    final filled = (done * n / total).round().clamp(0, n);
    return SizedBox(
      width: double.infinity,
      height: 4,
      child: Row(children: [
        for (var i = 0; i < n; i++) ...[
          if (i > 0) const SizedBox(width: 2),
          Expanded(
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: i < filled
                    ? AppColors.ok
                    : AppColors.fg1.withValues(alpha: 0.14),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
        ],
      ]),
    );
  }
}
