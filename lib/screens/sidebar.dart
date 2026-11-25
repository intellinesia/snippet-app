import 'group_messaging.dart' show openGroupThread;
import 'phone_agent_page.dart';
import 'agent_profile_panel.dart' show showAgentProfileSettings;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart'
    show kMiddleMouseButton, PointerDeviceKind;
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
import 'lead/coordination_agent_detail.dart';
import 'settings_panel.dart';
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
import 'agent_view_mode.dart' show activeShellPlace, openAgentTab, openGroupTab;
import 'all_agents_view.dart';
import '../panel.dart' show presentScreen;
import '../shell_panel.dart' show ShellPanelPurpose;
import '../quiet.dart' show QuietOfflineBanner, QuietPlace;
import 'mobile_home/quiet_home.dart';
import 'mobile_home/quiet_lists.dart';
import 'tasks/tasks_panel.dart' show TasksPanel;
import 'mobile_chrome.dart';
import 'mobile_session_home.dart';
import 'phone_hero.dart';
import '../session_quick_send.dart';
import 'artifacts_screen.dart' show openArtifactsList;
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
  final ValueChanged<MobileHome> onMobileHome;

  /// Phone drill-down state + setters. Also shell-owned, for the same reason:
  /// the back handler and the bar's visibility both live up there.
  final SettingsPage? settingsSection;
  final ValueChanged<SettingsPage?> onSettingsSection;
  final CoordinationAgent? agent;
  final ValueChanged<CoordinationAgent?> onAgent;
  final VoidCallback? onSettingsClose;
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
    required this.onMobileHome,
    required this.settingsSection,
    required this.onSettingsSection,
    required this.agent,
    required this.onAgent,
    this.onSettingsClose,
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
  String _filterQuery = '';
  String _agentFilterQuery = '';

  final GlobalKey<SettingsPanelState> _mobileSettingsKey =
      GlobalKey<SettingsPanelState>();
  SettingsPage? _pendingSettingsCreate;
  final GlobalKey<AgentsSidebarPanelState> _agentsPanelKey =
      GlobalKey<AgentsSidebarPanelState>();

  /// The Agents tab with no agent open mirrors the Chats list; its panel needs
  /// its own key or it collides with the Chats page's in the PageView.
  final GlobalKey<AgentsSidebarPanelState> _agentsMirrorKey =
      GlobalKey<AgentsSidebarPanelState>();
  bool _selecting = false;
  static bool _settledOpen = false;

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
  final TextEditingController _desktopChatsSearchCtl = TextEditingController();
  final FocusNode _desktopChatsSearchFocus = FocusNode();
  final TextEditingController _desktopAgentsSearchCtl = TextEditingController();
  final FocusNode _desktopAgentsSearchFocus = FocusNode();
  bool _agentSearchOpen = false;
  _AgentListStateFilter _agentStateFilter = _AgentListStateFilter.all;
  bool _agentsCollapsed = false;
  int? _collapsedAgentsCount;

  MobileHome _lastMainHome = MobileHome.chats;
  // Settings rides over the main homes as a page, so it is never current here.
  late MobileHome _currentHome = widget.mobileHome == MobileHome.settings
      ? MobileHome.chats
      : widget.mobileHome;
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
    if (widget.mobileHome != MobileHome.settings) {
      _lastMainHome = widget.mobileHome;
    }
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
      if (oldWidget.mobileHome != MobileHome.settings) {
        _lastMainHome = oldWidget.mobileHome;
      }
      if (kMobile) _loadHeroAgents();
      if (widget.mobileHome == MobileHome.settings) {
        // Shown by the page stack over whatever home is current.
      } else if (_slot(widget.mobileHome) == _slot(_currentHome)) {
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
    _desktopChatsSearchCtl.dispose();
    _desktopChatsSearchFocus.dispose();
    _desktopAgentsSearchCtl.dispose();
    _desktopAgentsSearchFocus.dispose();
    super.dispose();
  }

  final Set<String> _deleting = {};
  String? _lastSeen;

  List<SessionInfo>? get _sessions => _deleting.isEmpty
      ? widget.sessions
      : widget.sessions?.where((s) => !_deleting.contains(s.id)).toList();
  bool get _loading => widget.sessionsLoading;

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
    return PhonePageStack(
      onBack: _closeSettings,
      page: widget.mobileHome == MobileHome.settings
          ? KeyedSubtree(
              key: const ValueKey('mobile-settings'),
              child: _mobileHomeBody(hasClient, MobileHome.settings),
            )
          : null,
      base: homes,
    );
  }

  void _closeSettings() {
    if (widget.onSettingsClose != null) {
      widget.onSettingsClose!();
    } else {
      widget.onMobileHome(_lastMainHome);
    }
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
          onSettings: () => widget.onMobileHome(MobileHome.settings),
          onSearch: () => showEveryoneSwitcher(
            context,
            agents: _heroAgents,
            groups: _heroGroups,
            sessions: list,
            onOpenAgent: (a) => widget.onAgent?.call(a),
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

      case MobileHome.settings:
        final client = widget.client;
        if (client == null) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _mobileSettingsHeader(),
              Expanded(
                child: _mobileUnavailable('Add a machine to configure it.'),
              ),
            ],
          );
        }
        final section = widget.settingsSection;
        return Padding(
          padding: EdgeInsets.only(bottom: _scrollBottomPad),
          child: PhonePageStack(
            onBack: () => widget.onSettingsSection(null),
            page: section != null
                ? SettingsPanel(
                    key: const ValueKey('settings-detail'),
                    client: client,
                    instances: widget.instances,
                    active: widget.active,
                    onRemove: widget.onRemoveInstance,
                    onSelect: widget.onSelectInstance,
                    onRename: widget.onRenameInstance,
                    section: section,
                    onSection: widget.onSettingsSection,
                    onClose: () => widget.onSettingsSection(null),
                    embedded: true,
                    createOnOpen:
                        _pendingSettingsCreate == section ? section : null,
                    onCreateHandled: () =>
                        setState(() => _pendingSettingsCreate = null),
                  )
                : null,
            base: Column(
              key: const ValueKey('settings-root'),
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _mobileSettingsHeader(),
                Expanded(
                  child: SettingsPanel(
                    key: _mobileSettingsKey,
                    client: client,
                    instances: widget.instances,
                    active: widget.active,
                    onRemove: widget.onRemoveInstance,
                    onSelect: widget.onSelectInstance,
                    onRename: widget.onRenameInstance,
                    section: null,
                    onSection: widget.onSettingsSection,
                    onClose: _closeSettings,
                    embedded: true,
                  ),
                ),
              ],
            ),
          ),
        );
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
        onOpenAgent: (a) =>
            kMobile ? widget.onAgent(a) : widget.onOpenAgent?.call(a),
      );

  Widget _selectionHeader() {
    final n = _selected.length;
    return Padding(
      padding: EdgeInsets.fromLTRB(S.s4, S.s16, M.gutter, S.s6),
      child: SizedBox(
        height: M.minTarget,
        child: Row(children: [
          IconBtn('x',
              size: M.minTarget,
              iconSize: 20,
              tooltip: 'Cancel',
              onTap: _exitSelect),
          SizedBox(width: S.s4),
          Expanded(
            child: Text(n == 0 ? 'Select chats' : '$n selected',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(kMobile ? M.sectionTitle : 15,
                    weight: W.label, color: AppColors.fg1)),
          ),
          _selectAllToggle(),
        ]),
      ),
    );
  }

  Widget _mobileSettingsHeader() => MobileHomeHeader(
        title: 'Settings',
        onBack: () => widget.onMobileHome(_lastMainHome),
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

  Widget _sessionList() {
    if (_loading && _sessions == null) {
      return Center(child: DelayedSpinner(size: 20));
    }
    final all = _sessions ?? const <SessionInfo>[];
    if (all.isEmpty) {
      // Offline ≠ empty: a failed fetch gets an explicit error + retry.
      if (widget.sessionsError != null) {
        return ListView(
            padding: EdgeInsets.fromLTRB(M.gutter, S.s2, M.gutter, S.s32),
            children: [
              Padding(
                  padding: EdgeInsets.all(S.s20),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    AppIcon('wifi-off', size: 20, color: AppColors.fg4),
                    SizedBox(height: S.of(10)),
                    Text(widget.sessionsError!,
                        textAlign: TextAlign.center, style: TS.meta()),
                    SizedBox(height: S.s12),
                    TextButton(
                        onPressed: widget.onRefreshSessions,
                        child: Text('Retry',
                            style: sans(12, color: AppColors.accent))),
                  ])),
            ]);
      }
      return ListView(
          padding: EdgeInsets.fromLTRB(M.gutter, S.s2, M.gutter, S.s32),
          children: [_emptySessions()]);
    }
    final split = splitSettled(_sortSessionsByRecency(all.where((s) =>
        !isDedicatedLeadSession(s.id) &&
        !isInboxSessionRow(s) &&
        _matchesQuery(s))));
    final children = <Widget>[
      if (kMobile && _filterQuery.trim().isEmpty) _phoneHero(split.main),
      ...(kMobile
          ? _mobileGroupedRows(split.main)
          : _groupedRows(split.main, attentionFirst: true)),
    ];
    if (kMobile && split.settled.isNotEmpty) {
      children.add(_mobileSettledCard(split.settled));
    } else if (split.settled.isNotEmpty) {
      final settledOpen = _settledOpen || _filterQuery.trim().isNotEmpty;
      children.add(SessionGroupHeader(
        'Settled',
        count: split.settled.length,
        collapsed: !settledOpen,
        chevronRight: true,
        onToggle: () => setState(() => _settledOpen = !_settledOpen),
      ));
      children.add(Reveal(
        show: settledOpen,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < split.settled.length; i++)
              _listRow(split.settled[i],
                  above: i > 0 ? split.settled[i - 1] : null,
                  below: i + 1 < split.settled.length
                      ? split.settled[i + 1]
                      : null,
                  divider: kMobile && i + 1 < split.settled.length),
          ],
        ),
      ));
    }
    if (children.isEmpty) {
      children.add(_emptySessions(searching: _filterQuery.trim().isNotEmpty));
    }
    final list = PullToRefresh(
      onRefresh: () async => widget.onRefreshSessions(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding:
            EdgeInsets.fromLTRB(M.gutter, S.s4, M.gutter, _scrollBottomPad),
        children: children,
      ),
    );
    return list;
  }

  /// Phone list: pinned sessions first, live sessions as cards, then each folder in its own card.
  List<Widget> _mobileGroupedRows(List<SessionInfo> sorted) {
    if (sorted.isEmpty) return const [];
    final out = <Widget>[];
    final filtering = _filterQuery.trim().isNotEmpty;
    _chatsShownAt ??= DateTime.now();
    var n = 0;
    final pinned = _pinnedSessions(sorted);
    final pinnedIds = {for (final s in pinned) s.id};
    if (pinned.isNotEmpty) {
      out.add(MobileSectionLabel('Pinned',
          icon: 'pin', count: pinned.length, top: 2));
      bool isLive(SessionInfo s) =>
          !filtering &&
          (sessionNeedsYou(s) || sessionCameBack(s) || sessionBusy(s));
      final rest = [
        ...pinned.where(isLive),
        ...pinned.where((s) => !isLive(s))
      ];
      if (rest.isNotEmpty) {
        out.add(Appear(
          key: const ValueKey('folder-pinned'),
          index: n++,
          since: _chatsShownAt,
          child: MobileGroupCard(children: [
            for (var i = 0; i < rest.length; i++)
              _listRow(rest[i],
                  above: i > 0 ? rest[i - 1] : null,
                  below: i + 1 < rest.length ? rest[i + 1] : null,
                  divider: i + 1 < rest.length,
                  showProject: true),
          ]),
        ));
      }
    }
    final remaining = [
      for (final s in sorted)
        if (!pinnedIds.contains(s.id)) s,
    ];
    final needs = filtering
        ? const <SessionInfo>[]
        : [
            for (final s in remaining)
              if (sessionNeedsYou(s)) s
          ];
    final cameBack = filtering
        ? const <SessionInfo>[]
        : [
            for (final s in remaining)
              if (sessionCameBack(s)) s
          ];
    final running = filtering
        ? const <SessionInfo>[]
        : [
            for (final s in remaining)
              if (!sessionNeedsYou(s) && !sessionCameBack(s) && sessionBusy(s))
                s,
          ];
    var top = pinned.isEmpty ? 2.0 : 18.0;
    void liveSection(String label, List<SessionInfo> rows) {
      if (rows.isEmpty) return;
      out.add(MobileSectionLabel(label, top: top));
      top = 18;
      // Same rows as the folders; detail (plans, lanes, asks) lives in the hero.
      out.add(Appear(
        key: ValueKey('live-$label'),
        index: n++,
        since: _chatsShownAt,
        child: MobileGroupCard(children: [
          for (var i = 0; i < rows.length; i++)
            _listRow(rows[i],
                above: i > 0 ? rows[i - 1] : null,
                below: i + 1 < rows.length ? rows[i + 1] : null,
                divider: i + 1 < rows.length,
                showProject: true),
        ]),
      ));
    }

    liveSection('Needs you', needs);
    liveSection('Running', running);
    liveSection('Completed', cameBack);
    final liveIds = {
      for (final s in [...needs, ...cameBack, ...running]) s.id
    };
    final byFolder = <String, List<SessionInfo>>{};
    for (final s in remaining) {
      if (liveIds.contains(s.id)) continue;
      byFolder.putIfAbsent(projectKey(s), () => []).add(s);
    }
    final labelCount = <String, int>{};
    for (final rows in byFolder.values) {
      final l = projectLabel(rows.first);
      labelCount[l] = (labelCount[l] ?? 0) + 1;
    }
    var first = top == 2;
    for (final rows in byFolder.values) {
      var label = projectLabel(rows.first);
      if ((labelCount[label] ?? 0) > 1) label = _projectPath(rows.first);
      out.add(MobileSectionLabel(label,
          icon: 'folder', count: rows.length, top: first ? 2 : 18));
      first = false;
      out.add(Appear(
        key: ValueKey('folder-${projectKey(rows.first)}'),
        index: n++,
        since: _chatsShownAt,
        child: MobileGroupCard(children: [
          for (var i = 0; i < rows.length; i++)
            _listRow(rows[i],
                above: i > 0 ? rows[i - 1] : null,
                below: i + 1 < rows.length ? rows[i + 1] : null,
                divider: i + 1 < rows.length),
        ]),
      ));
    }
    return out;
  }

  /// Settled sessions as the last card in the phone list, expanding in place.
  Widget _mobileSettledCard(List<SessionInfo> rows) {
    final open = _settledOpen || _filterQuery.trim().isNotEmpty;
    return Padding(
      padding: EdgeInsets.only(top: S.of(18)),
      child: MobileGroupCard(children: [
        Semantics(
          button: true,
          expanded: open,
          label: 'Settled, ${rows.length}',
          child: ExcludeSemantics(
            child: InkWell(
              overlayColor: const WidgetStatePropertyAll(Colors.transparent),
              splashFactory: NoSplash.splashFactory,
              highlightColor: Colors.transparent,
              onTap: () {
                pickHaptic();
                setState(() => _settledOpen = !_settledOpen);
              },
              child: SizedBox(
                height: M.minTarget + 4,
                child: Row(children: [
                  AppIcon('archive', size: 16, color: AppColors.fg3),
                  SizedBox(width: S.s12),
                  Expanded(
                      child:
                          Text('Settled', style: TS.rowTitle(AppColors.fg2))),
                  Text('${rows.length}', style: TS.meta()),
                  SizedBox(width: S.s6),
                  AnimatedRotation(
                    turns: open ? 0.25 : 0,
                    duration: Motion.base,
                    curve: Curves.easeOutCubic,
                    child: AppIcon('chevron-right',
                        size: 14, color: AppColors.fg3),
                  ),
                ]),
              ),
            ),
          ),
        ),
        Reveal(
          show: open,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(height: 1, color: AppColors.line),
            for (var i = 0; i < rows.length; i++)
              _listRow(rows[i],
                  above: i > 0 ? rows[i - 1] : null,
                  below: i + 1 < rows.length ? rows[i + 1] : null,
                  divider: i + 1 < rows.length),
          ]),
        ),
      ]),
    );
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
  Widget _sidebarSearch() {
    final palette = widget.onOpenPalette;
    if (palette != null) {
      return _searchBox(
        onTap: palette,
        child: Row(children: [
          AppIcon('search', size: 13, color: AppColors.fg2),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Search', style: sans(12, color: AppColors.fg2)),
          ),
          Text('Cmd K', style: sans(11, color: AppColors.fg3)),
        ]),
      );
    }
    final ctl = _desktopChatsSearchCtl;
    return _searchBox(
      child: Row(children: [
        AppIcon('search', size: 13, color: AppColors.fg2),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: ctl,
            focusNode: _desktopChatsSearchFocus,
            onChanged: (v) => setState(() {
              _filterQuery = v;
              _agentFilterQuery = v;
            }),
            style: sans(12, color: AppColors.fg1),
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              hintText: 'Search',
              hintStyle: sans(12, color: AppColors.fg2),
            ),
          ),
        ),
        if (ctl.text.isEmpty)
          Text('Cmd K', style: sans(11, color: AppColors.fg3))
        else
          IconBtn('x', size: 24, iconSize: 10, tooltip: 'Clear', onTap: () {
            ctl.clear();
            setState(() {
              _filterQuery = '';
              _agentFilterQuery = '';
            });
          }),
      ]),
    );
  }

  Widget _searchBox({VoidCallback? onTap, required Widget child}) =>
      _SidebarSearchBox(onTap: onTap, child: child);

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

  /// Home sits above the agents.
  Widget _desktopNav() => Padding(
        padding: const EdgeInsets.fromLTRB(8, 0, 8, 6),
        child: ValueListenableBuilder<String>(
          valueListenable: activeShellPlace,
          builder: (_, place, __) => Column(children: [
            _PlaceRow(
              label: 'Home',
              icon: 'home',
              selected: place == 'home' && _place != QuietPlace.sessions,
              onTap: () => _selectPlace(QuietPlace.home),
            ),
            _PlaceRow(
              label: 'Tasks',
              icon: 'list-checks',
              selected: _place == QuietPlace.tasks,
              onTap: () => _selectPlace(QuietPlace.tasks),
            ),
            _PlaceRow(
              label: 'Artifacts',
              icon: 'file-stack',
              selected: false,
              onTap: () => openArtifactsList(context),
            ),
            _PlaceRow(
              label: 'Automations',
              icon: 'repeat',
              selected: false,
              onTap: widget.onOpenWakes,
            ),
          ]),
        ),
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
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(R.of(8)),
          ),
          child: Row(children: [
            AppIcon('search', size: 12, color: AppColors.fg3),
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
      _collapsedAgentsCount = _agentsPanelKey.currentState?.agents.length ??
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
    return Padding(
      padding: const EdgeInsets.only(top: 2),
      child: SidebarSectionHeader(
        'Agents',
        collapsed: _agentsCollapsed,
        count: _agentsCollapsed
            ? (_collapsedAgentsCount ?? cachedCount)
            : panelCount ?? cachedCount,
        onToggle: _toggleAgentsCollapsed,
        actions: [
          SidebarSectionAction(
            icon: 'search',
            tooltip: 'Search agents',
            onTap: (_) => _toggleAgentSearch(),
          ),
          SidebarSectionAction(
            icon: 'sliders-horizontal',
            tooltip: 'Filter agents',
            onTap: (ctx) {
              _openAgentStateFilter(ctx);
            },
          ),
          SidebarSectionAction(
            icon: 'plus',
            tooltip: 'New agent or group',
            onTap: (ctx) =>
                _agentsPanelKey.currentState?.openCreateMenu(ctx, above: false),
          ),
        ],
      ),
    );
  }

  Widget _pinnedArtifactsHeader() => Padding(
        padding: const EdgeInsets.only(top: 2, bottom: 2),
        child: SidebarSectionHeader(
          'Pinned artifacts',
          collapsed: true,
          count: 0,
          actions: const [
            SidebarSectionAction(
              icon: 'plus',
              tooltip: 'No artifact picker available',
              enabled: false,
            ),
          ],
        ),
      );

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
    final agent = _focusedRowId('agent-card-');
    if (agent != null) {
      if (expand) {
        openAgentTab.value = agent;
      } else if (openAgentTab.value == agent) {
        openAgentTab.value = null;
      }
      return;
    }
    final group = _focusedRowId('group-row-');
    if (group != null) {
      if (expand) {
        openGroupTab.value = group;
      } else if (openGroupTab.value == group) {
        openGroupTab.value = null;
      }
    }
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
                  padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
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
      if (hasClient)
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 4, 8, 6),
          child: _sidebarSearch(),
        ),
      Expanded(
        child: SidebarHoverScope(
          child: _withSidebarKeyboard(
            Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (hasClient) _desktopNav(),
              Expanded(child: body),
            ]),
          ),
        ),
      ),
      if (hasClient) _pinnedArtifactsHeader(),
      if (widget.desktopFooter != null) widget.desktopFooter!,
    ]);
  }

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

class _SidebarSearchBox extends StatefulWidget {
  const _SidebarSearchBox({required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_SidebarSearchBox> createState() => _SidebarSearchBoxState();
}

class _SidebarSearchBoxState extends State<_SidebarSearchBox> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(R.of(8));
    final tappable = widget.onTap != null;
    final fill = _focus
        ? AppColors.surface3
        : _hover && tappable
            ? AppColors.hoverPlate
            : AppColors.surface2;
    final box = ClipRRect(
      borderRadius: radius,
      child: Stack(children: [
        AnimatedContainer(
          duration: reduceMotion(context) ? Duration.zero : Motion.quick,
          curve: Curves.easeOut,
          height: 28,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          decoration: BoxDecoration(color: fill, borderRadius: radius),
          child: widget.child,
        ),
        if (_focus)
          Positioned(
            left: 0,
            top: 0,
            bottom: 0,
            width: 2,
            child: ColoredBox(color: AppColors.fg1),
          ),
      ]),
    );
    final focused = Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (v) => setState(() => _focus = v &&
          FocusManager.instance.highlightMode ==
              FocusHighlightMode.traditional),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: tappable ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: tappable
            ? Material(
                type: MaterialType.transparency,
                child: InkWell(
                  borderRadius: radius,
                  hoverColor: Colors.transparent,
                  focusColor: Colors.transparent,
                  splashFactory: NoSplash.splashFactory,
                  onTap: widget.onTap,
                  child: box,
                ),
              )
            : box,
      ),
    );
    if (!tappable) return focused;
    return Tooltip(
      message: kMacOS ? 'Search or jump (⌘K)' : 'Search or jump (Ctrl+K)',
      child: focused,
    );
  }
}

class _PlaceRow extends StatefulWidget {
  const _PlaceRow({
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final String icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  State<_PlaceRow> createState() => _PlaceRowState();
}

class _PlaceRowState extends State<_PlaceRow> {
  bool _hover = false;
  bool _focus = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onTap != null;
    final fill = _focus
        ? AppColors.surface3
        : widget.selected
            ? AppColors.surface2
            : _hover && enabled
                ? AppColors.hoverPlate
                : Colors.transparent;
    final fg = !enabled
        ? AppColors.fg4
        : widget.selected
            ? AppColors.fg1
            : AppColors.fg2;
    final radius = BorderRadius.circular(R.of(8));
    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onFocusChange: (v) => setState(() => _focus = v &&
          FocusManager.instance.highlightMode ==
              FocusHighlightMode.traditional),
      child: MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: enabled ? SystemMouseCursors.click : SystemMouseCursors.basic,
        child: Listener(
          onPointerDown: !enabled
              ? null
              : (e) {
                  if (e.kind == PointerDeviceKind.mouse &&
                      e.buttons & kMiddleMouseButton != 0) {
                    middleClickOpen = true;
                    widget.onTap!();
                    middleClickOpen = false;
                  }
                },
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: radius,
              hoverColor: Colors.transparent,
              focusColor: Colors.transparent,
              splashFactory: NoSplash.splashFactory,
              onTap: enabled
                  ? () {
                      tapHaptic();
                      widget.onTap!();
                    }
                  : null,
              child: ClipRRect(
                borderRadius: radius,
                child: Stack(children: [
                  AnimatedContainer(
                    duration:
                        reduceMotion(context) ? Duration.zero : Motion.quick,
                    curve: Curves.easeOut,
                    height: 28,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration:
                        BoxDecoration(color: fill, borderRadius: radius),
                    child: Row(children: [
                      AppIcon(widget.icon, size: 14, color: fg),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          widget.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(13,
                              weight: widget.selected ? W.label : W.body,
                              color: fg),
                        ),
                      ),
                    ]),
                  ),
                  if (_focus)
                    Positioned(
                      left: 0,
                      top: 0,
                      bottom: 0,
                      width: 2,
                      child: ColoredBox(color: AppColors.fg1),
                    ),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
