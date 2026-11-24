import 'package:flutter/material.dart';

import '../../api.dart';
import '../../chat/signal_row.dart' show profileMeta;
import '../../crew_status.dart';
import '../../models.dart';
import '../../quiet.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../group_messaging.dart' show openGroupThread;
import '../shell_nav.dart' show sessionBusy;
import 'agents_home.dart';
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
    final leadBusy = widget.sessions.any((s) =>
        s.displayAgentId == 'lead' && !s.settled && sessionBusy(s));
    final everyone = <_Line>[
      for (final r in [...rows.needs, ...rows.working, ...rows.asleep])
        _Line(r.agent, r.state, r.line, model(r.agent)),
      if (lead != null)
        _Line(
            lead,
            leadBusy ? CrewState.working : CrewState.standingBy,
            lead.lastMessage?.text ?? 'Orchestrator',
            model(lead)),
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
    final subtitle =
        '${everyone.length} ${everyone.length == 1 ? 'agent' : 'agents'}, ${groups.length} ${groups.length == 1 ? 'group' : 'groups'}';

    final children = <Widget>[];
    if (_searching) {
      children.add(Padding(
        padding: const EdgeInsets.fromLTRB(kGutter, 8, kGutter, 0),
        child: SizedBox(
          height: 44,
          child: TextField(
            controller: _q,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            style: sans(14, color: AppColors.fg1),
            cursorColor: AppColors.fg1,
            decoration: InputDecoration(
              isDense: true,
              filled: true,
              fillColor: AppColors.surface2,
              hintText: 'Search agents and groups',
              hintStyle: sans(14, color: AppColors.fg3),
              prefixIcon: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 12),
                  child: AppIcon('search', size: 20, color: AppColors.fg2)),
              prefixIconConstraints:
                  const BoxConstraints(minWidth: 0, minHeight: 0),
              contentPadding: const EdgeInsets.symmetric(vertical: 12),
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none),
            ),
          ),
        ),
      ));
    }
    children.add(Padding(
      padding: const EdgeInsets.only(top: 8),
      child: _groupsSegment
          ? ChipRow(gap: 8, chips: [
              StateChip('Agents', false, () => setState(() => _groupsSegment = false),
                  fill: AppColors.surface2),
              StateChip('Groups ${groups.length}', true, () {}),
            ])
          : ChipRow(gap: 8, chips: [
              StateChip('All ${everyone.length}', _filter == AllFilter.all,
                  () => setState(() => _filter = AllFilter.all),
                  fill: AppColors.surface2),
              StateChip('Working $working', _filter == AllFilter.working,
                  () => setState(() => _filter = AllFilter.working),
                  fill: AppColors.surface2),
              StateChip('Idle $idle', _filter == AllFilter.idle,
                  () => setState(() => _filter = AllFilter.idle),
                  fill: AppColors.surface2),
              StateChip('Asking $asking', _filter == AllFilter.asking,
                  () => setState(() => _filter = AllFilter.asking),
                  fill: AppColors.surface2, amberDot: asking > 0),
            ]),
    ));

    if (_groupsSegment) {
      if (shownGroups.isEmpty) children.add(const _Empty('No groups'));
      for (final g in shownGroups) {
        final members = g.members.length;
        final workingIds = {
          for (final l in everyone)
            if (l.state == CrewState.working) l.agent.id
        };
        final active = g.members.where((m) => workingIds.contains(m.id)).length;
        final at = groupActivityAt(g);
        children.add(MarkRow(
          mark: groupMark(44, radius: 12.3),
          markSize: 44,
          gap: 12,
          minHeight: 68,
          title: g.title.isEmpty ? 'Group' : g.title,
          time: at == null ? null : relativeTime(at.millisecondsSinceEpoch ~/ 1000),
          sub: g.preview,
          subColor: AppColors.fg2,
          sub2: '$members ${members == 1 ? 'member' : 'members'}, $active active',
          onTap: () =>
              openGroupThread(context, client: widget.client, group: g),
        ));
      }
    } else {
      children.add(HomeLabel('Agents',
          top: 12,
          trailing: Semantics(
            button: true,
            label: 'Groups',
            excludeSemantics: true,
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => setState(() => _groupsSegment = true),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48, minWidth: 80),
                child: Align(
                    alignment: Alignment.centerRight,
                    child: Text('Groups',
                        style: sans(12,
                            weight: FontWeight.w500, color: AppColors.fg3))),
              ),
            ),
          )));
      if (shownAgents.isEmpty) {
        children.add(_Empty(switch (_filter) {
          AllFilter.working => 'No agents are working',
          AllFilter.asking => 'No agents are asking',
          AllFilter.idle => 'No agents are idle',
          AllFilter.all => 'No agents match',
        }));
      }
      final folded = !_expanded && q.isEmpty && shownAgents.length > _fold + 1;
      final visible = folded ? shownAgents.take(_fold).toList() : shownAgents;
      for (final l in visible) {
        final working = l.state == CrewState.working;
        final ask = l.state == CrewState.needsYou;
        children.add(MarkRow(
          mark: agentFace(l.agent.id, 36),
          title: l.agent.displayName,
          sub: [if (l.model.isNotEmpty) l.model, if (l.line.isNotEmpty) l.line]
              .join('  ·  '),
          subStyleSize: 12.5,
          trailing: ask
              ? const QuietHand(size: 20)
              : working
                  ? AppIcon('circle', size: 20, color: AppColors.fg2)
                  : null,
          onTap: () => l.agent.isLead
              ? widget.onOpenLead()
              : widget.onOpenAgent(l.agent),
        ));
      }
      if (folded) {
        children.add(TextLink('Show ${shownAgents.length - _fold} more',
            () => setState(() => _expanded = true),
            left: 62));
      }
    }
    children.add(const SizedBox(height: 24));

    return Column(children: [
      PushedBar(
        title: 'All agents',
        subtitle: subtitle,
        onBack: widget.onBack,
        actions: [
          BarIcon('search', 'Search', () {
            setState(() {
              _searching = !_searching;
              if (!_searching) _q.clear();
            });
          }, color: AppColors.fg2),
        ],
      ),
      Expanded(child: ListView(padding: EdgeInsets.zero, children: children)),
    ]);
  }
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
