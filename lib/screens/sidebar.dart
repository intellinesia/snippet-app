import 'group_messaging.dart' show openGroupThread;
import 'phone_agent_page.dart';
import 'agent_profile_panel.dart' show showAgentProfileSettings;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../crew_status.dart';
import '../drafts.dart';
import '../models.dart';
import '../pins.dart';
import '../settled_sessions.dart';
import 'sidebar_mode.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'agents_sidebar_panel.dart';
import 'lead.dart';
import 'settings_overlay.dart' show showSettings;
import 'shell_models.dart';
import 'shell_nav.dart';
import 'session_list_row.dart';
import 'sidebar_mobile.dart';
import 'sidebar_tiles.dart';
import '../pull_refresh.dart';
import '../motion.dart';
import '../page_stack.dart';
import '../mochi.dart';
import '../chat_scene.dart' show ChatScene;
import 'agent_view_mode.dart' show activeShellPlace;
import 'all_agents_view.dart';
import '../panel.dart' show presentScreen;
import '../shell_panel.dart' show ShellPanelPurpose;
import '../quiet.dart' show QuietOfflineBanner, QuietPlace;
import 'mobile_home/quiet_home.dart';
import 'mobile_home/quiet_lists.dart';
import 'tasks/tasks_panel.dart' show TasksPanel;
import 'phone_hero.dart';
import '../session_quick_send.dart';
import 'artifacts_screen.dart' show openArtifactsList;
import 'sessions_inbox.dart' show openSessionsInbox;
import 'mobile_home/everyone_switcher.dart' show showEveryoneSwitcher;
import 'pull_requests.dart' show openPullRequest;
export 'sidebar_mobile.dart';
export 'sidebar_tiles.dart' show SidebarBrand;

enum _AgentListStateFilter { all, needsYou, working, idle }

extension on _AgentListStateFilter {
  String get label => switch (this) {
        _AgentListStateFilter.all => 'All',
        _AgentListStateFilter.needsYou => 'Needs you',
        _AgentListStateFilter.working => 'Working',
        _AgentListStateFilter.idle => 'Idle',
      };
}

class _FilteredAgentsSidebarPanel extends AgentsSidebarPanel {
  const _FilteredAgentsSidebarPanel({
    super.key,
    required super.client,
    required this.stateFilter,
    super.onOpenAgent,
    super.onOpenLead,
    super.lead,
    super.searchQuery,
    super.onSearchChanged,
    super.bottomPadding,
    super.groupsKey,
    super.heroBuilder,
    super.sessions,
    super.onOpenSession,
    super.embedded,
    super.onAgentCountChanged,
  });

  final _AgentListStateFilter stateFilter;

  @override
  AgentsSidebarPanelState createState() => _FilteredAgentsSidebarPanelState();
}

class _FilteredAgentsSidebarPanelState extends AgentsSidebarPanelState {
  @override
  Widget build(BuildContext context) {
    final filter = (widget as _FilteredAgentsSidebarPanel).stateFilter;
    if (filter == _AgentListStateFilter.all) return super.build(context);
    return ListenableBuilder(
      listenable: widget.client.presence,
      builder: (context, _) {
        final unfiltered = agents;
        final sessions = [
          for (final s in widget.sessions ?? const <SessionInfo>[])
            if (!s.settled) s,
        ];
        final crew = {
          for (final e in deriveCrew(unfiltered, sessions,
              presence: widget.client.presence))
            e.agent.id: e,
        };
        bool needsYou(CoordinationAgent a) =>
            crew[a.id]?.state == CrewState.needsYou || a.needsYou > 0;
        bool working(CoordinationAgent a) {
          final presence = widget.client.presence.presenceForAgentId(a.id);
          return crew[a.id]?.state == CrewState.working ||
              (presence?.active ?? false) ||
              (a.presence?.live ?? false) ||
              a.tasksIn({'in_progress'}) > 0;
        }

        bool matches(CoordinationAgent a) => switch (filter) {
              _AgentListStateFilter.all => true,
              _AgentListStateFilter.needsYou => needsYou(a),
              _AgentListStateFilter.working => working(a),
              _AgentListStateFilter.idle => !needsYou(a) && !working(a),
            };
        agents = [
          for (final a in unfiltered)
            if (matches(a)) a
        ];
        try {
          return super.build(context);
        } finally {
          agents = unfiltered;
        }
      },
    );
  }
}

class _SidebarExpandIntent extends Intent {
  const _SidebarExpandIntent(this.expand);
  final bool expand;
}

class Sidebar extends StatefulWidget {
  final List<Instance> instances;
  final Instance? active;
  final DaemonClient? client;
  final String? selectedSessionId;
  final List<SessionInfo>? sessions;
  final bool sessionsLoading;
  final String? sessionsError;
  final VoidCallback onRefreshSessions;
  final VoidCallback onNewSession;
  final ValueChanged<String>? onNewSessionIn;
  final void Function(Instance) onSelectInstance;
  final VoidCallback onOpenLead;
  final ValueChanged<CoordinationAgent>? onOpenAgent;
  final VoidCallback? onOpenPalette;
  final VoidCallback? onOpenTasks;
  final VoidCallback? onOpenHome;
  final VoidCallback? onOpenPullRequests;
  final VoidCallback? onOpenArtifacts;
  final VoidCallback? onOpenWakes;
  final Widget? desktopFooter;
  final void Function(String id, String title, String? profile) onOpenSession;
  final VoidCallback onAddInstance;
  final void Function(Instance, String) onRenameInstance;
  final void Function(Instance) onRemoveInstance;
  final void Function(String id) onSessionDeleted;
  final Map<String, bool> health;
  final VoidCallback onRefreshHealth;
  final bool topInset;
  final void Function(String action)? onSessionAction;

  /// Phone home destination + its setter. Owned by the shell so that back can
  /// return to Chats; passed down because the phone home IS this widget.
  final MobileHome mobileHome;
  final Widget? mobileTopBar;
  final VoidCallback? onMobileMenu;

  /// The shell's Settings entry; preferred so every opener shares one path.
  final VoidCallback? onOpenSettings;
  final ValueChanged<MobileHome> onMobileHome;

  /// Phone drill-down state + setter. Also shell-owned, for the same reason:
  /// the back handler and the bar's visibility both live up there.
  final CoordinationAgent? agent;
  final ValueChanged<CoordinationAgent?> onAgent;
  final bool listening;
  final int? mcAttention;

  const Sidebar({
    super.key,
    required this.instances,
    required this.active,
    required this.client,
    required this.selectedSessionId,
    required this.sessions,
    required this.sessionsLoading,
    this.sessionsError,
    required this.onRefreshSessions,
    required this.onNewSession,
    this.onNewSessionIn,
    required this.onSelectInstance,
    required this.onOpenLead,
    this.onOpenAgent,
    this.onOpenPalette,
    this.onOpenTasks,
    this.onOpenHome,
    this.onOpenPullRequests,
    this.onOpenArtifacts,
    this.onOpenWakes,
    this.desktopFooter,
    required this.onOpenSession,
    required this.onAddInstance,
    required this.onRenameInstance,
    required this.onRemoveInstance,
    required this.onSessionDeleted,
    required this.health,
    required this.onRefreshHealth,
    required this.topInset,
    this.onSessionAction,
    required this.mobileHome,
    this.mobileTopBar,
    this.onMobileMenu,
    this.onOpenSettings,
    required this.onMobileHome,
    required this.agent,
    required this.onAgent,
    this.listening = false,
    this.mcAttention,
  });
  @override
  State<Sidebar> createState() => SidebarState();
}

class SidebarState extends State<Sidebar> with SingleTickerProviderStateMixin {
  DateTime? _chatsShownAt;
  // The session list now lives in the shell (passed via widget.sessions); the
  // sidebar is presentational, so opening the drawer doesn't refetch.
  final String _filterQuery = '';
  String _agentFilterQuery = '';

  final GlobalKey<AgentsSidebarPanelState> _agentsPanelKey =
      GlobalKey<AgentsSidebarPanelState>();

  /// The Agents tab with no agent open mirrors the Chats list; its panel needs
  /// its own key or it collides with the Chats page's in the PageView.
  final GlobalKey<AgentsSidebarPanelState> _agentsMirrorKey =
      GlobalKey<AgentsSidebarPanelState>();
  bool _selecting = false;

  // The desktop title bar's one "new" button reaches the mounted sidebar here.
  static SidebarState? _desktop;

  /// New session, or the new agent/group menu when the sidebar shows agents.
  static void openNew(BuildContext anchor, VoidCallback fallback) {
    final st = _desktop;
    if (st == null || !st.mounted || !sidebarAgentsFirst.value) {
      fallback();
      return;
    }
    st._agentsPanelKey.currentState?.openCreateMenu(anchor, above: false);
  }

  /// The agent rail's "All sessions" link switches the sidebar to its list.
  static void showAllSessions() {
    final st = _desktop;
    if (st != null && st.mounted) st._selectPlace(QuietPlace.sessions);
  }

  final Set<String> _selected = {};

  /// Phone search: a filter field at the top of each tab.

  double get _scrollBottomPad => _selecting ? 24.0 : 0.0;

  /// Desktop search in section headers.
  final TextEditingController _desktopAgentsSearchCtl = TextEditingController();
  final FocusNode _desktopAgentsSearchFocus = FocusNode();
  bool _agentSearchOpen = false;
  _AgentListStateFilter _agentStateFilter = _AgentListStateFilter.all;
  bool _agentsCollapsed = false;
  int? _collapsedAgentsCount;
  int? _agentsCount;

  late MobileHome _currentHome = widget.mobileHome;
  MobileHome? _prevHome;
  final Set<MobileHome> _mountedHomes = <MobileHome>{};
  AnimationController? _homeAnimC;
  AnimationController get _homeAnim => _homeAnimC ??= AnimationController(
        vsync: this,
        duration: Motion.fast,
        value: 1.0,
      )..addStatusListener((status) {
          if (status == AnimationStatus.completed &&
              mounted &&
              _prevHome != null) {
            setState(() {
              if (_prevHome == MobileHome.tasks) {
                _mountedHomes.remove(_prevHome);
              }
              _prevHome = null;
            });
          }
        });

  Map<String, String> _profileProviders = const {};
  String? _providersFor;

  Future<void> _loadProviders() async {
    final client = widget.client;
    if (client == null) return;
    final key = '${client.baseUrl}|${widget.sessions?.length}';
    if (_providersFor == key) return;
    _providersFor = key;
    try {
      final cfg = await client.getConfig();
      if (!mounted) return;
      setState(() => _profileProviders = {
            for (final p in cfg.profiles) p.name: p.provider,
          });
    } catch (_) {}
  }

  List<CoordinationAgent> _heroAgents = const [];
  List<GroupSummary> _heroGroups = const [];
  DateTime? _heroAgentsAt;

  Future<void> _loadHeroAgents() async {
    final client = widget.client;
    final at = _heroAgentsAt;
    final now = DateTime.now();
    if (client == null) return;
    if (at != null && now.difference(at) < const Duration(minutes: 1)) return;
    _heroAgentsAt = now;
    try {
      final all = await client.coordinationAgents();
      if (mounted) setState(() => _heroAgents = all);
    } catch (_) {}
    try {
      final g = await client.groups();
      if (mounted) setState(() => _heroGroups = g);
    } catch (_) {}
  }

  Future<bool> _decideHero(SessionInfo s, bool approve) async {
    final client = widget.client;
    if (client == null) return false;
    final ok = await quickSend(
      client: client,
      session: s.id,
      action: approve ? const QuickApprove() : const QuickDeny(),
    );
    if (!mounted) return false;
    if (!ok) {
      toast(context, "Couldn't send the decision", danger: true);
      return false;
    }
    widget.onRefreshSessions();
    return true;
  }

  Widget _phoneHero(List<SessionInfo> sessions,
      {bool idleCast = true, bool wholeTeam = false}) {
    final c = widget.client;
    return PhoneHero(
      sessions: sessions,
      agents: _heroAgents,
      onOpenSession: (s) => widget.onOpenSession(s.id, s.title, s.profile),
      onDecide: c == null ? null : _decideHero,
      onReviewPr: c == null ? null : _reviewSessionPr,
      onMergePr: c == null ? null : _mergeSessionPr,
      idleCast: idleCast,
      wholeTeam: wholeTeam,
    );
  }

  @override
  void initState() {
    super.initState();
    if (!kMobile) _desktop = this;
    Drafts.instance.addListener(_onDrafts);
    Pins.instance.addListener(_onDrafts);
    if (kMobile) ChatScene.instance.addListener(_onDrafts);
    _loadProviders();
    _mountedHomes.add(_slot(_currentHome));
    if (kMobile) _loadHeroAgents();
    if (!kMobile) sidebarAgentsFirst.addListener(_onAgentsList);
  }

  @override
  void didUpdateWidget(covariant Sidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.sessionsError == null && widget.sessions != null) {
      final n = DateTime.now();
      _lastSeen =
          '${n.hour.toString().padLeft(2, '0')}:${n.minute.toString().padLeft(2, '0')}';
    }
    if (kMobile) _loadHeroAgents();
    if (oldWidget.client != widget.client ||
        (widget.sessions ?? const <SessionInfo>[]).any((s) =>
            (s.profile ?? '').isNotEmpty &&
            !_profileProviders.containsKey(s.profile))) {
      _loadProviders();
    }
    if (oldWidget.mobileHome != widget.mobileHome) {
      if (kMobile) _loadHeroAgents();
      if (_slot(widget.mobileHome) == _slot(_currentHome)) {
        _currentHome = widget.mobileHome;
      } else if (widget.mobileHome != _currentHome) {
        _prevHome = _currentHome;
        _currentHome = widget.mobileHome;
        _mountedHomes.add(_slot(_currentHome));
        _homeAnim.duration = reduceMotion(context)
            ? const Duration(milliseconds: 150)
            : Motion.fast;
        _homeAnim.forward(from: 0.0);
      }
    }
  }

  String? _renamingId;
  final TextEditingController _renameCtl = TextEditingController();
  final FocusNode _renameFocus = FocusNode();

  void _onDrafts() {
    if (mounted) setState(() {});
  }

  String? get _pinHost => widget.client?.baseUrl ?? widget.active?.url;

  bool _isPinnedSession(SessionInfo s) =>
      Pins.instance.isPinned(Pins.session, s.id, host: _pinHost);

  int? _sessionPinnedAt(SessionInfo s) =>
      Pins.instance.pinnedAt(Pins.session, s.id, host: _pinHost);

  List<SessionInfo> _pinnedSessions(List<SessionInfo> sessions) {
    final pinned = [
      for (final s in sessions)
        if (_isPinnedSession(s)) s,
    ];
    pinned.sort((a, b) =>
        (_sessionPinnedAt(b) ?? 0).compareTo(_sessionPinnedAt(a) ?? 0));
    return pinned;
  }

  /// Whether a chat you are not looking at has unsent text waiting.
  bool _hasDraft(SessionInfo s) {
    final c = widget.client;
    return c != null &&
        s.id != widget.selectedSessionId &&
        Drafts.instance.has(Drafts.keyFor(c.baseUrl, s.id));
  }

  @override
  void dispose() {
    if (identical(_desktop, this)) _desktop = null;
    sidebarAgentsFirst.removeListener(_onAgentsList);
    Drafts.instance.removeListener(_onDrafts);
    Pins.instance.removeListener(_onDrafts);
    ChatScene.instance.removeListener(_onDrafts);
    _homeAnimC?.dispose();
    _renameCtl.dispose();
    _renameFocus.dispose();
    _desktopAgentsSearchCtl.dispose();
    _desktopAgentsSearchFocus.dispose();
    super.dispose();
  }

  final Set<String> _deleting = {};
  String? _lastSeen;

  List<SessionInfo>? get _sessions => _deleting.isEmpty
      ? widget.sessions
      : widget.sessions?.where((s) => !_deleting.contains(s.id)).toList();

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    final hasClient = widget.client != null;
    return Container(
      color: !kMobile || ChatScene.instance.active
          ? Colors.transparent
          : AppColors.bg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.topInset && kMacOS) SizedBox(height: kMacTitlebar + 6),
        if (kMobile) ...[
          // The bar is a SIBLING of the content, not an overlay: the content
          // gets the remaining height, so nothing hides behind the bar and no
          // scroll-padding hack is needed. It still reads as floating (inset,
          // rounded, raised).
          Expanded(
            child: Stack(clipBehavior: Clip.none, children: [
              _buildMobileHomeStack(hasClient),
            ]),
          ),
        ],
        if (!kMobile) ...[
          if (hasClient && (_sessions?.isNotEmpty ?? false) && _selecting)
            Padding(
              padding: EdgeInsets.fromLTRB(S.s4, S.s4, S.s8, S.s4),
              child: _selectionBar(mobile: false),
            ),
          // Sectioned, collapsible sidebar — the reference's left column.
          Expanded(child: _sectionedSidebar()),
        ],
      ]),
    );
  }

  /// Full-surface placeholder for a phone destination with no machine.
  ///
  /// Local to the sidebar rather than reusing the shell's `_sidebarUnavailable`:
  /// that one is a `_DesktopShellState` method and is not in scope here.
  Widget _mobileUnavailable(String message) => EmptyState(
        icon: 'server',
        title: 'No machine yet',
        body: message,
        action: Btn('Add machine',
            icon: 'plus', small: true, onTap: widget.onAddInstance),
      );

  /// Sessions and Agents share one pager layer; everything else is its own.
  static MobileHome _slot(MobileHome h) =>
      h == MobileHome.agents ? MobileHome.chats : h;

  Widget _buildMobileHomeStack(bool hasClient) {
    final prev = _prevHome == null ? null : _slot(_prevHome!);
    final curr = _slot(_currentHome);
    final ordered = <MobileHome>[
      for (final h in MobileHome.values)
        if (_mountedHomes.contains(h) && h != prev && h != curr) h,
      if (prev != null && _mountedHomes.contains(prev)) prev,
      if (_mountedHomes.contains(curr)) curr,
    ];
    final bodies = <MobileHome, Widget>{
      for (final h in ordered)
        h: KeyedSubtree(
          key: ValueKey('mobile-${h.name}'),
          child: h == MobileHome.chats
              ? _mobilePair(hasClient)
              : _mobileHomeBody(hasClient, h),
        ),
    };
    final reduced = reduceMotion(context);
    final homes = AnimatedBuilder(
      animation: _homeAnim,
      builder: (context, _) {
        final curved = Motion.enter.transform(_homeAnim.value);
        return Stack(
          clipBehavior: Clip.none,
          fit: StackFit.expand,
          children: [
            for (final h in ordered)
              _homeLayer(h,
                  body: bodies[h]!,
                  prev: prev,
                  curr: curr,
                  curved: curved,
                  reduced: reduced),
          ],
        );
      },
    );
    return homes;
  }

  Widget _homeLayer(
    MobileHome h, {
    required Widget body,
    required MobileHome? prev,
    required MobileHome curr,
    required double curved,
    required bool reduced,
  }) {
    final active = h == curr || (prev != null && h == prev);
    var dx = 0.0;
    var opacity = 1.0;
    if (active && prev != null) {
      final dir = curr.index > prev.index ? 1.0 : -1.0;
      if (h == curr) {
        opacity = curved;
        if (!reduced) dx = dir * 8.0 * (1.0 - curved);
      } else {
        opacity = 1.0 - curved;
        if (!reduced) dx = -dir * 8.0 * curved;
      }
    }
    return KeyedSubtree(
      key: ValueKey('mobile-layer-${h.name}'),
      child: Offstage(
        offstage: !active,
        child: IgnorePointer(
          ignoring: h != curr,
          child: Transform.translate(
            offset: Offset(dx, 0),
            child: Opacity(
              opacity: opacity.clamp(0.0, 1.0),
              child: RepaintBoundary(child: body),
            ),
          ),
        ),
      ),
    );
  }

  /// The gear on the phone home: Settings opens as an overlay, not a home
  /// (spec S0).
  void _openSettings() {
    final open = widget.onOpenSettings;
    if (open != null) return open();
    final client = widget.client;
    if (client == null) return;
    showSettings(
      context,
      client: client,
      instances: widget.instances,
      active: widget.active,
      onRemove: widget.onRemoveInstance,
      onRename: widget.onRenameInstance,
      onSelect: widget.onSelectInstance,
    );
  }

  /// One scrolling home: Needs you, Agents and Sessions. An open agent
  /// detail covers it.
  Widget _mobilePair(bool hasClient) {
    final client = widget.client;
    final agent = widget.agent;
    final inDetail = widget.mobileHome == MobileHome.agents && agent != null;
    return PhonePageStack(
      onBack: () => widget.onAgent(null),
      base: _selecting
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(child: _mobileHome(client!, MobileHome.chats)),
                _mobileSelectionActions(),
              ],
            )
          : !hasClient
              ? _mobileUnavailable('Add a machine to begin.')
              : _mobileHome(
                  client!,
                  widget.mobileHome == MobileHome.agents
                      ? MobileHome.agents
                      : MobileHome.chats),
      page: inDetail && client != null
          ? KeyedSubtree(
              key: ValueKey('agent-page-${agent.id}'),
              child: Padding(
                padding: EdgeInsets.only(bottom: _scrollBottomPad),
                child: PhoneAgentPage(
                  agent: agent,
                  client: client,
                  sessions: _sessions ?? const <SessionInfo>[],
                  onClose: () => widget.onAgent(null),
                  onOpenSession: (s) =>
                      widget.onOpenSession(s.id, s.title, s.profile),
                  onAllSessions: () => widget.onMobileHome(MobileHome.chats),
                  onDecide: _decideHero,
                ),
              ),
            )
          : null,
    );
  }

  Widget _mobileHome(DaemonClient client, [MobileHome? place]) {
    final list = [
      for (final s in _sessions ?? const <SessionInfo>[])
        if (!isDedicatedLeadSession(s.id) && !isInboxSessionRow(s)) s,
    ];
    switch (place ?? widget.mobileHome) {
      case MobileHome.home:
        return QuietHomeScreen(
          key: const ValueKey('quiet-home'),
          sessions: list,
          agents: _heroAgents,
          groups: _heroGroups,
          onOpenGroup: (g) =>
              openGroupThread(context, client: client, group: g),
          onOpenSession: (s) => widget.onOpenSession(s.id, s.title, s.profile),
          onOpenSessions: () => widget.onMobileHome(MobileHome.chats),
          onSettings: _openSettings,
          onSearch: () => showEveryoneSwitcher(
            context,
            agents: _heroAgents,
            groups: _heroGroups,
            sessions: list,
            onOpenAgent: (a) => widget.onAgent(a),
            onOpenGroup: (g) =>
                openGroupThread(context, client: client, group: g),
            onOpenSession: (s) =>
                widget.onOpenSession(s.id, s.title, s.profile),
          ),
          onNew: widget.onNewSession,
          onNewAgent: () => showCreateAgentDialog(context, client),
          pinHost: client.baseUrl,
          onOpenAgent: widget.onAgent,
          onOpenLead: widget.onOpenLead,
          onAllAgents: () => widget.onMobileHome(MobileHome.agents),
          onArtifacts:
              widget.client == null ? null : () => openArtifactsList(context),
          onProfile: (a) => showAgentProfileSettings(context,
              client: client, agent: a, name: a.displayName),
          onDecide: _decideHero,
          offline: widget.sessionsError == null
              ? null
              : QuietOfflineBanner(
                  machine: widget.active?.name ?? 'this machine',
                  since: _lastSeen,
                  onRetry: widget.onRefreshSessions),
        );
      case MobileHome.chats:
        return QuietSessionsScreen(
          key: const ValueKey('quiet-sessions'),
          sessions: list,
          agents: _heroAgents,
          onOpenSession: (s) => widget.onOpenSession(s.id, s.title, s.profile),
          onSessionActions: _sessionActions,
          onNew: widget.onNewSession,
          selecting: _selecting,
          selected: _selected,
          onToggle: (s) => _toggleSelected(s.id),
          onExitSelect: _exitSelect,
          onSelectAll: (shown) => setState(() {
            _selected.addAll([
              for (final s in shown)
                if (!isDedicatedLeadSession(s.id)) s.id
            ]);
          }),
        );
      default:
        return _agentsHome(client);
    }
  }

  Widget _agentsHome(DaemonClient client) => QuietAgentsScreen(
        key: const ValueKey('quiet-agents'),
        client: client,
        agents: _heroAgents,
        sessions: [
          for (final s in _sessions ?? const <SessionInfo>[])
            if (!isDedicatedLeadSession(s.id) && !isInboxSessionRow(s)) s,
        ],
        onOpenAgent: widget.onAgent,
        onOpenLead: widget.onOpenLead,
        onBack: () => widget.onMobileHome(MobileHome.home),
        onOpenSession: (s) => widget.onOpenSession(s.id, s.title, s.profile),
      );

  /// The phone home body for the destination the bar currently selects.
  ///
  /// Each destination gets the whole surface below the bar. Chats keeps a head
  /// for its title and context controls; Agents and Settings own their own
  /// headers, so they render directly.
  Widget _mobileHomeBody(bool hasClient, [MobileHome? home]) {
    final destination = home ?? widget.mobileHome;
    switch (destination) {
      case MobileHome.home:
      case MobileHome.chats:
        return !hasClient
            ? _mobileUnavailable('Add a machine to begin.')
            : _mobileHome(widget.client!, destination);

      case MobileHome.tasks:
        final client = widget.client;
        if (client == null) {
          return _mobileUnavailable('Add a machine to see its tasks.');
        }
        return TasksPanel(key: const ValueKey('phone-tasks'), client: client);

      case MobileHome.agents:
        final client = widget.client;
        if (client == null) {
          return _mobileUnavailable('Add a machine to see its agents.');
        }
        // The agent list lives on the home list; this is one agent's detail.
        final agent = widget.agent;
        // The list stays mounted under the detail so coming back is instant.
        return Stack(fit: StackFit.expand, children: [
          Offstage(
            offstage: agent != null,
            child: TickerMode(
              enabled: agent == null,
              child: hasClient
                  ? _mobileHome(client, MobileHome.agents)
                  : _mobileUnavailable('Add a machine to begin.'),
            ),
          ),
          if (agent != null)
            Padding(
              padding: EdgeInsets.only(bottom: _scrollBottomPad),
              child: PhoneAgentPage(
                agent: agent,
                client: client,
                sessions: _sessions ?? const <SessionInfo>[],
                onClose: () => widget.onAgent(null),
                onOpenSession: (s) =>
                    widget.onOpenSession(s.id, s.title, s.profile),
                onAllSessions: () => widget.onMobileHome(MobileHome.chats),
                onDecide: _decideHero,
              ),
            ),
        ]);
    }
  }

  void _onAgentsList() {
    if (mounted) setState(() {});
  }

  Widget _agentList(DaemonClient client,
          {SessionInfo? lead,
          VoidCallback? onOpenLead,
          bool mirror = false,
          bool embedded = false}) =>
      _FilteredAgentsSidebarPanel(
        embedded: embedded,
        key: mirror ? _agentsMirrorKey : _agentsPanelKey,
        client: client,
        stateFilter: _agentStateFilter,
        lead: lead,
        onOpenLead: onOpenLead,
        searchQuery: _agentFilterQuery,
        bottomPadding: _scrollBottomPad,
        groupsKey: mirror ? 'groups-mirror' : null,
        heroBuilder: kMobile
            ? (count, needs, working) => _phoneHero(
                widget.sessions ?? const <SessionInfo>[],
                idleCast: false,
                wholeTeam: true)
            : null,
        sessions: widget.sessions,
        onOpenSession: (s) => widget.onOpenSession(s.id, s.title, s.profile),
        onSearchChanged: (v) => setState(() => _agentFilterQuery = v),
        onAgentCountChanged: (count) {
          final next = count == 0 ? null : count;
          if (mounted && _agentsCount != next) {
            setState(() => _agentsCount = next);
          }
        },
        onOpenAgent: (a) =>
            kMobile ? widget.onAgent(a) : widget.onOpenAgent?.call(a),
      );

  Widget _emptySessions({bool searching = false}) => Padding(
        padding: EdgeInsets.only(top: kMobile ? 72 : S.s32),
        child: EmptyState(
          icon: searching ? 'search' : 'chat',
          title: searching ? 'No matching sessions' : 'No sessions yet',
          body: searching
              ? 'Nothing matches "${_filterQuery.trim()}". Try a title, project or branch.'
              : 'Start one and it shows up here with its project, status and changes.',
          // On phone the bottom bar's pill is the one new-session action.
          action: searching || widget.client == null || kMobile
              ? null
              : Btn('New session',
                  icon: 'plus', small: !kMobile, onTap: widget.onNewSession),
        ),
      );

  bool _matchesQuery(SessionInfo s) {
    final q = _filterQuery.trim().toLowerCase();
    if (q.isEmpty) return true;
    return s.title.toLowerCase().contains(q) ||
        s.projectFolder.toLowerCase().contains(q) ||
        (s.branch?.toLowerCase().contains(q) ?? false);
  }

  Future<void> _setSettled(SessionInfo s, bool settle) async {
    final c = widget.client;
    if (c == null) return;
    try {
      if (settle) {
        await c.settleSession(s.id);
      } else {
        await c.unsettleSession(s.id);
      }
      if (!mounted) return;
      toast(context, settle ? 'Settled' : 'Awake');
      widget.onRefreshSessions();
    } catch (e) {
      if (mounted) {
        toast(context, "Couldn't ${settle ? 'settle' : 'wake'}: $e",
            danger: true);
      }
    }
  }

  List<SessionInfo> _sortSessionsByRecency(Iterable<SessionInfo> sessions) {
    final sorted = sessions.toList();
    sorted.sort((a, b) => b.lastActive.compareTo(a.lastActive));
    return sorted;
  }

  /// Rows under their project's header, with cross-project Needs you first on
  /// phone when not filtering.
  List<Widget> _groupedRows(List<SessionInfo> sorted,
      {required bool attentionFirst}) {
    if (sorted.isEmpty) return const [];
    final pin = attentionFirst && _filterQuery.trim().isEmpty;
    final out = <Widget>[];
    _chatsShownAt ??= DateTime.now();
    var n = 0;

    final pinnedRows = _pinnedSessions(sorted);
    final pinnedIds = {for (final s in pinnedRows) s.id};
    if (pinnedRows.isNotEmpty) {
      out.add(SessionGroupHeader(
        'Pinned',
        count: pinnedRows.length,
      ));
      for (var i = 0; i < pinnedRows.length; i++) {
        out.add(Appear(
          key: ValueKey('chat-${pinnedRows[i].id}'),
          index: n++,
          since: _chatsShownAt,
          child: _listRow(
            pinnedRows[i],
            above: i > 0 ? pinnedRows[i - 1] : null,
            below: i + 1 < pinnedRows.length ? pinnedRows[i + 1] : null,
            divider: kMobile && i + 1 < pinnedRows.length,
            showProject: true,
          ),
        ));
      }
    }
    final unpinned = [
      for (final s in sorted)
        if (!pinnedIds.contains(s.id)) s,
    ];

    if (!kMobile) {
      // Desktop: one flat newest-first list; no state or project groups.
      for (var i = 0; i < unpinned.length; i++) {
        out.add(Appear(
          key: ValueKey('chat-${unpinned[i].id}'),
          index: n++,
          since: _chatsShownAt,
          child: _listRow(unpinned[i],
              above: i > 0 ? unpinned[i - 1] : null,
              below: i + 1 < unpinned.length ? unpinned[i + 1] : null),
        ));
      }
      return out;
    }

    final List<SessionInfo> groupedSource;
    if (pin) {
      final needsYouRows = [
        for (final s in unpinned)
          if (sessionNeedsYou(s)) s,
      ];
      final cameBackRows = [
        for (final s in unpinned)
          if (sessionCameBack(s)) s,
      ];
      final runningRows = kMobile
          ? const <SessionInfo>[]
          : [
              for (final s in unpinned)
                if (!sessionNeedsYou(s) &&
                    !sessionCameBack(s) &&
                    sessionBusy(s))
                  s,
            ];
      final runningIds = {for (final s in runningRows) s.id};
      groupedSource = [
        for (final s in unpinned)
          if (!sessionNeedsYou(s) &&
              !sessionCameBack(s) &&
              !runningIds.contains(s.id))
            s,
      ];
      void group(String label, List<SessionInfo> rows,
          {bool needsYou = false}) {
        if (rows.isEmpty) return;
        out.add(
            SessionGroupHeader(label, count: rows.length, needsYou: needsYou));
        for (var i = 0; i < rows.length; i++) {
          out.add(Appear(
            key: ValueKey('chat-${rows[i].id}'),
            index: n++,
            since: _chatsShownAt,
            child: _listRow(
              rows[i],
              above: i > 0 ? rows[i - 1] : null,
              below: i + 1 < rows.length ? rows[i + 1] : null,
              divider: kMobile && i + 1 < rows.length,
              showProject: true,
            ),
          ));
        }
      }

      group('Needs you', needsYouRows, needsYou: true);
      group('Running', runningRows);
      group('Completed', cameBackRows);
    } else {
      groupedSource = unpinned;
    }

    if (groupedSource.isEmpty) return out;
    final byFolder = <String, List<SessionInfo>>{};
    for (final s in groupedSource) {
      byFolder.putIfAbsent(projectKey(s), () => []).add(s);
    }
    int rank(SessionInfo s) => !pin
        ? 0
        : s.status == 'waiting_for_input'
            ? 0
            : sessionBusy(s)
                ? 1
                : 2;
    final keys = byFolder.keys.toList();
    final labelCount = <String, int>{};
    for (final k in keys) {
      final l = projectLabel(byFolder[k]!.first);
      labelCount[l] = (labelCount[l] ?? 0) + 1;
    }
    for (final k in keys) {
      final rows = [
        for (var r = 0; r <= 2; r++)
          ...byFolder[k]!.where((s) => rank(s) == r || (!pin && r == 0)),
      ];
      final first = rows.first;
      var label = projectLabel(first);
      if ((labelCount[label] ?? 0) > 1) label = _projectPath(first);
      final needsYou = rows.any(sessionNeedsYou);
      out.add(SessionGroupHeader(
        label,
        count: rows.length,
        needsYou: needsYou,
      ));
      for (var i = 0; i < rows.length; i++) {
        out.add(Appear(
          key: ValueKey('chat-${rows[i].id}'),
          index: n++,
          since: _chatsShownAt,
          child: _listRow(rows[i],
              above: i > 0 ? rows[i - 1] : null,
              below: i + 1 < rows.length ? rows[i + 1] : null,
              divider: kMobile && i + 1 < rows.length),
        ));
      }
    }
    return out;
  }

  String _projectPath(SessionInfo s) {
    final f = s.projectFolder.trim();
    if (f.isEmpty) return 'No project';
    final home = RegExp(r'^(/home/[^/]+|/Users/[^/]+)(?=/|$)').firstMatch(f);
    final rest = home == null ? f : f.substring(home.end);
    final parts = rest.split('/').where((e) => e.isNotEmpty).toList();
    if (parts.isEmpty) return home == null ? '/' : '~';
    final tail = parts.length > 3 ? parts.sublist(parts.length - 3) : parts;
    final lead = parts.length > 3
        ? '…/'
        : home != null
            ? '~/'
            : f.startsWith('/')
                ? '/'
                : '';
    return '$lead${tail.join('/')}';
  }

  String? _providerOf(SessionInfo s) {
    final profile = s.profile ?? '';
    final p = profile.isEmpty ? null : _profileProviders[profile];
    return p != null && providerLogoAsset(p) != null ? p : null;
  }

  Widget _agentBadge(SessionInfo s) {
    final agent = s.displayAgentId?.trim() ?? '';
    if (agent.isNotEmpty) {
      // The moving character is the working signal; rows carry no plan text.
      final state = sessionNeedsYou(s)
          ? AgentCharacterState.needs
          : sessionBusy(s)
              ? AgentCharacterState.working
              : AgentCharacterState.idle;
      if (!kMobile) {
        // Desktop: the same 28 px rounded square as agent rows.
        return ClipRRect(
            borderRadius: BorderRadius.circular(7),
            child: AgentMochi(agent, size: 28, state: state));
      }
      return AgentMochi(agent, size: 20.0, state: state);
    }
    final profile = s.profile ?? '';
    final provider = profile.isEmpty ? null : _profileProviders[profile];
    if (provider != null && providerLogoAsset(provider) != null) {
      return ProviderLogo(provider, size: kMobile ? 16.0 : 14.0);
    }
    return Container(
      width: 6,
      height: 6,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        color: AppColors.fg4,
      ),
    );
  }

  Widget _listRow(SessionInfo s,
      {bool divider = false,
      bool showProject = false,
      SessionInfo? above,
      SessionInfo? below}) {
    final renaming = _renamingId == s.id;
    final checked = _selected.contains(s.id);
    return SessionListRow(
      session: s,
      selected: !kMobile && s.id == widget.selectedSessionId,
      selecting: _selecting,
      checked: checked,
      joinAbove: checked && above != null && _selected.contains(above.id),
      joinBelow: checked && below != null && _selected.contains(below.id),
      draft: !renaming && _hasDraft(s),
      pinned: _isPinnedSession(s),
      divider: divider && !(below != null && _selected.contains(below.id)),
      showProject: showProject,
      renameField: renaming ? _inlineRenameField(s, compact: !kMobile) : null,
      leading: _agentBadge(s),
      provider: kMobile ? null : _providerOf(s),
      machine: kMobile ? null : widget.active?.label,
      onTogglePin: kMobile || isDedicatedLeadSession(s.id)
          ? null
          : () => Pins.instance.toggle(Pins.session, s.id, host: _pinHost),
      onMore: kMobile || isDedicatedLeadSession(s.id)
          ? null
          : (p) => _sessionActions(s, position: p),
      onDecide: kMobile || widget.client == null
          ? null
          : (ok) => quickSend(
              client: widget.client!,
              session: s.id,
              action: ok ? const QuickApprove() : const QuickDeny()),
      onReviewPr: s.pr?.state == 'open' && widget.client != null
          ? () => _reviewSessionPr(s)
          : null,
      onMergePr: s.pr?.state == 'open' && widget.client != null
          ? () => _mergeSessionPr(s)
          : null,
      onTap: renaming
          ? null
          : () => _selecting
              ? _toggleSelected(s.id)
              : widget.onOpenSession(s.id, s.title, s.profile),
      onLongPress: renaming || !kMobile
          ? null
          : () => _selecting ? _toggleSelected(s.id) : _sessionActions(s),
      onSecondaryTapDown: renaming || kMobile || _selecting
          ? null
          : (d) => _sessionActions(s, position: d.globalPosition),
    );
  }

  /// The quiet search field: a palette opener when one is wired, else an
  /// inline filter for both lists.
  /// Desktop sidebar: one scroll holding the agents (Lead first,
  /// then groups) and the recency-ordered sessions. Workspace is metadata on
  /// each row, never a grouping or sort key.
  QuietPlace _place = QuietPlace.home;

  void _selectPlace(QuietPlace p) {
    setState(() => _place = p);
    switch (p) {
      case QuietPlace.home:
        widget.onOpenHome?.call();
      case QuietPlace.tasks:
        widget.onOpenTasks?.call();
      case QuietPlace.agents:
        final c = widget.client;
        if (c == null) {
          widget.onOpenHome?.call();
        } else {
          presentScreen<void>(
            context,
            purpose: ShellPanelPurpose.agents,
            panelId: 'all-agents',
            originClient: c,
            title: 'All agents and groups',
            maxWidth: 720,
            builder: (_, close) => AllAgentsView(
              client: c,
              sessions: widget.sessions ?? const <SessionInfo>[],
              lead: (widget.sessions ?? const <SessionInfo>[])
                  .where((s) => isDedicatedLeadSession(s.id))
                  .firstOrNull,
              onOpenLead: widget.onOpenLead,
              onOpenAgent: (a) => widget.onOpenAgent?.call(a),
              onOpenSession: (s) =>
                  widget.onOpenSession(s.id, s.title, s.profile),
            ),
          );
        }
      case QuietPlace.sessions:
      case QuietPlace.artifacts:
        break;
    }
  }

  /// Desktop Sessions is a page (the cross-agent inbox), not a sidebar mode.
  void _openSessionsPage() {
    final c = widget.client;
    if (c == null) return;
    openSessionsInbox(context,
        client: c,
        initial: widget.sessions ?? const <SessionInfo>[],
        onOpen: (s) => widget.onOpenSession(s.id, s.title, s.profile),
        onNewSession: widget.onOpenHome);
  }

  /// Home sits above the agents.
  Widget _desktopNav() => ValueListenableBuilder<String>(
        valueListenable: activeShellPlace,
        builder: (_, place, __) {
          Widget b(String icon, String tip, bool on, VoidCallback tap) =>
              IconBtn(icon,
                  size: 28,
                  iconSize: 15,
                  active: on,
                  tooltip: tip,
                  onTap: tap);
          return Row(mainAxisSize: MainAxisSize.min, children: [
            b('home', 'Home', place == 'home' && _place != QuietPlace.sessions,
                () => _selectPlace(QuietPlace.home)),
            b('chat-thread', 'Sessions', place == 'sessions',
                _openSessionsPage),
            b('list-checks', 'Tasks', _place == QuietPlace.tasks,
                () => _selectPlace(QuietPlace.tasks)),
            b('file-stack', 'Artifacts', false,
                () => openArtifactsList(context)),
          ]);
        },
      );

  void _toggleAgentSearch() {
    setState(() {
      _agentSearchOpen = !_agentSearchOpen;
      if (_agentSearchOpen) {
        final text = _agentFilterQuery;
        _desktopAgentsSearchCtl.value = TextEditingValue(
          text: text,
          selection: TextSelection.collapsed(offset: text.length),
        );
      } else {
        _desktopAgentsSearchCtl.clear();
        _agentFilterQuery = '';
      }
    });
    if (_agentSearchOpen) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _desktopAgentsSearchFocus.requestFocus();
      });
    }
  }

  Future<void> _openAgentStateFilter(BuildContext anchor) async {
    final picked = await showAppMenu<_AgentListStateFilter>(
      context,
      anchor: anchor,
      below: true,
      alignEnd: true,
      minWidth: 160,
      maxWidth: 200,
      items: [
        for (final filter in _AgentListStateFilter.values)
          appMenuItem(
            value: filter,
            label: filter.label,
            selected: filter == _agentStateFilter,
          ),
      ],
    );
    if (picked != null && mounted) {
      setState(() => _agentStateFilter = picked);
    }
  }

  Widget _agentInlineSearch() => Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
        child: Container(
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(R.of(8)),
          ),
          child: Row(children: [
            AppIcon('search', size: 13, color: AppColors.fg3),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                controller: _desktopAgentsSearchCtl,
                focusNode: _desktopAgentsSearchFocus,
                onChanged: (v) => setState(() => _agentFilterQuery = v),
                style: sans(12, color: AppColors.fg1),
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Search agents',
                  hintStyle: sans(12, color: AppColors.fg3),
                ),
              ),
            ),
            if (_desktopAgentsSearchCtl.text.isNotEmpty)
              IconBtn('x', size: 24, iconSize: 10, tooltip: 'Clear', onTap: () {
                _desktopAgentsSearchCtl.clear();
                setState(() => _agentFilterQuery = '');
              }),
          ]),
        ),
      );

  void _toggleAgentsCollapsed() {
    if (!_agentsCollapsed) {
      _collapsedAgentsCount = _agentsCount ??
          _agentsPanelKey.currentState?.agents.length ??
          widget.client
              ?.cachedCoordinationAgents()
              ?.where((a) => !a.isLead)
              .length;
    }
    setState(() => _agentsCollapsed = !_agentsCollapsed);
  }

  Widget _agentsHeader() {
    final panelCount = _agentsPanelKey.currentState?.agents.length;
    final cachedCount = widget.client
        ?.cachedCoordinationAgents()
        ?.where((a) => !a.isLead)
        .length;
    final loadedCount = _agentsCount ?? panelCount ?? cachedCount;
    final visibleCount = loadedCount == 0 ? null : loadedCount;
    return SidebarSectionHeader(
      'Agents',
      collapsed: _agentsCollapsed,
      count: _agentsCollapsed
          ? (_collapsedAgentsCount ?? visibleCount)
          : visibleCount,
      onToggle: _toggleAgentsCollapsed,
      // Capy: plus and more; search and filter live under more.
      moreTooltip: 'Search and filter',
      moreBuilder: (ctx) async {
        final pick = await showAppMenu<String>(context, anchor: ctx, items: [
          appMenuItem(value: 'search', icon: 'search', label: 'Search agents'),
          appMenuItem(
              value: 'filter',
              icon: 'sliders-horizontal',
              label: 'Filter agents'),
        ]);
        if (!mounted || !ctx.mounted) return;
        if (pick == 'search') _toggleAgentSearch();
        if (pick == 'filter') _openAgentStateFilter(ctx);
      },
      actions: [
        SidebarSectionAction(
          icon: 'plus',
          tooltip: 'New agent or group',
          onTap: (ctx) =>
              _agentsPanelKey.currentState?.openCreateMenu(ctx, above: false),
        ),
      ],
    );
  }

  String? _focusedRowId(String prefix) {
    final ctx = FocusManager.instance.primaryFocus?.context;
    if (ctx == null) return null;
    String? hit;
    void inspect(BuildContext c) {
      final key = c.widget.key;
      if (key is ValueKey<String> && key.value.startsWith(prefix)) {
        hit = key.value.substring(prefix.length);
      }
    }

    inspect(ctx);
    ctx.visitAncestorElements((element) {
      inspect(element);
      return hit == null;
    });
    return hit;
  }

  void _setFocusedExpansion(bool expand) {
    final panel = _agentsPanelKey.currentState;
    if (panel == null) return;
    final agent = _focusedRowId('agent-card-');
    if (agent != null) {
      panel.setAgentRowExpanded(agent, expand);
      return;
    }
    final group = _focusedRowId('group-row-');
    if (group != null) panel.setGroupRowExpanded(group, expand);
  }

  Widget _withSidebarKeyboard(Widget child) => Actions(
        actions: {
          _SidebarExpandIntent:
              CallbackAction<_SidebarExpandIntent>(onInvoke: (intent) {
            _setFocusedExpansion(intent.expand);
            return null;
          }),
        },
        child: Shortcuts(
          shortcuts: const {
            SingleActivator(LogicalKeyboardKey.arrowUp):
                DirectionalFocusIntent(TraversalDirection.up),
            SingleActivator(LogicalKeyboardKey.arrowDown):
                DirectionalFocusIntent(TraversalDirection.down),
            SingleActivator(LogicalKeyboardKey.arrowRight):
                _SidebarExpandIntent(true),
            SingleActivator(LogicalKeyboardKey.arrowLeft):
                _SidebarExpandIntent(false),
            SingleActivator(LogicalKeyboardKey.enter, meta: true):
                ActivateIntent(),
            SingleActivator(LogicalKeyboardKey.enter, control: true):
                ActivateIntent(),
          },
          child: FocusTraversalGroup(child: child),
        ),
      );

  Widget _sectionedSidebar() {
    final hasClient = widget.client != null;
    final all = _sessions ?? const <SessionInfo>[];
    final split = splitSettled(_sortSessionsByRecency(all.where((s) =>
        !isDedicatedLeadSession(s.id) &&
        !isInboxSessionRow(s) &&
        _matchesQuery(s))));
    final list = split.main;
    final mc = all.where((s) => isDedicatedLeadSession(s.id)).firstOrNull;
    _chatsShownAt ??= DateTime.now();
    final rows = _groupedRows(list, attentionFirst: true);
    final searching = _filterQuery.trim().isNotEmpty;
    final showSessions = !hasClient || _place == QuietPlace.sessions;
    final body = showSessions
        ? PullToRefresh(
            onRefresh: () async => widget.onRefreshSessions(),
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              children: [
                // Desktop selects from a row's right-click menu instead.
                SidebarSectionHeader(
                  'Sessions',
                  moreTooltip: 'Session options',
                  moreBuilder: hasClient && kMobile ? _sessionsMenu : null,
                ),
                if (!hasClient)
                  const SidebarEmpty('Add a machine to begin.')
                else if (list.isEmpty)
                  _emptySessions(searching: searching)
                else
                  ...rows,
              ],
            ),
          )
        : Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            // New agents and sessions come from the top + menu.
            _agentsHeader(),
            if (_agentSearchOpen) _agentInlineSearch(),
            Expanded(
              child: PullToRefresh(
                onRefresh: () async => widget.onRefreshSessions(),
                child: ListView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  padding: const EdgeInsets.fromLTRB(0, 0, 0, 8),
                  children: [
                    if (!_agentsCollapsed)
                      _agentList(widget.client!,
                          lead: mc,
                          onOpenLead: widget.onOpenLead,
                          embedded: true),
                  ],
                ),
              ),
            ),
          ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (hasClient) _brandRow(),
      Expanded(
        child: SidebarHoverScope(
          child: _withSidebarKeyboard(body),
        ),
      ),
      // Capy footer: places and tools as one quiet row of icons.
      SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 0, 0, 0),
          // The shell pins its footer tools over the right end of this row.
          child: Row(children: [
            if (hasClient) _desktopNav(),
            const Spacer(),
            if (widget.desktopFooter != null) widget.desktopFooter!,
          ]),
        ),
      ),
    ]);
  }

  /// Capy's brand row: the mark, then search and a new session at the right.
  Widget _brandRow() => SizedBox(
        height: PaneRow.height,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(15, 0, 6, 0),
          child: Row(children: [
            const AgentMochi('snippet', size: 20),
            const Spacer(),
            if (widget.onOpenPalette != null)
              IconBtn('search',
                  size: 28,
                  iconSize: 15,
                  tooltip: kMacOS ? 'Search  Cmd K' : 'Search  Ctrl K',
                  onTap: widget.onOpenPalette),
            IconBtn('square-pen',
                size: 28,
                iconSize: 15,
                tooltip: 'New session',
                onTap: widget.onNewSession),
          ]),
        ),
      );

  Future<void> _sessionsMenu(BuildContext anchor) async {
    final pick = await showAppMenu<String>(
      context,
      anchor: anchor,
      items: [
        appMenuItem(value: 'select', icon: 'check', label: 'Select sessions'),
      ],
    );
    if (pick == 'select' && mounted) _enterSelect();
  }

  // Long-press / right-click a session → pin, rename, settle or delete.
  Future<void> _sessionActions(SessionInfo s, {Offset? position}) async {
    if (isDedicatedLeadSession(s.id)) return;
    final pinned = _isPinnedSession(s);
    if (!kMobile) {
      final overlay =
          Overlay.of(context).context.findRenderObject() as RenderBox;
      final point = position ?? overlay.size.center(Offset.zero);
      final selected = await showAppMenu<String>(
        context,
        point: point,
        items: [
          appMenuItem(
              value: 'pin',
              icon: pinned ? 'pin-off' : 'pin',
              label: pinned ? 'Unpin' : 'Pin'),
          appMenuItem(value: 'rename', icon: 'edit', label: 'Rename'),
          appMenuItem(value: 'select', icon: 'check', label: 'Select'),
          if (s.settled)
            appMenuItem(value: 'wake', icon: 'play', label: 'Wake')
          else if (!sessionIsActive(s.status))
            appMenuItem(value: 'settle', icon: 'archive', label: 'Settle now'),
          const PopupMenuDivider(height: 9),
          appMenuItem(
              value: 'delete', icon: 'trash', label: 'Delete', danger: true),
        ],
      );
      if (selected == 'pin') {
        await Pins.instance.toggle(Pins.session, s.id, host: _pinHost);
      } else if (selected == 'select') {
        _enterSelect(seed: s.id);
      } else if (selected == 'settle' || selected == 'wake') {
        await _setSettled(s, selected == 'settle');
      } else if (selected == 'rename') {
        _beginRename(s);
      } else if (selected == 'delete') {
        await _confirmDeleteSessions([s]);
      }
      return;
    }
    final project = lastPathSegment(s.folder);
    showAppSheet(context,
        title: s.title.isEmpty ? '(untitled)' : s.title,
        subtitle: project.isEmpty ? 'Chat' : project,
        child: SheetActions([
          SheetAction(pinned ? 'pin-off' : 'pin', pinned ? 'Unpin' : 'Pin', () {
            Navigator.pop(context);
            Pins.instance.toggle(Pins.session, s.id, host: _pinHost);
          },
              detail: pinned
                  ? 'Remove from the Pinned section'
                  : 'Keep at the top of the list'),
          SheetAction('edit', 'Rename', () {
            Navigator.pop(context);
            _beginRename(s);
          }, detail: 'Change the title'),
          SheetAction('check', 'Select', () {
            Navigator.pop(context);
            _enterSelect(seed: s.id);
          }, detail: 'Pick several to settle or delete'),
          if (s.settled)
            SheetAction('play', 'Wake', () {
              Navigator.pop(context);
              _setSettled(s, false);
            }, detail: 'Bring it back to the list')
          else if (!sessionIsActive(s.status))
            SheetAction('archive', 'Settle', () {
              Navigator.pop(context);
              _setSettled(s, true);
            }, detail: 'Save its memory and park it'),
          SheetAction('trash', 'Delete', () {
            Navigator.pop(context);
            _confirmDeleteSessions([s]);
          }, danger: true, detail: 'Remove this chat and its history'),
        ]));
  }

  void _enterSelect({String? seed}) {
    if (seed != null && isDedicatedLeadSession(seed)) return;
    setState(() {
      _selecting = true;
      _renamingId = null;
      if (seed != null) _selected.add(seed);
    });
  }

  void _exitSelect() {
    setState(() {
      _selecting = false;
      _selected.clear();
    });
  }

  void _toggleSelected(String id) {
    if (isDedicatedLeadSession(id)) return;
    setState(() {
      if (!_selected.add(id)) _selected.remove(id);
    });
  }

  /// Rows the current filter is showing — the exact set "Select all" acts on.
  ///
  /// Mirrors [_sessionList]'s predicate deliberately: selecting rows the user
  /// cannot see (a filtered-out chat) would let a bulk delete remove something
  /// that was never on screen.
  List<SessionInfo> get _visibleSessions => [
        for (final s in _sessions ?? const <SessionInfo>[])
          if (!isDedicatedLeadSession(s.id) &&
              !isInboxSessionRow(s) &&
              _matchesQuery(s))
            s,
      ];

  bool get _allVisibleSelected {
    final ids = _visibleSessions.map((s) => s.id).toList();
    return ids.isNotEmpty && ids.every(_selected.contains);
  }

  void _toggleSelectAllVisible() {
    final ids = _visibleSessions.map((s) => s.id).toList();
    if (ids.isEmpty) return;
    setState(() {
      if (ids.every(_selected.contains)) {
        for (final id in ids) {
          _selected.remove(id);
        }
      } else {
        _selected.addAll(ids);
      }
      // An emptied selection must not leave the bar up reading "0 selected".
      if (_selected.isEmpty) _selecting = false;
    });
  }

  /// "Select all" / "Unselect all" as a text toggle, not an icon: nothing in the
  /// icon set means "all" unambiguously, and the label also states which way the
  /// next tap goes.
  Widget _selectAllToggle() {
    final all = _allVisibleSelected;
    return TextAction(all ? 'Clear' : 'Select all',
        onTap: _toggleSelectAllVisible);
  }

  /// Desktop: count and Select all on one line, Cancel and Delete below at
  /// equal width, so the destructive action has room and never crowds the count.
  Widget _selectionBar({required bool mobile}) {
    final n = _selected.length;
    if (mobile) {
      return Row(children: [
        IconBtn('x',
            size: M.minTarget,
            iconSize: 18,
            tooltip: 'Cancel',
            onTap: _exitSelect),
        SizedBox(width: S.s4),
        Text(n == 0 ? 'Select chats' : '$n selected', style: TS.sectionTitle()),
        const Spacer(),
        _selectAllToggle(),
        SizedBox(width: S.s4),
        Btn(n == 0 ? 'Delete' : 'Delete $n',
            small: true,
            icon: 'trash',
            variant: BtnVariant.danger,
            disabled: n == 0,
            onTap: _confirmDeleteSelected),
      ]);
    }
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Padding(
        padding: EdgeInsets.symmetric(horizontal: S.s4),
        child: Row(children: [
          Expanded(
            child: Text(n == 0 ? 'Select chats' : '$n selected',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TS.label(AppColors.fg1)),
          ),
          _selectAllToggle(),
        ]),
      ),
      SizedBox(height: S.s8),
      Row(children: [
        Expanded(
          child: Btn('Cancel',
              small: true,
              full: true,
              variant: BtnVariant.secondary,
              onTap: _exitSelect),
        ),
        SizedBox(width: S.s8),
        Expanded(
          child: Btn(n == 0 ? 'Delete' : 'Delete $n',
              small: true,
              full: true,
              icon: 'trash',
              variant: BtnVariant.danger,
              disabled: n == 0,
              onTap: _confirmDeleteSelected),
        ),
      ]),
    ]);
  }

  /// Phone selection's action bar, pinned under the list where the thumb is.
  Widget _mobileSelectionActions() {
    final n = _selected.length;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface1,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      padding: EdgeInsets.fromLTRB(M.gutter, S.s12, M.gutter, S.s12),
      child: Btn(n == 0 ? 'Delete' : 'Delete $n',
          full: true,
          icon: 'trash',
          variant: BtnVariant.danger,
          disabled: n == 0,
          onTap: _confirmDeleteSelected),
    );
  }

  void _beginRename(SessionInfo s) {
    if (isDedicatedLeadSession(s.id)) return;
    _renameCtl.text = s.title;
    _renameCtl.selection =
        TextSelection(baseOffset: 0, extentOffset: _renameCtl.text.length);
    setState(() {
      _selecting = false;
      _selected.clear();
      _renamingId = s.id;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _renameFocus.requestFocus();
    });
  }

  Widget _inlineRenameField(SessionInfo s, {required bool compact}) {
    return InlineEditField(
      controller: _renameCtl,
      focusNode: _renameFocus,
      dense: compact,
      hint: 'Chat title',
      onSubmit: () => _commitRename(s),
      onCancel: () => setState(() => _renamingId = null),
    );
  }

  Future<void> _commitRename(SessionInfo s) async {
    if (_renamingId != s.id) return;
    final c = widget.client;
    final title = _renameCtl.text.trim();
    setState(() => _renamingId = null);
    if (c == null || title.isEmpty || title == s.title) return;
    try {
      await c.renameSession(s.id, title);
      widget.onRefreshSessions();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    }
  }

  Future<void> _confirmDeleteSelected() async {
    final ids = _selected.toList();
    final sessions = (widget.sessions ?? const <SessionInfo>[])
        .where((s) => ids.contains(s.id))
        .toList();
    if (sessions.isEmpty) return;
    await _confirmDeleteSessions(sessions);
  }

  Future<void> _confirmDeleteSessions(List<SessionInfo> sessions) async {
    final c = widget.client;
    if (c == null || sessions.isEmpty) return;
    final n = sessions.length;
    final first = sessions.first.title.isEmpty
        ? '(untitled session)'
        : sessions.first.title;
    final body = n == 1
        ? '$first\n\nPermanently removes the conversation. The folder and its files are untouched.'
        : 'Delete $n conversations? Folders and files are untouched.';
    final ok = await confirmAction(
      context,
      title: n == 1 ? 'Delete session?' : 'Delete $n sessions?',
      body: body,
      confirmLabel: n == 1 ? 'Delete' : 'Delete $n',
    );
    if (!ok || !mounted) return;
    final ids = [for (final s in sessions) s.id];
    setState(() => _deleting.addAll(ids));
    _exitSelect();
    final failed = <String>[];
    Object? lastError;
    await Future.wait(ids.map((id) => c.deleteSession(id).then(
          (_) => widget.onSessionDeleted(id),
          onError: (Object e) {
            failed.add(id);
            lastError = e;
          },
        )));
    if (!mounted) return;
    setState(() => _deleting.removeAll(failed));
    if (failed.isNotEmpty) {
      toast(context,
          "Couldn't delete ${failed.length == 1 ? 'a session' : '${failed.length} sessions'}: $lastError",
          danger: true);
    }
    widget.onRefreshSessions();
  }

  Future<void> _reviewSessionPr(SessionInfo s) async {
    final c = widget.client;
    final pr = s.pr;
    if (c == null || pr == null) return;
    final status = await c.githubStatus(s.id);
    if (!mounted) return;
    if (status == null || !status.available) {
      toast(
        context,
        status?.reason.isNotEmpty == true
            ? status!.reason
            : 'GitHub PRs are unavailable',
        danger: true,
      );
      return;
    }
    await openPullRequest(
      context,
      client: c,
      session: s.id,
      status: status,
      number: pr.number,
    );
  }

  Future<void> _mergeSessionPr(SessionInfo s) async {
    final c = widget.client;
    final pr = s.pr;
    if (c == null || pr == null) return;
    final ok = await confirmAction(
      context,
      title: 'Merge PR #${pr.number}?',
      body: pr.title,
      confirmLabel: 'Merge',
    );
    if (!ok || !mounted) return;
    try {
      await c.mergePr(s.id, pr.number);
      if (!mounted) return;
      toast(context, 'Merged #${pr.number}');
      widget.onRefreshSessions();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    }
  }
}
