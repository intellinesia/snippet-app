import 'package:flutter/material.dart';

import '../../api.dart';
import '../../chat/signal_row.dart' show profileMeta;
import '../../crew_status.dart';
import '../../mobile_kit.dart';
import '../../mochi.dart';
import '../../models.dart';
import '../../tap_detector.dart';
import '../../toast_avoid.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../group_messaging.dart' show openGroupThread;
import '../shell_nav.dart' show sessionBusy;
import 'agents_home.dart';
import 'collapsing_root.dart';
import 'home_data.dart';

enum AllFilter { all, working, idle, asking }

/// All agents (HM-04): a pushed page with back, state chips, full-bleed rows.
class QuietAgentsScreen extends StatefulWidget {
  const QuietAgentsScreen({
    super.key,
    required this.client,
    required this.agents,
    required this.sessions,
    required this.onOpenAgent,
    required this.onOpenLead,
    this.onOpenSession,
    this.onBack,
    this.groups,
    this.initialGroups = false,
  });

  final void Function(SessionInfo s)? onOpenSession;
  final DaemonClient client;
  final List<CoordinationAgent> agents;
  final List<SessionInfo> sessions;
  final void Function(CoordinationAgent a) onOpenAgent;
  final VoidCallback onOpenLead;
  final VoidCallback? onBack;

  /// Groups to show; when null they are fetched from the client.
  final List<GroupSummary>? groups;
  final bool initialGroups;

  @override
  State<QuietAgentsScreen> createState() => _QuietAgentsScreenState();
}

class _Line {
  _Line(this.agent, this.state, this.line, this.model);
  final CoordinationAgent agent;
  final CrewState state;
  final String line, model;
}

class _QuietAgentsScreenState extends State<QuietAgentsScreen> {
  List<GroupSummary> _groups = const [];
  Map<String, InferenceProfile> _profiles = const {};
  final _q = TextEditingController();
  AllFilter _filter = AllFilter.all;
  bool _groupsSegment = false;
  bool _searching = false;
  bool _expanded = false;

  static const _fold = 8;

  @override
  void initState() {
    super.initState();
    _groupsSegment = widget.initialGroups;
    if (widget.groups != null) {
      _groups = widget.groups!;
    } else {
      widget.client.groups().then((g) {
        if (mounted) setState(() => _groups = g);
      }).catchError((_) {});
    }
    widget.client.getConfig().then((cfg) {
      if (mounted) {
        setState(() => _profiles = {for (final p in cfg.profiles) p.name: p});
      }
    }).catchError((_) {});
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final q = _q.text.trim().toLowerCase();
    final rows = agentRows(widget.agents, widget.sessions);
    final lead = widget.agents.where((a) => a.isLead).firstOrNull;
    String model(CoordinationAgent a) =>
        profileMeta(_profiles, a.deskProfile ?? a.profile).label.toLowerCase();
    final leadBusy = widget.sessions
        .any((s) => s.displayAgentId == 'lead' && !s.settled && sessionBusy(s));
    final everyone = <_Line>[
      for (final r in [...rows.needs, ...rows.working, ...rows.asleep])
        _Line(r.agent, r.state, r.line, model(r.agent)),
      if (lead != null)
        _Line(lead, leadBusy ? CrewState.working : CrewState.standingBy,
            lead.lastMessage?.text ?? 'Orchestrator', model(lead)),
    ];
    int n(CrewState s) => everyone.where((l) => l.state == s).length;
    final working = n(CrewState.working),
        idle = n(CrewState.standingBy),
        asking = n(CrewState.needsYou);
    final groups = sortedGroups(_groups);
    final shownAgents = [
      for (final l in everyone)
        if ((q.isEmpty || l.agent.displayName.toLowerCase().contains(q)) &&
            switch (_filter) {
              AllFilter.all => true,
              AllFilter.working => l.state == CrewState.working,
              AllFilter.idle => l.state == CrewState.standingBy,
              AllFilter.asking => l.state == CrewState.needsYou,
            })
          l
    ];
    final shownGroups = [
      for (final g in groups)
        if (q.isEmpty || g.title.toLowerCase().contains(q)) g
    ];
    final a = kAndroidLook;
    final side = a ? 16.0 : MK.gutter;
    final children = <Widget>[
      // iPhone: the back button needs its own row above the large title.
      if (!a) const SizedBox(height: 50),
      const LargeTitle('All agents'),
      if (_searching)
        ToastAvoid(
          child: Padding(
            padding: EdgeInsets.fromLTRB(side, 8, side, 0),
            child: Semantics(
              textField: true,
              label: 'Search agents and groups',
              child: TextField(
                controller: _q,
                autofocus: true,
                onChanged: (_) => setState(() {}),
                style: sans(15, color: AppColors.fg1),
                cursorColor: AppColors.fg1,
                decoration: InputDecoration(
                  isDense: true,
                  filled: true,
                  fillColor: AppColors.surface2,
                  prefixIcon: Padding(
                    padding: const EdgeInsets.only(left: 12, right: 8),
                    child: AppIcon('search', size: 16, color: AppColors.fg3),
                  ),
                  prefixIconConstraints:
                      const BoxConstraints(minWidth: 36, minHeight: 20),
                  hintText: 'Search agents and groups',
                  hintStyle: sans(15, color: AppColors.fg3),
                  contentPadding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                  border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(a ? 28 : 12),
                      borderSide: BorderSide.none),
                ),
              ),
            ),
          ),
        ),
      if (_groupsSegment)
        MkFilterGroup<bool>(
          padding: MK.filterPad,
          options: [
            const MkFilter(false, 'Agents'),
            MkFilter(true, 'Groups', count: groups.length),
          ],
          selected: true,
          onSelect: (v) => setState(() => _groupsSegment = v),
        )
      else
        MkFilterGroup<AllFilter>(
          padding: MK.filterPad,
          options: [
            MkFilter(AllFilter.all, 'All', count: everyone.length),
            MkFilter(AllFilter.working, 'Working', count: working),
            MkFilter(AllFilter.idle, 'Idle', count: idle),
            MkFilter(AllFilter.asking, 'Needs you', count: asking),
          ],
          selected: _filter,
          onSelect: (f) => setState(() => _filter = f),
        ),
    ];

    if (_groupsSegment) {
      if (shownGroups.isEmpty) children.add(const _Empty('No groups'));
      final workingIds = {
        for (final l in everyone)
          if (l.state == CrewState.working) l.agent.id
      };
      children.add(const SizedBox(height: 8));
      children.add(MkList(children: [
        for (var i = 0; i < shownGroups.length; i++)
          () {
            final g = shownGroups[i];
            final members = g.members.length;
            final active =
                g.members.where((m) => workingIds.contains(m.id)).length;
            final at = groupActivityAt(g);
            final roster =
                '$members ${members == 1 ? 'member' : 'members'}, $active active';
            return MkRow(
              title: g.title.isEmpty ? 'Group' : g.title,
              leading: groupMark(40, radius: 14),
              time: at == null
                  ? null
                  : relativeTime(at.millisecondsSinceEpoch ~/ 1000),
              subtitle: (g.preview ?? '').isEmpty ? roster : g.preview,
              divider: i < shownGroups.length - 1,
              onTap: () =>
                  openGroupThread(context, client: widget.client, group: g),
            );
          }(),
      ]));
    } else {
      children.add(const MkSection('Agents'));
      if (shownAgents.isEmpty) {
        children.add(_Empty(switch (_filter) {
          AllFilter.working => 'No agents are working',
          AllFilter.asking => 'No agents need you',
          AllFilter.idle => 'No agents are idle',
          AllFilter.all => 'No agents match',
        }));
      }
      final folded = !_expanded && q.isEmpty && shownAgents.length > _fold + 1;
      final visible = folded ? shownAgents.take(_fold).toList() : shownAgents;
      children.add(MkList(children: [
        for (var i = 0; i < visible.length; i++)
          () {
            final l = visible[i];
            final busy = l.state == CrewState.working;
            final ask = l.state == CrewState.needsYou;
            return MkRow(
              title: l.agent.shortName,
              leading: AgentMochi(l.agent.id, size: 40),
              subtitle: [
                if (l.model.isNotEmpty) l.model,
                if (l.line.isNotEmpty) l.line
              ].join(' · '),
              trailing: ask
                  ? const MkStateMark(MkState.needsYou)
                  : busy
                      ? const MkStateMark(MkState.working)
                      : null,
              divider: i < visible.length - 1 || folded,
              onTap: () => l.agent.isLead
                  ? widget.onOpenLead()
                  : widget.onOpenAgent(l.agent),
            );
          }(),
      ]));
      if (folded) {
        children.add(_Fold('Show ${shownAgents.length - _fold} more',
            () => setState(() => _expanded = true)));
      }
    }
    children.add(SizedBox(height: MK.bottomClearance(context)));

    return CollapsingRoot(
      title: 'All agents',
      leading: MkIconButton(
          icon: a ? 'arrow-left' : 'chevron-left',
          label: 'Back',
          onTap: widget.onBack ?? () => Navigator.maybePop(context)),
      actions: [
        MkIconButton(
            icon: 'users',
            label: 'Groups',
            bare: !a,
            onTap: () => setState(() => _groupsSegment = !_groupsSegment)),
        MkIconButton(
            icon: 'search',
            label: 'Search',
            bare: !a,
            onTap: () => setState(() {
                  _searching = !_searching;
                  if (!_searching) _q.clear();
                })),
      ],
      child: ListView(padding: EdgeInsets.zero, children: children),
    );
  }
}

class _Fold extends StatelessWidget {
  const _Fold(this.label, this.onTap);
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 48),
            child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: kAndroidLook ? 28 : MK.gutter),
              child: Row(children: [
                Text(label,
                    style: sans(14, weight: W.label, color: AppColors.fg3)),
                const SizedBox(width: 6),
                AppIcon('chevron-down', size: 16, color: AppColors.fg3),
              ]),
            ),
          ),
        ),
      );
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(kGutter, 24, kGutter, 8),
        child: Center(
            child: Text(text,
                textAlign: TextAlign.center,
                style: sans(14, color: AppColors.fg3))),
      );
}
