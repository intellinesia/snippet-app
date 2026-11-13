import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'agent_card.dart';
import 'create_agent_form.dart';
import 'group_messaging.dart';
import 'mission_control_card.dart';
import 'shell_nav.dart';
import '../pull_refresh.dart';
import '../message_reactions.dart' show isReactionEvent;
import '../motion.dart';
import '../swr.dart';

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
}) async {
  final box = anchorContext?.findRenderObject() as RenderBox?;
  final anchor = box == null
      ? const Rect.fromLTWH(16, 96, 0, 0)
      : box.localToGlobal(Offset.zero) & box.size;

  return kMobile
      ? await showAppSheet<bool>(
          context,
          title: 'New agent',
          child: CreateAgentForm(client: client),
        )
      : await showGeneralDialog<bool>(
          context: context,
          barrierDismissible: true,
          barrierLabel: 'create agent',
          barrierColor: Colors.transparent,
          transitionDuration: Motion.quick,
          pageBuilder: (ctx, _, __) => SafeArea(
            minimum: const EdgeInsets.all(12),
            child: Padding(
              padding:
                  EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
              child: LayoutBuilder(builder: (context, constraints) {
                final origin = (context.findRenderObject() as RenderBox?)
                        ?.localToGlobal(Offset.zero) ??
                    Offset.zero;
                return CustomSingleChildLayout(
                  delegate: _CreateAgentPopoverLayout(anchor.shift(-origin)),
                  child: Material(
                    key: const ValueKey('create-agent-popover'),
                    color: AppColors.overlay,
                    shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(R.lg),
                        side: BorderSide(color: AppColors.line)),
                    clipBehavior: Clip.antiAlias,
                    elevation: 4,
                    shadowColor: Colors.black.withValues(alpha: 0.4),
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text('New agent',
                              style: sans(kMobile ? 14 : 13,
                                  weight: W.label, color: AppColors.fg1)),
                          const SizedBox(height: 12),
                          CreateAgentForm(client: client),
                        ],
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),
        );
}

class _CreateAgentPopoverLayout extends SingleChildLayoutDelegate {
  const _CreateAgentPopoverLayout(this.anchor);

  final Rect anchor;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) =>
      BoxConstraints(
        minWidth: constraints.maxWidth.clamp(0, 340),
        maxWidth: constraints.maxWidth.clamp(0, 340),
        maxHeight: constraints.maxHeight,
      );

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final right = anchor.right + 8;
    final left = right + childSize.width <= size.width
        ? right
        : anchor.right - childSize.width;
    return Offset(
      left.clamp(0, size.width - childSize.width),
      anchor.top.clamp(0, size.height - childSize.height),
    );
  }

  @override
  bool shouldRelayout(_CreateAgentPopoverLayout oldDelegate) =>
      anchor != oldDelegate.anchor;
}

class AgentsSidebarPanel extends StatefulWidget {
  const AgentsSidebarPanel({
    super.key,
    required this.client,
    this.onOpenAgent,
    this.onOpenMissionControl,
    this.missionControl,
    this.trailingHeader,
    this.searchQuery,
    this.onSearchChanged,
    this.bottomPadding,
    this.groupsKey,
    this.heroBuilder,
  });

  /// Phone list header built from the agent count and how many need you.
  final Widget Function(int count, int needsYou, int working)? heroBuilder;

  final DaemonClient client;

  /// Called when a row is tapped. The host decides where detail goes.
  final void Function(CoordinationAgent agent)? onOpenAgent;

  /// Open Mission Control chat when tapped.
  final VoidCallback? onOpenMissionControl;

  final SessionInfo? missionControl;

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

  @override
  State<AgentsSidebarPanel> createState() => AgentsSidebarPanelState();
}

class AgentsSidebarPanelState extends State<AgentsSidebarPanel> {
  List<CoordinationAgent> agents = const [];
  AgentLastMessage? _mcLast;
  DateTime? _shownAt;

  String? error;
  bool loading = true;
  bool busy = false;
  late final Swr<List<GroupSummary>> _groups;

  @override
  void initState() {
    super.initState();
    _groups = Swr<List<GroupSummary>>(
      client: widget.client,
      key: widget.groupsKey ?? 'groups',
      fetch: widget.client.groups,
      onChange: () {
        if (mounted) setState(() {});
      },
    );
    final cached = widget.client.cachedCoordinationAgents();
    if (cached != null) {
      agents = cached.where((a) => !a.isMissionControl).toList();
      _mcLast =
          cached.where((a) => a.isMissionControl).firstOrNull?.lastMessage;
    }
    refresh();
  }

  Future<void> _deleteAgent(CoordinationAgent agent) async {
    final name =
        agent.displayName.trim().isEmpty ? agent.id : agent.displayName.trim();
    final ok = await confirmAction(context,
        title: 'Delete $name?',
        body:
            'This removes the agent, its identity and its notes. Its past task history loses it too. This can\'t be undone.',
        confirmLabel: 'Delete agent');
    if (!ok || !mounted) return;
    try {
      await widget.client.deleteAgent(agent.id);
      if (!mounted) return;
      setState(() => agents = agents.where((a) => a.id != agent.id).toList());
      toast(context, 'Deleted $name');
      refresh();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    }
  }

  @override
  void dispose() {
    _groups.dispose();
    super.dispose();
  }

  /// The + menu: create an agent or a group chat.
  Future<void> openCreateMenu(BuildContext anchor, {bool above = true}) async {
    final pick = await showAnchoredPanel<String>(
      anchor,
      width: 288,
      maxHeight: 200,
      above: above,
      alignRight: true,
      child: const _CreateMenu(),
    );
    if (!mounted || pick == null) return;
    if (pick == 'agent') {
      await _openCreateAgent(anchor.mounted ? anchor : context);
    } else if (await createAndOpenGroup(context, widget.client) != null) {
      _groups.refresh();
    }
  }

  void _openGroup(GroupSummary g) {
    openGroupThread(context, client: widget.client, group: g);
    _groups.refresh();
  }

  Future<void> refresh() async {
    _groups.refresh();
    if (mounted) {
      setState(() {
        loading = true;
        error = null;
      });
    }
    try {
      final all = await widget.client.coordinationAgents();
      if (!mounted) return;
      setState(() {
        // Mission Control is excluded: it has its own pinned chat, so it is not
        // one of the workers this panel lists.
        agents = [
          for (final a in all)
            if (!a.isMissionControl)
              _dmLast == null ? a : a.withLastMessage(_dmLast![a.id]),
        ];
        _mcLast = all.where((a) => a.isMissionControl).firstOrNull?.lastMessage;
        error = null;
      });
      unawaited(_loadDmLast());
    } catch (e) {
      if (mounted) setState(() => error = '$e');
    } finally {
      if (mounted) setState(() => loading = false);
    }
  }

  /// Agent id to the newest message in your direct thread with it. The
  /// daemon's own preview also counts session turns ("Posted."), which is not
  /// what the list should say.
  Map<String, AgentLastMessage?>? _dmLast;

  Future<void> _loadDmLast() async {
    try {
      final threads = await widget.client.directThreads();
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
              );
      }
      if (!mounted) return;
      setState(() {
        _dmLast = next;
        agents = [for (final a in agents) a.withLastMessage(next[a.id])];
      });
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

  Future<void> _openCreateAgent(BuildContext btnCtx) async {
    final submitted = await showCreateAgentDialog(context, widget.client,
        anchorContext: btnCtx);
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
              .where((a) => !a.isMissionControl)
              .toList();
          if (!mounted) return;
          if (latest.any((a) => !before.contains(a.id))) {
            await refresh();
            if (mounted) toast(context, 'New agent is ready');
            return;
          }
          setState(() => agents = latest);
        } catch (_) {}
      }
      if (mounted) {
        toast(context, 'Still building — check Mission Control for progress.',
            danger: true);
      }
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final q = effectiveQuery.toLowerCase();
    final mc = widget.missionControl;
    final onOpenMc = widget.onOpenMissionControl;
    final mcCard = mc != null && onOpenMc != null && q.isEmpty
        ? MissionControlCard(
            key: const ValueKey('agents-mc-card'),
            client: widget.client,
            session: mc,
            lastMessage: _mcLast,
            onOpen: onOpenMc,
          )
        : null;
    // The phone's v5 header avatar is the Mission Control entry point, so the
    // pinned card only shows on desktop.
    final showMcCard = mcCard != null && !kMobile;

    if (loading && agents.isEmpty && !showMcCard) {
      return Container(
        color: kMobile ? AppColors.bg : Colors.transparent,
        alignment: Alignment.center,
        child: kMobile
            ? const AppLoading(label: 'Loading agents')
            : Spinner(size: 20, color: AppColors.fg3),
      );
    }
    if (error != null && agents.isEmpty && !showMcCard) {
      if (kMobile) {
        return Material(
          color: kMobile ? AppColors.bg : Colors.transparent,
          child: SafeArea(
            bottom: false,
            child: ListView(
              padding: EdgeInsets.fromLTRB(M.gutter, 24, M.gutter, 32),
              children: [
                Text('Could not load agents',
                    style: sans(13, color: AppColors.fg2)),
                const SizedBox(height: 10),
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
        color: kMobile ? AppColors.bg : Colors.transparent,
        padding: const EdgeInsets.fromLTRB(16, 28, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Could not load agents',
              textAlign: TextAlign.center,
              style: sans(13, color: AppColors.fg2)),
          const SizedBox(height: 10),
          Btn('Retry', small: true, onTap: refresh),
        ]),
      );
    }

    final createBtn = Builder(
      builder: (ctx) => ShellSectionAction(
        icon: 'plus',
        tooltip: 'New agent or group',
        onTap: busy ? null : () => openCreateMenu(ctx, above: false),
      ),
    );

    if (agents.isNotEmpty) _shownAt ??= DateTime.now();
    final ordered = (q.isEmpty
        ? [...agents]
        : agents.where((a) => _agentMatchesMetadata(a, q)).toList());
    final groups = (_groups.data ?? const <GroupSummary>[])
        .where((g) => q.isEmpty || g.title.toLowerCase().contains(q))
        .toList();
    final groupTitles = {for (final g in groups) g.id: g.title};
    final entries = <({Object item, DateTime? at, String name})>[
      for (final a in ordered)
        (item: a, at: a.lastMessage?.at, name: a.displayName.toLowerCase()),
      for (final g in groups)
        (
          item: g,
          at: DateTime.tryParse(g.lastEventAt ?? g.createdAt),
          name: g.title.toLowerCase()
        ),
    ]..sort((a, b) {
        if (a.at != b.at) {
          if (a.at == null) return 1;
          if (b.at == null) return -1;
          return b.at!.compareTo(a.at!);
        }
        return a.name.compareTo(b.name);
      });
    Widget agentTile(CoordinationAgent a) => AgentCard(
          key: ValueKey('agent-card-${a.id}'),
          client: widget.client,
          agent: a,
          groupTitles: groupTitles,
          onOpen: () => widget.onOpenAgent?.call(a),
          onDelete: () => _deleteAgent(a),
          onChanged: refresh,
        );

    Widget groupTile(GroupSummary g) => GroupRow(
          key: ValueKey('group-row-${g.id}'),
          group: g,
          onTap: () => _openGroup(g),
          onLongPress: () async {
            if (await confirmDeleteGroup(context, widget.client, g)) {
              _groups.refresh();
            }
          },
        );

    Widget row(int i) {
      final e = entries[i].item;
      final Widget child =
          e is CoordinationAgent ? agentTile(e) : groupTile(e as GroupSummary);
      return Appear(
        key: ValueKey('appear-${child.key}'),
        index: i,
        since: _shownAt,
        child: child,
      );
    }

    final Widget? emptyState = entries.isNotEmpty || (loading && agents.isEmpty)
        ? null
        : error != null && agents.isEmpty
            ? Padding(
                padding: const EdgeInsets.symmetric(vertical: 20),
                child: Column(children: [
                  Text('Could not load agents',
                      style: sans(13, color: AppColors.fg2)),
                  const SizedBox(height: 10),
                  Btn('Retry', small: true, onTap: refresh),
                ]),
              )
            : q.isNotEmpty
                ? const _EmptySearch()
                : _EmptyTeam();

    if (kMobile) {
      return PullToRefresh(
        onRefresh: refresh,
        child: ListenableBuilder(
          listenable: widget.client.presence,
          builder: (context, _) {
            final children = <Widget>[];
            Widget hairline() => Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: M.gutter),
                color: AppColors.border);
            if (q.isEmpty) {
              final buckets = <AgentGroup, List<Widget>>{
                for (final g in AgentGroup.values) g: <Widget>[],
              };
              // Agents and groups interleave by recency inside each section.
              var i = 0;
              for (final e in entries) {
                final item = e.item;
                final Widget tile;
                final AgentGroup bucket;
                if (item is CoordinationAgent) {
                  tile = agentTile(item);
                  bucket = agentGroupFor(item,
                      presence: widget.client.presence
                          .presenceForAgentId(item.id));
                } else {
                  final g = item as GroupSummary;
                  tile = groupTile(g);
                  bucket =
                      g.hasUnread ? AgentGroup.needsYou : AgentGroup.recent;
                }
                buckets[bucket]!.add(Appear(
                    key: ValueKey('appear-${tile.key}-$i'),
                    index: i++,
                    since: _shownAt,
                    child: tile));
              }
              final sectionDefs = <(AgentGroup, String, Color)>[
                (AgentGroup.needsYou, 'Needs you', AppColors.accent),
                (AgentGroup.working, 'Working', AppColors.fg3),
                (AgentGroup.recent, 'Recent', AppColors.fg3),
              ];
              final totalRows =
                  buckets.values.fold(0, (s, l) => s + l.length);
              var rowCount = 0;
              for (final (grp, label, color) in sectionDefs) {
                final rows = buckets[grp]!;
                if (rows.isEmpty) continue;
                if (grp != AgentGroup.recent) {
                  children.add(Padding(
                    padding: const EdgeInsets.fromLTRB(
                        M.gutter, 14, M.gutter, 4),
                    child: Text(label,
                        style: sans(13, weight: W.label, color: color)),
                  ));
                }
                for (final r in rows) {
                  children.add(r);
                  rowCount++;
                  if (rowCount < totalRows) {
                    children.add(hairline());
                  }
                }
              }
              final hero = widget.heroBuilder;
              if (hero != null && entries.isNotEmpty) {
                children.insert(
                    0,
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: M.gutter),
                      child: hero(
                          agents.length,
                          buckets[AgentGroup.needsYou]!.length,
                          buckets[AgentGroup.working]!.length),
                    ));
              }
            } else {
              for (var i = 0; i < entries.length; i++) {
                children.add(row(i));
                if (i < entries.length - 1) {
                  children.add(hairline());
                }
              }
            }
            if (emptyState != null)
              children.add(Padding(
                  padding: const EdgeInsets.symmetric(horizontal: M.gutter),
                  child: emptyState));
            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: EdgeInsets.fromLTRB(
                  0, 8, 0, widget.bottomPadding ?? 88),
              children: children,
            );
          },
        ),
      );
    }

    final desktopChildren = [
      for (var i = 0; i < entries.length; i++) row(i),
    ];

    return Container(
      color: kMobile ? AppColors.bg : Colors.transparent,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ShellSectionHeader(
            label: 'Agents',
            actions: [
              createBtn,
            ],
          ),
          Expanded(
            child: PullToRefresh(
              onRefresh: refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(8, 4, 8, 18),
                children: [
                  if (mcCard != null) mcCard,
                  ...desktopChildren,
                  if (emptyState != null) emptyState,
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _EmptySearch extends StatelessWidget {
  const _EmptySearch();

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
            kMobile ? 0 : 20, kMobile ? 8 : 24, kMobile ? 0 : 20, 20),
        child: Text(
          'No agents match the search.',
          style: sans(12, color: AppColors.fg3, height: 1.5),
        ),
      );
}

class _EmptyTeam extends StatelessWidget {
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
            kMobile ? 0 : 20, kMobile ? 8 : 24, kMobile ? 0 : 20, 20),
        child: Text(
          'No agents yet.\n\nBuild one and it appears here, along with the '
          'sessions it is working in.',
          style: sans(12, color: AppColors.fg3, height: 1.5),
        ),
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
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
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: sans(15,
                          weight: W.label, color: AppColors.fg1)),
                  const SizedBox(height: 1),
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

  @override
  Widget build(BuildContext context) => Column(
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
