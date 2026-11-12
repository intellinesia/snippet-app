import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../crew_status.dart';
import '../crew_widgets.dart' show showCrewAgentMenu;
import '../mochi.dart';
import '../models.dart';
import '../presence.dart';
import '../platform.dart';
import '../theme.dart';
import '../swr.dart';
import '../widgets.dart' show AppIcon;
import 'agent_card.dart' show agentPresenceRingColor;
import 'agents_sidebar_panel.dart' show showCreateAgentDialog;
import 'mission_control/mission_control_state.dart' show isDedicatedMcSession;
import 'shell_nav.dart' show sessionIsActive;

const double kAgentRailWidth = 52;
const double _tile = 34;
const double _slot = 42;

/// The rail shows on a wide desktop window; a phone or a narrow window gets
/// the drawer, where Mission Control stays a row in the sidebar.
bool agentRailShown(BuildContext context) =>
    !kMobile && MediaQuery.sizeOf(context).width >= kShellCompact;

/// A narrow column at the far left of the desktop shell: Mission Control, then
/// one tile per agent, then a button to create one.
class AgentRail extends StatefulWidget {
  const AgentRail({
    super.key,
    required this.client,
    required this.sessions,
    required this.mcSelected,
    required this.selectedAgentId,
    required this.onOpenMissionControl,
    required this.onOpenAgent,
    this.topInset = 46,
    this.footer = const [],
  });

  final DaemonClient? client;
  final List<SessionInfo>? sessions;
  final bool mcSelected;
  final String? selectedAgentId;
  final VoidCallback onOpenMissionControl;
  final ValueChanged<CoordinationAgent> onOpenAgent;

  /// Clears the macOS traffic lights; the window controls float over the rail.
  final double topInset;

  /// Pinned under the agents, bottom-most last.
  final List<Widget> footer;

  @override
  State<AgentRail> createState() => _AgentRailState();
}

class _AgentRailState extends State<AgentRail> {
  List<CoordinationAgent> _agents = const [];
  Map<String, int> _unread = const {};
  DateTime? _loadedAt;
  Revalidator? _live;

  @override
  void initState() {
    super.initState();
    _load();
    _bindLive();
  }

  void _bindLive() {
    _live?.dispose();
    final client = widget.client;
    _live = client == null
        ? null
        : Revalidator(
            client: client,
            on: (e) => Swr.coordination(e) || Swr.sessionStatus(e),
            debounce: const Duration(seconds: 1),
            onRevalidate: ({required bool force}) => _load(force: true));
  }

  @override
  void didUpdateWidget(covariant AgentRail old) {
    super.didUpdateWidget(old);
    if (old.client != widget.client) {
      _bindLive();
      _load(force: true);
    } else if (old.selectedAgentId != widget.selectedAgentId) {
      _load();
    }
  }

  @override
  void dispose() {
    _live?.dispose();
    super.dispose();
  }

  Future<void> _load({bool force = false}) async {
    final client = widget.client;
    if (client == null) return;
    final now = DateTime.now();
    final at = _loadedAt;
    if (!force && at != null && now.difference(at).inSeconds < 10) return;
    _loadedAt = now;
    try {
      final agents = await client.coordinationAgents();
      if (!mounted) return;
      setState(() => _agents = agents
          .where((a) => a.status != 'archived' && !a.isMissionControl)
          .toList());
    } catch (_) {}
    try {
      final threads = await client.directThreads();
      if (!mounted) return;
      setState(() => _unread = {
            for (final t in threads)
              if (t.peerKind == 'agent' && t.unread > 0) t.peerId: t.unread,
          });
    } catch (_) {}
  }

  CrewState get _mcState {
    final mc = (widget.sessions ?? const <SessionInfo>[])
        .where((s) => isDedicatedMcSession(s.id))
        .firstOrNull;
    if (mc == null) return CrewState.standingBy;
    if (mc.status == 'waiting_for_input') return CrewState.needsYou;
    if (sessionIsActive(mc.status)) return CrewState.working;
    return CrewState.standingBy;
  }

  Future<void> _create(BuildContext ctx) async {
    final client = widget.client;
    if (client == null) return;
    await showCreateAgentDialog(context, client, anchorContext: ctx);
    _load(force: true);
  }

  @override
  Widget build(BuildContext context) {
    final presence = widget.client?.presence;
    if (presence == null) return _buildRail(context, null);
    return ListenableBuilder(
      listenable: presence,
      builder: (ctx, _) => _buildRail(ctx, presence),
    );
  }

  Widget _buildRail(BuildContext context, PresenceStore? presence) {
    Theme.of(context);
    final crew = deriveCrew(_agents, widget.sessions ?? const <SessionInfo>[],
        presence: presence);
    final client = widget.client;
    return Container(
      width: kAgentRailWidth,
      decoration: BoxDecoration(
        color: AppColors.windowBg,
        border: Border(
            right: BorderSide(color: AppColors.line.withValues(alpha: 0.65))),
      ),
      child: Column(children: [
        SizedBox(height: widget.topInset),
        _RailTile(
          selected: widget.mcSelected,
          state: _mcState,
          tooltip: 'Mission Control\nOrchestrator · ${_stateWord(_mcState)}',
          onTap: client == null ? null : widget.onOpenMissionControl,
          child: MochiIcon(color: AppColors.accent, size: 22),
        ),
        Container(
          width: 22,
          height: 1,
          margin: const EdgeInsets.symmetric(vertical: 4),
          color: AppColors.line,
        ),
        Expanded(
          child: ScrollConfiguration(
            behavior:
                ScrollConfiguration.of(context).copyWith(scrollbars: false),
            child: ListView(
              padding: const EdgeInsets.only(bottom: 8),
              children: [
                for (final e in crew)
                  _RailTile(
                    key: ValueKey('rail-agent-${e.agent.id}'),
                    selected: widget.selectedAgentId == e.agent.id,
                    state: e.state,
                    dotColor: _dotColor(e),
                    unread: _unread[e.agent.id] ?? 0,
                    tooltip: _agentTip(e),
                    onTap: () => widget.onOpenAgent(e.agent),
                    onMenu: client == null
                        ? null
                        : (ctx, point) => showCrewAgentMenu(ctx,
                            client: client,
                            agent: e.agent,
                            point: point,
                            onDeleted: () => _load(force: true)),
                    child: AgentMochi(e.agent.id, size: 20),
                  ),
                Builder(
                  builder: (ctx) => _RailTile(
                    key: const ValueKey('rail-new-agent'),
                    tooltip: 'New agent',
                    onTap: client == null ? null : () => _create(ctx),
                    dashed: true,
                    child:
                        AppIcon('plus', size: 16, color: AppColors.fg3),
                  ),
                ),
              ],
            ),
          ),
        ),
        if (widget.footer.isNotEmpty) ...[
          ...widget.footer,
          const SizedBox(height: 10),
        ],
      ]),
    );
  }
}

/// The tile's state dot: the live presence colour when there is one, else
/// the crew fallback (needs you amber, working green, idle none).
Color? _dotColor(CrewEntry e) {
  final p = e.presence;
  if (p != null && p.active) {
    return agentPresenceRingColor(
        p.state == 'tool' || p.state == 'running' ? 'working' : p.state);
  }
  return switch (e.state) {
    CrewState.needsYou => AppColors.run,
    CrewState.working => AppColors.ok,
    CrewState.standingBy => null,
  };
}

String _stateWord(CrewState s) => switch (s) {
      CrewState.needsYou => 'Needs you',
      CrewState.working => 'Working',
      CrewState.standingBy => 'Idle',
    };

String _agentTip(CrewEntry e) {
  final name = e.agent.displayName.trim().isEmpty
      ? e.agent.id
      : e.agent.displayName.trim();
  final line = e.presenceWord == null
      ? _stateWord(e.state)
      : [e.presenceWord!, if (e.presenceDetail != null) e.presenceDetail!]
          .join(' ');
  return '$name\n$line';
}

class _RailTile extends StatefulWidget {
  const _RailTile({
    super.key,
    required this.child,
    required this.tooltip,
    this.onTap,
    this.onMenu,
    this.selected = false,
    this.state = CrewState.standingBy,
    this.dotColor,
    this.unread = 0,
    this.dashed = false,
  });

  final Widget child;
  final String tooltip;
  final VoidCallback? onTap;
  final void Function(BuildContext, Offset)? onMenu;
  final bool selected;
  final CrewState state;

  /// Overrides the state-derived dot colour (presence wins).
  final Color? dotColor;
  final int unread;
  final bool dashed;

  @override
  State<_RailTile> createState() => _RailTileState();
}

class _RailTileState extends State<_RailTile> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final sel = widget.selected;
    final dot = widget.dotColor ??
        switch (widget.state) {
          CrewState.needsYou => AppColors.run,
          CrewState.working => AppColors.ok,
          CrewState.standingBy => null,
        };
    final bg = sel
        ? AppColors.surface3
        : _hover
            ? AppColors.surface2
            : widget.dashed
                ? Colors.transparent
                : AppColors.surface1;
    final count = widget.unread > 99 ? '99+' : '${widget.unread}';
    return Tooltip(
      message: widget.tooltip,
      waitDuration: const Duration(milliseconds: 120),
      showDuration: const Duration(seconds: 3),
      textAlign: TextAlign.left,
      positionDelegate: (c) => Offset(c.target.dx + c.targetSize.width / 2 + 6,
          c.target.dy - c.tooltipSize.height / 2),
      child: MouseRegion(
        cursor:
            widget.onTap == null ? MouseCursor.defer : SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          onSecondaryTapDown: widget.onMenu == null
              ? null
              : (d) => widget.onMenu!(context, d.globalPosition),
          child: SizedBox(
            height: _slot,
            child: Stack(alignment: Alignment.center, children: [
              Positioned(
                left: 0,
                child: AnimatedContainer(
                  duration: Motion.quick,
                  curve: Motion.exit,
                  width: 3,
                  height: sel ? 18 : (_hover ? 8 : 0),
                  decoration: BoxDecoration(
                    color: AppColors.fg3,
                    borderRadius: const BorderRadius.horizontal(
                        right: Radius.circular(3)),
                  ),
                ),
              ),
              SizedBox.square(
                dimension: _tile,
                child: Stack(clipBehavior: Clip.none, children: [
                  AnimatedContainer(
                    duration: Motion.quick,
                    curve: Motion.exit,
                    width: _tile,
                    height: _tile,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: bg,
                      borderRadius: BorderRadius.circular(sel ? 12 : 10),
                      border: Border.all(
                        color: sel
                            ? AppColors.lineStrong
                            : widget.dashed
                                ? AppColors.line
                                : Colors.transparent,
                        width: sel ? 1.5 : 1,
                      ),
                    ),
                    child: widget.child,
                  ),
                  if (dot != null)
                    Positioned(
                      right: -3,
                      bottom: -3,
                      child: Container(
                        width: 11,
                        height: 11,
                        decoration: BoxDecoration(
                          color: dot,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: AppColors.windowBg, width: 2),
                        ),
                      ),
                    ),
                  if (widget.unread > 0)
                    Positioned(
                      right: -6,
                      top: -4,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 16),
                        height: 16,
                        padding: const EdgeInsets.symmetric(horizontal: 4),
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          color: AppColors.fg2,
                          borderRadius: BorderRadius.circular(8),
                          border:
                              Border.all(color: AppColors.windowBg, width: 2),
                        ),
                        child: Text(count, style: TS.caption(AppColors.bg)),
                      ),
                    ),
                ]),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
