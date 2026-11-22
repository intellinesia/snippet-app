import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';

import '../../api.dart';
import '../../glass.dart';
import '../../models.dart';
import '../../motion_routes.dart';
import '../../tap_detector.dart';
import '../../theme.dart';
import '../../widgets.dart';
import '../mobile_chrome.dart' show RoundBtn;
import 'agents_group.dart';
import 'everyone_sheet.dart';
import 'home_composer.dart';
import 'home_data.dart';
import 'home_resting.dart';
import 'home_style.dart';
import 'managed_view.dart';
import 'one_thing_ask.dart';
import 'sessions_group.dart';

/// Round 6 "One thing" phone first screen:
/// - Bare top bar over Silk (Search, "Snippet" + status, Settings)
/// - Quiet state: resting Silk + "Everyone" pull-up handle above the composer
/// - Busy state: the single top ask centred in Literata with its two actions
///   and a "n more" control
/// - Pull-up "Everyone" sheet over dimmed home (Working, Your sessions, Asleep,
///   Settled), with the shared MC composer staying on top.
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

class _MobileHomeScreenState extends State<MobileHomeScreen>
    with SingleTickerProviderStateMixin {
  final TextEditingController _search = TextEditingController();
  final FocusNode _searchFocus = FocusNode();
  late final ValueNotifier<List<SessionInfo>> _live =
      ValueNotifier(widget.sessions);
  bool _searching = false;
  bool _everyoneOpen = false;
  bool _sheetShown = false;
  LocalHistoryEntry? _backEntry;
  late final AnimationController _sheet;

  @override
  void initState() {
    super.initState();
    _sheet = AnimationController.unbounded(vsync: this, value: 0)
      ..addStatusListener(_sheetStatus);
  }
  bool _asleepOpen = false;
  // Null until the user toggles; then Settled starts open only when there
  // are no live sessions to show instead.
  bool? _settledUser;
  bool _settledOpenFor(bool noLive) => _settledUser ?? noLive;

  @override
  void didUpdateWidget(MobileHomeScreen old) {
    super.didUpdateWidget(old);
    if (!identical(old.sessions, widget.sessions)) {
      _live.value = widget.sessions;
    }
  }

  @override
  void dispose() {
    _backEntry = null;
    _sheet.dispose();
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
    if (_everyoneOpen) _settleSheet(open: false);
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

  double get _sheetHeight {
    final mq = MediaQuery.of(context);
    return mq.size.height - math.max(132.0, mq.padding.top + 72.0);
  }

  void _sheetStatus(AnimationStatus status) {
    if (status != AnimationStatus.completed) return;
    if (!_everyoneOpen && _sheetShown && _sheet.value <= 0.001) {
      setState(() => _sheetShown = false);
    }
  }

  /// Hold a local history entry while the sheet is open, so the shell's Back
  /// handling closes the sheet before it pops anything.
  void _holdBack() {
    if (_backEntry != null) return;
    final entry = LocalHistoryEntry(onRemove: () {
      _backEntry = null;
      if (_everyoneOpen && mounted) _settleSheet(open: false, fromBack: true);
    });
    _backEntry = entry;
    ModalRoute.of(context)?.addLocalHistoryEntry(entry);
  }

  void _releaseBack() {
    final e = _backEntry;
    _backEntry = null;
    e?.remove();
  }

  void _settleSheet({required bool open, double velocity = 0, bool fromBack = false}) {
    if (open) {
      _holdBack();
    } else if (!fromBack) {
      _releaseBack();
    }
    final changed = _everyoneOpen != open;
    setState(() {
      _everyoneOpen = open;
      if (open) _sheetShown = true;
    });
    if (changed) tapHaptic();
    final target = open ? 1.0 : 0.0;
    if (reduceMotion(context)) {
      _sheet.animateTo(target,
          duration: const Duration(milliseconds: 120),
          curve: Curves.easeOut);
      return;
    }
    final v = velocity / _sheetHeight;
    _sheet.animateWith(SpringSimulation(
        const SpringDescription(mass: 1, stiffness: 380, damping: 34),
        _sheet.value,
        target,
        v));
  }

  void _openEveryone() {
    if (_everyoneOpen) return;
    _settleSheet(open: true);
  }

  void _closeEveryone() {
    if (!_everyoneOpen) return;
    _settleSheet(open: false);
  }

  void _dragSheet(double dy) {
    if (!_sheetShown) setState(() => _sheetShown = true);
    _sheet.stop();
    final step = -dy / _sheetHeight;
    final next = _sheet.value + step;
    // Past either end the finger moves the sheet 30% as far.
    final v = next < 0 || next > 1 ? _sheet.value + step * 0.3 : next;
    _sheet.value = v;
  }

  void _releaseSheet(double vy) {
    // vy is px/s downward; progress velocity is the opposite.
    final up = -vy;
    final open = up.abs() >= 700 ? up > 0 : _sheet.value > 0.5;
    _settleSheet(open: open, velocity: up);
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
    final managed = managedByAgent(sessions);
    final human = humanSessions(sessions);
    final working = rows.working.length;
    final bottom = MediaQuery.paddingOf(context).bottom;
    final statusDot = working > 0
        ? AppColors.ok
        : (asks.isNotEmpty ? askAmber : AppColors.ok);
    final statusText = working > 0
        ? '$working working'
        : (asks.isNotEmpty ? '${asks.length} waiting' : 'All quiet');

    // Composer sits at bottom (52 pill + 18 bottom padding + safe area).
    final composerClearance = 82.0 + bottom;

    return Stack(clipBehavior: Clip.none, children: [
      // 1. Resting home canvas over Silk: either the single centred ask or pure
      // resting Silk, with vertical drag-up opening the Everyone sheet.
      Positioned.fill(
        child: GestureDetector(
          behavior: HitTestBehavior.translucent,
          onVerticalDragUpdate:
              _searching || _everyoneOpen ? null : (d) => _dragSheet(d.delta.dy),
          onVerticalDragEnd: _searching || _everyoneOpen
              ? null
              : (d) => _releaseSheet(d.primaryVelocity ?? 0),
          child: Padding(
            padding: EdgeInsets.only(
              top: 96,
              bottom: composerClearance + 48,
              left: kHomeMargin,
              right: kHomeMargin,
            ),
            child: _centerStage(asks, names, rows, managed, human),
          ),
        ),
      ),

      // 2. Bottom scrim so content softens before meeting the composer.
      Positioned(
        left: 0,
        right: 0,
        bottom: 0,
        height: 112 + bottom,
        child: IgnorePointer(
          child: DecoratedBox(
            key: const ValueKey('home-scrim'),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  AppColors.bg.withValues(alpha: 0),
                  AppColors.bg.withValues(alpha: 0.92),
                  AppColors.bg,
                ],
                stops: const [0, 0.72, 1],
              ),
            ),
          ),
        ),
      ),

      // 3. "Everyone" pull-up handle sitting 4 pt above the composer.
      if (!_searching && !_everyoneOpen)
        Positioned(
          left: 0,
          right: 0,
          bottom: composerClearance + 4,
          child: Center(child: _everyoneHandle()),
        ),

      // 4. Bare top bar (no glass band; Silk runs to the top).
      if (!_searching)
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: Padding(
            key: const ValueKey('home-stage-bar'),
            padding: const EdgeInsets.fromLTRB(
                kHomeMargin - 2, 8, kHomeMargin - 2, 0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _round('search', 'Search', _openSearch),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text('Snippet',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(17,
                                weight: FontWeight.w600, color: AppColors.fg1)),
                        const SizedBox(height: 3),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Container(
                              width: 6,
                              height: 6,
                              decoration: BoxDecoration(
                                color: statusDot,
                                shape: BoxShape.circle,
                              ),
                            ),
                            const SizedBox(width: 6),
                            Text(statusText,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: sans(13, color: AppColors.fg2)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
                _round('settings', 'Settings', widget.onSettings),
              ],
            ),
          ),
        ),

      // 5. Pull-up "Everyone" sheet over dimmed home (composer stays above it).
      if (_sheetShown && !_searching)
        Positioned.fill(
          child: EveryoneSheet(
            key: const ValueKey('everyone-sheet'),
            rows: rows,
            managed: managed,
            mainSessions: human.main,
            settledSessions: human.settled,
            asleepOpen: _asleepOpen,
            settledOpen: _settledOpenFor(human.main.isEmpty),
            onToggleAsleep: () => setState(() => _asleepOpen = !_asleepOpen),
            onToggleSettled: () => setState(() => _settledUser =
                !_settledOpenFor(human.main.isEmpty)),
            onOpenAgent: widget.onOpenAgent,
            onOpenManaged: _openManaged,
            onOpenSession: widget.onOpenSession,
            onSessionActions: widget.onSessionActions,
            onClose: _closeEveryone,
            onRefresh: widget.onRefresh,
            progress: _sheet,
            onDrag: _dragSheet,
            onRelease: _releaseSheet,
          ),
        ),

      // 6. Search overlay (pinned frosted pill bar + live filtered results).
      if (_searching)
        Positioned.fill(
          child: _searchOverlay(rows, managed, human, bottom),
        ),

      // 7. Shared composer (always on top, including over the Everyone sheet).
      if (!_searching)
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
            onOpenChat: widget.onOpenMissionControl,
            openOnFocus: true,
          ),
        ),
    ]);
  }

  Widget _centerStage(
    List<AskItem> asks,
    Map<String, String> names,
    ({List<AgentRow> working, List<AgentRow> needs, List<AgentRow> asleep})
        rows,
    Map<String, List<SessionInfo>> managed,
    ({List<SessionInfo> main, List<SessionInfo> settled}) human) {
    if (asks.isNotEmpty) {
      return LayoutBuilder(
        builder: (context, box) => SingleChildScrollView(
          physics: const BouncingScrollPhysics(),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: box.maxHeight),
            child: Center(
              child: OneThingAsk(
                items: asks,
                names: names,
                onOpen: (i) => widget.onOpenSession(i.session),
                onDecide: widget.onDecide == null
                    ? null
                    : (i, ok) => widget.onDecide!(i.session, ok),
              ),
            ),
          ),
        ),
      );
    }
    if (widget.loading && widget.sessions.isEmpty && widget.agents.isEmpty) {
      return const Center(child: DelayedSpinner(size: 20));
    }
    final err = widget.error;
    if (err != null && widget.sessions.isEmpty && widget.agents.isEmpty) {
      return Center(
        child: EmptyState(
          icon: 'wifi-off',
          title: "Couldn't load",
          body: err,
          action: Btn('Retry', small: true, onTap: widget.onRefresh ?? () {}),
        ),
      );
    }
    return HomeResting(
      working: rows.working,
      sessions: widget.sessions,
      managed: managed,
      asleepCount: rows.asleep.length,
      settledCount: human.settled.length,
      onOpenSession: widget.onOpenSession,
      onOpenAgent: widget.onOpenAgent,
      onOpenManaged: _openManaged,
      onOpenEveryone: _openEveryone,
    );
  }

  Widget _everyoneHandle() => Semantics(
        button: true,
        label: 'Everyone, open sheet',
        child: ExcludeSemantics(
          child: GestureDetector(
            key: const ValueKey('everyone-handle'),
            behavior: HitTestBehavior.opaque,
            onTap: () {
              tapHaptic();
              _openEveryone();
            },
            onVerticalDragUpdate: (d) => _dragSheet(d.delta.dy),
            onVerticalDragEnd: (d) => _releaseSheet(d.primaryVelocity ?? 0),
            onVerticalDragCancel: () => _releaseSheet(0),
            child: SizedBox(
              width: 128,
              height: 44,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Container(
                    width: 36,
                    height: 5,
                    decoration: BoxDecoration(
                      color: AppColors.fg1.withValues(alpha: 0.34),
                      borderRadius: BorderRadius.circular(2.5),
                    ),
                  ),
                  const SizedBox(height: 5),
                  Text('Everyone',
                      style: sans(13,
                          weight: FontWeight.w500, color: AppColors.fg3)),
                ],
              ),
            ),
          ),
        ),
      );

  Widget _searchOverlay(
    ({List<AgentRow> working, List<AgentRow> needs, List<AgentRow> asleep})
        rows,
    Map<String, List<SessionInfo>> managed,
    ({List<SessionInfo> main, List<SessionInfo> settled}) human,
    double bottom,
  ) {
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
    final main = human.main.where(_matches).toList();
    final settled = human.settled.where(_matches).toList();
    final sessionCount = main.length + settled.length;
    final empty = agentCount == 0 && sessionCount == 0;

    return ColoredBox(
      color: AppColors.bg,
      child: Stack(children: [
        Positioned.fill(
          child: SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
                M.gutter, 70, M.gutter, 32 + bottom),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (agentCount > 0) ...[
                  HomeLabel('Agents', count: agentCount),
                  AgentsGroup(
                    rows: shown,
                    managed: managed,
                    asleepOpen: true,
                    onToggleAsleep: () {},
                    onOpenAgent: (a) {
                      _closeSearch();
                      widget.onOpenAgent(a);
                    },
                    onOpenManaged: (a) {
                      _closeSearch();
                      _openManaged(a);
                    },
                  ),
                ],
                if (sessionCount > 0) ...[
                  HomeLabel('Your sessions',
                      count: sessionCount, top: agentCount > 0 ? 18 : 0),
                  SessionsGroup(
                    main: main,
                    settled: settled,
                    settledOpen:
                        q.isNotEmpty || _settledOpenFor(main.isEmpty),
                    onToggleSettled: () => setState(
                        () => _settledUser = !_settledOpenFor(main.isEmpty)),
                    onOpen: (s) {
                      _closeSearch();
                      widget.onOpenSession(s);
                    },
                    onLongPress: widget.onSessionActions,
                  ),
                ],
                if (empty)
                  Padding(
                    padding: EdgeInsets.only(top: S.s40),
                    child: EmptyState(
                      icon: q.isEmpty ? 'chat' : 'search',
                      title: q.isEmpty ? 'No sessions yet' : 'Nothing matches',
                      body: q.isEmpty
                          ? 'Start one with the plus and it shows up here.'
                          : 'Try a title, project, branch or agent name.',
                    ),
                  ),
              ],
            ),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: _searchTopBar(),
        ),
      ]),
    );
  }

  Widget _searchTopBar() => GlassTopFrame(
        key: const ValueKey('home-search-bar'),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
              kHomeMargin, 8, kHomeMargin - 2, 4),
          child: Row(children: [
            Expanded(
              child: Container(
                height: 44,
                padding: EdgeInsets.only(
                    left: S.of(14),
                    right: _search.text.isNotEmpty ? S.s6 : S.of(14)),
                decoration: BoxDecoration(
                  color: AppColors.surface2.withValues(alpha: 0.92),
                  borderRadius: BorderRadius.circular(R.pill),
                ),
                child: Row(children: [
                  AppIcon('search', size: 16, color: AppColors.fg3),
                  SizedBox(width: S.of(10)),
                  Expanded(
                    child: TextField(
                      controller: _search,
                      focusNode: _searchFocus,
                      onChanged: (_) => setState(() {}),
                      textInputAction: TextInputAction.search,
                      textAlignVertical: TextAlignVertical.center,
                      style: sans(16, color: AppColors.fg1),
                      cursorColor: AppColors.accent,
                      decoration: InputDecoration(
                        isCollapsed: true,
                        border: InputBorder.none,
                        hintText: 'Search agents and sessions',
                        hintStyle: sans(16, color: AppColors.fg4),
                      ),
                    ),
                  ),
                  if (_search.text.isNotEmpty)
                    Tooltip(
                      message: 'Clear search',
                      child: Semantics(
                        button: true,
                        label: 'Clear search',
                        child: ExcludeSemantics(
                          child: TapDetector(
                            behavior: HitTestBehavior.opaque,
                            onTap: () {
                              _search.clear();
                              setState(() {});
                            },
                            child: SizedBox(
                              width: 32,
                              height: 32,
                              child: Center(
                                child: Container(
                                  width: 20,
                                  height: 20,
                                  decoration: BoxDecoration(
                                    color:
                                        AppColors.fg1.withValues(alpha: 0.12),
                                    shape: BoxShape.circle,
                                  ),
                                  alignment: Alignment.center,
                                  child: AppIcon('x',
                                      size: 11, color: AppColors.fg2),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ]),
              ),
            ),
            SizedBox(width: S.s6),
            _round('x', 'Close search', _closeSearch),
          ]),
        ),
      );
}
