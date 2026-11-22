import 'package:flutter/material.dart';

import '../../mochi.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../agent_card.dart' show agentRowTime;
import '../phone_hero.dart' show heroAgentColor;
import '../shell_nav.dart' show sessionBusy;
import 'agents_group.dart' show ManagedPill;
import 'home_data.dart';
import 'home_style.dart';

const int _maxWorking = 3;

/// The newest finished session that left a result, for the "last result" row.
SessionInfo? lastResult(Iterable<SessionInfo> sessions) {
  SessionInfo? best;
  for (final s in sessions) {
    final at = s.finishedAt;
    if (at == null || s.running) continue;
    if (best == null || at > best.finishedAt!) best = s;
  }
  return best;
}

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
/// line, plus who is working and the last result. Never an empty centre.
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
    final last = lastResult(sessions);
    final isWorking = working.isNotEmpty;
    return AnimatedSwitcher(
      duration: reduce ? const Duration(milliseconds: 120) : Motion.base,
      child: isWorking
          ? _workingView(context, last)
          : _quietView(context, last),
    );
  }

  Widget _quietView(BuildContext context, SessionInfo? last) {
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
        if (last != null) ...[
          const SizedBox(height: 20),
          _lastRow(last),
        ],
      ],
    );
  }

  Widget _workingView(BuildContext context, SessionInfo? last) {
    final shown = working.take(_maxWorking).toList();
    final more = working.length - shown.length;
    return ListView(
      key: const ValueKey('home-working'),
      physics: const BouncingScrollPhysics(),
      padding: EdgeInsets.zero,
      children: [
        Row(children: [
          const AgentMochi('mission-control', size: 52),
          const SizedBox(width: 12),
          Expanded(
            child: Text('Nothing needs you.',
                style:
                    sans(22, weight: FontWeight.w500, color: AppColors.fg1)),
          ),
        ]),
        const HomeLabel('In progress', top: 20),
        for (final r in shown) _workingBlock(r),
        if (more > 0)
          Hit44(
            label: '$more more working, open Everyone',
            onTap: onOpenEveryone,
            width: 160,
            child: Text('+$more working',
                style: sans(15, weight: FontWeight.w500, color: AppColors.fg2)),
          ),
        if (last != null) ...[
          const HomeLabel('Last result', top: 16),
          _lastRow(last),
        ],
      ],
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
              child: Row(children: [
                AgentMochi(r.agent.id, size: 48),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                              color: AppColors.ok, shape: BoxShape.circle),
                        ),
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(r.agent.displayName,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(17,
                                  weight: FontWeight.w600,
                                  color: AppColors.fg1)),
                        ),
                      ]),
                      const SizedBox(height: 2),
                      Text(task,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(14, color: AppColors.fg2)),
                      if (plan != null && plan.total > 0) ...[
                        const SizedBox(height: 6),
                        Row(children: [
                          _SegBar(done: plan.done, total: plan.total),
                          const SizedBox(width: 8),
                          Text('${plan.done} of ${plan.total}',
                              style: codeMono(12, color: AppColors.fg3)),
                        ]),
                      ],
                    ],
                  ),
                ),
                if (count > 0)
                  ManagedPill(
                    name: r.agent.displayName,
                    count: count,
                    tone: pillTone(heroAgentColor(r.agent.id)),
                    onTap: () => onOpenManaged(r.agent),
                  ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _lastRow(SessionInfo s) {
    final said = (s.resultSummary ?? '').trim();
    final line = said.isNotEmpty ? said.split('\n').first : s.title;
    final at = s.finishedAt == null
        ? null
        : DateTime.fromMillisecondsSinceEpoch(s.finishedAt! * 1000);
    return Semantics(
      button: true,
      label: 'Last result, $line',
      child: ExcludeSemantics(
        child: GestureDetector(
          key: const ValueKey('home-last-result'),
          behavior: HitTestBehavior.opaque,
          onTap: () {
            tapHaptic();
            onOpenSession(s);
          },
          child: SizedBox(
            height: 48,
            child: Row(children: [
              AgentMochi(s.displayAgentId ?? 'snippet', size: 28),
              const SizedBox(width: 10),
              Expanded(
                child: Text(line,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(15, color: AppColors.fg2)),
              ),
              const SizedBox(width: 8),
              Text(agentRowTime(at), style: codeMono(12, color: AppColors.fg3)),
              const SizedBox(width: 4),
              AppIcon('chevron-right', size: 14, color: AppColors.fg3),
            ]),
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
      width: 150,
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
