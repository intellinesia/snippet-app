import 'collapsing_root.dart';
export 'sessions_list_phone.dart';
import 'package:flutter/material.dart';

import '../../crew_status.dart';
import '../../models.dart';
import '../../tap_detector.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../../mobile_kit.dart';
import '../session_list_row.dart' show sessionNeedsYou;
import '../shell_nav.dart' show sessionBusy;
import '../../pins.dart';
import 'agents_home.dart';
import 'lead_phone.dart';
import 'home_data.dart';
import 'home_style.dart' show homeAge;
import 'needs_you_pager.dart' show askText;

/// Quiet Home and Sessions: two calm lists, no hero, no shader, no cards.
/// Both read the same sessions; Home shows only what matters now.
class _IconTap extends StatelessWidget {
  const _IconTap(this.icon, this.label, this.onTap);
  final String icon, label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
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

String _agentName(SessionInfo s, Map<String, String> names) {
  final id = s.displayAgentId ?? '';
  return names[id] ?? (id.isEmpty ? 'Snippet' : id);
}

enum HomeFilter { all, working, needs, pinned }

class QuietHomeScreen extends StatefulWidget {
  const QuietHomeScreen({
    super.key,
    required this.sessions,
    required this.agents,
    required this.onOpenSession,
    required this.onOpenSessions,
    required this.onSettings,
    required this.onSearch,
    this.onNew,
    this.onNewMenu,
    this.onNewAgent,
    this.onOpenAgent,
    this.onOpenLead,
    this.onAllAgents,
    this.onArtifacts,
    this.onProfile,
    this.onDecide,
    this.offline,
    this.groups = const [],
    this.onOpenGroup,
    this.pinHost,
  });

  final Widget? offline;
  final List<SessionInfo> sessions;
  final List<CoordinationAgent> agents;
  final void Function(SessionInfo s) onOpenSession;
  final VoidCallback onOpenSessions;
  final VoidCallback onSettings;
  final VoidCallback onSearch;
  final VoidCallback? onNew;
  final void Function(BuildContext anchor)? onNewMenu;
  final VoidCallback? onNewAgent;
  final void Function(CoordinationAgent a)? onOpenAgent;
  final VoidCallback? onOpenLead;
  final VoidCallback? onAllAgents;
  final VoidCallback? onArtifacts;
  final void Function(CoordinationAgent a)? onProfile;
  final List<GroupSummary> groups;
  final void Function(GroupSummary g)? onOpenGroup;
  final Future<bool> Function(SessionInfo s, bool approve)? onDecide;

  /// Host the pins are stored under; null means nothing is pinned.
  final String? pinHost;
  int get groupCount => groups.length;

  @override
  State<QuietHomeScreen> createState() => _QuietHomeScreenState();
}

class _HomeAgent {
  _HomeAgent(this.agent, this.state, this.line, this.activityMs, this.since);
  final CoordinationAgent agent;
  final CrewState state;
  final String line;
  final int activityMs;

  /// Unix seconds the current work started; null when not working.
  final int? since;
}

class _QuietHomeScreenState extends State<QuietHomeScreen> {
  HomeFilter _filter = HomeFilter.all;
  bool _showAllWorking = false;

  @override
  void initState() {
    super.initState();
    Pins.instance.addListener(_pins);
  }

  @override
  void dispose() {
    Pins.instance.removeListener(_pins);
    super.dispose();
  }

  void _pins() {
    if (mounted) setState(() {});
  }

  bool _pinned(CoordinationAgent a) =>
      widget.pinHost != null &&
      Pins.instance.isPinned(Pins.agent, a.id, host: widget.pinHost!);

  @override
  Widget build(BuildContext context) {
    final w = widget;
    final names = {for (final a in w.agents) a.id: a.displayName};
    final asks = needsYouItems(w.sessions);
    final rows = agentRows(w.agents, w.sessions);
    final lead = w.agents.where((a) => a.isLead).firstOrNull;
    final nowS = DateTime.now().millisecondsSinceEpoch ~/ 1000;

    List<SessionInfo> mine(CoordinationAgent a) => [
          for (final s in w.sessions)
            if (s.displayAgentId == a.id) s
        ]..sort((x, y) => y.lastActive.compareTo(x.lastActive));
    int activity(CoordinationAgent a) {
      final s = mine(a).firstOrNull?.lastActive ?? 0;
      final said = a.lastMessage?.at?.millisecondsSinceEpoch ?? 0;
      return s * 1000 > said ? s * 1000 : said;
    }

    final all = <_HomeAgent>[];
    for (final r in [...rows.needs, ...rows.working, ...rows.asleep]) {
      final ms = mine(r.agent);
      final busy = ms.where((s) => !s.settled && sessionBusy(s)).firstOrNull;
      all.add(_HomeAgent(
          r.agent,
          r.state,
          r.state == CrewState.working
              ? (busy?.title.trim().isNotEmpty == true
                  ? busy!.title.trim()
                  : r.line)
              : r.line,
          activity(r.agent),
          r.state == CrewState.working
              ? (busy?.runningSince ?? busy?.lastActive)
              : null));
    }
    if (lead != null) {
      final ls = w.sessions.where((s) => s.displayAgentId == 'lead').toList();
      final busy = ls.any((s) => !s.settled && sessionBusy(s));
      all.add(_HomeAgent(
          lead,
          busy ? CrewState.working : CrewState.standingBy,
          lead.lastMessage?.text ?? 'Orchestrator',
          activity(lead),
          busy ? nowS : null));
    }
    final working = [
      for (final a in all)
        if (a.state == CrewState.working) a
    ]..sort((a, b) => (a.since ?? nowS).compareTo(b.since ?? nowS));
    final needsAgents = {
      for (final a in all)
        if (a.state == CrewState.needsYou) a.agent.id
    };
    final recent = [
      for (final a in all)
        if (a.state == CrewState.standingBy) a
    ]..sort((a, b) => b.activityMs.compareTo(a.activityMs));
    final pinned = [
      for (final a in all)
        if (_pinned(a.agent)) a
    ];

    // Group asks count only when the asker has no session ask of its own.
    final withAsk = {for (final a in asks) a.agentId};
    final askers = {
      for (final id in needsAgents)
        if (!withAsk.contains(id)) id
    };
    final groupAsks = [
      for (final g in w.groups)
        if (g.agentIds.any(askers.contains)) g
    ];
    final pager = <AskCardData>[
      for (final a in asks)
        AskCardData(
            agentId: a.agentId,
            name: _agentName(a.session, names),
            time: relativeTime(a.session.lastActive),
            text: askText(a).ask,
            onTap: () => w.onOpenSession(a.session),
            // Approvals answer in place; questions open the session to reply.
            primary: a.kind == AskKind.approval && w.onDecide != null
                ? 'Go ahead'
                : (a.kind == AskKind.question ? 'Answer' : 'Open'),
            secondary: a.kind == AskKind.approval && w.onDecide != null
                ? 'Not yet'
                : null,
            onPrimary: a.kind == AskKind.approval && w.onDecide != null
                ? () => w.onDecide!(a.session, true)
                : null,
            onSecondary: a.kind == AskKind.approval && w.onDecide != null
                ? () => w.onDecide!(a.session, false)
                : null),
      for (final g in groupAsks)
        AskCardData(
            agentId: g.agentIds.firstOrNull ?? 'snippet',
            name: g.title.isEmpty ? 'Group' : g.title,
            time: relativeTime(
                (groupActivityAt(g)?.millisecondsSinceEpoch ?? 0) ~/ 1000),
            text: 'Waiting on ${[
              for (final id in g.agentIds)
                if (askers.contains(id)) (names[id] ?? id)
            ].join(', ')}',
            onTap: () => w.onOpenGroup?.call(g)),
    ];

    final dayStart = DateTime.now()
            .copyWith(hour: 0, minute: 0, second: 0, millisecond: 0)
            .millisecondsSinceEpoch ~/
        1000;
    final finished = w.sessions
        .where((s) =>
            !sessionBusy(s) && !sessionNeedsYou(s) && s.lastActive >= dayStart)
        .length;

    const bar = LargeTitle('Agents');
    Widget root(Widget list) => CollapsingRoot(
        title: 'Agents',
        actions: [
          _IconTap('search', 'Search', w.onSearch),
          _IconTap('settings', 'Settings', w.onSettings),
        ],
        child: list);
    if (all.isEmpty && w.groups.isEmpty) {
      return root(ListView(children: [
        bar,
        if (w.offline != null) w.offline!,
        EmptyState(
            icon: 'users',
            title: 'No agents yet',
            body: 'Create one to start delegating work.',
            action: StateButton('New agent',
                key: const ValueKey('empty-new-agent'),
                onTap: w.onNewAgent ?? w.onNew)),
      ]));
    }

    String status(_HomeAgent a) {
      if (a.state == CrewState.working) {
        final age = homeAge(a.since ?? nowS);
        return 'Working · ${age == 'now' ? '1m' : age}';
      }
      return a.state == CrewState.needsYou ? 'Needs you' : 'Idle';
    }

    AgentCardData card(_HomeAgent a) =>
        AgentCardData(a.agent, status(a), a.line,
            working: a.state == CrewState.working);
    void open(CoordinationAgent a) {
      if (a.isLead && w.onOpenLead != null) {
        w.onOpenLead!();
      } else {
        w.onOpenAgent?.call(a);
      }
    }

    final f = _filter;
    final body = <Widget>[];
    final delegating = [
      for (final s in w.sessions)
        if (s.ownerAgentId == 'lead' &&
            s.workerAgentId != null &&
            !s.settled &&
            sessionBusy(s))
          s
    ];
    if (f == HomeFilter.all && delegating.isNotEmpty && w.onOpenLead != null) {
      body.add(LeadHomeCard(
          running: delegating.length, onTap: () => w.onOpenLead!()));
    }
    if (f == HomeFilter.all || f == HomeFilter.needs) {
      if (pager.isNotEmpty) {
        body.add(const SizedBox(height: 14));
        body.add(AskPager(items: pager));
      } else if (f == HomeFilter.needs) {
        body.add(const _Empty('Nothing needs you'));
      }
    }
    if (f == HomeFilter.all || f == HomeFilter.working) {
      if (working.isNotEmpty) {
        body.add(HomeLabel('Working'));
        final shown = _showAllWorking || f == HomeFilter.working
            ? working
            : working.take(4).toList();
        body.add(
            AgentGrid(cards: [for (final a in shown) card(a)], onOpen: open));
        if (shown.length < working.length) {
          body.add(TextLink('Show ${working.length - shown.length} more',
              () => setState(() => _showAllWorking = true)));
        }
      } else if (f == HomeFilter.working) {
        body.add(const _Empty('No agents are working'));
      }
    }
    if (f == HomeFilter.pinned) {
      if (pinned.isEmpty) {
        body.add(const _Empty('Nothing is pinned'));
      } else {
        body.add(HomeLabel('Pinned  ${pinned.length}'));
        body.add(
            AgentGrid(cards: [for (final a in pinned) card(a)], onOpen: open));
      }
    }
    if (f == HomeFilter.all) {
      if (w.groups.isNotEmpty) {
        body.add(const HomeLabel('Groups'));
        final workingIds = {
          for (final a in all)
            if (a.state == CrewState.working) a.agent.id
        };
        for (final g in sortedGroups(w.groups)) {
          final n = g.members.length;
          final active =
              g.members.where((m) => workingIds.contains(m.id)).length;
          body.add(MarkRow(
            mark: groupMark(36),
            title: g.title.isEmpty ? 'Group' : g.title,
            sub: '$n ${n == 1 ? 'member' : 'members'} · $active active',
            trailing: AppIcon('chevron-right', size: 16, color: AppColors.fg3),
            hairline: false,
            onTap: w.onOpenGroup == null ? null : () => w.onOpenGroup!(g),
          ));
        }
      }
      if (recent.isNotEmpty) {
        body.add(HomeLabel('Recent',
            trailing: finished > 0
                ? Semantics(
                    button: true,
                    child: TapDetector(
                      behavior: HitTestBehavior.opaque,
                      onTap: w.onOpenSessions,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Center(
                          widthFactor: 1,
                          child: Text('$finished finished today',
                              style: sans(13, color: AppColors.fg3)),
                        ),
                      ),
                    ),
                  )
                : null));
        for (final a in recent.take(3)) {
          final at = a.activityMs;
          body.add(MarkRow(
            mark: agentFace(a.agent.id, 36),
            title: a.agent.displayName,
            time: at == 0 ? null : relativeTime(at ~/ 1000),
            sub: a.line,
            onTap: () => open(a.agent),
          ));
        }
      }
    }

    final foot = w.onAllAgents == null
        ? const SizedBox(height: 16)
        : Padding(
            padding: const EdgeInsets.only(top: 8, bottom: 16),
            child: TextLink('All agents', w.onAllAgents!),
          );

    return root(CustomScrollView(slivers: [
      SliverList(
        delegate: SliverChildListDelegate([
          bar,
          if (w.offline != null) w.offline!,
          Padding(
            padding: const EdgeInsets.only(top: 10),
            child: ChipRow(chips: [
              StateChip('All', f == HomeFilter.all,
                  () => setState(() => _filter = HomeFilter.all)),
              StateChip('Working', f == HomeFilter.working,
                  () => setState(() => _filter = HomeFilter.working)),
              StateChip('Needs you', f == HomeFilter.needs,
                  () => setState(() => _filter = HomeFilter.needs)),
              StateChip('Pinned', f == HomeFilter.pinned,
                  () => setState(() => _filter = HomeFilter.pinned)),
            ]),
          ),
          ...body,
        ]),
      ),
      SliverFillRemaining(
        hasScrollBody: false,
        child: Align(alignment: Alignment.bottomCenter, child: foot),
      ),
    ]));
  }
}

class _Empty extends StatelessWidget {
  const _Empty(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(kGutter, 24, kGutter, 8),
        child: Center(child: Text(text, style: sans(14, color: AppColors.fg3))),
      );
}
