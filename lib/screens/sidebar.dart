import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../drafts.dart';
import '../models.dart';
import '../settled_sessions.dart';
import '../crew_status.dart';
import 'agent_rail.dart' show agentRailShown;
import 'sidebar_mode.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'agents_sidebar_panel.dart';
import 'mission_control.dart';
import 'mission_control/coordination_agent_detail.dart';
import 'settings_panel.dart';
import 'shell_models.dart';
import 'shell_nav.dart';
import 'session_list_row.dart';
import 'sidebar_mobile.dart';
import 'tasks/tasks_panel.dart';
import '../pull_refresh.dart';
import '../motion.dart';
import '../mochi.dart';
import '../swr.dart';
import 'mobile_chrome.dart';
export 'sidebar_mobile.dart';

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
  final VoidCallback onOpenMissionControl;
  final ValueChanged<CoordinationAgent>? onOpenAgent;
  final VoidCallback? onOpenPalette;
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
    required this.onOpenMissionControl,
    this.onOpenAgent,
    this.onOpenPalette,
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
  });
  @override
  State<Sidebar> createState() => SidebarState();
}

class SidebarState extends State<Sidebar> {
  DateTime? _chatsShownAt;
  // The session list now lives in the shell (passed via widget.sessions); the
  // sidebar is presentational, so opening the drawer doesn't refetch.
  String _filterQuery = '';
  String _agentFilterQuery = '';

  /// The phone home list shows agents instead of sessions; kept across launches.
  bool get _agentsList => mobileAgentsList.value;
  final _machineKey = GlobalKey(); // anchors the desktop machine popover
  final GlobalKey<TasksPanelState> _tasksPanelKey =
      GlobalKey<TasksPanelState>();
  final GlobalKey<SettingsPanelState> _mobileSettingsKey =
      GlobalKey<SettingsPanelState>();
  SettingsPage? _pendingSettingsCreate;
  final GlobalKey<AgentsSidebarPanelState> _agentsPanelKey =
      GlobalKey<AgentsSidebarPanelState>();
  bool _selecting = false;
  static bool _settledOpen = false;
  final Set<String> _selected = {};
  final Set<String> _collapsedGroups = {};

  /// Phone search: a filter field at the top of each tab.
  final TextEditingController _searchCtl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final TextEditingController _agentSearchCtl = TextEditingController();
  final FocusNode _agentSearchFocus = FocusNode();

  /// Desktop search in section headers.
  final TextEditingController _desktopChatsSearchCtl = TextEditingController();
  final FocusNode _desktopChatsSearchFocus = FocusNode();

  MobileHome _lastMainHome = MobileHome.chats;
  late final PageController _pageController;
  int? _targetPage;

  void _goToPage(int index) {
    if (_pageController.hasClients) {
      _targetPage = index;
      _pageController.jumpToPage(index);
      _targetPage = null;
    }
  }

  Map<String, String> _profileProviders = const {};
  String? _providersFor;

  List<CoordinationAgent> _crew = const [];
  DateTime? _crewAt;
  Revalidator? _crewLive;

  Future<void> _loadCrew() async {
    final client = widget.client;
    if (client == null || kMobile) return;
    final now = DateTime.now();
    if (_crewAt != null && now.difference(_crewAt!).inSeconds < 60) return;
    _crewAt = now;
    try {
      try {
        final a = await client.coordinationAgents();
        if (mounted) {
          setState(() => _crew = a
              .where(
                  (x) => x.status != 'archived' && x.kind != 'mission_control')
              .toList());
        }
      } catch (_) {}
    } catch (_) {}
  }

  Future<void> _loadProviders() async {
    _loadCrew();
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

  void _bindCrewLive() {
    _crewLive?.dispose();
    final client = widget.client;
    _crewLive = client == null
        ? null
        : Revalidator(
            client: client,
            on: (e) => Swr.coordination(e) || Swr.sessionStatus(e),
            debounce: const Duration(seconds: 2),
            onRevalidate: ({required bool force}) {
              _crewAt = null;
              _loadCrew();
            });
  }

  @override
  void initState() {
    super.initState();
    Drafts.instance.addListener(_onDrafts);
    _loadProviders();
    if (!kMobile) {
      _bindCrewLive();
    }
    _pageController = PageController(initialPage: widget.mobileHome.index);
    if (kMobile) {
      mobileAgentsList.addListener(_onAgentsList);
      loadMobileAgentsList();
    }
    if (!kMobile) sidebarAgentsFirst.addListener(_onAgentsList);
    if (widget.mobileHome != MobileHome.settings) {
      _lastMainHome = widget.mobileHome;
    }
  }

  @override
  void didUpdateWidget(covariant Sidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) {
      _crewAt = null;
      if (!kMobile) _bindCrewLive();
    }
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
      if (_targetPage != widget.mobileHome.index &&
          _pageController.hasClients) {
        final current =
            _pageController.page?.round() ?? _pageController.initialPage;
        if (current != widget.mobileHome.index) {
          _goToPage(widget.mobileHome.index);
        }
      }
    }
  }

  String? _renamingId;
  final TextEditingController _renameCtl = TextEditingController();
  final FocusNode _renameFocus = FocusNode();

  void _onDrafts() {
    if (mounted) setState(() {});
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
    mobileAgentsList.removeListener(_onAgentsList);
    sidebarAgentsFirst.removeListener(_onAgentsList);
    Drafts.instance.removeListener(_onDrafts);
    _crewLive?.dispose();
    _pageController.dispose();
    _renameCtl.dispose();
    _renameFocus.dispose();
    _searchCtl.dispose();
    _searchFocus.dispose();
    _agentSearchCtl.dispose();
    _agentSearchFocus.dispose();
    _desktopChatsSearchCtl.dispose();
    _desktopChatsSearchFocus.dispose();
    super.dispose();
  }

  final Set<String> _deleting = {};

  List<SessionInfo>? get _sessions => _deleting.isEmpty
      ? widget.sessions
      : widget.sessions?.where((s) => !_deleting.contains(s.id)).toList();
  bool get _loading => widget.sessionsLoading;

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    final hasClient = widget.client != null;
    return Container(
      color: !kMobile ? Colors.transparent : AppColors.bg,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (widget.topInset && kMacOS) SizedBox(height: kMacTitlebar + 6),
        if (kMobile) ...[
          // The bar is a SIBLING of the content, not an overlay: the content
          // gets the remaining height, so nothing hides behind the bar and no
          // scroll-padding hack is needed. It still reads as floating (inset,
          // rounded, raised).
          // PageView gives smooth swiping left and right across sessions,
          // settings, and agents, with slide transitions when navigating.
          Expanded(
            child: Stack(children: [
              PageView(
                controller: _pageController,
                physics: const NeverScrollableScrollPhysics(),
                onPageChanged: (index) {
                  if (_targetPage != null && _targetPage != index) {
                    return;
                  }
                  _targetPage = null;
                  final dest = MobileHome.values[index];
                  if (widget.mobileHome != dest) {
                    widget.onMobileHome(dest);
                  }
                },
                children: [
                  for (final h in MobileHome.values)
                    SidebarKeepAlivePage(
                      key: ValueKey('mobile-${h.name}'),
                      child: _mobileHomeBody(hasClient, h),
                    ),
                ],
              ),
            ]),
          ),
        ],
        if (!kMobile) ...[
          if (hasClient && (_sessions?.isNotEmpty ?? false) && _selecting)
            Padding(
              padding: const EdgeInsets.fromLTRB(S.s4, S.s4, S.s8, S.s4),
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

  /// The phone home body for the destination the bar currently selects.
  ///
  /// Each destination gets the whole surface below the bar. Chats keeps a head
  /// for its title and context controls; Agents and Settings own their own
  /// headers, so they render directly.
  Widget _mobileHomeBody(bool hasClient, [MobileHome? home]) {
    final destination = home ?? widget.mobileHome;
    switch (destination) {
      case MobileHome.chats:
        // The header STAYS while searching. It names the machine whose chats are
        // being filtered — hiding it exactly when you are narrowing a machine's
        // chats took away the context you were filtering against.
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_selecting || widget.mobileTopBar == null)
              _mobileChatsHeader(hasClient)
            else
              widget.mobileTopBar!,
            Expanded(
              child: !hasClient
                  ? _mobileUnavailable('Add a machine to begin.')
                  : Stack(children: [
                      Positioned.fill(
                          child: _agentsList && !_selecting
                              ? _agentList(widget.client!)
                              : _sessionList()),
                      if (!_selecting) ...[
                        const Positioned(
                            left: 0, right: 0, bottom: 0, child: BottomFade()),
                        Positioned(
                          left: M.gutter,
                          right: M.gutter,
                          bottom: 12,
                          child: Row(children: [
                            Expanded(
                              child: _agentsList
                                  ? FloatingSearch(
                                      key: const ValueKey('search-agents'),
                                      controller: _agentSearchCtl,
                                      focusNode: _searchFocus,
                                      hint: 'Search agents',
                                      onChanged: (v) =>
                                          setState(() => _agentFilterQuery = v),
                                    )
                                  : FloatingSearch(
                                      key: const ValueKey('search-sessions'),
                                      controller: _searchCtl,
                                      focusNode: _searchFocus,
                                      hint: 'Search sessions',
                                      onChanged: (v) =>
                                          setState(() => _filterQuery = v),
                                    ),
                            ),
                            const SizedBox(width: 8),
                            _agentsList
                                ? Builder(
                                    builder: (fab) => AccentFab(
                                        tooltip: 'New agent or group',
                                        onTap: () => _agentsPanelKey
                                            .currentState
                                            ?.openCreateMenu(fab)))
                                : AccentFab(
                                    tooltip: 'New session',
                                    onTap: widget.onNewSession),
                          ]),
                        ),
                      ],
                    ]),
            ),
            if (_selecting) _mobileSelectionActions(),
          ],
        );

      case MobileHome.tasks:
        final client = widget.client;
        if (client == null) {
          return _mobileUnavailable('Add a machine to see its tasks.');
        }
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            MobileBackBar(
              title: 'Tasks',
              menu: widget.onMobileMenu != null,
              onBack: widget.onMobileMenu ?? () => Navigator.maybePop(context),
              trailing: [
                RoundBtn(
                    icon: 'plus',
                    tooltip: 'New task',
                    onTap: () => _tasksPanelKey.currentState?.create()),
              ],
            ),
            Expanded(
              child: TasksPanel(
                key: _tasksPanelKey,
                client: client,
                trailing: const [],
                phoneHeader: false,
              ),
            ),
          ],
        );

      case MobileHome.agents:
        final client = widget.client;
        if (client == null) {
          return _mobileUnavailable('Add a machine to see its agents.');
        }
        // The agent list lives on the home list; this is one agent's detail.
        final agent = widget.agent;
        if (agent == null) return _mobileHomeBody(hasClient, MobileHome.chats);
        return CoordinationAgentDetail(
          key: const ValueKey('agent-detail'),
          agent: agent,
          client: client,
          embedded: false,
          onClose: () => widget.onAgent(null),
        );

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
        return AnimatedSwitcher(
          duration: Motion.base,
          switchInCurve: Motion.enter,
          switchOutCurve: Motion.exit,
          transitionBuilder: (child, anim) {
            final isDetail = child.key == const ValueKey('settings-detail');
            final dx = isDetail ? 0.08 : -0.08;
            return FadeTransition(
              opacity: anim,
              child: SlideTransition(
                position: Tween<Offset>(
                  begin: Offset(dx, 0),
                  end: Offset.zero,
                ).animate(anim),
                child: child,
              ),
            );
          },
          child: section != null
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
              : Column(
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
                        section: widget.settingsSection,
                        onSection: widget.onSettingsSection,
                        onClose: () {
                          if (widget.onSettingsClose != null) {
                            widget.onSettingsClose!();
                          } else {
                            widget.onMobileHome(_lastMainHome);
                          }
                        },
                        embedded: true,
                      ),
                    ),
                  ],
                ),
        );
    }
  }

  void _onAgentsList() {
    if (mounted) setState(() {});
  }

  Widget _agentList(DaemonClient client,
          {SessionInfo? missionControl, VoidCallback? onOpenMissionControl}) =>
      AgentsSidebarPanel(
        key: _agentsPanelKey,
        client: client,
        missionControl: missionControl,
        onOpenMissionControl: onOpenMissionControl,
        searchQuery: _agentFilterQuery,
        onSearchChanged: (v) => setState(() {
          _agentFilterQuery = v;
          if (_agentSearchCtl.text != v) _agentSearchCtl.text = v;
        }),
        onOpenAgent: (a) =>
            kMobile ? widget.onAgent(a) : widget.onOpenAgent?.call(a),
      );

  /// The Chats header: the destination name on the left, icon buttons on
  /// the right for search, new chat, Mission Control and machine avatar.
  Widget _mobileChatsHeader(bool hasClient) {
    if (_selecting) {
      final n = _selected.length;
      // Same footprint as the title row, so entering selection doesn't jump
      // the list; Delete lives in the bottom bar.
      return Padding(
        padding: const EdgeInsets.fromLTRB(S.s4, 16, M.gutter, 6),
        child: SizedBox(
          height: M.minTarget,
          child: Row(children: [
            IconBtn('x',
                size: M.minTarget,
                iconSize: 20,
                tooltip: 'Cancel',
                onTap: _exitSelect),
            const SizedBox(width: S.s4),
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
    return Padding(
      padding: EdgeInsets.fromLTRB(M.gutter, 16, M.gutter, 6),
      child: Row(children: [
        Text('Chats', style: TS.pageTitle()),
        const Spacer(),
        ..._headerTrailing(hasClient),
      ]),
    );
  }

  /// The control at the right of every phone page header: the machine
  /// switcher.
  List<Widget> _headerTrailing(bool hasClient) => [_machineAvatarButton()];

  Widget _mobileSettingsHeader() => MobileBackBar(
        title: 'Settings',
        onBack: () => Navigator.maybePop(context),
      );

  /// Machine switcher, as a small round button: the machine's initial plus a
  /// reachability dot, matching the desktop window bar's avatar so the two read
  /// as the same control.
  Widget _machineAvatarButton() {
    final a = widget.active;
    final ok = a == null ? null : widget.health[a.url];
    final initial = a == null || a.label.trim().isEmpty
        ? '+'
        : a.label.trim().characters.first.toUpperCase();
    return Tooltip(
      message: a == null ? 'Add machine' : 'Switch machine',
      child: Material(
        color: Colors.transparent,
        shape: const CircleBorder(),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap:
              widget.instances.isEmpty ? widget.onAddInstance : _openMachines,
          child: SizedBox(
            width: M.minTarget,
            height: M.minTarget,
            child: Center(
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 30,
                    height: 30,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.surface2,
                      shape: BoxShape.circle,
                    ),
                    child: Text(initial,
                        style: sans(13, weight: W.title, color: AppColors.fg1)),
                  ),
                  Positioned(
                    right: -1,
                    bottom: -1,
                    child: Container(
                      width: 9,
                      height: 9,
                      decoration: BoxDecoration(
                        color: ok == true ? AppColors.ok : AppColors.fg4,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.bg, width: 1.5),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _emptySessions({bool searching = false}) => Padding(
        padding: EdgeInsets.only(top: kMobile ? 72 : 32),
        child: EmptyState(
          icon: searching ? 'search' : 'chat',
          title: searching ? 'No matching sessions' : 'No sessions yet',
          body: searching
              ? 'Nothing matches "${_filterQuery.trim()}". Try a title, project or branch.'
              : 'Start one and it shows up here with its project, status and changes.',
          action: searching || widget.client == null
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

  Widget _settledHeader(List<SessionInfo> rows, {required bool open}) {
    return Padding(
      padding: EdgeInsets.only(top: kMobile ? 8 : 4),
      child: Semantics(
        button: true,
        expanded: open,
        label: 'Settled, ${rows.length}',
        child: ExcludeSemantics(
          child: HoverSurface(
            radius: 8,
            onTap: () => setState(() => _settledOpen = !_settledOpen),
            child: Container(
              height: kMobile ? M.minTarget : 32,
              padding:
                  EdgeInsets.fromLTRB(kMobile ? 4 : 10, 0, kMobile ? 4 : 10, 0),
              child: Row(children: [
                Text('Settled', style: TS.label(AppColors.fg3)),
                const SizedBox(width: 8),
                Text('${rows.length}', style: TS.meta()),
                const Spacer(),
                AnimatedRotation(
                  turns: open ? 0.25 : 0,
                  duration: Motion.base,
                  curve: Curves.easeOutCubic,
                  child:
                      AppIcon('chevron-right', size: 13, color: AppColors.fg3),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
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
            padding: const EdgeInsets.fromLTRB(M.gutter, 2, M.gutter, 32),
            children: [
              Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(mainAxisSize: MainAxisSize.min, children: [
                    AppIcon('wifi-off', size: 20, color: AppColors.fg4),
                    const SizedBox(height: 10),
                    Text(widget.sessionsError!,
                        textAlign: TextAlign.center, style: TS.meta()),
                    const SizedBox(height: 12),
                    TextButton(
                        onPressed: widget.onRefreshSessions,
                        child: Text('Retry',
                            style: sans(12, color: AppColors.accent))),
                  ])),
            ]);
      }
      return ListView(
          padding: const EdgeInsets.fromLTRB(M.gutter, 2, M.gutter, 32),
          children: [_emptySessions()]);
    }
    final split = splitSettled(_sortSessionsByRecency(all.where((s) =>
        !isDedicatedMcSession(s.id) &&
        !isInboxSessionRow(s) &&
        _matchesQuery(s))));
    final children = <Widget>[
      ..._groupedRows(split.main, attentionFirst: true),
    ];
    if (children.isEmpty && split.settled.isEmpty) {
      children.add(_emptySessions(searching: _filterQuery.trim().isNotEmpty));
    }
    final list = PullToRefresh(
      onRefresh: () async => widget.onRefreshSessions(),
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(
            M.gutter, 4, M.gutter, split.settled.isEmpty ? 120 : 16),
        children: children,
      ),
    );
    if (split.settled.isEmpty) return list;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(child: list),
      _settledPinned(split.settled),
    ]);
  }

  /// Rows under their project's header. Groups follow the recency of their
  /// newest session; on phones a group holding a chat that needs input leads,
  /// and inside a group input-needed then working chats come first.
  List<Widget> _groupedRows(List<SessionInfo> sorted,
      {required bool attentionFirst}) {
    if (sorted.isEmpty) return const [];
    final byFolder = <String, List<SessionInfo>>{};
    for (final s in sorted) {
      byFolder.putIfAbsent(projectKey(s), () => []).add(s);
    }
    final pin = attentionFirst && _filterQuery.trim().isEmpty;
    int rank(SessionInfo s) => !pin
        ? 0
        : s.status == 'waiting_for_input'
            ? 0
            : sessionIsActive(s.status)
                ? 1
                : 2;
    var keys = byFolder.keys.toList();
    if (pin) {
      bool needs(String k) =>
          byFolder[k]!.any((s) => s.status == 'waiting_for_input');
      keys = [...keys.where(needs), ...keys.where((k) => !needs(k))];
    }
    final labelCount = <String, int>{};
    for (final k in keys) {
      final l = projectLabel(byFolder[k]!.first);
      labelCount[l] = (labelCount[l] ?? 0) + 1;
    }
    _chatsShownAt ??= DateTime.now();
    final out = <Widget>[];
    var n = 0;
    for (final k in keys) {
      final rows = [
        for (var r = 0; r <= 2; r++)
          ...byFolder[k]!.where((s) => rank(s) == r || (!pin && r == 0)),
      ];
      final first = rows.first;
      var label = projectLabel(first);
      if ((labelCount[label] ?? 0) > 1) label = _projectPath(first);
      final collapsed = _collapsedGroups.contains(k);
      final needsYou = rows.any((s) => s.status == 'waiting_for_input');
      out.add(SessionGroupHeader(
        label,
        count: rows.length,
        collapsed: collapsed,
        needsYou: needsYou,
        onToggle: () => setState(() {
          if (!_collapsedGroups.remove(k)) _collapsedGroups.add(k);
        }),
      ));
      if (!collapsed) {
        for (var i = 0; i < rows.length; i++) {
          out.add(Appear(
            key: ValueKey('chat-${rows[i].id}'),
            index: n++,
            since: _chatsShownAt,
            child: _listRow(rows[i], divider: kMobile && i + 1 < rows.length),
          ));
        }
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

  Widget _agentBadge(SessionInfo s) {
    final size = kMobile ? 16.0 : 14.0;
    final agent = s.displayAgentId?.trim() ?? '';
    if (agent.isNotEmpty) return AgentMochi(agent, size: size);
    final profile = s.profile ?? '';
    final provider = profile.isEmpty ? null : _profileProviders[profile];
    if (provider != null && providerLogoAsset(provider) != null) {
      return ProviderLogo(provider, size: size);
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

  Widget _listRow(SessionInfo s, {bool divider = false}) {
    final renaming = _renamingId == s.id;
    return SessionListRow(
      session: s,
      selected: !kMobile && s.id == widget.selectedSessionId,
      selecting: _selecting,
      checked: _selected.contains(s.id),
      draft: !renaming && _hasDraft(s),
      divider: divider,
      renameField: renaming ? _inlineRenameField(s, compact: !kMobile) : null,
      leading: _agentBadge(s),
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

  /// Settled chats sit pinned under the list and open upward over it.
  Widget _settledPinned(List<SessionInfo> rows) {
    final open = _settledOpen || _filterQuery.trim().isNotEmpty;
    final maxHeight = MediaQuery.sizeOf(context).height * (kMobile ? 0.5 : 0.4);
    return AnimatedContainer(
      duration: Motion.base,
      margin: EdgeInsets.symmetric(horizontal: kMobile ? M.gutter : 4),
      decoration: BoxDecoration(
          border: Border(
              top: BorderSide(
                  color: open ? AppColors.line : Colors.transparent))),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        _settledHeader(rows, open: open),
        Reveal(
          show: open,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: ListView(
              shrinkWrap: true,
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                for (var i = 0; i < rows.length; i++)
                  _listRow(rows[i], divider: kMobile && i + 1 < rows.length),
              ],
            ),
          ),
        ),
        if (kMobile) const SizedBox(height: 76),
      ]),
    );
  }

  /// Desktop sidebar as a single recency-ordered chat stream. Workspace is
  /// metadata on each row, never a grouping or sort key.
  Widget _sectionedSidebar() {
    final hasClient = widget.client != null;
    final all = _sessions ?? const <SessionInfo>[];
    final split = splitSettled(_sortSessionsByRecency(all.where((s) =>
        !isDedicatedMcSession(s.id) &&
        !isInboxSessionRow(s) &&
        _matchesQuery(s))));
    final list = split.main;
    final settledRows = split.settled;
    final mc = all.where((s) => isDedicatedMcSession(s.id)).firstOrNull;
    _chatsShownAt ??= DateTime.now();
    final rows = _groupedRows(list, attentionFirst: false);
    final mcSelected = mc != null && mc.id == widget.selectedSessionId;
    final mcWaiting = mc != null && mc.status == 'waiting_for_input';
    String crewLine() => _crew.isEmpty
        ? 'Standing by'
        : crewSummary(deriveCrew(
            _crew, widget.sessions ?? const <SessionInfo>[],
            presence: widget.client?.presence));
    final mcBusy = mc != null &&
        (sessionIsActive(mc.status) || mc.status == 'waiting_for_input');
    final sessionsBody =
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      if (hasClient || _crew.isNotEmpty) ...[
        if (!agentRailShown(context))
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 4, 8, 4),
            child: HoverSurface(
              selected: mcSelected,
              radius: 8,
              onTap: hasClient ? widget.onOpenMissionControl : null,
              child: Container(
                height: 46,
                padding: const EdgeInsets.only(left: 6, right: 2),
                child: Row(children: [
                  MochiIcon(color: AppColors.accent, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('Mission Control',
                            style: sans(13,
                                weight: W.label,
                                color: mcSelected
                                    ? AppColors.fg1
                                    : AppColors.fg2)),
                        Row(children: [
                          if (mcBusy && !mcWaiting) ...[
                            SessionStateIcon(
                              status: 'running',
                              icon: 'activity',
                              size: 11,
                              activeColor: AppColors.accent,
                            ),
                            const SizedBox(width: 4),
                          ],
                          Expanded(
                            child: ListenableBuilder(
                              listenable:
                                  widget.client?.presence ?? _noPresence,
                              builder: (_, __) => Text(
                                  mcWaiting
                                      ? 'Waiting on you'
                                      : mcBusy
                                          ? 'Working'
                                          : crewLine(),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: sans(12,
                                      color: mcWaiting
                                          ? AppColors.run
                                          : mcBusy
                                              ? AppColors.fg1
                                              : AppColors.fg4)),
                            ),
                          ),
                        ]),
                      ],
                    ),
                  ),
                  const SizedBox(width: 6),
                ]),
              ),
            ),
          ),
        if (widget.onOpenPalette == null)
          Padding(
            padding: const EdgeInsets.fromLTRB(8, 10, 8, 4),
            child: Container(
              height: 32,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              decoration: BoxDecoration(
                color: AppColors.surface1,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: AppColors.line),
              ),
              child: Row(children: [
                AppIcon('search', size: 14, color: AppColors.fg4),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _desktopChatsSearchCtl,
                    focusNode: _desktopChatsSearchFocus,
                    onChanged: (v) => setState(() => _filterQuery = v),
                    style: sans(13, color: AppColors.fg1),
                    decoration: InputDecoration(
                      isCollapsed: true,
                      border: InputBorder.none,
                      hintText: 'Search chats',
                      hintStyle: sans(13, color: AppColors.fg4),
                    ),
                  ),
                ),
                if (_desktopChatsSearchCtl.text.isNotEmpty)
                  IconBtn('x', size: 20, iconSize: 10, tooltip: 'Clear',
                      onTap: () {
                    _desktopChatsSearchCtl.clear();
                    setState(() => _filterQuery = '');
                  }),
              ]),
            ),
          ),
      ],
      Expanded(
        child: PullToRefresh(
          onRefresh: () async => widget.onRefreshSessions(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(4, 0, 4, 16),
            children: [
              if (!hasClient)
                const SidebarEmpty('Add a machine to begin.')
              else if (list.isEmpty && settledRows.isEmpty)
                _emptySessions(searching: _filterQuery.trim().isNotEmpty)
              else
                ...rows,
            ],
          ),
        ),
      ),
      if (hasClient && settledRows.isNotEmpty) _settledPinned(settledRows),
    ]);
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: SidebarModeSwap(
          // The narrow drawer has no switch, so it always lists sessions.
          agentsFirst:
              sidebarAgentsFirst.value && hasClient && agentRailShown(context),
          sessions: sessionsBody,
          agents: (_) => _agentList(widget.client!,
              missionControl: mc,
              onOpenMissionControl: widget.onOpenMissionControl),
        ),
      ),
      Container(
        decoration: BoxDecoration(
            border: Border(top: BorderSide(color: AppColors.line))),
        child: Column(children: [
          if (widget.desktopFooter != null) widget.desktopFooter!,
        ]),
      ),
    ]);
  }

  // Long-press / right-click a session → rename or delete.
  Future<void> _sessionActions(SessionInfo s, {Offset? position}) async {
    if (isDedicatedMcSession(s.id)) return;
    if (!kMobile) {
      final overlay =
          Overlay.of(context).context.findRenderObject() as RenderBox;
      final point = position ?? overlay.size.center(Offset.zero);
      final selected = await showAppMenu<String>(
        context,
        point: point,
        items: [
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
      if (selected == 'select') {
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
    if (seed != null && isDedicatedMcSession(seed)) return;
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
    if (isDedicatedMcSession(id)) return;
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
          if (!isDedicatedMcSession(s.id) &&
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

  Widget _selectionBar({required bool mobile}) {
    final n = _selected.length;
    return Row(children: [
      IconBtn('x',
          size: mobile ? M.minTarget : 28,
          iconSize: mobile ? 18 : 15,
          tooltip: 'Cancel',
          onTap: _exitSelect),
      const SizedBox(width: S.s4),
      Text(n == 0 ? 'Select chats' : '$n selected',
          style: mobile ? TS.sectionTitle() : TS.label(AppColors.fg1)),
      const Spacer(),
      _selectAllToggle(),
      const SizedBox(width: S.s4),
      Btn(n == 0 ? 'Delete' : 'Delete $n',
          small: true,
          icon: 'trash',
          variant: BtnVariant.danger,
          disabled: n == 0,
          onTap: _confirmDeleteSelected),
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
      padding: const EdgeInsets.fromLTRB(M.gutter, S.s12, M.gutter, S.s12),
      child: Btn(n == 0 ? 'Delete' : 'Delete $n',
          full: true,
          icon: 'trash',
          variant: BtnVariant.danger,
          disabled: n == 0,
          onTap: _confirmDeleteSelected),
    );
  }

  void _beginRename(SessionInfo s) {
    if (isDedicatedMcSession(s.id)) return;
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

  // ---- machines ----

  /// Machine list: bottom sheet on phones, a popover anchored to the block on
  /// desktop. Same rows + "Add machine" footer either way.
  Future<void> _openMachines() => showSidebarMachinesPicker(
        context,
        anchorKey: _machineKey,
        instances: widget.instances,
        active: widget.active,
        health: widget.health,
        onSelect: widget.onSelectInstance,
        onAdd: widget.onAddInstance,
        onManage: _machineActions,
        onRefreshHealth: widget.onRefreshHealth,
      );

  void _machineActions(Instance i) => showManageMachineSheet(
        context: context,
        instance: i,
        onRename: (inst, name) => widget.onRenameInstance(inst, name),
        onRemove: (inst) => widget.onRemoveInstance(inst),
      );
}

final _noPresence = ValueNotifier<int>(0);
