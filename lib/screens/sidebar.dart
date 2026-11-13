import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../drafts.dart';
import '../models.dart';
import '../settled_sessions.dart';
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
import '../ambient/controller.dart';
import 'mobile_chrome.dart';
import 'mobile_session_home.dart';
import 'mobile_voice_page.dart' show startMobileVoice;
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

  final GlobalKey<TasksPanelState> _tasksPanelKey =
      GlobalKey<TasksPanelState>();
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
  final Set<String> _selected = {};

  /// Phone search: a filter field at the top of each tab.
  final TextEditingController _searchCtl = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  final TextEditingController _agentSearchCtl = TextEditingController();
  final FocusNode _agentSearchFocus = FocusNode();

  /// Measured height of the shared bottom bar; scroll views pad by it so the
  /// last row clears the glass.
  // Plus button, its gap, the dock and the gap under it.
  double get _barHeight =>
      44 + 10 + 56 + 12 + MediaQuery.viewPaddingOf(context).bottom;
  double get _bottomClearance => _barHeight + M.gutter;

  bool get _showMobileBottomBar =>
      !_selecting &&
      widget.mobileHome != MobileHome.tasks &&
      !(widget.mobileHome == MobileHome.agents && widget.agent != null) &&
      widget.mobileHome != MobileHome.settings;

  double get _scrollBottomPad =>
      _selecting ? 24.0 : (_showMobileBottomBar ? _bottomClearance : 0.0);

  /// Desktop search in section headers.
  final TextEditingController _desktopChatsSearchCtl = TextEditingController();
  final FocusNode _desktopChatsSearchFocus = FocusNode();

  MobileHome _lastMainHome = MobileHome.chats;
  late MobileHome _currentHome = widget.mobileHome;
  MobileHome? _prevHome;
  final Set<MobileHome> _mountedHomes = <MobileHome>{};
  AnimationController? _homeAnimC;
  AnimationController get _homeAnim => _homeAnimC ??= AnimationController(
    vsync: this,
    duration: Motion.fast,
    value: 1.0,
  )..addStatusListener((status) {
      if (status == AnimationStatus.completed && mounted && _prevHome != null) {
        setState(() {
          if (_prevHome == MobileHome.settings || _prevHome == MobileHome.tasks) {
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

  @override
  void initState() {
    super.initState();
    Drafts.instance.addListener(_onDrafts);
    _loadProviders();
    _mountedHomes.add(_currentHome);
    if (!kMobile) sidebarAgentsFirst.addListener(_onAgentsList);
    if (widget.mobileHome != MobileHome.settings) {
      _lastMainHome = widget.mobileHome;
    }
  }

  @override
  void didUpdateWidget(covariant Sidebar oldWidget) {
    super.didUpdateWidget(oldWidget);
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
      if (widget.mobileHome != _currentHome) {
        _prevHome = _currentHome;
        _currentHome = widget.mobileHome;
        _mountedHomes.add(_currentHome);
        final reduced = reduceMotion(context);
        final settingsPush = _currentHome == MobileHome.settings;
        final settingsPop = _prevHome == MobileHome.settings;
        _homeAnim.duration = reduced
            ? const Duration(milliseconds: 150)
            : settingsPush
                ? const Duration(milliseconds: 340)
                : settingsPop
                    ? const Duration(milliseconds: 260)
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

  /// Whether a chat you are not looking at has unsent text waiting.
  bool _hasDraft(SessionInfo s) {
    final c = widget.client;
    return c != null &&
        s.id != widget.selectedSessionId &&
        Drafts.instance.has(Drafts.keyFor(c.baseUrl, s.id));
  }

  @override
  void dispose() {
    sidebarAgentsFirst.removeListener(_onAgentsList);
    Drafts.instance.removeListener(_onDrafts);
    _homeAnimC?.dispose();
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
          Expanded(
            child: Stack(children: [
              _buildMobileHomeStack(hasClient),
              if (_showMobileBottomBar)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          AppColors.bg.withValues(alpha: 0),
                          AppColors.bg.withValues(alpha: 0.85),
                        ],
                      ),
                    ),
                    child: _mobileDock(hasClient),
                  ),
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

  Widget _buildMobileHomeStack(bool hasClient) {
    final prev = _prevHome;
    final curr = _currentHome;
    final ordered = <MobileHome>[
      for (final h in MobileHome.values)
        if (_mountedHomes.contains(h) && h != prev && h != curr) h,
      if (prev != null && _mountedHomes.contains(prev)) prev,
      if (_mountedHomes.contains(curr)) curr,
    ];
    if (prev != null && prev == MobileHome.settings && ordered.length >= 2) {
      final iCurr = ordered.indexOf(curr);
      final iPrev = ordered.indexOf(prev);
      if (iCurr >= 0 && iPrev >= 0 && iPrev < iCurr) {
        ordered[iCurr] = prev;
        ordered[iPrev] = curr;
      }
    }
    final bodies = <MobileHome, Widget>{
      for (final h in ordered)
        h: KeyedSubtree(
          key: ValueKey('mobile-${h.name}'),
          child: _mobileHomeBody(hasClient, h),
        ),
    };
    final reduced = reduceMotion(context);
    return AnimatedBuilder(
      animation: _homeAnim,
      builder: (context, _) {
        final t = _homeAnim.value;
        final settingsPush = prev != null && curr == MobileHome.settings;
        final settingsPop = prev == MobileHome.settings;
        final curved = (settingsPush || settingsPop)
            ? Curves.easeOutCubic.transform(t)
            : Motion.enter.transform(t);
        return Stack(
          fit: StackFit.expand,
          children: [
            for (final h in ordered)
              _homeLayer(
                h,
                body: bodies[h]!,
                prev: prev,
                curr: curr,
                curved: curved,
                reduced: reduced,
                settingsPush: settingsPush,
                settingsPop: settingsPop,
              ),
          ],
        );
      },
    );
  }

  Widget _homeLayer(
    MobileHome h, {
    required Widget body,
    required MobileHome? prev,
    required MobileHome curr,
    required double curved,
    required bool reduced,
    required bool settingsPush,
    required bool settingsPop,
  }) {
    final active = h == curr || (prev != null && h == prev);
    var offstage = !active;
    var ignoring = h != curr;
    var fractionalDx = 0.0;
    var dx = 0.0;
    var opacity = 1.0;
    var scrimAlpha = 0.0;
    var opaqueBg = false;

    if (active && prev != null) {
      if (settingsPush) {
        if (h == curr) {
          opaqueBg = true;
          if (reduced) {
            opacity = curved;
          } else {
            fractionalDx = 1.0 - curved;
          }
        } else {
          if (reduced) {
            opacity = 1.0 - curved;
          } else {
            fractionalDx = -0.3 * curved;
            scrimAlpha = 0.18 * curved;
          }
        }
      } else if (settingsPop) {
        final p = 1.0 - curved;
        if (h == prev) {
          opaqueBg = true;
          if (reduced) {
            opacity = p;
          } else {
            fractionalDx = 1.0 - p;
          }
        } else {
          if (reduced) {
            opacity = curved;
          } else {
            fractionalDx = -0.3 * p;
            scrimAlpha = 0.18 * p;
          }
        }
      } else {
        final dir = curr.index > prev.index ? 1.0 : -1.0;
        if (h == curr) {
          opacity = curved;
          if (!reduced) dx = dir * 8.0 * (1.0 - curved);
        } else {
          opacity = 1.0 - curved;
          if (!reduced) dx = -dir * 8.0 * curved;
        }
      }
    }

    return KeyedSubtree(
      key: ValueKey('mobile-layer-${h.name}'),
      child: Offstage(
        offstage: offstage,
        child: IgnorePointer(
          ignoring: ignoring,
          child: FractionalTranslation(
            translation: Offset(fractionalDx, 0),
            child: Transform.translate(
              offset: Offset(dx, 0),
              child: Opacity(
                opacity: opacity.clamp(0.0, 1.0),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    ColoredBox(
                      color: opaqueBg ? AppColors.bg : Colors.transparent,
                      child: body,
                    ),
                    if (scrimAlpha > 0)
                      Positioned.fill(
                        child: IgnorePointer(
                          child: ColoredBox(
                            color: Colors.black.withValues(alpha: scrimAlpha),
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// The phone home body for the destination the bar currently selects.
  ///
  /// Each destination gets the whole surface below the bar. Chats keeps a head
  /// for its title and context controls; Agents and Settings own their own
  /// headers, so they render directly.
  Widget _mobileHomeBody(bool hasClient,
      [MobileHome? home, bool agentsMirror = false]) {
    final destination = home ?? widget.mobileHome;
    switch (destination) {
      case MobileHome.chats:
        final showAgents = agentsMirror;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _mobileChatsHeader(
              hasClient,
              title: showAgents ? 'Agents' : 'Sessions',
              agents: showAgents,
              agentsMirror: agentsMirror,
            ),
            Expanded(
              child: !hasClient
                  ? _mobileUnavailable('Add a machine to begin.')
                  : showAgents && !_selecting
                      ? _agentList(widget.client!, mirror: agentsMirror)
                      : _sessionList(),
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
              child: Padding(
                padding: EdgeInsets.only(bottom: _scrollBottomPad),
                child: TasksPanel(
                  key: _tasksPanelKey,
                  client: client,
                  trailing: const [],
                  phoneHeader: false,
                ),
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
        if (agent == null) {
          return _mobileHomeBody(hasClient, MobileHome.chats, true);
        }
        return Padding(
          padding: EdgeInsets.only(bottom: _scrollBottomPad),
          child: CoordinationAgentDetail(
            key: const ValueKey('agent-detail'),
            agent: agent,
            client: client,
            embedded: false,
            onClose: () => widget.onAgent(null),
          ),
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
        return Padding(
          padding: EdgeInsets.only(bottom: _scrollBottomPad),
          child: AnimatedSwitcher(
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
          ),
        );
    }
  }

  void _onAgentsList() {
    if (mounted) setState(() {});
  }

  Widget _agentList(DaemonClient client,
          {SessionInfo? missionControl,
          VoidCallback? onOpenMissionControl,
          bool mirror = false}) =>
      AgentsSidebarPanel(
        key: mirror ? _agentsMirrorKey : _agentsPanelKey,
        client: client,
        missionControl: missionControl,
        onOpenMissionControl: onOpenMissionControl,
        searchQuery: _agentFilterQuery,
        bottomPadding: _scrollBottomPad,
        groupsKey: mirror ? 'groups-mirror' : null,
        onSearchChanged: (v) => setState(() {
          _agentFilterQuery = v;
          if (_agentSearchCtl.text != v) _agentSearchCtl.text = v;
        }),
        onOpenAgent: (a) =>
            kMobile ? widget.onAgent(a) : widget.onOpenAgent?.call(a),
      );

  /// The bar's search field filters the list in place, on Chats and Agents.

  int get _mcAttentionCount {
    final override = widget.mcAttention;
    if (override != null) return override;
    var count = 0;
    for (final s in widget.sessions ?? const <SessionInfo>[]) {
      if (!s.settled && (s.needsInput || s.attention != null)) {
        count++;
      }
    }
    return count;
  }

  Widget _mobileChatsHeader(
    bool hasClient, {
    String title = 'Sessions',
    bool agents = false,
    bool agentsMirror = false,
  }) {
    if (_selecting) {
      final n = _selected.length;
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
    return MobileHomeTopBar(
      key: const ValueKey('mobile-home-top'),
      agents: agents,
      controller: agents ? _agentSearchCtl : _searchCtl,
      focusNode: _searchFocus,
      onChanged: (v) =>
          setState(() => agents ? _agentFilterQuery = v : _filterQuery = v),
      onSessions: () => widget.onMobileHome(MobileHome.chats),
      onAgents: () => widget.onMobileHome(MobileHome.agents),
      onSettings: () => widget.onMobileHome(MobileHome.settings),
    );
  }

  Widget _mobileDock(bool hasClient) {
    final agents = widget.mobileHome == MobileHome.agents;
    return Padding(
      padding: EdgeInsets.fromLTRB(
          M.gutter, 12, M.gutter, 12 + MediaQuery.viewPaddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Builder(
            builder: (btnCtx) => _DockPlus(
              tooltip: agents ? 'New agent or group' : 'New session',
              onTap: !hasClient
                  ? null
                  : agents
                      ? () => _agentsMirrorKey.currentState
                          ?.openCreateMenu(btnCtx, above: true)
                      : widget.onNewSession,
            ),
          ),
          const SizedBox(height: 10),
          ListenableBuilder(
            listenable: AmbientController.instance,
            builder: (context, _) => MissionControlDock(
              live: widget.listening || AmbientController.instance.running,
              badgeCount: _mcAttentionCount,
              onOpen: widget.onOpenMissionControl,
              onCall: widget.client == null
                  ? null
                  : () => startMobileVoice(context, widget.client!),
            ),
          ),
        ],
      ),
    );
  }

  Widget _mobileSettingsHeader() => MobileHomeHeader(
        title: 'Settings',
        onBack: () => widget.onMobileHome(_lastMainHome),
      );

  Widget _emptySessions({bool searching = false}) => Padding(
        padding: EdgeInsets.only(top: kMobile ? 72 : 32),
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

  Widget _settledTap({required VoidCallback onTap, required Widget child}) =>
      kMobile
          ? GestureDetector(
              behavior: HitTestBehavior.opaque, onTap: onTap, child: child)
          : HoverSurface(radius: 8, onTap: onTap, child: child);

  Widget _settledHeader(List<SessionInfo> rows, {required bool open}) {
    return Padding(
      padding: EdgeInsets.only(top: kMobile ? 8 : 4),
      child: Semantics(
        button: true,
        expanded: open,
        label: 'Settled, ${rows.length}',
        child: ExcludeSemantics(
          child: _settledTap(
            onTap: () => setState(() => _settledOpen = !_settledOpen),
            child: Container(
              height: kMobile ? M.minTarget : 32,
              padding:
                  EdgeInsets.fromLTRB(kMobile ? 0 : 10, 0, kMobile ? 0 : 10, 0),
              child: Row(children: [
                Text('Settled',
                    style: TS.label(kMobile ? AppColors.fg3 : AppColors.fg4)),
                const SizedBox(width: 8),
                Text('${rows.length}',
                    style: kMobile
                        ? TS.meta()
                        : mono(11, color: AppColors.fg4)),
                const Spacer(),
                AnimatedRotation(
                  turns: open ? 0.25 : 0,
                  duration: Motion.base,
                  curve: Curves.easeOutCubic,
                  child: AppIcon('chevron-right',
                      size: 13,
                      color: kMobile ? AppColors.fg3 : AppColors.fg4),
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
        padding: EdgeInsets.fromLTRB(
            M.gutter, 4, M.gutter, _scrollBottomPad),
        children: children,
      ),
    );
    return list;
  }

  /// Phone list: live sessions as cards, then each folder in its own card.
  List<Widget> _mobileGroupedRows(List<SessionInfo> sorted) {
    if (sorted.isEmpty) return const [];
    final out = <Widget>[];
    final filtering = _filterQuery.trim().isNotEmpty;
    _chatsShownAt ??= DateTime.now();
    var n = 0;
    final live = filtering
        ? const <SessionInfo>[]
        : [
            for (final s in sorted)
              if (sessionNeedsYou(s)) s,
            for (final s in sorted)
              if (!sessionNeedsYou(s) && sessionIsActive(s.status)) s,
          ];
    if (live.isNotEmpty) {
      out.add(MobileSectionLabel('Now', count: live.length, top: 2));
      for (final s in live) {
        out.add(Appear(
          key: ValueKey('chat-${s.id}'),
          index: n++,
          since: _chatsShownAt,
          child: LiveSessionCard(
            session: s,
            leading: _agentBadge(s),
            onTap: () => _selecting
                ? _toggleSelected(s.id)
                : widget.onOpenSession(s.id, s.title, s.profile),
            onLongPress: () =>
                _selecting ? _toggleSelected(s.id) : _sessionActions(s),
          ),
        ));
      }
    }
    final liveIds = {for (final s in live) s.id};
    final byFolder = <String, List<SessionInfo>>{};
    for (final s in sorted) {
      if (liveIds.contains(s.id)) continue;
      byFolder.putIfAbsent(projectKey(s), () => []).add(s);
    }
    final labelCount = <String, int>{};
    for (final rows in byFolder.values) {
      final l = projectLabel(rows.first);
      labelCount[l] = (labelCount[l] ?? 0) + 1;
    }
    var first = live.isEmpty;
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
            _listRow(rows[i], divider: i + 1 < rows.length),
        ]),
      ));
    }
    return out;
  }

  /// Settled sessions as the last card in the phone list, expanding in place.
  Widget _mobileSettledCard(List<SessionInfo> rows) {
    final open = _settledOpen || _filterQuery.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.only(top: 18),
      child: MobileGroupCard(children: [
        Semantics(
          button: true,
          expanded: open,
          label: 'Settled, ${rows.length}',
          child: ExcludeSemantics(
            child: InkWell(
              onTap: () => setState(() => _settledOpen = !_settledOpen),
              child: SizedBox(
                height: M.minTarget + 4,
                child: Row(children: [
                  AppIcon('archive', size: 16, color: AppColors.fg3),
                  const SizedBox(width: 12),
                  Expanded(
                      child: Text('Settled', style: TS.rowTitle(AppColors.fg2))),
                  Text('${rows.length}', style: TS.meta()),
                  const SizedBox(width: 6),
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
              _listRow(rows[i], divider: i + 1 < rows.length),
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

    final List<SessionInfo> groupedSource;
    if (pin) {
      final needsYouRows = [
        for (final s in sorted)
          if (sessionNeedsYou(s)) s,
      ];
      groupedSource = [
        for (final s in sorted)
          if (!sessionNeedsYou(s)) s,
      ];
      if (needsYouRows.isNotEmpty) {
        out.add(SessionGroupHeader(
          'Needs you',
          count: needsYouRows.length,
          needsYou: true,
        ));
        for (var i = 0; i < needsYouRows.length; i++) {
          out.add(Appear(
            key: ValueKey('chat-${needsYouRows[i].id}'),
            index: n++,
            since: _chatsShownAt,
            child: _listRow(
              needsYouRows[i],
              divider: kMobile && i + 1 < needsYouRows.length,
              showProject: true,
            ),
          ));
        }
      }
    } else {
      groupedSource = sorted;
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
            : sessionIsActive(s.status)
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
          child: _listRow(rows[i], divider: kMobile && i + 1 < rows.length),
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

  Widget _agentBadge(SessionInfo s) {
    final agent = s.displayAgentId?.trim() ?? '';
    if (agent.isNotEmpty) {
      return AgentMochi(agent, size: kMobile ? 20.0 : 17.0);
    }
    final profile = s.profile ?? '';
    final provider = profile.isEmpty ? null : _profileProviders[profile];
    if (provider != null && providerLogoAsset(provider) != null) {
      return ProviderLogo(provider, size: kMobile ? 18.0 : 15.0);
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
      {bool divider = false, bool showProject = false}) {
    final renaming = _renamingId == s.id;
    return SessionListRow(
      session: s,
      selected: !kMobile && s.id == widget.selectedSessionId,
      selecting: _selecting,
      checked: _selected.contains(s.id),
      draft: !renaming && _hasDraft(s),
      divider: divider,
      showProject: showProject,
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
      margin: EdgeInsets.only(
          left: kMobile ? M.gutter : 8,
          right: kMobile ? M.gutter : 8,
          bottom: kMobile ? 0 : 6),
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
        if (kMobile) SizedBox(height: _scrollBottomPad),
      ]),
    );
  }

  /// `.sctl`: the Sessions|Agents segment over the palette/search field.
  bool _desktopAgentsAvailable(BuildContext context) =>
      !kMobile && MediaQuery.sizeOf(context).width >= kShellCompact;

  Widget _sidebarControls({required bool agentsFirst}) {
    final agentsAvailable =
        widget.client != null && _desktopAgentsAvailable(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(10, 2, 10, 6),
      child: Column(children: [
        Container(
          height: 28,
          padding: const EdgeInsets.all(2),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(color: AppColors.line),
          ),
          child: Row(children: [
            _segCell('Sessions', !agentsFirst,
                const ValueKey('sidebar-mode-sessions'),
                () => setSidebarAgentsFirst(false)),
            const SizedBox(width: 2),
            _segCell(
                'Agents',
                agentsFirst,
                const ValueKey('sidebar-mode-agents'),
                agentsAvailable ? () => setSidebarAgentsFirst(true) : null),
          ]),
        ),
        const SizedBox(height: 8),
        _sidebarSearch(agentsFirst: agentsFirst),
      ]),
    );
  }

  Widget _segCell(String label, bool on, Key key, VoidCallback? onTap) =>
      Expanded(
        child: Semantics(
          button: true,
          selected: on,
          label: label,
          child: GestureDetector(
            key: key,
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: AnimatedContainer(
              duration: Motion.quick,
              height: 24,
              decoration: BoxDecoration(
                color: on ? AppColors.surface2 : Colors.transparent,
                borderRadius: BorderRadius.circular(7),
              ),
              alignment: Alignment.center,
              child: Text(label,
                  style: sans(12,
                      color: on ? AppColors.fg1 : AppColors.fg4)),
            ),
          ),
        ),
      );

  /// The `.search` field: a palette opener when one is wired, else the
  /// inline filter for whichever list is showing.
  Widget _sidebarSearch({required bool agentsFirst}) {
    final palette = widget.onOpenPalette;
    if (palette != null) {
      return _searchBox(
        onTap: palette,
        child: Row(children: [
          AppIcon('search', size: 14, color: AppColors.fg4),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Search', style: sans(12, color: AppColors.fg4)),
          ),
          Text(kMacOS ? '⌘K' : 'Ctrl+K',
              style: mono(11, color: AppColors.fg4)),
        ]),
      );
    }
    final ctl = agentsFirst ? _agentSearchCtl : _desktopChatsSearchCtl;
    final focus = agentsFirst ? _agentSearchFocus : _desktopChatsSearchFocus;
    return _searchBox(
      child: Row(children: [
        AppIcon('search', size: 14, color: AppColors.fg4),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: ctl,
            focusNode: focus,
            onChanged: (v) => setState(() =>
                agentsFirst ? _agentFilterQuery = v : _filterQuery = v),
            style: sans(12, color: AppColors.fg1),
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              hintText: agentsFirst ? 'Search agents' : 'Search chats',
              hintStyle: sans(12, color: AppColors.fg4),
            ),
          ),
        ),
        if (ctl.text.isNotEmpty)
          IconBtn('x', size: 20, iconSize: 10, tooltip: 'Clear', onTap: () {
            ctl.clear();
            setState(() =>
                agentsFirst ? _agentFilterQuery = '' : _filterQuery = '');
          }),
      ]),
    );
  }

  Widget _searchBox({VoidCallback? onTap, required Widget child}) {
    final box = Container(
      height: 28,
      padding: const EdgeInsets.symmetric(horizontal: 9),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: AppColors.line),
      ),
      child: child,
    );
    if (onTap == null) return box;
    return Tooltip(
      message: kMacOS ? 'Search or jump (⌘K)' : 'Search or jump (Ctrl+K)',
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: box,
        ),
      ),
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
    final rows = _groupedRows(list, attentionFirst: true);
    final agentsFirst =
        sidebarAgentsFirst.value && hasClient && _desktopAgentsAvailable(context);
    final sessionsBody =
        Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Expanded(
        child: PullToRefresh(
          onRefresh: () async => widget.onRefreshSessions(),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
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
      if (hasClient) _sidebarControls(agentsFirst: agentsFirst),
      Expanded(
        child: SidebarModeSwap(
          // The narrow drawer has no switch, so it always lists sessions.
          agentsFirst: agentsFirst,
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


}

class _DockPlus extends StatelessWidget {
  const _DockPlus({required this.tooltip, this.onTap});

  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: Semantics(
          button: true,
          label: tooltip,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap == null
                ? null
                : () {
                    HapticFeedback.lightImpact();
                    onTap!();
                  },
            child: Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                  color: AppColors.accentFill, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: AppIcon('plus', size: 20, color: AppColors.accentFg),
            ),
          ),
        ),
      );
}
