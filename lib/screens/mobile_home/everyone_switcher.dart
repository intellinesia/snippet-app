import 'package:flutter/material.dart';

import '../../models.dart';
import '../../mochi.dart';
import '../../quiet.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../session_list_row.dart' show projectLabel;
import 'home_data.dart';

/// Rows each section shows before its "Show n more" fold row.
const int kSwitcherFold = 6;

/// SH-11: the Everyone switcher sheet for agents, groups and sessions.
Future<void> showEveryoneSwitcher(
  BuildContext context, {
  required List<CoordinationAgent> agents,
  required List<GroupSummary> groups,
  required List<SessionInfo> sessions,
  required void Function(CoordinationAgent a) onOpenAgent,
  required void Function(GroupSummary g) onOpenGroup,
  required void Function(SessionInfo s) onOpenSession,
}) {
  final dark = AppColors.bg.computeLuminance() < 0.5;
  final reduced = reduceMotion(context);
  final h = MediaQuery.sizeOf(context).height;
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: false,
    backgroundColor: Colors.transparent,
    barrierColor: Colors.black.withValues(alpha: dark ? 0.58 : 0.32),
    constraints:
        BoxConstraints(maxHeight: h - 100, maxWidth: double.infinity),
    sheetAnimationStyle: reduced
        ? AnimationStyle.noAnimation
        : sheetMotion,
    builder: (ctx) => AppSheetSurface(
        expand: true,
        child: EveryoneSwitcher(
      agents: agents,
      groups: groups,
      sessions: sessions,
      onOpenAgent: (a) {
        Navigator.of(ctx).pop();
        onOpenAgent(a);
      },
      onOpenGroup: (g) {
        Navigator.of(ctx).pop();
        onOpenGroup(g);
      },
      onOpenSession: (s) {
        Navigator.of(ctx).pop();
        onOpenSession(s);
      },
    )),
  );
}

class EveryoneSwitcher extends StatefulWidget {
  const EveryoneSwitcher({
    super.key,
    required this.agents,
    required this.groups,
    required this.sessions,
    required this.onOpenAgent,
    required this.onOpenGroup,
    required this.onOpenSession,
  });
  final List<CoordinationAgent> agents;
  final List<GroupSummary> groups;
  final List<SessionInfo> sessions;
  final void Function(CoordinationAgent a) onOpenAgent;
  final void Function(GroupSummary g) onOpenGroup;
  final void Function(SessionInfo s) onOpenSession;

  @override
  State<EveryoneSwitcher> createState() => _EveryoneSwitcherState();
}

class _EveryoneSwitcherState extends State<EveryoneSwitcher> {
  final _q = TextEditingController();
  final _open = <String>{};

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Widget _label(String t) => Container(
        height: 28,
        alignment: Alignment.bottomLeft,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 6),
        child: Text(t, style: sans(12, weight: W.label, color: AppColors.fg3)),
      );

  /// Rows up to the fold, then a "Show n more" row that expands in place.
  List<Widget> _section(String key, List<Widget> rows) {
    final searching = _q.text.trim().isNotEmpty;
    final expanded = searching || _open.contains(key);
    if (rows.length <= kSwitcherFold || expanded) return rows;
    return [
      ...rows.take(kSwitcherFold),
      Semantics(
        button: true,
        label: 'Show all ${rows.length}',
        excludeSemantics: true,
        child: InkWell(
          onTap: () => setState(() => _open.add(key)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: const EdgeInsets.only(left: 29, right: 20),
              child: Row(children: [
                AppIcon('chevron-down', size: 16, color: AppColors.fg2),
                const SizedBox(width: 8),
                Text('Show all ${rows.length}',
                    style: sans(14, weight: W.label, color: AppColors.fg2)),
              ]),
            ),
          ),
        ),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim().toLowerCase();
    bool hit(String s) => q.isEmpty || s.toLowerCase().contains(q);
    final crew = agentRows(widget.agents, widget.sessions);
    final needs = {for (final r in crew.needs) r.agent.id};
    final ordered = [...crew.needs, ...crew.working, ...crew.asleep]
        .where((r) => hit(r.agent.displayName))
        .toList();
    final idle = {for (final r in crew.asleep) r.agent.id};
    final groups =
        sortedGroups(widget.groups).where((g) => hit(g.title)).toList();
    final sessions = [
      for (final s in widget.sessions)
        if (hit(s.title)) s
    ];
    final agentRowsW = [
      for (final r in ordered)
        _AgentLine(
          key: ValueKey('sw-agent-${r.agent.id}'),
          agent: r.agent,
          needsYou: needs.contains(r.agent.id),
          idle: idle.contains(r.agent.id),
          last: r.line,
          onTap: () => widget.onOpenAgent(r.agent),
        )
    ];
    final groupRowsW = [
      for (final g in groups)
        _GroupLine(group: g, onTap: () => widget.onOpenGroup(g))
    ];
    final sessionRowsW = [
      for (final s in sessions)
        _SessionLine(session: s, onTap: () => widget.onOpenSession(s))
    ];
    final mq = MediaQuery.of(context);
    return Padding(
      padding: EdgeInsets.only(bottom: mq.viewInsets.bottom),
      child: Column(children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: SizedBox(
            height: 44,
            child: TextField(
              key: const ValueKey('switcher-search'),
              controller: _q,
              onChanged: (_) => setState(() {}),
              style: sans(14, color: AppColors.fg1),
              cursorColor: AppColors.fg1,
              textAlignVertical: TextAlignVertical.center,
              decoration: InputDecoration(
                filled: true,
                fillColor: AppColors.surface2,
                hintText: MediaQuery.textScalerOf(context).scale(14) / 14 >= 1.5
                    ? 'Search'
                    : 'Search agents, groups, sessions',
                hintStyle: sans(14, color: AppColors.fg3),
                prefixIcon: Padding(
                  padding: const EdgeInsets.only(left: 12, right: 10),
                  child: AppIcon('search', size: 20, color: AppColors.fg2),
                ),
                prefixIconConstraints:
                    const BoxConstraints(minWidth: 0, minHeight: 0),
                contentPadding: EdgeInsets.zero,
                border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(12),
                    borderSide: BorderSide.none),
              ),
            ),
          ),
        ),
        Expanded(
          child: ListView(
            padding: EdgeInsets.only(bottom: mq.padding.bottom + 8),
            children: [
              if (agentRowsW.isNotEmpty) ...[
                _label('Agents'),
                ..._section('agents', agentRowsW),
              ],
              if (groupRowsW.isNotEmpty) ...[
                _label('Groups'),
                ..._section('groups', groupRowsW),
              ],
              if (sessionRowsW.isNotEmpty) ...[
                _label('Sessions'),
                ..._section('sessions', sessionRowsW),
              ],
            ],
          ),
        ),
      ]),
    );
  }
}

/// Name first: it keeps its natural width (up to 70 percent) and the quiet
/// last line shrinks with an ellipsis; under the name once text is large.
Widget _line(BuildContext context, Widget name, Widget? trailing,
    {required double leadWidth}) {
  final big = MediaQuery.textScalerOf(context).scale(15) / 15 >= 1.3;
  if (big || trailing == null) {
    return Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
      name,
      if (trailing != null) trailing,
    ]);
  }
  return LayoutBuilder(
    builder: (context, box) => Row(children: [
      ConstrainedBox(
          constraints: BoxConstraints(maxWidth: box.maxWidth * 0.7),
          child: name),
      const SizedBox(width: 12),
      Expanded(
          child: Align(
              alignment: Alignment.centerRight,
              child: trailing)),
    ]),
  );
}

class _AgentLine extends StatelessWidget {
  const _AgentLine(
      {super.key,
      required this.agent,
      required this.needsYou,
      required this.idle,
      required this.last,
      required this.onTap});
  final CoordinationAgent agent;
  final bool needsYou, idle;
  final String last;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final name = Text(agent.shortName,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: sans(15,
            weight: idle ? W.body : W.label, color: AppColors.fg1));
    final Widget? tail = needsYou
        ? FittedBox(
            fit: BoxFit.scaleDown,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              const QuietHand(size: 16),
              const SizedBox(width: 4),
              Text('Needs you',
                  style: sans(12, weight: W.label, color: quietAmber)),
            ]))
        : last.isEmpty
            ? null
            : Text(last,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.right,
                style: sans(12, color: AppColors.fg3));
    return Semantics(
      button: true,
      label: agent.shortName,
      hint: needsYou ? 'Needs you' : last,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(21, 4, 20, 4),
            child: Row(children: [
              AgentMochi(agent.id, size: 30),
              const SizedBox(width: 12),
              Expanded(
                  child: _line(context, name, tail, leadWidth: 63)),
            ]),
          ),
        ),
      ),
    );
  }
}

class _GroupLine extends StatelessWidget {
  const _GroupLine({required this.group, required this.onTap});
  final GroupSummary group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final n = group.members.length;
    return Semantics(
      button: true,
      label: group.title,
      hint: '$n members',
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(21, 4, 20, 4),
            child: Row(children: [
              Container(
                width: 30,
                height: 30,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(8.4),
                  border: Border.all(color: AppColors.border),
                ),
                child: Center(
                    child: AppIcon('users', size: 16, color: AppColors.fg2)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: _line(
                    context,
                    Text(group.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(15, color: AppColors.fg1)),
                    Text('$n members',
                        style: sans(12, color: AppColors.fg3)),
                    leadWidth: 63),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

class _SessionLine extends StatelessWidget {
  const _SessionLine({required this.session, required this.onTap});
  final SessionInfo session;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final t = session.title.trim().isEmpty
        ? 'Untitled session'
        : session.title.trim();
    final owner = projectLabel(session);
    return Semantics(
      button: true,
      label: t,
      hint: owner,
      excludeSemantics: true,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 48),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28.5, 4, 20, 4),
            child: Row(children: [
              AppIcon('chat', size: 20, color: AppColors.fg2),
              const SizedBox(width: 14),
              Expanded(
                child: _line(
                    context,
                    Text(t,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(14, color: AppColors.fg1)),
                    owner.isEmpty
                        ? null
                        : Text(owner,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(12, color: AppColors.fg3)),
                    leadWidth: 62),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
