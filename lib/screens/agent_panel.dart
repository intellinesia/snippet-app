import 'agent_rail.dart';
import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../shell_panel.dart';
import '../theme.dart';
import '../widgets.dart';
import '../chat/chat_info.dart' show AgentInfoPanel, AgentPageButton;
import '../platform.dart';
import 'agent_appearance.dart';
import 'agent_profile_panel.dart';
import 'agent_reach_panel.dart';
import 'agent_records.dart';
import 'agent_wake_panel.dart';
import 'memory_screen.dart';
import 'pane_add_menu.dart' show PaneAddEntry, PanePill, showPaneAddMenu;
import 'shell_models.dart' show RightTab;
import '../tap_detector.dart';

/// The agent actions that open as right-panel tabs. `desk` opens a session tab
/// and `delete` a confirm.
const agentPanelPages = ['inbox', 'board', 'memory', 'wakes', 'reach', 'model'];

String _pageTitle(String action) => switch (action) {
      'inbox' => 'Inbox',
      'board' => 'Board',
      'memory' => 'Memory',
      'wakes' => 'Wakes',
      'reach' => 'How it reaches you',
      'model' => 'Models and context',
      'nickname' => 'Nickname',
      _ => 'Appearance',
    };

/// One agent action as a right-panel page. Each page loads the agent record
/// itself, so it is never stale when reopened.
ShellPanelRequest agentPanelRequest(
  String action, {
  required DaemonClient client,
  required String agentId,
  required String agentName,
}) =>
    ShellPanelRequest(
      purpose: ShellPanelPurpose.agent,
      id: '$agentId:$action',
      client: client,
      title: _pageTitle(action),
      builder: (_, close) => switch (action) {
        'inbox' => agentRecordsBody(client, agentId, agentName, board: false),
        'board' => agentRecordsBody(client, agentId, agentName, board: true),
        'memory' => MemoryScreen(
            client: client,
            embedded: true,
            onBack: close,
            hideBack: true,
            initialKey: 'agent:$agentId'),
        'wakes' => _WithAgent(
            client: client,
            agentId: agentId,
            builder: (a) => SingleChildScrollView(
                padding: EdgeInsets.all(S.s12),
                child: AgentWakePanel(
                    client: client, owner: agentId, name: agentName)),
          ),
        'reach' => SingleChildScrollView(
            padding: EdgeInsets.all(S.s12),
            child: AgentReachPanel(client: client, agentId: agentId)),
        'model' => _WithAgent(
            client: client,
            agentId: agentId,
            builder: (a) => SingleChildScrollView(
                padding: EdgeInsets.all(S.s12),
                child: AgentProfilePanel(
                    client: client, agent: a, name: agentName)),
          ),
        'nickname' => _WithAgent(
            client: client,
            agentId: agentId,
            builder: (a) =>
                _NicknamePage(client: client, agent: a, onDone: close),
          ),
        _ => SingleChildScrollView(
            padding: EdgeInsets.all(S.s8),
            child: Align(
              alignment: Alignment.topLeft,
              child: AgentAppearancePicker(
                  client: client, agentId: agentId, onDone: close),
            ),
          ),
      },
    );

class _WithAgent extends StatefulWidget {
  const _WithAgent(
      {required this.client, required this.agentId, required this.builder});
  final DaemonClient client;
  final String agentId;
  final Widget Function(CoordinationAgent agent) builder;

  @override
  State<_WithAgent> createState() => _WithAgentState();
}

class _WithAgentState extends State<_WithAgent> {
  CoordinationAgent? _agent;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    widget.client.coordinationAgents().then((all) {
      if (!mounted) return;
      final a = all.where((x) => x.id == widget.agentId).firstOrNull;
      setState(() {
        _agent = a;
        _failed = a == null;
      });
    }).catchError((_) {
      if (mounted) setState(() => _failed = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final a = _agent;
    if (a != null) return widget.builder(a);
    if (_failed) {
      return Center(
          child: Text("Couldn't load this agent", style: TS.ui(AppColors.fg3)));
    }
    return Center(child: DelayedSpinner(size: 16));
  }
}

class _NicknamePage extends StatefulWidget {
  const _NicknamePage(
      {required this.client, required this.agent, required this.onDone});
  final DaemonClient client;
  final CoordinationAgent agent;
  final VoidCallback onDone;

  @override
  State<_NicknamePage> createState() => _NicknamePageState();
}

class _NicknamePageState extends State<_NicknamePage> {
  late final _text = TextEditingController(text: widget.agent.nickname ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final next = _text.text.trim();
    if (next == (widget.agent.nickname ?? '')) return widget.onDone();
    setState(() => _saving = true);
    try {
      await widget.client
          .setAgentNickname(widget.agent.id, next.isEmpty ? null : next);
      if (mounted) widget.onDone();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      toast(context, '$e', danger: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final full = widget.agent.fullName.trim().isEmpty
        ? widget.agent.id
        : widget.agent.fullName.trim();
    final phone = kMobile;
    final fs = phone ? 15.0 : 13.0;
    final radius = BorderRadius.circular(R.of(phone ? 12 : 7));
    OutlineInputBorder edge(Color c) => OutlineInputBorder(
        borderRadius: radius, borderSide: BorderSide(color: c));
    return Padding(
      padding: phone
          ? EdgeInsets.fromLTRB(S.s16, S.s8, S.s16, S.s16)
          : EdgeInsets.fromLTRB(S.s12, S.of(10), S.s12, S.s12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(S.s4, 0, S.s4, S.s6),
            child: Text('Nickname', style: sans(12, color: AppColors.fg3)),
          ),
          TextField(
            controller: _text,
            autofocus: true,
            style: sans(fs, color: AppColors.fg1),
            cursorColor: AppColors.accent,
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              hintText: full,
              hintStyle: sans(fs, color: AppColors.fg4),
              isDense: true,
              filled: true,
              fillColor: AppColors.surface1,
              contentPadding: EdgeInsets.symmetric(
                  horizontal: phone ? S.of(14) : S.of(10),
                  vertical: phone ? S.of(13) : S.s8),
              border: edge(AppColors.lineStrong),
              enabledBorder: edge(AppColors.lineStrong),
              focusedBorder: edge(AppColors.accent),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(S.s4, S.s6, S.s4, 0),
            child: Text('What it is called here. Leave empty to use $full.',
                style: sans(12, color: AppColors.fg3)),
          ),
          SizedBox(height: S.s16),
          Align(
            alignment: Alignment.centerRight,
            child: AgentPageButton('Save',
                primary: true, expand: phone, onTap: _saving ? null : _save),
          ),
        ],
      ),
    );
  }
}

/// The desktop right panel of an agent tab: the iMessage-style info page, then
/// one closable tab per page opened from it ([readouts], scoped to this tab).
class AgentSidePanel extends StatelessWidget {
  const AgentSidePanel({
    super.key,
    required this.client,
    this.agent,
    this.onHide,
    required this.agentId,
    required this.agentName,
    required this.onAction,
    this.readouts = const [],
    this.activeReadout,
    this.readoutBody,
    this.onSelectReadout,
    this.onCloseReadout,
    this.onClearReadout,
    this.contextUsed = 0,
    this.contextWindow = 0,
    this.onCompact,
    this.onAutonomy,
    this.onScheduled,
    this.sessionId,
    this.onModel,
    this.railSessions,
    this.onOpenSession,
    this.onAllSessions,
  });

  /// Sessions this agent owns; when given, the rail replaces the About page.
  final List<SessionInfo>? railSessions;
  final void Function(SessionInfo s)? onOpenSession;
  final VoidCallback? onAllSessions;

  /// Lead's session, for its model and cold-resume rows.
  final String? sessionId;
  final VoidCallback? onModel;
  final int contextUsed;
  final int contextWindow;
  final VoidCallback? onCompact;
  final VoidCallback? onAutonomy;
  final VoidCallback? onScheduled;
  final DaemonClient client;
  final CoordinationAgent? agent;
  final VoidCallback? onHide;
  final String agentId;
  final String agentName;
  final ValueChanged<String> onAction;
  final List<RightTab> readouts;
  final String? activeReadout;
  final Widget Function(RightTab readout)? readoutBody;
  final ValueChanged<RightTab>? onSelectReadout;
  final ValueChanged<RightTab>? onCloseReadout;
  final VoidCallback? onClearReadout;

  RightTab? get _reading =>
      readouts.where((r) => r.key == activeReadout).firstOrNull;

  Widget _seg(String text, bool on, VoidCallback onTap,
      {VoidCallback? onClose}) {
    return Padding(
      padding: EdgeInsets.only(right: S.s2),
      child: Material(
        color: on ? AppColors.tint2 : Colors.transparent,
        borderRadius: BorderRadius.circular(R.sm),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.sm),
          onTap: onTap,
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                S.of(10), 0, onClose != null ? S.s6 : S.of(10), 0),
            child: SizedBox(
              height: 28,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Text(text, style: TS.ui(on ? AppColors.fg1 : AppColors.fg3)),
                if (onClose != null) ...[
                  SizedBox(width: S.of(5)),
                  Tooltip(
                    message: 'Close tab',
                    child: TapDetector(
                      onTap: onClose,
                      behavior: HitTestBehavior.opaque,
                      child: Padding(
                        padding: EdgeInsets.all(S.s2),
                        child: AppIcon('x', size: 11, color: AppColors.fg3),
                      ),
                    ),
                  ),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }

  /// Desktop pane row: Overview, each opened page, + and hide.
  Widget _tabRow(BuildContext context, RightTab? reading) => Container(
        key: const ValueKey('agent-panel-tabs'),
        height: PaneRow.height,
        padding: const EdgeInsets.fromLTRB(10, 0, 10, 0),
        decoration: BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.paneLine))),
        child: Row(children: [
          // Expanded, not Flexible + Spacer: those split the free width.
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                PanePill(
                    icon: 'list',
                    label: 'Overview',
                    active: reading == null,
                    onTap: reading == null ? null : onClearReadout),
                for (final r in readouts) ...[
                  const SizedBox(width: 2),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 160),
                    child: PanePill(
                        icon: r.icon,
                        label: r.label,
                        active: r.key == reading?.key,
                        onTap: () => onSelectReadout?.call(r),
                        onClose: () => onCloseReadout?.call(r)),
                  ),
                ],
                const SizedBox(width: 2),
                Builder(
                  builder: (ctx) => IconBtn('plus',
                      size: 28,
                      iconSize: 14,
                      tooltip: 'Open a tab',
                      onTap: () => _addMenu(ctx)),
                ),
              ]),
            ),
          ),
          if (onHide != null)
            IconBtn('sidebar',
                size: 28, iconSize: 14, tooltip: 'Hide panel', onTap: onHide),
        ]),
      );

  void _addMenu(BuildContext ctx) {
    final lead = agentId == 'lead';
    PaneAddEntry e(String action, String icon, String label) => PaneAddEntry(
        icon: icon,
        label: label,
        checked: readouts.any((r) => r.label == label),
        onTap: () => onAction(action));
    showPaneAddMenu(
      ctx,
      title: agentName,
      views: [
        e('inbox', 'inbox', 'Inbox'),
        e('board', 'kanban', 'Board'),
        e('memory', 'book', 'Memory'),
        e('wakes', 'clock', 'Wakes'),
        if (!lead) e('reach', 'send', 'Reach'),
      ],
      crew: [
        if (!lead)
          PaneAddEntry(
              icon: 'layers', label: 'Desk work', onTap: () => onAction('desk')),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final reading = _reading;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!kMobile) _tabRow(context, reading),
        if (kMobile && readouts.isNotEmpty)
          Container(
            height: 46,
            padding: EdgeInsets.fromLTRB(S.of(10), 0, S.s8, 0),
            alignment: Alignment.centerLeft,
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(children: [
                _seg('Info', reading == null, () => onClearReadout?.call()),
                for (final r in readouts)
                  _seg(r.label, r.key == reading?.key,
                      () => onSelectReadout?.call(r),
                      onClose: () => onCloseReadout?.call(r)),
              ]),
            ),
          ),
        Expanded(
          child: reading != null && readoutBody != null
              ? readoutBody!(reading)
              : railSessions != null && onOpenSession != null
                  ? AgentRail(
                      key: ValueKey('agent-rail-$agentId'),
                      sessions: railSessions!,
                      onOpenSession: onOpenSession!,
                      onAllSessions: onAllSessions)
                  : AgentInfoPanel(
                      key: ValueKey('agent-info-$agentId'),
                      client: client,
                      agentId: agentId,
                      name: agentName,
                      agent: agent,
                      docked: true,
                      onOpenInbox: () => onAction('inbox'),
                      onOpenBoard: () => onAction('board'),
                      onOpenDesk: () => onAction('desk'),
                      onOpenMemory: () => onAction('memory'),
                      onClose: onHide,
                      contextUsed: contextUsed,
                      contextWindow: contextWindow,
                      onCompact: onCompact,
                      onAutonomy: onAutonomy,
                      onScheduled: onScheduled,
                      sessionId: sessionId,
                      onModel: onModel,
                    ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Desktop docked-panel primitives (round 17). Mockup pixels go through [pr] so
// The theme's radius scale still applies.
// ---------------------------------------------------------------------------

double pr(double px) => R.of(px / 0.6);

/// The page a docked panel lives in. Docked it is flat on the inset panel;
/// in a dialog it keeps the surface1 card.
class PanelCard extends StatelessWidget {
  const PanelCard({super.key, required this.child, this.flat = false});
  final Widget child;
  final bool flat;

  @override
  Widget build(BuildContext context) {
    if (flat) {
      return Align(
        alignment: Alignment.topCenter,
        child: Material(type: MaterialType.transparency, child: child),
      );
    }
    return Padding(
      padding: EdgeInsets.only(top: S.s12, right: S.s8, bottom: S.s12),
      child: Align(
        alignment: Alignment.topCenter,
        child: Material(
          color: AppColors.surface1,
          clipBehavior: Clip.antiAlias,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(pr(14)),
            side: BorderSide(color: AppColors.line),
          ),
          child: child,
        ),
      ),
    );
  }
}

/// The 40px bar: optional back, a title, then icon buttons on the right.
class PanelBar extends StatelessWidget {
  const PanelBar({
    super.key,
    required this.title,
    this.onBack,
    this.actions = const [],
  });
  final String title;
  final VoidCallback? onBack;
  final List<Widget> actions;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 40,
        child: Padding(
          padding: EdgeInsets.fromLTRB(S.s8, 0, S.s8, 0),
          child: Row(children: [
            if (onBack != null)
              PanelBarButton('chevron-left', 'Back', onBack)
            else
              SizedBox(width: S.s4),
            Expanded(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13, weight: W.strong, color: AppColors.fg1)),
            ),
            ...actions,
          ]),
        ),
      );
}

class PanelBarButton extends StatelessWidget {
  const PanelBarButton(this.icon, this.tooltip, this.onTap, {super.key});
  final String icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: tooltip,
        child: InkResponse(
          onTap: onTap,
          radius: 15,
          child: SizedBox(
            width: 28,
            height: 28,
            child: Center(child: AppIcon(icon, size: 15, color: AppColors.fg3)),
          ),
        ),
      );
}

/// Rows as separate 8 px cards on surface2, 6 px apart.
class PanelGroup extends StatelessWidget {
  const PanelGroup({super.key, required this.children, this.top = 0});
  final List<Widget> children;
  final double top;

  @override
  Widget build(BuildContext context) {
    final n = children.length;
    return Padding(
      padding: EdgeInsets.fromLTRB(S.s8, top, S.s8, S.s8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < n; i++) ...[
            if (i > 0) const SizedBox(height: 6),
            _HoverCard(child: children[i]),
          ],
        ],
      ),
    );
  }
}

/// A card that steps surface2 to surface3 on hover; the row inside paints
/// nothing of its own.
class _HoverCard extends StatefulWidget {
  const _HoverCard({required this.child});
  final Widget child;

  @override
  State<_HoverCard> createState() => _HoverCardState();
}

class _HoverCardState extends State<_HoverCard> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 150),
          curve: const Cubic(.23, 1, .32, 1),
          decoration: BoxDecoration(
            color: _hover ? AppColors.surface3 : AppColors.surface2,
            borderRadius: BorderRadius.circular(R.of(8)),
          ),
          clipBehavior: Clip.antiAlias,
          child: Material(type: MaterialType.transparency, child: widget.child),
        ),
      );
}

/// One row's content; the card comes from [PanelGroup].
class PanelRow extends StatelessWidget {
  const PanelRow({
    super.key,
    required this.label,
    this.sub,
    this.icon,
    this.leading,
    this.value,
    this.trailing,
    this.onTap,
    this.chevron = false,
    this.danger = false,
    this.minHeight = 44,
  });
  final String label;
  final String? sub;
  final String? icon;
  final Widget? leading;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool chevron;
  final bool danger;
  final double minHeight;

  @override
  Widget build(BuildContext context) {
    final tint = danger ? AppColors.danger : AppColors.fg2;
    final row = ConstrainedBox(
      constraints: BoxConstraints(minHeight: minHeight),
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Row(children: [
          if (leading != null) ...[leading!, SizedBox(width: S.of(10))],
          if (leading == null && icon != null) ...[
            Container(
              width: 28,
              height: 28,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.fg1.withValues(alpha: 0.07),
                borderRadius: BorderRadius.circular(R.of(6)),
              ),
              child: AppIcon(icon!, size: 15, color: tint),
            ),
            SizedBox(width: S.of(10)),
          ],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(13,
                        weight: FontWeight.w500,
                        color: danger ? AppColors.danger : AppColors.fg1)),
                if (sub != null && sub!.isNotEmpty)
                  Text(sub!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: sans(12, color: AppColors.fg3)),
              ],
            ),
          ),
          if (value != null && value!.isNotEmpty) ...[
            SizedBox(width: S.s8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(value!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12, color: AppColors.fg3, tabular: true)),
            ),
          ],
          if (trailing != null) ...[SizedBox(width: S.s8), trailing!],
          if (chevron) ...[
            SizedBox(width: S.s6),
            AppIcon('chevron-right', size: 14, color: AppColors.fg3),
          ],
        ]),
      ),
    );
    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      splashFactory: NoSplash.splashFactory,
      hoverColor: Colors.transparent,
      child: row,
    );
  }
}

class PanelRadio extends StatelessWidget {
  const PanelRadio({super.key, required this.on});
  final bool on;

  @override
  Widget build(BuildContext context) => Container(
        width: 16,
        height: 16,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          border: Border.all(
              color: on ? AppColors.fg1 : AppColors.lineStrong, width: 1.4),
        ),
        child: on
            ? Container(
                width: 8,
                height: 8,
                decoration:
                    BoxDecoration(color: AppColors.fg1, shape: BoxShape.circle),
              )
            : null,
      );
}

/// A small segmented control: one chosen cell on surface3.
class PanelSegments extends StatelessWidget {
  const PanelSegments({
    super.key,
    required this.labels,
    required this.index,
    required this.onSelect,
  });
  final List<String> labels;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.all(2),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(pr(8)),
          border: Border.all(color: AppColors.lineStrong),
        ),
        child: Row(children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              flex: 30 + labels[i].length * 10,
              child: TapDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => onSelect(i),
                child: Container(
                  height: 22,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: i == index ? AppColors.surface3 : null,
                    borderRadius: BorderRadius.circular(pr(6)),
                  ),
                  child: Text(labels[i],
                      maxLines: 1,
                      style: sans(12,
                          color: i == index ? AppColors.fg1 : AppColors.fg3)),
                ),
              ),
            ),
        ]),
      );
}

class PanelFootnote extends StatelessWidget {
  const PanelFootnote(this.text, {super.key, this.top = 0});
  final String text;
  final double top;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(S.of(18), top, S.of(18), S.s8),
        child:
            Text(text, style: sans(11.5, color: AppColors.fg4, height: 1.45)),
      );
}
