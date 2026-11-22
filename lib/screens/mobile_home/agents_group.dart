import 'package:flutter/material.dart';

import '../../crew_status.dart' show CrewState;
import '../../mochi.dart';
import '../../models.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../phone_hero.dart' show heroAgentColor;
import 'home_data.dart';
import 'home_style.dart';

/// The Agents group card: working, then needs you, then the Asleep fold.
class AgentsGroup extends StatelessWidget {
  const AgentsGroup({
    super.key,
    required this.rows,
    required this.managed,
    required this.asleepOpen,
    required this.onToggleAsleep,
    required this.onOpenAgent,
    required this.onOpenManaged,
  });

  final ({List<AgentRow> working, List<AgentRow> needs, List<AgentRow> asleep})
      rows;

  /// Managed, non-settled sessions per owning agent id.
  final Map<String, List<SessionInfo>> managed;
  final bool asleepOpen;
  final VoidCallback onToggleAsleep;
  final void Function(CoordinationAgent agent) onOpenAgent;
  final void Function(CoordinationAgent agent) onOpenManaged;

  Widget _row(AgentRow r) => AgentTile(
        key: ValueKey('agent-row-${r.agent.id}'),
        row: r,
        managedCount: managed[r.agent.id]?.length ?? 0,
        onOpen: () => onOpenAgent(r.agent),
        onManaged: () => onOpenManaged(r.agent),
      );

  @override
  Widget build(BuildContext context) {
    final live = [...rows.working, ...rows.needs];
    final asleep = rows.asleep;
    final reduce = reduceMotion(context);
    final children = <Widget>[
      for (final r in live) _row(r),
      if (asleep.isNotEmpty)
        FoldRow(
          key: const ValueKey('asleep-fold'),
          label: 'Asleep',
          count: asleep.length,
          open: asleepOpen,
          onTap: onToggleAsleep,
          lead: SizedBox(
            width: 24.0 + (asleep.take(4).length - 1) * 14,
            height: 24,
            child: Stack(children: [
              for (var i = 0; i < asleep.take(4).length; i++)
                Positioned(
                  left: i * 14.0,
                  child: AgentMochi(asleep[i].agent.id,
                      size: 24, state: AgentCharacterState.sleeping),
                ),
            ]),
          ),
        ),
    ];
    return HomeCard(children: [
      ...withDividers(children),
      AnimatedSize(
        duration: reduce ? const Duration(milliseconds: 1) : Motion.base,
        curve: Curves.easeOutCubic,
        alignment: Alignment.topCenter,
        child: asleepOpen && asleep.isNotEmpty
            ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                const HomeDivider(),
                ...withDividers([for (final r in asleep) _row(r)]),
              ])
            : const SizedBox(width: double.infinity),
      ),
    ]);
  }
}

class AgentTile extends StatelessWidget {
  const AgentTile({
    super.key,
    required this.row,
    required this.managedCount,
    required this.onOpen,
    required this.onManaged,
  });

  final AgentRow row;
  final int managedCount;
  final VoidCallback onOpen;
  final VoidCallback onManaged;

  @override
  Widget build(BuildContext context) {
    final a = row.agent;
    final charState = switch (row.state) {
      CrewState.needsYou => AgentCharacterState.needs,
      CrewState.working => AgentCharacterState.working,
      CrewState.standingBy => AgentCharacterState.sleeping,
    };
    final body = Row(children: [
      AgentMochi(a.id, size: 40, state: charState),
      SizedBox(width: S.s12),
      Expanded(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(a.displayName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(17, weight: FontWeight.w500, color: AppColors.fg1)),
            Row(children: [
              if (row.state == CrewState.working) ...[
                Spinner(size: 12, color: AppColors.fg3),
                SizedBox(width: S.s6),
              ] else if (row.state == CrewState.needsYou) ...[
                Container(
                  width: 7,
                  height: 7,
                  decoration:
                      BoxDecoration(color: askAmber, shape: BoxShape.circle),
                ),
                SizedBox(width: S.s6),
              ],
              Expanded(
                child: Text(row.line,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(13, color: AppColors.fg3)),
              ),
            ]),
          ],
        ),
      ),
    ]);
    final tapArea = Semantics(
      button: true,
      label: '${a.displayName}, ${row.line}',
      child: ExcludeSemantics(
        child: InkWell(
          onTap: onOpen,
          child: Padding(
            padding: EdgeInsets.only(left: S.of(14), right: S.of(10)),
            child: managedCount > 0
                ? body
                : Row(children: [
                    Expanded(child: body),
                    SizedBox(width: S.s8),
                    AppIcon('chevron-right', size: 14, color: AppColors.fg3),
                    SizedBox(width: S.s4),
                  ]),
          ),
        ),
      ),
    );
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 64),
      child: managedCount == 0
          ? tapArea
          : Row(children: [
              Expanded(child: tapArea),
              ManagedPill(
                name: a.displayName,
                count: managedCount,
                tone: pillTone(heroAgentColor(a.id)),
                onTap: onManaged,
              ),
              SizedBox(width: S.s6),
            ]),
    );
  }
}

/// The tinted "n managed" pill: 30 pt visual inside a 44 pt hit box.
class ManagedPill extends StatelessWidget {
  const ManagedPill({
    super.key,
    required this.name,
    required this.count,
    required this.tone,
    required this.onTap,
  });

  final String name;
  final int count;
  final Color tone;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Hit44(
        label: '$name, $count managed session${count == 1 ? '' : 's'}',
        onTap: onTap,
        width: 112,
        child: TonePill('$count managed', tone: tone, icon: 'layers', height: 30),
      );
}
