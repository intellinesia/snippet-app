import 'dart:async';

import 'package:flutter/material.dart';

import '../../agent_character.dart' show AgentCharacterState;
import '../../api.dart';
import '../../chat/stage_bar.dart';
import '../../chat/stage_header.dart' show StageMember;
import '../../models.dart';
import '../../motion_routes.dart';
import '../../pull_refresh.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../mobile_chrome.dart' show RoundBtn;
import 'agents_group.dart';
import 'home_composer.dart';
import 'home_data.dart';
import 'home_style.dart';
import 'managed_view.dart';
import 'needs_you_pager.dart';
import 'sessions_group.dart';

/// The phone's first screen: Needs you, Agents and Sessions in one list under
/// the stage bar, with the composer floating over a bottom scrim.
class MobileHomeScreen extends StatefulWidget {
  const MobileHomeScreen({
    super.key,
    required this.client,
    required this.sessions,
    required this.agents,
    required this.onOpenSession,
    required this.onOpenAgent,
    required this.onOpenMissionControl,
    required this.onSettings,
    required this.onPlus,
    this.loading = false,
    this.error,
    this.onRefresh,
    this.onDecide,
    this.onSessionActions,
  });

  final DaemonClient client;
  final List<SessionInfo> sessions;
  final List<CoordinationAgent> agents;
  final bool loading;
  final String? error;
  final VoidCallback? onRefresh;
  final void Function(SessionInfo s) onOpenSession;
  final void Function(CoordinationAgent a) onOpenAgent;
  final VoidCallback onOpenMissionControl;
  final VoidCallback onSettings;
  final void Function(BuildContext anchor) onPlus;

  /// Approve or deny a session's pending approval; true when it was sent.
  final Future<bool> Function(SessionInfo s, bool approve)? onDecide;
  final void Function(SessionInfo s)? onSessionActions;

  @override
  State<MobileHomeScreen> createState() => _MobileHomeScreenState();
}

class _MobileHomeScreenState extends State<MobileHomeScreen> {
  final ScrollController _scroll = ScrollController();
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  late final ValueNotifier<List<SessionInfo>> _live =
      ValueNotifier(widget.sessions);
  bool _searching = false;
  bool _asleepOpen = false;
  bool _settledOpen = false;

  @override
  void didUpdateWidget(MobileHomeScreen old) {
    super.didUpdateWidget(old);
    if (!identical(old.sessions, widget.sessions)) {
      _live.value = widget.sessions;
    }
  }

  @override
  void dispose() {
    _scroll.dispose();
    _search.dispose();
    _searchFocus.dispose();
    _live.dispose();
    super.dispose();
  }

  String get _q => _search.text.trim().toLowerCase();

  bool _matches(SessionInfo s) =>
      _q.isEmpty ||
      s.title.toLowerCase().contains(_q) ||
      s.projectFolder.toLowerCase().contains(_q) ||
      (s.branch?.toLowerCase().contains(_q) ?? false);

  void _openSearch() {
    setState(() => _searching = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _searchFocus.requestFocus();
    });
  }

  void _closeSearch() {
    _search.clear();
    _searchFocus.unfocus();
    setState(() => _searching = false);
  }

  void _openManaged(CoordinationAgent agent) {
    Navigator.of(context).push<void>(AppPageRoute<void>(
      builder: (ctx) => ManagedView(
        client: widget.client,
        agent: agent,
        sessions: _live,
        // The shell's tabs sit under this route, so leave it first.
        onOpenSession: (s) {
          Navigator.of(ctx).pop();
          widget.onOpenSession(s);
        },
        onPlus: widget.onPlus,
        onSent: () {},
        onOpenAgent: () {
          Navigator.of(ctx).pop();
          widget.onOpenAgent(agent);
        },
      ),
    ));
  }

  Widget _round(String icon, String label, VoidCallback onTap) => Hit44(
        label: label,
        onTap: onTap,
        child: IgnorePointer(child: RoundBtn(icon: icon, tooltip: label)),
      );

  @override
  Widget build(BuildContext context) {
    final sessions = widget.sessions;
    final asks = needsYouItems(sessions);
    final names = {for (final a in widget.agents) a.id: a.displayName};
    final rows = agentRows(widget.agents, sessions,
        presence: widget.client.presence);
    final q = _q;
    bool agentMatch(AgentRow r) =>
        q.isEmpty || r.agent.displayName.toLowerCase().contains(q);
    final shown = (
      working: rows.working.where(agentMatch).toList(),
      needs: rows.needs.where(agentMatch).toList(),
      asleep: rows.asleep.where(agentMatch).toList(),
    );
    final agentCount =
        shown.working.length + shown.needs.length + shown.asleep.length;
    final human = humanSessions(sessions);
    final main = human.main.where(_matches).toList();
    final settled = human.settled.where(_matches).toList();
    final sessionCount = main.length + settled.length;
    final managed = managedByAgent(sessions);
    final working = rows.working.length;
    final cast = [
      for (final r in rows.working.take(3))
        StageMember(r.agent.id, state: AgentCharacterState.working),
    ];
    final subtitle = asks.isEmpty && working == 0
        ? 'All quiet'
        : [
            if (asks.isNotEmpty) '${asks.length} need you',
            if (working > 0) '$working working',
          ].join(' · ');
    final bottom = MediaQuery.paddingOf(context).bottom;
    final empty = agentCount == 0 && sessionCount == 0 && asks.isEmpty;

    return Stack(clipBehavior: Clip.none, children: [
      Positioned.fill(
        child: PullToRefresh(
          onRefresh: () async => widget.onRefresh?.call(),
          child: SingleChildScrollView(
            controller: _scroll,
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.only(
                top: StageBar.height + 8, bottom: 160 + bottom),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (_searching) _searchField(),
                if (q.isEmpty)
                  NeedsYouSection(
                    items: asks,
                    names: names,
                    onOpen: (i) => widget.onOpenSession(i.session),
                    onDecide: widget.onDecide == null
                        ? null
                        : (i, ok) => widget.onDecide!(i.session, ok),
                  ),
                Padding(
                  padding: EdgeInsets.symmetric(horizontal: M.gutter),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (agentCount > 0) ...[
                        HomeLabel('Agents', count: agentCount),
                        AgentsGroup(
                          rows: shown,
                          managed: managed,
                          asleepOpen: _asleepOpen || q.isNotEmpty,
                          onToggleAsleep: () =>
                              setState(() => _asleepOpen = !_asleepOpen),
                          onOpenAgent: widget.onOpenAgent,
                          onOpenManaged: _openManaged,
                        ),
                      ],
                      if (sessionCount > 0) ...[
                        HomeLabel('Sessions',
                            count: sessionCount,
                            top: agentCount > 0 ? 18 : 0),
                        SessionsGroup(
                          main: main,
                          settled: settled,
                          settledOpen: _settledOpen || q.isNotEmpty,
                          onToggleSettled: () =>
                              setState(() => _settledOpen = !_settledOpen),
                          onOpen: widget.onOpenSession,
                          onLongPress: widget.onSessionActions,
                        ),
                      ],
                      if (empty) _empty(),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        height: 140 + bottom,
        child: IgnorePointer(
          child: DecoratedBox(
            key: const ValueKey('home-scrim'),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.bg.withValues(alpha: 0),
                  AppColors.bg.withValues(alpha: 0.94),
                  AppColors.bg,
                ],
                stops: const [0, 0.75, 1],
              ),
            ),
          ),
        ),
      ),
      Positioned(
        top: 0,
        left: 0,
        right: 0,
        child: StageBar(
          members: cast,
          title: 'Snippet',
          subtitle: subtitle,
          subtitleDot: asks.isNotEmpty ? AppColors.run : AppColors.ok,
        ),
      ),
      Positioned(
          left: M.gutter - 2,
          top: S.s8 - 2,
          child: _round(_searching ? 'x' : 'search',
              _searching ? 'Close search' : 'Search',
              _searching ? _closeSearch : _openSearch)),
      Positioned(
          right: M.gutter - 2,
          top: S.s8 - 2,
          child: _round('settings', 'Settings', widget.onSettings)),
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        child: HomeComposer(
          client: widget.client,
          agentId: 'mission-control',
          agentName: 'Mission Control',
          hint: 'Ask Mission Control',
          onPlus: widget.onPlus,
          onSent: widget.onOpenMissionControl,
        ),
      ),
    ]);
  }

  Widget _searchField() => Padding(
        padding: EdgeInsets.fromLTRB(M.gutter, 0, M.gutter, S.s12),
        child: Container(
          height: 44,
          padding: EdgeInsets.symmetric(horizontal: S.s12),
          decoration: BoxDecoration(
            color: AppColors.surface2.withValues(alpha: 0.9),
            borderRadius: BorderRadius.circular(R.lg),
          ),
          child: Row(children: [
            AppIcon('search', size: 16, color: AppColors.fg3),
            SizedBox(width: S.s8),
            Expanded(
              child: TextField(
                controller: _search,
                focusNode: _searchFocus,
                onChanged: (_) => setState(() {}),
                textInputAction: TextInputAction.search,
                style: sans(15, color: AppColors.fg1),
                cursorColor: AppColors.accent,
                decoration: InputDecoration(
                  isCollapsed: true,
                  border: InputBorder.none,
                  hintText: 'Search agents and sessions',
                  hintStyle: sans(15, color: AppColors.fg3),
                ),
              ),
            ),
          ]),
        ),
      );

  Widget _empty() {
    if (widget.loading && widget.sessions.isEmpty) {
      return Padding(
        padding: EdgeInsets.only(top: S.s40),
        child: Center(child: DelayedSpinner(size: 20)),
      );
    }
    final err = widget.error;
    if (err != null && widget.sessions.isEmpty) {
      return EmptyState(
        icon: 'wifi-off',
        title: "Couldn't load",
        body: err,
        action: Btn('Retry', small: true, onTap: widget.onRefresh ?? () {}),
      );
    }
    return Padding(
      padding: EdgeInsets.only(top: S.s40),
      child: EmptyState(
        icon: _q.isEmpty ? 'chat' : 'search',
        title: _q.isEmpty ? 'No sessions yet' : 'Nothing matches',
        body: _q.isEmpty
            ? 'Start one with the plus and it shows up here.'
            : 'Try a title, project, branch or agent name.',
      ),
    );
  }
}
