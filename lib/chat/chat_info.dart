import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../glass.dart';
import '../models.dart';
import '../mochi.dart';
import '../platform.dart';
import '../presence.dart';
import '../theme.dart';
import '../widgets.dart';
import '../screens/agent_appearance.dart' show showAgentAppearance;
import '../screens/agent_reach_panel.dart' show showAgentReachSettings;
import '../screens/agent_wake_panel.dart' show showAgentWakeSettings;
import '../screens/group_messaging.dart' show confirmDeleteGroup;
import 'agent_cluster.dart';
import '../screens/agent_profile_panel.dart'
    show AgentModelRows, showAgentProfileSettings;
import 'chat_style.dart';

/// Lets rows inside a docked [AgentInfoPanel] push a nested page instead of
/// opening a popover or sheet. Absent everywhere else, so the same rows keep
/// their old behaviour.
class DockedInfoNav extends InheritedWidget {
  const DockedInfoNav({
    super.key,
    required this.push,
    required this.pop,
    required super.child,
  });

  final void Function(String title, WidgetBuilder body) push;
  final VoidCallback pop;

  static DockedInfoNav? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DockedInfoNav>();

  @override
  bool updateShouldNotify(DockedInfoNav oldWidget) =>
      push != oldWidget.push || pop != oldWidget.pop;
}

/// iMessage-style contact/info screen for a direct agent chat.
///
/// On phones this is a full-height frosted route over the chat; on desktop the
/// panels dock at the right of the chat pane (340px) and [showAgentInfo] falls
/// back to a right-side dialog of the same width.
Future<void> showAgentInfo(
  BuildContext context, {
  required DaemonClient client,
  required String agentId,
  required String name,
  CoordinationAgent? agent,
  VoidCallback? onOpenTasks,
  VoidCallback? onOpenInbox,
  VoidCallback? onOpenBoard,
  VoidCallback? onOpenDesk,
  VoidCallback? onChanged,
}) {
  Widget panel(VoidCallback close) => AgentInfoPanel(
        client: client,
        agentId: agentId,
        name: name,
        agent: agent,
        onOpenTasks: onOpenTasks,
        onOpenInbox: onOpenInbox,
        onOpenBoard: onOpenBoard,
        onOpenDesk: onOpenDesk,
        onChanged: onChanged,
        onClose: close,
      );
  if (kMobile) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      _InfoSheetRoute(builder: (ctx) => _PhoneSheet(
          child: panel(() => Navigator.of(ctx, rootNavigator: true).pop()))),
    );
  }
  return _showDesktopInfo(context, panel);
}

/// iMessage-style info screen for a group chat. Same presentation rules as
/// [showAgentInfo].
Future<void> showGroupInfo(
  BuildContext context, {
  required DaemonClient client,
  required GroupSummary group,
  VoidCallback? onOpenTasks,
  VoidCallback? onChanged,
}) {
  Widget panel(VoidCallback close) => GroupInfoPanel(
        client: client,
        group: group,
        onOpenTasks: onOpenTasks,
        onChanged: onChanged,
        onClose: close,
      );
  if (kMobile) {
    return Navigator.of(context, rootNavigator: true).push<void>(
      _InfoSheetRoute(builder: (ctx) => _PhoneSheet(
          child: panel(() => Navigator.of(ctx, rootNavigator: true).pop()))),
    );
  }
  return _showDesktopInfo(context, panel);
}

/// The agent info panel, for desktop docking (right of the chat pane, 340px)
/// or inside the phone sheet. [onClose] dismisses it.
class AgentInfoPanel extends StatefulWidget {
  const AgentInfoPanel({
    super.key,
    required this.client,
    required this.agentId,
    required this.name,
    this.agent,
    this.onOpenTasks,
    this.onOpenInbox,
    this.onOpenBoard,
    this.onOpenDesk,
    this.onOpenMemory,
    this.onChanged,
    this.onClose,
    this.docked = false,
  });

  final DaemonClient client;
  final String agentId;
  final String name;
  final CoordinationAgent? agent;
  final VoidCallback? onOpenTasks;
  final VoidCallback? onOpenInbox;
  final VoidCallback? onOpenBoard;
  final VoidCallback? onOpenDesk;
  final VoidCallback? onOpenMemory;
  final VoidCallback? onChanged;
  final VoidCallback? onClose;

  /// Docked in the desktop agent panel: actions open beside it, so they leave
  /// the panel up.
  final bool docked;

  @override
  State<AgentInfoPanel> createState() => _AgentInfoPanelState();
}

class _AgentInfoPanelState extends State<AgentInfoPanel> {
  final _navKey = GlobalKey<NavigatorState>();

  void _pushNested(String title, WidgetBuilder body) {
    _navKey.currentState?.push(_NestedPageRoute(title: title, builder: body));
  }

  void _popNested() => _navKey.currentState?.maybePop();

  void _close() {
    final close = widget.onClose;
    if (close != null) {
      close();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _editNickname(BuildContext ctx) async {
    final agent = widget.agent;
    if (agent == null) return;
    final nav = DockedInfoNav.maybeOf(ctx);
    if (nav != null) {
      nav.push(
          'Nickname',
          (_) => _NicknameEditor(
                client: widget.client,
                agent: agent,
                onChanged: widget.onChanged,
                onClose: nav.pop,
              ));
      return;
    }
    final next = await promptText(ctx,
        title: 'Nickname for ${widget.name}',
        initial: agent.nickname ?? '',
        hint: 'Leave empty to use the name');
    if (next == null || next == (agent.nickname ?? '') || !mounted) return;
    try {
      await widget.client
          .setAgentNickname(agent.id, next.isEmpty ? null : next);
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    }
  }

  Future<void> _deleteAgent(BuildContext ctx) async {
    final agent = widget.agent;
    if (agent == null) return;
    final name = agent.displayName.trim().isEmpty
        ? agent.id
        : agent.displayName.trim();
    final ok = await confirmAction(ctx,
        title: 'Delete $name?',
        body:
            'This removes the agent, its identity and its notes. Its past task history loses it too. This can\'t be undone.',
        confirmLabel: 'Delete agent');
    if (!ok || !mounted) return;
    try {
      await widget.client.deleteAgent(agent.id);
      if (!mounted) return;
      toast(context, 'Deleted $name');
      widget.onChanged?.call();
      _close();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    }
  }

  Widget _statusLine() {
    final fallback = widget.agent?.status ?? 'Active';
    return ListenableBuilder(
      listenable: widget.client.presence,
      builder: (_, __) {
        final p = widget.client.presence.presenceForAgentId(widget.agentId);
        final s = p != null ? PresenceStore.chatWord(p) : fallback;
        final text = s.isEmpty
            ? 'Active'
            : s[0].toUpperCase() + s.substring(1);
        return Text(text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: sans(13, color: AppColors.fg3));
      },
    );
  }

  Widget _infoTab(BuildContext context) {
    final agent = widget.agent;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (agent != null)
          _InfoCard(children: [
            AgentModelRows(
              client: widget.client,
              agent: agent,
              name: widget.name,
              onChanged: widget.onChanged,
            ),
          ]),
        if (agent != null)
          _InfoCard(children: [
            if (!agent.isMissionControl)
              _InfoRow(
                  label: 'Nickname',
                  icon: 'edit',
                  value: agent.nickname ?? '',
                  onTap: () => _editNickname(context)),
            if (widget.onOpenMemory != null)
              _InfoRow(
                  label: 'Memory',
                  icon: 'brain',
                  onTap: widget.onOpenMemory),
            _InfoRow(
                label: 'Appearance',
                icon: 'sparkles',
                onTap: () => showAgentAppearance(
                    context, widget.client, widget.agentId, widget.name)),
            if (!agent.isMissionControl)
              _InfoRow(
                  label: 'Wakes and reporting',
                  icon: 'calendar-clock',
                  onTap: () => showAgentWakeSettings(context,
                      client: widget.client,
                      owner: widget.agentId,
                      name: widget.name,
                      onChanged: widget.onChanged)),
            _InfoRow(
                label: 'How it reaches you',
                icon: 'bell',
                onTap: () => showAgentReachSettings(context,
                    client: widget.client,
                    agentId: widget.agentId,
                    name: widget.name)),
          ]),
        _InfoCard(children: [
          _CopyRow(label: 'Agent ID', value: widget.agentId),
        ]),
        if (widget.agentId != 'mission-control')
          _InfoCard(children: [
            _DangerRow(
                label: 'Delete agent', onTap: () => _deleteAgent(context)),
          ]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final agent = widget.agent;
    final actions = <_CircleAction>[
      if (widget.onOpenTasks != null)
        _CircleAction('task', 'Tasks', () {
          if (!widget.docked) _close();
          widget.onOpenTasks!();
        }),
      if (widget.onOpenInbox != null)
        _CircleAction('inbox', 'Inbox', () {
          if (!widget.docked) _close();
          widget.onOpenInbox!();
        }),
      if (widget.onOpenBoard != null)
        _CircleAction('kanban', 'Board', () {
          if (!widget.docked) _close();
          widget.onOpenBoard!();
        }),
      if (widget.onOpenDesk != null)
        _CircleAction('terminal', 'Desk', () {
          if (!widget.docked) _close();
          widget.onOpenDesk!();
        }),
    ];
    Widget info(BuildContext ctx) => _InfoFrame(
          onClose: widget.docked ? null : _close,
          edit: agent == null
              ? null
              : _EditPill(onTap: () => showAgentProfileSettings(
                    ctx,
                    client: widget.client,
                    agent: agent,
                    name: widget.name,
                    onChanged: widget.onChanged,
                  )),
          avatar: MochiDisc(id: widget.agentId, size: kMobile ? 88 : 64),
          name: widget.name,
          status: _statusLine(),
          actions: actions,
          tabs: const [],
          tab: 0,
          onTab: (_) {},
          body: _infoTab(ctx),
        );
    if (!widget.docked) return info(context);
    return DockedInfoNav(
      push: _pushNested,
      pop: _popNested,
      child: Navigator(
        key: _navKey,
        onGenerateRoute: (settings) => _NestedPageRoute(builder: info),
      ),
    );
  }
}

/// The group info panel. Same presentation rules as [AgentInfoPanel].
class GroupInfoPanel extends StatefulWidget {
  const GroupInfoPanel({
    super.key,
    required this.client,
    required this.group,
    this.onOpenTasks,
    this.onChanged,
    this.onClose,
  });

  final DaemonClient client;
  final GroupSummary group;
  final VoidCallback? onOpenTasks;
  final VoidCallback? onChanged;
  final VoidCallback? onClose;

  @override
  State<GroupInfoPanel> createState() => _GroupInfoPanelState();
}

class _GroupInfoPanelState extends State<GroupInfoPanel> {
  static const _tabs = ['Info', 'Members'];
  int _tab = 0;
  late GroupSummary _group = widget.group;
  List<CoordinationAgent> _agents = const [];
  Map<String, CoordinationAgent> _byId = const {};
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _loadAgents();
  }

  Future<void> _loadAgents() async {
    try {
      final all = await widget.client.coordinationAgents();
      if (!mounted) return;
      setState(() {
        _agents = all
            .where((a) => !a.isMissionControl && a.status != 'archived')
            .toList()
          ..sort((a, b) => a.displayName.compareTo(b.displayName));
        _byId = {for (final a in _agents) a.id: a};
      });
    } catch (_) {}
  }

  void _close() {
    final close = widget.onClose;
    if (close != null) {
      close();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _update(Future<GroupSummary> Function() call) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final g = await call();
      if (!mounted) return;
      setState(() => _group = g);
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  String _name(String id, String kind) {
    if (kind == 'human') return 'You';
    final a = _byId[id];
    if (a == null) return id;
    final n = a.displayName.trim();
    return n.isEmpty ? id : n;
  }

  String? _leadName() {
    final lead = _group.lead;
    if (lead == null || lead.isEmpty) return null;
    return _name(lead, 'agent');
  }

  Future<void> _rename() async {
    final text = await promptText(context,
        title: 'Rename group', initial: _group.title);
    if (text == null || !mounted) return;
    final title = text.trim();
    if (title.isEmpty || title == _group.title) return;
    await _update(() => widget.client.updateGroup(_group.id, title: title));
  }

  Future<void> _pickLead() async {
    final members = [
      for (final m in _group.members)
        if (m.isAgent) m,
    ];
    if (members.isEmpty) return;
    final picked = await showAppSheet<String>(
      context,
      title: 'Group lead',
      child: Builder(
        builder: (ctx) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final m in members)
              ListRow(
                title: _name(m.id, m.kind),
                leading: AgentMochi(m.id, size: 20),
                trailing: m.id == _group.lead
                    ? AppIcon('check', size: 14, color: AppColors.fg1)
                    : null,
                onTap: () => Navigator.pop(ctx, m.id),
              ),
          ],
        ),
      ),
    );
    if (picked == null || picked == _group.lead || !mounted) return;
    await _update(() => widget.client.updateGroup(_group.id, lead: picked));
  }

  List<CoordinationAgent> get _addable => [
        for (final a in _agents)
          if (!_group.agentIds.contains(a.id)) a,
      ];

  Future<void> _pickAdd() async {
    final addable = _addable;
    if (addable.isEmpty) {
      toast(context, 'Every agent is already in this group');
      return;
    }
    final picked = await showAppSheet<String>(
      context,
      title: 'Add member',
      child: Builder(
        builder: (ctx) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final a in addable)
              ListRow(
                title: a.displayName.trim().isEmpty ? a.id : a.displayName,
                subtitle: a.id,
                leading: AgentMochi(a.id, size: 20),
                onTap: () => Navigator.pop(ctx, a.id),
              ),
          ],
        ),
      ),
    );
    if (picked == null || !mounted) return;
    await _update(
        () => widget.client.updateGroup(_group.id, addMembers: [picked]));
  }

  Future<void> _deleteGroup() async {
    if (await confirmDeleteGroup(context, widget.client, _group)) {
      widget.onChanged?.call();
      _close();
    }
  }

  Widget _membersSection() => _InfoCard(children: [
        for (final m in _group.members) _memberRow(m),
        _InfoRow(
          label: 'Lead',
          icon: 'crown',
          value: _leadName() ?? 'None',
          onTap: _busy ? null : _pickLead,
        ),
        _InfoRow(
          label: 'Add member',
          icon: 'user-plus',
          accent: true,
          onTap: _busy ? null : _pickAdd,
        ),
      ]);

  Widget _memberRow(GroupMember m) {
    final lead = m.id == _group.lead;
    final role = m.isHuman ? 'You' : (lead ? 'Lead' : 'Member');
    return _LongPressRow(
      onLongPress: _busy || m.isHuman
          ? null
          : () => _update(() => widget.client
              .updateGroup(_group.id, removeMembers: [m.id])),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: S.s16, vertical: S.s4),
          child: Row(children: [
            if (m.isAgent)
              AgentMochi(m.id, size: 26)
            else
              AppIcon('user', size: 20, color: AppColors.fg3),
            const SizedBox(width: S.s12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(_name(m.id, m.kind),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(15, color: AppColors.fg1)),
                  Text(role,
                      style: sans(12,
                          color: lead ? AppColors.accent : AppColors.fg3)),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }

  Widget _infoTab() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _membersSection(),
        _InfoCard(children: [
          _DangerRow(label: 'Delete group', onTap: _deleteGroup),
        ]),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final title = _group.title.trim().isEmpty ? 'Group' : _group.title.trim();
    final actions = <_CircleAction>[
      if (widget.onOpenTasks != null)
        _CircleAction('task', 'Tasks', () {
          _close();
          widget.onOpenTasks!();
        }),
      _CircleAction('users', 'Add', _pickAdd),
    ];
    return _InfoFrame(
      onClose: _close,
      edit: _EditPill(onTap: _busy ? null : _rename),
      avatar: AgentCluster(ids: _group.agentIds, size: kMobile ? 88 : 64),
      name: title,
      status: Text('${_group.members.length} '
          '${_group.members.length == 1 ? 'member' : 'members'}',
          style: sans(13, color: AppColors.fg3)),
      actions: actions,
      tabs: _tabs,
      tab: _tab,
      onTab: (i) => setState(() => _tab = i),
      body: _tab == 1 ? _membersSection() : _infoTab(),
    );
  }
}

// ---------------------------------------------------------------------------
// Shared chrome
// ---------------------------------------------------------------------------

class _CircleAction {
  const _CircleAction(this.icon, this.label, this.onTap);
  final String icon;
  final String label;
  final VoidCallback onTap;
}

class _InfoFrame extends StatelessWidget {
  const _InfoFrame({
    required this.onClose,
    required this.avatar,
    required this.name,
    required this.status,
    required this.actions,
    required this.tabs,
    required this.tab,
    required this.onTab,
    required this.body,
    this.edit,
  });

  final VoidCallback? onClose;
  final Widget? edit;
  final Widget avatar;
  final String name;
  final Widget status;
  final List<_CircleAction> actions;
  final List<String> tabs;
  final int tab;
  final ValueChanged<int> onTab;
  final Widget body;

  @override
  Widget build(BuildContext context) {
    final reduced = reduceMotion(context);
    return Material(
      type: MaterialType.transparency,
      child: Column(children: [
      SizedBox(
        height: 52,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: S.s16),
          child: Row(children: [
            if (onClose != null)
              _GlassCircle(onTap: onClose!, icon: 'x', label: 'Close'),
            const Spacer(),
            if (edit != null) edit!,
          ]),
        ),
      ),
      Padding(
        padding: const EdgeInsets.fromLTRB(S.s16, S.s4, S.s16, 0),
        child: Column(children: [
          avatar,
          const SizedBox(height: S.s12),
          Text(name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: sans(kMobile ? 26 : 20,
                  weight: W.strong, color: AppColors.fg1)),
          const SizedBox(height: S.s4),
          status,
          if (actions.isNotEmpty) ...[
            const SizedBox(height: S.s16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final a in actions) ...[
                  Flexible(child: _ActionCircle(action: a)),
                  if (a != actions.last) const SizedBox(width: S.s12),
                ],
              ],
            ),
          ],
          const SizedBox(height: S.s20),
          if (tabs.length > 1) ...[
            _Segmented(labels: tabs, index: tab, onSelect: onTab),
            const SizedBox(height: S.s16),
          ],
        ]),
      ),
      Expanded(
        child: ListView(
          physics: kMobile
              ? const BouncingScrollPhysics()
              : const ClampingScrollPhysics(),
          padding: EdgeInsets.fromLTRB(
              S.s16, 0, S.s16, S.s24 + MediaQuery.paddingOf(context).bottom),
          children: [
            AnimatedSwitcher(
              duration:
                  reduced ? Motion.fast : const Duration(milliseconds: 180),
              switchInCurve: Motion.enter,
              switchOutCurve: Motion.exit,
              transitionBuilder: (child, anim) {
                final curved =
                    CurvedAnimation(parent: anim, curve: Motion.enter);
                if (reduced) {
                  return FadeTransition(opacity: curved, child: child);
                }
                return FadeTransition(
                  opacity: curved,
                  child: SlideTransition(
                    position: Tween(
                            begin: const Offset(0, 0.02), end: Offset.zero)
                        .animate(curved),
                    child: child,
                  ),
                );
              },
              child: KeyedSubtree(key: ValueKey(tab), child: body),
            ),
          ],
        ),
      ),
    ]),
    );
  }
}

class _GlassCircle extends StatelessWidget {
  const _GlassCircle({required this.onTap, required this.icon, this.label});

  final VoidCallback onTap;
  final String icon;
  final String? label;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Glass(
            child: SizedBox.square(
              dimension: 36,
              child: Center(
                  child: AppIcon(icon, size: 16, color: AppColors.fg1)),
            ),
          ),
        ),
      );
}

class _EditPill extends StatelessWidget {
  const _EditPill({required this.onTap});

  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Glass(
          radius: BorderRadius.circular(R.pill),
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: S.s12, vertical: S.s6),
            child: Text('Edit',
                style: sans(13, weight: W.label, color: AppColors.fg1)),
          ),
        ),
      );
}

class _ActionCircle extends StatelessWidget {
  const _ActionCircle({required this.action});

  final _CircleAction action;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: action.label,
        excludeSemantics: true,
        child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: action.onTap,
        child: SizedBox(
        width: kMobile ? 64 : 56,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Glass(
            child: SizedBox.square(
              dimension: kMobile ? 48 : 40,
              child: Center(
                  child: AppIcon(action.icon,
                      size: kMobile ? 20 : 17, color: AppColors.fg1)),
            ),
          ),
          const SizedBox(height: S.s6),
          Text(action.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(11, color: AppColors.fg3)),
        ]),
      )));
}

class _Segmented extends StatelessWidget {
  const _Segmented(
      {required this.labels, required this.index, required this.onSelect});

  final List<String> labels;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final reduced = reduceMotion(context);
    return Glass(
      radius: BorderRadius.circular(R.pill),
      child: Container(
        padding: const EdgeInsets.all(3),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < labels.length; i++)
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: i == index ? null : () => onSelect(i),
              child: AnimatedContainer(
                duration: reduced ? Duration.zero : Motion.fast,
                padding: const EdgeInsets.symmetric(
                    horizontal: S.s12, vertical: S.s6),
                decoration: BoxDecoration(
                  color: i == index
                      ? AppColors.fg1.withValues(alpha: 0.12)
                      : Colors.transparent,
                  borderRadius: BorderRadius.circular(R.pill),
                ),
                child: Text(labels[i],
                    style: sans(13,
                        weight: i == index ? W.label : W.body,
                        color: i == index ? AppColors.fg1 : AppColors.fg3)),
              ),
            ),
        ]),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Cards and rows
// ---------------------------------------------------------------------------

class _InfoCard extends StatelessWidget {
  const _InfoCard({required this.children});

  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: S.s12),
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surface2.withValues(alpha: 0.6),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < children.length; i++) ...[
              if (i > 0)
                const Divider(
                    height: 1, thickness: 1, indent: S.s16, endIndent: 0),
              children[i],
            ],
          ],
        ),
      );
}

class _InfoRow extends StatelessWidget {
  const _InfoRow({
    required this.label,
    this.value,
    this.onTap,
    this.trailing,
    this.icon,
    this.accent = false,
  });

  final String label;
  final String? value;
  final VoidCallback? onTap;
  final Widget? trailing;
  final String? icon;
  final bool accent;

  @override
  Widget build(BuildContext context) {
    final labelColor = accent ? AppColors.accent : AppColors.fg1;
    final hasValue = value != null && value!.isNotEmpty;
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: BoxConstraints(minHeight: kMobile ? 48 : 40),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: S.s16),
          child: Row(children: [
            if (icon != null) ...[
              AppIcon(icon!,
                  size: kMobile ? 18 : 16,
                  color: accent ? AppColors.accent : AppColors.fg3),
              const SizedBox(width: S.s12),
            ],
            Flexible(
              flex: hasValue ? 1 : 100,
              fit: hasValue ? FlexFit.loose : FlexFit.tight,
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(kMobile ? 15 : 13, color: labelColor)),
            ),
            if (hasValue)
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: S.s8),
                  child: Text(value!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.end,
                      style: sans(13, color: AppColors.fg3)),
                ),
              ),
            if (trailing != null) ...[
              const SizedBox(width: S.s4),
              trailing!,
            ],
            if (onTap != null && trailing == null)
              AppIcon('chevron-right', size: 14, color: AppColors.fg4),
          ]),
        ),
      ),
    );
  }
}

class _CopyRow extends StatelessWidget {
  const _CopyRow({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) => _InfoRow(
        label: label,
        icon: 'hash',
        onTap: () {
          Clipboard.setData(ClipboardData(text: value));
          toast(context, 'Copied');
        },
        trailing: Row(mainAxisSize: MainAxisSize.min, children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mono(12, color: AppColors.fg3)),
          ),
          const SizedBox(width: S.s4),
          AppIcon('copy', size: 13, color: AppColors.fg4),
        ]),
      );
}

class _DangerRow extends StatelessWidget {
  const _DangerRow({required this.label, required this.onTap});

  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: kMobile ? 48 : 40),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: S.s12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                AppIcon('trash', size: 16, color: AppColors.danger),
                const SizedBox(width: S.s8),
                Text(label,
                    style:
                        sans(kMobile ? 15 : 13,
                            weight: W.label, color: AppColors.danger)),
              ]),
            ),
          ),
        ),
      );
}

class _LongPressRow extends StatelessWidget {
  const _LongPressRow({required this.child, this.onLongPress});

  final Widget child;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) => GestureDetector(
        behavior: HitTestBehavior.opaque,
        onLongPress: onLongPress,
        child: child,
      );
}

// ---------------------------------------------------------------------------
// Docked nested pages
// ---------------------------------------------------------------------------

/// A page pushed inside the docked panel's own [Navigator]: 52px chrome with a
/// back circle and centred title, then a scrolling body. Paints nothing, so
/// the see-through panel background shows through.
class _NestedPage extends StatelessWidget {
  const _NestedPage({required this.title, required this.builder});

  final String title;
  final WidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final nav = DockedInfoNav.maybeOf(context);
    return Material(
      type: MaterialType.transparency,
      // The transparent colour is only hit absorption: empty areas must not
      // fall through to the info page underneath.
      child: Container(
        color: Colors.transparent,
        child: Column(children: [
          SizedBox(
            height: 52,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: S.s16),
              child: Stack(children: [
                Align(
                  alignment: Alignment.centerLeft,
                  child: _GlassCircle(
                    onTap: nav == null
                        ? () => Navigator.of(context).maybePop()
                        : nav.pop,
                    icon: 'chevron-left',
                    label: 'Back',
                  ),
                ),
                Center(
                  child: Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(15,
                          weight: W.label, color: AppColors.fg1)),
                ),
              ]),
            ),
          ),
          Expanded(
            child: SingleChildScrollView(
              padding:
                  const EdgeInsets.fromLTRB(S.s16, S.s4, S.s16, S.s24),
              child: builder(context),
            ),
          ),
        ]),
      ),
    );
  }
}

/// Slide-from-right route for [_NestedPage]; the first route (no title) is the
/// info page itself. Nothing is painted, so the panel stays see-through.
class _NestedPageRoute extends PageRoute<void> {
  _NestedPageRoute({this.title, required this.builder});

  final String? title;
  final WidgetBuilder builder;

  @override
  bool get opaque => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => Motion.base;

  @override
  Duration get reverseTransitionDuration => Motion.base;

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation) =>
      title == null
          ? builder(context)
          : _NestedPage(title: title!, builder: builder);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
        parent: animation,
        curve: Motion.enter,
        reverseCurve: Motion.exit);
    // The panel is see-through, so a covered page must fade or it shows under the new one.
    final covered = FadeTransition(
        opacity: ReverseAnimation(secondaryAnimation), child: child);
    if (reduceMotion(context)) {
      return FadeTransition(opacity: curved, child: covered);
    }
    return SlideTransition(
      position:
          Tween(begin: const Offset(1, 0), end: Offset.zero).animate(curved),
      child: covered,
    );
  }
}

/// The docked 'Nickname' page: same save as the old prompt, minus the dialog.
class _NicknameEditor extends StatefulWidget {
  const _NicknameEditor({
    required this.client,
    required this.agent,
    required this.onChanged,
    required this.onClose,
  });

  final DaemonClient client;
  final CoordinationAgent agent;
  final VoidCallback? onChanged;
  final VoidCallback onClose;

  @override
  State<_NicknameEditor> createState() => _NicknameEditorState();
}

class _NicknameEditorState extends State<_NicknameEditor> {
  late final TextEditingController _text =
      TextEditingController(text: widget.agent.nickname ?? '');
  bool _saving = false;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final next = _text.text.trim();
    if (next == (widget.agent.nickname ?? '')) return widget.onClose();
    setState(() => _saving = true);
    try {
      await widget.client
          .setAgentNickname(widget.agent.id, next.isEmpty ? null : next);
      if (!mounted) return;
      widget.onChanged?.call();
      widget.onClose();
    } catch (e) {
      if (!mounted) return;
      setState(() => _saving = false);
      toast(context, '$e', danger: true);
    }
  }

  @override
  Widget build(BuildContext context) => Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          TextField(
            controller: _text,
            autofocus: true,
            style: TS.body(AppColors.fg1),
            onSubmitted: (_) => _save(),
            decoration: InputDecoration(
              hintText: 'Leave empty to use the name',
              hintStyle: TS.body(AppColors.fg4),
              isDense: true,
              filled: true,
              fillColor: AppColors.surface2,
              border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(R.sm),
                  borderSide: BorderSide(color: AppColors.border)),
              enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(R.sm),
                  borderSide: BorderSide(color: AppColors.border)),
            ),
          ),
          const SizedBox(height: S.s12),
          Align(
            alignment: Alignment.centerRight,
            child: Btn('Save', small: true, disabled: _saving, onTap: _save),
          ),
        ],
      );
}

// ---------------------------------------------------------------------------
// Phone sheet route and desktop dialog
// ---------------------------------------------------------------------------

/// A non-opaque full-height route: the chat stays visible under a 30px blur
/// and a dark tint, and the sheet slides up on [sheetMotion].
class _InfoSheetRoute extends PageRoute<void> {
  _InfoSheetRoute({required this.builder});

  final WidgetBuilder builder;

  @override
  bool get opaque => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration =>
      sheetMotion.duration ?? const Duration(milliseconds: 320);

  @override
  Duration get reverseTransitionDuration =>
      sheetMotion.reverseDuration ?? const Duration(milliseconds: 220);

  @override
  Widget buildPage(
          BuildContext context,
          Animation<double> animation,
          Animation<double> secondaryAnimation) =>
      builder(context);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    final curved = CurvedAnimation(
        parent: animation,
        curve: sheetMotion.curve ?? Curves.easeOutCubic,
        reverseCurve: sheetMotion.reverseCurve ?? Curves.easeOutCubic.flipped);
    if (reduceMotion(context)) {
      return FadeTransition(opacity: curved, child: child);
    }
    return SlideTransition(
      position:
          Tween(begin: const Offset(0, 1), end: Offset.zero).animate(curved),
      child: child,
    );
  }
}

/// Frosted chat backdrop plus drag-down dismissal for the phone sheet.
class _PhoneSheet extends StatefulWidget {
  const _PhoneSheet({required this.child});

  final Widget child;

  @override
  State<_PhoneSheet> createState() => _PhoneSheetState();
}

class _PhoneSheetState extends State<_PhoneSheet>
    with SingleTickerProviderStateMixin {
  late final AnimationController _settle =
      AnimationController(vsync: this, duration: Motion.base);
  Animation<double>? _settleAnim;
  double _drag = 0;
  bool _dragging = false;

  @override
  void initState() {
    super.initState();
    _settle.addStatusListener((s) {
      if (s == AnimationStatus.completed && mounted) {
        setState(() {
          _settleAnim = null;
          _drag = 0;
        });
      }
    });
  }

  @override
  void dispose() {
    _settle.dispose();
    super.dispose();
  }

  void _settleBack() {
    if (_drag <= 0) return;
    final from = _drag;
    _settleAnim = Tween(begin: from, end: 0.0)
        .animate(CurvedAnimation(parent: _settle, curve: Motion.exit));
    _settle.forward(from: 0);
  }

  void _dragUpdate(double dy) {
    if (_settle.isAnimating) _settle.stop();
    setState(() {
      _settleAnim = null;
      _dragging = true;
      _drag = (_drag + dy).clamp(0.0, 400.0);
    });
  }

  void _dragEnd(double velocity) {
    setState(() => _dragging = false);
    if (_drag > 96 || velocity > 650) {
      Navigator.of(context).maybePop();
      return;
    }
    _settleBack();
  }

  bool _onScroll(ScrollNotification n) {
    if (n is OverscrollNotification) {
      // Pulling down past the top edge drags the sheet with the finger.
      final pull = -n.overscroll;
      if (pull > 0 && n.metrics.pixels <= 0) {
        _dragUpdate(pull);
        if (_drag > 120) Navigator.of(context).maybePop();
      }
    } else if (n is ScrollEndNotification && !_dragging && _drag > 0) {
      _settleBack();
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final offset = _dragging ? _drag : (_settleAnim?.value ?? 0.0);
    return Stack(children: [
      Positioned.fill(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 30, sigmaY: 30),
          child: Container(color: Colors.black.withValues(alpha: 0.3)),
        ),
      ),
      Positioned.fill(
        child: SafeArea(
          child: GestureDetector(
            behavior: HitTestBehavior.translucent,
            onVerticalDragStart: (_) => setState(() => _dragging = true),
            onVerticalDragUpdate: (d) => _dragUpdate(d.delta.dy),
            onVerticalDragEnd: (d) =>
                _dragEnd(d.primaryVelocity ?? 0),
            onVerticalDragCancel: () {
              setState(() => _dragging = false);
              _settleBack();
            },
            child: NotificationListener<ScrollNotification>(
              onNotification: _onScroll,
              child: Transform.translate(
                offset: Offset(0, offset),
                child: widget.child,
              ),
            ),
          ),
        ),
      ),
    ]);
  }
}

Future<void> _showDesktopInfo(
    BuildContext context, Widget Function(VoidCallback) panel) {
  return showGeneralDialog<void>(
    context: context,
    barrierDismissible: true,
    barrierColor: AppColors.scrim,
    transitionDuration: Motion.base,
    pageBuilder: (ctx, _, __) => Stack(children: [
      Positioned(
        top: 0,
        bottom: 0,
        right: 0,
        width: 340,
        child: _DesktopPanelSurface(
          child: panel(() => Navigator.of(ctx).pop()),
        ),
      ),
    ]),
    transitionBuilder: (_, animation, __, child) {
      final curved = CurvedAnimation(parent: animation, curve: Motion.enter);
      if (reduceMotion(context)) {
        return FadeTransition(opacity: curved, child: child);
      }
      return SlideTransition(
        position:
            Tween(begin: const Offset(0.35, 0), end: Offset.zero).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
    },
  );
}

/// Frosted surface2 right panel for desktop use.
class _DesktopPanelSurface extends StatelessWidget {
  const _DesktopPanelSurface({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28),
          child: Container(
            decoration: BoxDecoration(
              color: AppColors.surface2.withValues(alpha: 0.88),
              border: Border(left: BorderSide(color: AppColors.border)),
            ),
            child: Material(type: MaterialType.transparency, child: child),
          ),
        ),
      );
}
