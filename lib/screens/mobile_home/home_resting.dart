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

/// The working session of [agentId], if one is busy.
SessionInfo? workingSessionOf(String agentId, Iterable<SessionInfo> sessions) {
  for (final s in sessions) {
    if (!sessionBusy(s)) continue;
    final owner = managedOwner(s) ?? s.displayAgentId;
    if (owner == agentId) return s;
  }
  return null;
}

/// Round 7 resting screen when nothing needs the user: Lead and one
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
            const AgentMochi('lead', size: 88),
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
    final reduce = reduceMotion(context);
    final first = working.first.agent.shortName;
    final headline =
        working.length == 1 ? '$first is working' : '${working.length} agents are working';
    // Centred in the free space, so the card never hangs from the nav.
    return Center(
      key: const ValueKey('home-working'),
      child: SingleChildScrollView(
        physics: const BouncingScrollPhysics(),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              height: 168,
              child: Stack(alignment: Alignment.center, children: [
                if (!reduce)
                  Container(
                    width: 168,
                    height: 168,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: RadialGradient(colors: [
                        AppColors.ok.withValues(alpha: 0.16),
                        AppColors.ok.withValues(alpha: 0),
                      ]),
                    ),
                  ),
                const AgentMochi('lead', size: 96),
              ]),
            ),
            Text(headline,
                textAlign: TextAlign.center,
                style: sans(26, weight: FontWeight.w500, color: AppColors.fg1)),
            const SizedBox(height: 6),
            Text('Nothing needs you',
                textAlign: TextAlign.center,
                style: sans(14, color: AppColors.fg3)),
            const SizedBox(height: 28),
            HomeWorkingBlock(
              working: working,
              sessions: sessions,
              managed: managed,
              onOpenAgent: onOpenAgent,
              onOpenManaged: onOpenManaged,
              onOpenEveryone: onOpenEveryone,
            ),
          ],
        ),
      ),
    );
  }
}

/// Who is working: one focal card for a single agent, a grouped list of rows
/// for several (up to three, then "+n working" opens Everyone).
class HomeWorkingBlock extends StatelessWidget {
  const HomeWorkingBlock({
    super.key,
    required this.working,
    required this.sessions,
    required this.managed,
    required this.onOpenAgent,
    required this.onOpenManaged,
    required this.onOpenEveryone,
    this.forceList = false,
  });

  final List<AgentRow> working;
  final List<SessionInfo> sessions;
  final Map<String, List<SessionInfo>> managed;
  final void Function(CoordinationAgent a) onOpenAgent;
  final void Function(CoordinationAgent a) onOpenManaged;
  final VoidCallback onOpenEveryone;

  /// Rows even for one agent, under an ask.
  final bool forceList;

  static const _glass = Color(0xB81C1C20);

  @override
  Widget build(BuildContext context) {
    final shown = working.take(_maxWorking).toList();
    final more = working.length - shown.length;
    final single = shown.length == 1 && !forceList;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (single)
          _card(shown.first)
        else
          Container(
            decoration: BoxDecoration(
              color: _glass,
              borderRadius: BorderRadius.circular(20),
            ),
            clipBehavior: Clip.antiAlias,
            child: Column(children: [
              for (var i = 0; i < shown.length; i++) ...[
                if (i > 0) const HomeDivider(inset: 0),
                _row(shown[i]),
              ],
            ]),
          ),
        if (more > 0)
          Align(
            alignment: Alignment.centerLeft,
            child: Hit44(
              label: '$more more working, open Everyone',
              onTap: onOpenEveryone,
              width: 160,
              child: Text('+$more working',
                  style:
                      sans(15, weight: FontWeight.w500, color: AppColors.fg2)),
            ),
          ),
      ],
    );
  }

  ({SessionInfo? s, String task, int count}) _facts(AgentRow r) {
    final s = workingSessionOf(r.agent.id, sessions);
    return (
      s: s,
      task: s?.title ?? r.line,
      count: managed[r.agent.id]?.length ?? 0,
    );
  }

  Widget _badgeAvatar(String id, double size, double dot, Color ring) =>
      SizedBox(
        width: size,
        height: size,
        child: Stack(clipBehavior: Clip.none, children: [
          Positioned.fill(child: AgentMochi(id, size: size)),
          Positioned(
            right: -2,
            bottom: -2,
            child: Container(
              width: dot,
              height: dot,
              decoration: BoxDecoration(
                color: AppColors.ok,
                shape: BoxShape.circle,
                border: Border.all(color: ring, width: dot > 14 ? 3 : 2),
              ),
            ),
          ),
        ]),
      );

  Widget _tap(AgentRow r, String label, Widget child) => Semantics(
        button: true,
        label: label,
        child: ExcludeSemantics(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () {
              tapHaptic();
              onOpenAgent(r.agent);
            },
            child: child,
          ),
        ),
      );

  Widget _card(AgentRow r) {
    final f = _facts(r);
    return _tap(
      r,
      '${r.agent.shortName}, ${f.task}',
      Container(
        padding: const EdgeInsets.all(18),
        decoration: BoxDecoration(
          color: _glass,
          borderRadius: BorderRadius.circular(24),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(children: [
              _badgeAvatar(r.agent.id, 56, 16, const Color(0xFF1C1C20)),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.agent.shortName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(20,
                            weight: FontWeight.w600, color: AppColors.fg1)),
                    const SizedBox(height: 2),
                    Text('Working now',
                        style: sans(14, color: AppColors.fg3)),
                  ],
                ),
              ),
              if (f.count > 0)
                ManagedPill(
                  name: r.agent.shortName,
                  count: f.count,
                  tone: pillTone(heroAgentColor(r.agent.id)),
                  onTap: () => onOpenManaged(r.agent),
                ),
            ]),
            const SizedBox(height: 14),
            Text(f.task,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: sans(16, height: 1.4, color: AppColors.fg2)),
          ],
        ),
      ),
    );
  }

  Widget _row(AgentRow r) {
    final f = _facts(r);
    return _tap(
      r,
      '${r.agent.shortName}, ${f.task}',
      ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 64),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(children: [
            _badgeAvatar(r.agent.id, 40, 12, const Color(0xFF1C1C20)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(r.agent.shortName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(16,
                          weight: FontWeight.w600, color: AppColors.fg1)),
                  Text(f.task,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(13, color: AppColors.fg3)),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
