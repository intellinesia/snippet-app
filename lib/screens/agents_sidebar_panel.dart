import 'dart:async';
import 'dart:math' as math;
import 'package:flutter/material.dart';

import '../api.dart';
import '../chat/agent_cluster.dart';
import '../crew_status.dart';
import '../models.dart';
import '../pins.dart';
import 'mobile_home/create_agent_phone.dart';
import '../platform.dart';
import 'agent_view_mode.dart' show openAgentTab, openGroupTab;
import '../theme.dart';
import '../widgets.dart';
import 'agent_card.dart';
import 'session_list_row.dart' show sessionNeedsYou;
import 'create_agent_form.dart';
import '../mochi.dart';
import 'group_messaging.dart';
import 'lead_card.dart';
import '../pull_refresh.dart';
import '../message_reactions.dart' show isReactionEvent;
import '../motion.dart';
import '../phosphor_icons.dart';
import '../swr.dart';
import '../tap_detector.dart';

/// The agent team, as a sidebar panel — the reference app's "People with
/// access" slot, holding our agents instead of collaborators.
///
/// This is what the shell rail switches to, and it directly answers the two
/// questions the old UI could not: *which agents are active right now*, and
/// *what is each one working on*. Active state comes from live leases, so it
/// reflects reality rather than a stored flag.
/// Open the create-agent sheet (on mobile) or popover (on desktop).
Future<bool?> showCreateAgentDialog(
  BuildContext context,
  DaemonClient client, {
  BuildContext? anchorContext,
  String? initialPrompt,
  String? initialCharacter,
}) =>
    kMobile
        ? Navigator.of(context).push<bool>(MaterialPageRoute(
            builder: (_) => PhoneCreateAgentPage(client: client)))
        : showSidePopover<bool>(context,
            anchorContext: anchorContext,
            title: 'New agent',
            popoverKey: const ValueKey('create-agent-popover'),
            child: CreateAgentForm(
                client: client,
                initialPrompt: initialPrompt,
                initialCharacter: initialCharacter));

class AgentsSidebarPanel extends StatefulWidget {
  const AgentsSidebarPanel({
    super.key,
    required this.client,
    this.onOpenAgent,
    this.onOpenLead,
    this.lead,
    this.trailingHeader,
    this.searchQuery,
    this.onSearchChanged,
    this.bottomPadding,
    this.groupsKey,
    this.heroBuilder,
    this.sessions,
    this.onOpenSession,
    this.embedded = false,
    this.onAgentCountChanged,
  });

  /// Desktop: opens a nested live session under the selected agent or group.
  final void Function(SessionInfo session)? onOpenSession;

  /// Desktop: non-scrolling rows (Lead, agents, groups) for a list
  /// the sidebar scrolls itself; no hero and no Working/Quiet sections.
  final bool embedded;

  /// Phone: live sessions, so rows show who is asking and what they work on.
  final List<SessionInfo>? sessions;

  /// Phone list header built from the agent count and how many need you.
  final Widget Function(int count, int needsYou, int working)? heroBuilder;

  final DaemonClient client;

  /// Called when a row is tapped. The host decides where detail goes.
  final void Function(CoordinationAgent agent)? onOpenAgent;

  /// Open Lead chat when tapped.
  final VoidCallback? onOpenLead;

  final SessionInfo? lead;

  /// Rendered in the top mobile header on the right (e.g. machine avatar switcher).
  final Widget? trailingHeader;

  /// External search query (e.g. from mobile bottom bar or screen header).
  final String? searchQuery;

  /// Notifies parent when local search text changes.
  final ValueChanged<String>? onSearchChanged;

  /// Phone list bottom padding; defaults to clearing the old floating bar.
  final double? bottomPadding;

  /// SWR scope for the groups list; mirrors of this panel need their own so
  /// two mounted instances don't share one entry's notifications.
  final String? groupsKey;

  /// Reports the total loaded agent count so the pinned desktop header can
  /// keep its count visible after the asynchronous refresh completes.
  final ValueChanged<int>? onAgentCountChanged;

  @override
  State<AgentsSidebarPanel> createState() => AgentsSidebarPanelState();
}

/// Last list per daemon, so a remounted panel paints at once and refreshes
/// quietly.
final _memo = <String,
    ({
  List<CoordinationAgent> agents,
  Map<String, AgentLastMessage?>? dmLast,
  AgentLastMessage? mcLast,
  CoordinationAgent? mc,
})>{};

class AgentsSidebarPanelState extends State<AgentsSidebarPanel> {
  List<CoordinationAgent> agents = const [];
  AgentLastMessage? _mcLast;
  CoordinationAgent? _mc;
  DateTime? _shownAt;

  String? error;
  bool loading = true;
  bool busy = false;
  late final Swr<List<GroupSummary>> _groups;
  final Set<String> _expandedAgentRows = <String>{};
  final Set<String> _expandedGroupRows = <String>{};

  bool agentRowExpanded(String id) => _expandedAgentRows.contains(id);
  bool groupRowExpanded(String id) => _expandedGroupRows.contains(id);

  void setAgentRowExpanded(String id, bool expanded) =>
      _setRowExpanded(_expandedAgentRows, id, expanded);

  void setGroupRowExpanded(String id, bool expanded) =>
      _setRowExpanded(_expandedGroupRows, id, expanded);

  void toggleAgentRowExpanded(String id) =>
      setAgentRowExpanded(id, !_expandedAgentRows.contains(id));

  void toggleGroupRowExpanded(String id) =>
      setGroupRowExpanded(id, !_expandedGroupRows.contains(id));

  void _setRowExpanded(Set<String> rows, String id, bool expanded) {
    if (expanded) {
      rows.add(id);
    } else {
      rows.remove(id);
    }
    if (mounted) setState(() {});
  }

  void _notifyAgentCount() {
    final callback = widget.onAgentCountChanged;
    if (callback == null) return;
    final count = agents.length;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) callback(count);
    });
  }

  void _onPinsChanged() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    Pins.instance.addListener(_onPinsChanged);
    _groups = Swr<List<GroupSummary>>(
      client: widget.client,
      key: widget.groupsKey ?? 'groups',
      fetch: widget.client.groups,
      onChange: () {
        if (mounted) setState(() {});
      },
    );
    final memo = _memo[widget.client.baseUrl];
    final cached =
        memo == null ? widget.client.cachedCoordinationAgents() : null;
    if (memo != null) {
      agents = memo.agents;
      _dmLast = memo.dmLast;
      _mcLast = memo.mcLast;
      _mc = memo.mc;
    } else if (cached != null) {
      agents = cached.where((a) => !a.isLead).toList();
      _mc = cached.where((a) => a.isLead).firstOrNull;
      _mcLast = _mc?.lastMessage;
    }
    // Seeded rows were already seen; don't replay the entrance.
    if (agents.isNotEmpty) _shownAt = DateTime.fromMillisecondsSinceEpoch(0);
    _notifyAgentCount();
    refresh();
  }

  Future<void> _deleteAgent(CoordinationAgent agent) async {
    final name =
        agent.displayName.trim().isEmpty ? agent.id : agent.displayName.trim();
    final ok = await confirmAction(context,
        title: 'Delete $name?',
        body:
            'This removes the agent, its identity and its notes. Its past task history loses it too. This can\'t be undone.',
        confirmLabel: 'Delete agent',
        typedName: name);
    if (!ok || !mounted) return;
    try {
      await widget.client.deleteAgent(agent.id);
      if (!mounted) return;
      setState(() => agents = agents.where((a) => a.id != agent.id).toList());
      _notifyAgentCount();
      toast(context, 'Deleted $name');
      refresh();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    }
  }

  @override
  void dispose() {
    Pins.instance.removeListener(_onPinsChanged);
    _groups.dispose();
    super.dispose();
  }

  /// The + menu: create an agent or a group chat.
  Future<void> openCreateMenu(BuildContext anchor, {bool above = true}) async {
    final pick = await showAnchoredPanel<String>(
      anchor,
      width: kMobile ? 288 : 260,
      maxHeight: 200,
      above: above,
      alignRight: true,
      child: const _CreateMenu(),
    );
    if (!mounted || pick == null) return;
    if (pick == 'agent') {
      await _openCreateAgent(anchor.mounted ? anchor : context);
    } else if (await createAndOpenGroup(context, widget.client,
            anchorContext: anchor.mounted ? anchor : null) !=
        null) {
      _groups.refresh();
    }
  }

  void _openGroup(GroupSummary g) {
    openGroupThread(context, client: widget.client, group: g);
    _groups.refresh();
  }

  String get _pinHost => widget.client.baseUrl;

  bool _isPinnedAgent(CoordinationAgent a) =>
      Pins.instance.isPinned(Pins.agent, a.id, host: _pinHost);

  bool _isPinnedGroup(GroupSummary g) =>
      Pins.instance.isPinned(Pins.group, g.id, host: _pinHost);

  int? _entryPinnedAt(Object item) => item is CoordinationAgent
      ? Pins.instance.pinnedAt(Pins.agent, item.id, host: _pinHost)
      : Pins.instance
          .pinnedAt(Pins.group, (item as GroupSummary).id, host: _pinHost);

  Future<void> _groupActions(GroupSummary g, {Offset? point}) async {
    final name = g.title.trim().isEmpty ? 'Group' : g.title.trim();
    final pinned = _isPinnedGroup(g);
    if (kMobile) {
      showAppSheet(
        context,
        title: name,
        subtitle: 'Group',
        child: SheetActions([
          SheetAction(
            pinned ? 'pin-off' : 'pin',
            pinned ? 'Unpin' : 'Pin',
            () {
              Navigator.pop(context);
              Pins.instance.toggle(Pins.group, g.id, host: _pinHost);
            },
            detail: pinned
                ? 'Remove from the top of the list'
                : 'Keep at the top of the list',
          ),
          SheetAction(
            'trash',
            'Delete group',
            () async {
              Navigator.pop(context);
              if (await confirmDeleteGroup(context, widget.client, g)) {
                _groups.refresh();
              }
            },
            danger: true,
            detail: 'Remove this group chat and its messages',
          ),
        ]),
      );
      return;
    }
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final pos = point ?? overlay.size.center(Offset.zero);
    final picked = await showAppMenu<String>(
      context,
      point: pos,
      items: [
        appMenuItem(
            value: 'pin',
            icon: pinned ? 'pin-off' : 'pin',
            label: pinned ? 'Unpin' : 'Pin'),
        const PopupMenuDivider(height: 9),
        appMenuItem(
            value: 'delete',
            icon: 'trash',
            label: 'Delete group',
            danger: true),
      ],
    );
    if (picked == 'pin') {
      await Pins.instance.toggle(Pins.group, g.id, host: _pinHost);
    } else if (picked == 'delete' && mounted) {
      if (await confirmDeleteGroup(context, widget.client, g)) {
        _groups.refresh();
      }
    }
  }

  Future<void> refresh() async {
    _groups.refresh();
    if (mounted && agents.isEmpty) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final all = await widget.client.coordinationAgents();
      if (!mounted) return;
      setState(() {
        // Lead is excluded: it has its own pinned chat, so it is not
        // one of the workers this panel lists.
        agents = [
          for (final a in all)
            if (!a.isLead)
              _dmLast == null ? a : a.withLastMessage(_dmLast![a.id]),
        ];
        _mc = all.where((a) => a.isLead).firstOrNull;
        _mcLast = _mc?.lastMessage;
        error = null;
      });
      _remember();
      _notifyAgentCount();
      unawaited(_loadDmLast());
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  void _remember() => _memo[widget.client.baseUrl] =
      (agents: agents, dmLast: _dmLast, mcLast: _mcLast, mc: _mc);

  /// Agent id to the newest message in your direct thread with it. The
  /// daemon's own preview also counts session turns ("Posted."), which is not
  /// what the list should say.
  Map<String, AgentLastMessage?>? _dmLast;

  Future<void> _loadDmLast() async {
    try {
      final threads = await widget.client.directThreads();
      final unread = {
        for (final t in threads)
          if (t.peerKind == 'agent' && t.hasUnread) t.peerId
      };
      final pages = await Future.wait([
        for (final t in threads)
          if (t.peerKind == 'agent')
            widget.client
                .agentThreadPage(
                    peerId: t.peerId,
                    afterSequence: t.lastSequence > 8 ? t.lastSequence - 8 : 0,
                    limit: 8)
                .then((p) => (t.peerId, p.events),
                    onError: (_) => (t.peerId, const <CoordinationEvent>[])),
      ]);
      final next = <String, AgentLastMessage?>{};
      for (final (id, events) in pages) {
        final shown = [
          for (final e in events)
            if (!isReactionEvent(e) && e.body.trim().isNotEmpty) e
        ];
        final e = shown.lastOrNull;
        next[id] = e == null
            ? null
            : AgentLastMessage(
                text: e.body.trim().split(RegExp(r'\s+')).join(' '),
                fromUser: e.actorKind == 'human',
                at: DateTime.tryParse(e.createdAt),
                unread: unread.contains(id),
              );
      }
      if (!mounted) return;
      setState(() {
        _dmLast = next;
        agents = [for (final a in agents) a.withLastMessage(next[a.id])];
      });
      _remember();
    } catch (_) {}
  }

  String get effectiveQuery {
    return (widget.searchQuery ?? '').trim();
  }

  bool _agentMatchesMetadata(CoordinationAgent a, String q) {
    if (q.isEmpty) return true;
    if (a.displayName.toLowerCase().contains(q)) return true;
    if (a.id.toLowerCase().contains(q)) return true;
    if (a.handle.toLowerCase().contains(q)) return true;
    if (a.capabilities.any((c) => c.toLowerCase().contains(q))) return true;
    return false;
  }

  /// Open the create agent modal/sheet.
  Future<void> openCreateAgent([BuildContext? btnCtx]) =>
      _openCreateAgent(btnCtx ?? context);

  Future<void> _openCreateAgent(BuildContext btnCtx,
      {String? prompt, String? character}) async {
    final submitted = await showCreateAgentDialog(context, widget.client,
        anchorContext: btnCtx,
        initialPrompt: prompt,
        initialCharacter: character);
    if (!mounted || submitted != true) return;
    toast(context, 'Building agent — researching your description…');
    await _awaitNewAgent();
  }

  /// Poll until an agent appears that was not in the list at the start.
  Future<void> _awaitNewAgent() async {
    if (busy) return;
    setState(() => busy = true);
    try {
      final before = agents.map((a) => a.id).toSet();
      for (var i = 0; i < 20; i++) {
        await Future<void>.delayed(const Duration(seconds: 3));
        if (!mounted) return;
        try {
          final latest = (await widget.client.coordinationAgents())
              .where((a) => !a.isLead)
              .toList();
          if (!mounted) return;
          if (latest.any((a) => !before.contains(a.id))) {
            await refresh();
            if (mounted) toast(context, 'New agent is ready');
            return;
          }
          setState(() => agents = latest);
          _notifyAgentCount();
        } catch (_) {}
      }
      if (mounted) {
        toast(context, 'Still building; check Lead for progress.',
            danger: true);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  /// Totals for the Lead strip, from the agents' own counts. The
  /// daemon keeps finished work for 7 days, so "came back" is null (cell
  /// dropped) when no agent reports counts at all.
  @override
  Widget build(BuildContext context) {
    final q = effectiveQuery.toLowerCase();
    final mc = widget.lead;
    final onOpenMc = widget.onOpenLead;
    // Desktop pins Lead as a window tab, so the list omits it.
    final mcCard = kMobile && mc != null && onOpenMc != null && q.isEmpty
        ? LeadCard(
            key: const ValueKey('agents-mc-card'),
            client: widget.client,
            session: mc,
            lastMessage: _mcLast,
            onOpen: onOpenMc,
            presenceDetail: _mc?.presence?.detail,
          )
        : null;
    if (!widget.embedded && loading && agents.isEmpty) {
      return Container(
        color: kMobile ? AppColors.pageBg : Colors.transparent,
        alignment: Alignment.center,
        child: kMobile
            ? const AppLoading(label: 'Loading agents')
            : Spinner(size: 20, color: AppColors.fg3),
      );
    }
    if (!widget.embedded && error != null && agents.isEmpty) {
      if (kMobile) {
        return Material(
          color: kMobile ? AppColors.pageBg : Colors.transparent,
          child: SafeArea(
            bottom: false,
            child: ListView(
              padding: EdgeInsets.fromLTRB(M.gutter, S.s24, M.gutter, S.s32),
              children: [
                Text('Could not load agents',
                    style: sans(13, color: AppColors.fg2)),
                SizedBox(height: S.of(10)),
                Align(
                  alignment: Alignment.centerLeft,
                  child: Btn('Retry', small: true, onTap: refresh),
                ),
              ],
            ),
          ),
        );
      }
      return Container(
        color: kMobile ? AppColors.pageBg : Colors.transparent,
        padding: EdgeInsets.fromLTRB(S.s16, S.of(28), S.s16, S.s16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Could not load agents',
              textAlign: TextAlign.center,
              style: sans(13, color: AppColors.fg2)),
          SizedBox(height: S.of(10)),
          Btn('Retry', small: true, onTap: refresh),
        ]),
      );
    }

    if (agents.isNotEmpty) _shownAt ??= DateTime.now();
    final ordered = (q.isEmpty
        ? [...agents]
        : agents.where((a) => _agentMatchesMetadata(a, q)).toList());
    final groups = (_groups.data ?? const <GroupSummary>[])
        .where((g) => q.isEmpty || g.title.toLowerCase().contains(q))
        .toList();
    final groupTitles = {for (final g in groups) g.id: g.title};
    final entries = <({Object item, DateTime? at, String name, int? pinnedAt})>[
      for (final a in ordered)
        (
          item: a,
          at: a.lastMessage?.at,
          name: a.displayName.toLowerCase(),
          pinnedAt: _entryPinnedAt(a),
        ),
      for (final g in groups)
        (
          item: g,
          at: DateTime.tryParse(g.lastEventAt ?? g.createdAt),
          name: g.title.toLowerCase(),
          pinnedAt: _entryPinnedAt(g),
        ),
    ]..sort((a, b) {
        final ap = a.pinnedAt;
        final bp = b.pinnedAt;
        if (ap != bp) {
          if (ap == null) return 1;
          if (bp == null) return -1;
          return bp.compareTo(ap);
        }
        // Desktop keeps a stable order so a row never moves under the pointer.
        if (kMobile && a.at != b.at) {
          if (a.at == null) return 1;
          if (b.at == null) return -1;
          return b.at!.compareTo(a.at!);
        }
        return a.name.compareTo(b.name);
      });
    final offlineHost = error == null ? null : hostOf(widget.client.baseUrl);
    Widget agentTile(CoordinationAgent a,
            {CrewEntry? crew,
            AgentGroup? group,
            bool expandable = false,
            bool expanded = false,
            VoidCallback? onToggleExpansion}) =>
        ValueListenableBuilder<String?>(
            key: ValueKey('agent-card-${a.id}'),
            valueListenable: openAgentTab,
            builder: (_, open, __) => AgentCard(
                  selected: !kMobile && open == a.id,
                  crew: crew,
                  group: group,
                  client: widget.client,
                  agent: a,
                  pinned: _isPinnedAgent(a),
                  onTogglePin: () =>
                      Pins.instance.toggle(Pins.agent, a.id, host: _pinHost),
                  groupTitles: groupTitles,
                  onOpen: () => widget.onOpenAgent?.call(a),
                  onDelete: () => _deleteAgent(a),
                  onChanged: refresh,
                  offlineHost: offlineHost,
                  expandable: expandable,
                  expanded: expanded,
                  onToggleExpansion: onToggleExpansion,
                ));

    String agentName(String id) {
      for (final a in agents) {
        if (a.id == id) {
          final name = a.displayName.trim();
          return name.isEmpty ? id : name;
        }
      }
      return id;
    }

    String groupMemberLine(GroupSummary g) {
      final names = [for (final id in g.agentIds) agentName(id)];
      if (names.isEmpty) return 'Just you';
      return '${names.join(', ')} and you';
    }

    Widget groupTile(GroupSummary g,
        {bool expandable = false,
        bool expanded = false,
        VoidCallback? onToggleExpansion}) {
      final pinned = _isPinnedGroup(g);
      if (!kMobile) {
        final needsCount = [
          for (final a in agents)
            if (g.agentIds.contains(a.id)) a.needsYou
        ].fold<int>(0, (sum, n) => sum + n);
        final running = g.replying.isNotEmpty;
        final kind = offlineHost != null
            ? AgentRowStatusKind.offline
            : needsCount > 0
                ? AgentRowStatusKind.needsYou
                : running
                    ? AgentRowStatusKind.running
                    : AgentRowStatusKind.idle;
        final memberCount =
            g.members.length + (g.members.any((m) => m.isHuman) ? 0 : 1);
        return ValueListenableBuilder<String?>(
          key: ValueKey('group-row-${g.id}'),
          valueListenable: openGroupTab,
          builder: (_, open, __) => AgentRowShell(
            selected: open == g.id,
            onTap: () => _openGroup(g),
            onLongPress: () => _groupActions(g),
            onSecondaryTapUp: (d) => _groupActions(g, point: d.globalPosition),
            avatar: g.agentIds.isEmpty
                ? Center(
                    child: AppIcon('users', size: 14, color: AppColors.fg3))
                : AgentCluster(ids: g.agentIds, size: 28, count: memberCount),
            name: g.title.trim().isEmpty ? 'Group' : g.title.trim(),
            pinned: pinned,
            time: agentRowAgo(DateTime.tryParse(g.lastEventAt ?? g.createdAt)),
            preview: groupMemberLine(g),
            needs: needsCount > 0,
            statusKind: kind,
            needsCount: needsCount,
            unread: g.unread > 0,
            offlineHost: offlineHost,
            expandable: expandable,
            expanded: expanded,
            onToggleExpansion: onToggleExpansion,
          ),
        );
      }
      return GestureDetector(
        key: ValueKey('group-row-${g.id}'),
        child: GroupRow(
          group: g,
          pinned: pinned,
          onTap: () => _openGroup(g),
          onLongPress: () => _groupActions(g),
          nameOf: agentName,
          needsYou: [
            for (final a in agents)
              if (g.agentIds.contains(a.id) && a.needsYou > 0) a
          ].isNotEmpty,
        ),
      );
    }

    final Widget? emptyState = entries.isNotEmpty || (loading && agents.isEmpty)
        ? null
        : error != null && agents.isEmpty
            ? Padding(
                padding: EdgeInsets.symmetric(vertical: S.s20),
                child: Column(children: [
                  Text('Could not load agents',
                      style: sans(13, color: AppColors.fg2)),
                  SizedBox(height: S.of(10)),
                  Btn('Retry', small: true, onTap: refresh),
                ]),
              )
            : q.isNotEmpty
                ? const _EmptySearch()
                : kMobile
                    ? null
                    : _EmptyTeam(
                        onTap: busy ? null : () => _openCreateAgent(context),
                      );

    if (widget.embedded && !kMobile) {
      return ListenableBuilder(
        listenable: widget.client.presence,
        builder: (context, _) {
          final presence = widget.client.presence;
          final sessions = widget.sessions;
          final crew = sessions == null
              ? const <String, CrewEntry>{}
              : {
                  for (final e in deriveCrew(
                      agents,
                      [
                        for (final s in sessions)
                          if (!s.settled) s
                      ],
                      presence: presence))
                    e.agent.id: e,
                };
          AgentGroup bucketOf(CoordinationAgent a) {
            final g = switch (crew[a.id]?.state) {
              CrewState.needsYou => AgentGroup.needsYou,
              CrewState.working => AgentGroup.working,
              _ =>
                agentGroupFor(a, presence: presence.presenceForAgentId(a.id)),
            };
            return g == AgentGroup.recent && a.available && a.needsYou > 0
                ? AgentGroup.needsYou
                : g;
          }

          DateTime? seen(int? secs) => secs == null || secs <= 0
              ? null
              : DateTime.fromMillisecondsSinceEpoch(secs * 1000);
          DateTime? latest(DateTime? a, DateTime? b) =>
              a == null ? b : (b == null || a.isAfter(b) ? a : b);
          // Sorted by the time each row shows: last message, or the live
          // session's activity while it works. Lead sorts too.
          Widget nested(List<SessionInfo> list) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final s in list)
                    _NestedSession(
                        key: ValueKey('nested-${s.id}'),
                        session: s,
                        onTap: () => widget.onOpenSession?.call(s),
                        active: s.running),
                ],
              );
          List<SessionInfo> liveOf(Iterable<String> ids) {
            final seenIds = <String>{};
            final out = <SessionInfo>[];
            for (final id in ids) {
              for (final s in crew[id]?.sessions ?? const <SessionInfo>[]) {
                if (!s.settled && seenIds.add(s.id)) out.add(s);
              }
            }
            return out;
          }

          Widget? nestFor(bool expanded, List<SessionInfo> list) =>
              expanded && list.isNotEmpty ? nested(list) : null;
          final ranked = <({
            Widget row,
            DateTime? at,
            int? pinnedAt,
            int i,
            Widget? nest
          })>[];
          for (final e in entries) {
            final item = e.item;
            if (item is CoordinationAgent) {
              final c = crew[item.id];
              final live = c != null && c.state != CrewState.standingBy
                  ? seen(c.lead?.lastActive)
                  : null;
              final liveSessions = liveOf([item.id]);
              final expanded = agentRowExpanded(item.id);
              ranked.add((
                row: agentTile(item,
                    crew: c,
                    group: bucketOf(item),
                    expandable: liveSessions.isNotEmpty || expanded,
                    expanded: expanded,
                    onToggleExpansion: () => toggleAgentRowExpanded(item.id)),
                at: latest(e.at, live),
                pinnedAt: e.pinnedAt,
                i: ranked.length,
                nest: nestFor(expanded, liveSessions),
              ));
            } else {
              // Groups sit in the same list, ranked by their last event.
              final group = item as GroupSummary;
              final liveSessions = liveOf(group.agentIds);
              final expanded = groupRowExpanded(group.id);
              ranked.add((
                row: groupTile(group,
                    expandable: liveSessions.isNotEmpty || expanded,
                    expanded: expanded,
                    onToggleExpansion: () => toggleGroupRowExpanded(group.id)),
                at: e.at,
                pinnedAt: e.pinnedAt,
                i: ranked.length,
                nest: nestFor(expanded, liveSessions),
              ));
            }
          }
          if (mcCard != null && kMobile) {
            ranked.add((
              row: mcCard,
              at: latest(_mcLast?.at, seen(mc?.lastActive)),
              pinnedAt: null,
              i: -1,
              nest: null,
            ));
          }
          ranked.sort((a, b) {
            final ap = a.pinnedAt, bp = b.pinnedAt;
            if (ap != bp) {
              if (ap == null) return 1;
              if (bp == null) return -1;
              return bp.compareTo(ap);
            }
            if (!kMobile || a.at == b.at) return a.i.compareTo(b.i);
            if (a.at == null) return 1;
            if (b.at == null) return -1;
            return b.at!.compareTo(a.at!);
          });
          final leadNeeds = mc != null && sessionNeedsYou(mc);
          final leadRunning =
              mc != null && (mc.running || mc.status == 'running');
          final leadKind = offlineHost != null
              ? AgentRowStatusKind.offline
              : leadNeeds
                  ? AgentRowStatusKind.needsYou
                  : leadRunning
                      ? AgentRowStatusKind.running
                      : AgentRowStatusKind.idle;
          final leadRow =
              !kMobile && mc != null && onOpenMc != null && q.isEmpty
                  ? AgentRowShell(
                      key: const ValueKey('agents-lead-row'),
                      avatar: const AgentMochi('lead', size: 28),
                      name: 'Lead',
                      preview: leadRunning ? 'Running' : 'Idle',
                      time: mc.lastActive <= 0
                          ? ''
                          : agentRowAgo(DateTime.fromMillisecondsSinceEpoch(
                              mc.lastActive * 1000)),
                      onTap: onOpenMc,
                      needs: leadNeeds,
                      statusKind: leadKind,
                      needsCount: leadNeeds ? 1 : 0,
                      offlineHost: offlineHost,
                    )
                  : null;
          final agentRows = [
            if (leadRow != null) leadRow,
            for (final r in ranked) ...[
              r.row,
              if (r.nest != null) r.nest!,
            ]
          ];
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              ...agentRows,
              if (emptyState != null && ranked.isEmpty) emptyState,
            ],
          );
        },
      );
    }

    if (kMobile) {
      return PullToRefresh(
        onRefresh: refresh,
        child: ListenableBuilder(
          listenable: widget.client.presence,
          builder: (context, _) {
            final presence = widget.client.presence;
            final crew = {
              for (final e in deriveCrew(
                  agents,
                  [
                    for (final s in widget.sessions ?? const <SessionInfo>[])
                      if (!s.settled) s
                  ],
                  presence: presence))
                e.agent.id: e,
            };
            AgentGroup bucketOf(CoordinationAgent a) =>
                switch (crew[a.id]?.state) {
                  CrewState.needsYou => AgentGroup.needsYou,
                  CrewState.working => AgentGroup.working,
                  _ => agentGroupFor(a,
                      presence: presence.presenceForAgentId(a.id)),
                };
            Widget tileOf(Object item, AgentGroup bucket) =>
                item is CoordinationAgent
                    ? agentTile(item, crew: crew[item.id], group: bucket)
                    : groupTile(item as GroupSummary);
            final children = <Widget>[];
            var n = 0;
            void label(String text) => children.add(Padding(
                  padding: EdgeInsets.fromLTRB(
                      0, children.isEmpty ? S.s8 : S.s20, 0, S.s8),
                  child: Text(text, style: TeamRow.subtitleStyle()),
                ));
            void section(String? text, List<Widget> rows) {
              if (rows.isEmpty) return;
              if (text != null) label(text);
              children.add(Appear(
                key: ValueKey('agents-section-${text ?? 'all'}'),
                index: n++,
                since: _shownAt,
                child: TeamRows(children: rows),
              ));
            }

            Widget addRow(String key, String title, String sub,
                    {String? prompt, String? character}) =>
                Builder(
                  builder: (ctx) => _AddAgentRow(
                    key: ValueKey('agents-add-$key'),
                    title: title,
                    subtitle: sub,
                    onTap: busy
                        ? null
                        : () => _openCreateAgent(ctx,
                            prompt: prompt, character: character),
                  ),
                );

            if (q.isEmpty) {
              final pinnedRows = <Widget>[];
              final buckets = <AgentGroup, List<Widget>>{
                for (final g in AgentGroup.values) g: <Widget>[],
              };
              // Agents and groups interleave by recency inside each section.
              for (final e in entries) {
                final item = e.item;
                final bucket = item is CoordinationAgent
                    ? bucketOf(item)
                    : (item as GroupSummary).hasUnread
                        ? AgentGroup.needsYou
                        : AgentGroup.recent;
                final tile = tileOf(item, bucket);
                (e.pinnedAt != null ? pinnedRows : buckets[bucket]!).add(tile);
              }
              // Option A drops the stage; the hero only fronts a one-agent team.
              final starter = agents.length <= 1 && groups.isEmpty;
              if (starter && (agents.isNotEmpty || !loading)) {
                final only = agents.firstOrNull;
                children.add(only == null
                    ? const _NoAgentsHero()
                    : _TeamHero(
                        agent: only,
                        group: bucketOf(only),
                        onOpen: () => widget.onOpenAgent?.call(only),
                      ));
                section('Your team', [
                  ...pinnedRows,
                  for (final b in AgentGroup.values) ...buckets[b]!,
                ]);
                label('Add an agent');
                children.add(TeamRows(children: [
                  for (final st in agentStarters.take(2))
                    addRow(st.title, st.title, st.summary,
                        prompt: st.prompt, character: st.character),
                  addRow('own', 'Describe your own',
                      'Or pick from ${agentStarters.length} starters'),
                ]));
                children.add(Padding(
                  padding: EdgeInsets.fromLTRB(0, S.s8, S.s16, 0),
                  child: Text(
                      'Each agent keeps its own memory, character and sessions.',
                      style: sans(14, height: 19 / 14, color: AppColors.fg3)),
                ));
              } else {
                section('Pinned', pinnedRows);
                section('Needs you', buckets[AgentGroup.needsYou]!);
                section('Working', buckets[AgentGroup.working]!);
                section('Asleep', buckets[AgentGroup.recent]!);
                // The floating + already adds agents and groups.
              }
            } else {
              section(null, [
                for (final e in entries)
                  tileOf(
                      e.item,
                      e.item is CoordinationAgent
                          ? bucketOf(e.item as CoordinationAgent)
                          : AgentGroup.recent),
              ]);
            }
            if (emptyState != null) children.add(emptyState);
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                  M.gutter, S.s8, M.gutter, widget.bottomPadding ?? 88),
              children: children,
            );
          },
        ),
      );
    }

    return Container(
      color: Colors.transparent,
      child: PullToRefresh(
        onRefresh: refresh,
        child: ListenableBuilder(
          listenable: widget.client.presence,
          builder: (context, _) {
            final presence = widget.client.presence;
            final sessions = widget.sessions;
            final crew = sessions == null
                ? const <String, CrewEntry>{}
                : {
                    for (final e in deriveCrew(
                        agents,
                        [
                          for (final s in sessions)
                            if (!s.settled) s
                        ],
                        presence: presence))
                      e.agent.id: e,
                  };
            AgentGroup bucketOf(CoordinationAgent a) {
              final g = switch (crew[a.id]?.state) {
                CrewState.needsYou => AgentGroup.needsYou,
                CrewState.working => AgentGroup.working,
                _ =>
                  agentGroupFor(a, presence: presence.presenceForAgentId(a.id)),
              };
              return g == AgentGroup.recent && a.available && a.needsYou > 0
                  ? AgentGroup.needsYou
                  : g;
            }

            Widget tile(int i, AgentGroup bucket) {
              final e = entries[i].item;
              final Widget child = e is CoordinationAgent
                  ? agentTile(e, crew: crew[e.id], group: bucket)
                  : groupTile(e as GroupSummary);
              return Appear(
                key: ValueKey('appear-${child.key}'),
                index: i,
                since: _shownAt,
                child: child,
              );
            }

            final children = <Widget>[if (mcCard != null) mcCard];
            void section(String? title, List<Widget> rows) {
              if (rows.isEmpty) return;
              if (title != null) {
                children.add(Padding(
                  key: ValueKey('agents-section-$title'),
                  padding: const EdgeInsets.fromLTRB(8, 14, 8, 4),
                  child: Row(children: [
                    Text(title, style: sans(11, color: AppColors.fg3)),
                    const SizedBox(width: 6),
                    Text('${rows.length}',
                        style: sans(11, color: AppColors.fg3, tabular: true)),
                  ]),
                ));
              }
              children.addAll(rows);
            }

            if (q.isNotEmpty) {
              section(null, [
                for (var i = 0; i < entries.length; i++)
                  tile(
                      i,
                      entries[i].item is CoordinationAgent
                          ? bucketOf(entries[i].item as CoordinationAgent)
                          : AgentGroup.recent),
              ]);
            } else {
              final pinned = <Widget>[];
              final buckets = <AgentGroup, List<Widget>>{
                for (final g in AgentGroup.values) g: <Widget>[],
              };
              final chatGroups = <Widget>[];
              for (var i = 0; i < entries.length; i++) {
                final item = entries[i].item;
                if (item is! CoordinationAgent) {
                  (entries[i].pinnedAt != null ? pinned : chatGroups)
                      .add(tile(i, AgentGroup.recent));
                  continue;
                }
                final bucket = bucketOf(item);
                (entries[i].pinnedAt != null ? pinned : buckets[bucket]!)
                    .add(tile(i, bucket));
              }
              section('Pinned', pinned);
              section('Needs you', buckets[AgentGroup.needsYou]!);
              section('Working', buckets[AgentGroup.working]!);
              section('Quiet', buckets[AgentGroup.recent]!);
              section('Groups', chatGroups);
            }
            if (emptyState != null) children.add(emptyState);
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(6, 6, 6, 18),
              children: children,
            );
          },
        ),
      ),
    );
  }
}

class _EmptySearch extends StatelessWidget {
  const _EmptySearch();

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(kMobile ? 0 : S.s20,
            kMobile ? S.s8 : S.s24, kMobile ? 0 : S.s20, S.s20),
        child: Text(
          'No agents match the search.',
          style: sans(12, color: AppColors.fg3, height: 1.5),
        ),
      );
}

class _EmptyTeam extends StatelessWidget {
  const _EmptyTeam({this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(kMobile ? 0 : S.s8, kMobile ? S.s8 : S.s20,
            kMobile ? 0 : S.s8, S.s20),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('No agents yet',
              style: sans(13, weight: FontWeight.w400, color: AppColors.fg3)),
          SizedBox(height: S.of(10)),
          Btn('New agent',
              small: true,
              variant: BtnVariant.surface,
              disabled: onTap == null,
              onTap: onTap),
        ]),
      );
}

class _CreateMenu extends StatelessWidget {
  const _CreateMenu();

  Widget _item(
    BuildContext context,
    String value,
    String icon,
    Color tileBg,
    Color iconColor,
    String title,
    String subtitle,
  ) =>
      InkWell(
        key: ValueKey('create-$value'),
        onTap: () => Navigator.of(context).pop(value),
        splashFactory: NoSplash.splashFactory,
        hoverColor: AppColors.hover,
        highlightColor: AppColors.hover,
        borderRadius: BorderRadius.circular(R.lg),
        child: Container(
          constraints: const BoxConstraints(minHeight: 60),
          padding: EdgeInsets.symmetric(horizontal: S.of(10), vertical: S.s8),
          child: Row(children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: tileBg,
                borderRadius: BorderRadius.circular(R.card),
              ),
              alignment: Alignment.center,
              child: AppIcon(icon, size: 18, color: iconColor),
            ),
            SizedBox(width: S.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: sans(15, weight: W.label, color: AppColors.fg1)),
                  SizedBox(height: S.of(1)),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(13, color: AppColors.fg3)),
                ],
              ),
            ),
          ]),
        ),
      );

  // Desktop: the same row as appMenuRow, so it reads like every other menu.
  Widget _row(BuildContext context, String value, String icon, String title,
          String subtitle) =>
      InkWell(
        key: ValueKey('create-$value'),
        onTap: () => Navigator.of(context).pop(value),
        splashFactory: NoSplash.splashFactory,
        hoverColor: AppColors.hover,
        highlightColor: AppColors.hover,
        borderRadius: BorderRadius.circular(R.sm),
        child: Container(
          constraints: const BoxConstraints(minHeight: 44),
          padding: EdgeInsets.symmetric(horizontal: S.s8, vertical: S.of(5)),
          child: Row(children: [
            AppIcon(icon, size: 15, color: AppColors.fg3),
            SizedBox(width: S.of(10)),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TS.ui(AppColors.fg1)),
                  SizedBox(height: S.of(1)),
                  Text(subtitle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TS.caption()),
                ],
              ),
            ),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) => !kMobile
      ? Column(mainAxisSize: MainAxisSize.min, children: [
          _row(context, 'agent', 'bot', 'New agent',
              'A specialist with its own model and memory'),
          _row(context, 'group', 'users', 'New group',
              'Several agents in one conversation'),
        ])
      : Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _item(
              context,
              'agent',
              'bot',
              AppColors.accentBg,
              AppColors.accent,
              'New agent',
              'A specialist with its own model and memory',
            ),
            Divider(height: 1, thickness: 1, color: AppColors.line),
            _item(
              context,
              'group',
              'users',
              AppColors.surface3,
              AppColors.fg1,
              'New group',
              'Several agents in one conversation',
            ),
          ],
        );
}

/// The one agent of a fresh team, large, above the list.
class _TeamHero extends StatelessWidget {
  const _TeamHero({required this.agent, required this.group, this.onOpen});

  final CoordinationAgent agent;
  final AgentGroup group;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final name =
        agent.displayName.trim().isEmpty ? agent.id : agent.displayName.trim();
    final (state, word) = !agent.available
        ? (AgentCharacterState.sleeping, 'paused')
        : switch (group) {
            AgentGroup.needsYou => (AgentCharacterState.needs, 'needs you'),
            AgentGroup.working => (AgentCharacterState.working, 'working'),
            AgentGroup.recent => (AgentCharacterState.sleeping, 'asleep'),
          };
    return Semantics(
      button: onOpen != null,
      label: '$name, your agent, $word',
      child: TapDetector(
        key: const ValueKey('agents-team-hero'),
        behavior: HitTestBehavior.opaque,
        onTap: onOpen,
        child: Padding(
          padding: EdgeInsets.fromLTRB(0, S.s12, 0, S.s4),
          child: Column(children: [
            SizedBox.square(
              dimension: 80,
              child: AgentMochi(agent.id, size: 80, state: state),
            ),
            SizedBox(height: S.s8),
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(kMobile ? 20 : 16,
                    weight: FontWeight.w600,
                    height: 26 / 20,
                    color: AppColors.fg1)),
            Text('Your agent · $word', style: TeamRow.subtitleStyle()),
          ]),
        ),
      ),
    );
  }
}

/// No agents at all (the default one was deleted): say so, then the starters.
class _NoAgentsHero extends StatelessWidget {
  const _NoAgentsHero();

  @override
  Widget build(BuildContext context) => Padding(
        key: const ValueKey('agents-empty-hero'),
        padding: EdgeInsets.fromLTRB(0, S.s24, 0, S.s4),
        child: Column(children: [
          SizedBox.square(
            dimension: 80,
            child: CustomPaint(
              painter: _DashedCircle(AppColors.border2),
              child: Center(
                  child: AppIcon('plus', size: 22, color: AppColors.fg3)),
            ),
          ),
          SizedBox(height: S.s8),
          Text('No agents yet',
              style: sans(kMobile ? 20 : 16,
                  weight: FontWeight.w600,
                  height: 26 / 20,
                  color: AppColors.fg1)),
          Text('Start from one below, or describe your own.',
              textAlign: TextAlign.center, style: TeamRow.subtitleStyle()),
        ]),
      );
}

/// An "Add an agent" row: title, line, and a dashed plus on the right.
class _AddAgentRow extends StatelessWidget {
  const _AddAgentRow({
    super.key,
    required this.title,
    required this.subtitle,
    this.onTap,
  });

  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => TeamRow(
        onTap: onTap,
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TeamRow.titleStyle()),
                SizedBox(height: S.of(1)),
                Text(subtitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TeamRow.subtitleStyle()),
              ],
            ),
          ),
          SizedBox(width: S.of(14)),
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: AppColors.fg1.withValues(alpha: 0.06)),
            child:
                Center(child: AppIcon('plus', size: 18, color: AppColors.fg2)),
          ),
        ]),
      );
}

class _DashedCircle extends CustomPainter {
  _DashedCircle(this.color);

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final r = size.shortestSide / 2 - 0.75;
    final c = size.center(Offset.zero);
    final dashes = (2 * math.pi * r / 6).floor();
    final step = 2 * math.pi / dashes;
    for (var i = 0; i < dashes; i++) {
      canvas.drawArc(Rect.fromCircle(center: c, radius: r), i * step,
          step * 0.55, false, paint);
    }
  }

  @override
  bool shouldRepaint(_DashedCircle old) => old.color != color;
}

/// A live session nested under its selected agent or group: 26 tall, indented.
class _NestedSession extends StatefulWidget {
  const _NestedSession(
      {super.key,
      required this.session,
      required this.onTap,
      this.active = false});

  final SessionInfo session;
  final VoidCallback onTap;
  final bool active;

  @override
  State<_NestedSession> createState() => _NestedSessionState();
}

class _NestedSessionState extends State<_NestedSession> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final session = widget.session;
    final title =
        session.title.trim().isEmpty ? 'Session' : session.title.trim();
    final time = session.lastActive <= 0
        ? ''
        : agentRowAgo(
            DateTime.fromMillisecondsSinceEpoch(session.lastActive * 1000));
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: AnimatedContainer(
          duration: reduceMotion(context)
              ? Duration.zero
              : const Duration(milliseconds: 150),
          height: 26,
          decoration: BoxDecoration(
            color: _hover ? AppColors.hoverPlate : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
          ),
          padding: const EdgeInsets.only(left: 36, right: 10),
          child: Row(children: [
            Icon(PhIcons.chatText,
                key: const ValueKey('nested-session-chat-icon'),
                size: 12,
                color: AppColors.fg3),
            const SizedBox(width: 6),
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12,
                      weight: widget.active ? FontWeight.w500 : FontWeight.w400,
                      height: 16 / 12,
                      color: widget.active ? AppColors.fg1 : AppColors.fg2)),
            ),
            if (time.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(time,
                  maxLines: 1,
                  style: sans(11,
                      weight: FontWeight.w400,
                      height: 16 / 11,
                      color: AppColors.fg3,
                      tabular: true)),
            ],
          ]),
        ),
      ),
    );
  }
}
