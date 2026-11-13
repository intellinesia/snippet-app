import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';

import '../api.dart';
import '../glass.dart';
import '../media_views.dart';
import '../models.dart';
import '../mochi.dart';
import '../platform.dart';
import '../presence.dart';
import '../swr.dart';
import '../theme.dart';
import '../widgets.dart';
import '../screens/agent_thread_cards.dart' show daemonRelativeUrl;
import '../screens/group_messaging.dart' show confirmDeleteGroup;
import 'agent_cluster.dart';
import '../screens/agent_profile_panel.dart'
    show AgentModelRows, showAgentProfileSettings;
import 'chat_style.dart';

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
    this.onChanged,
    this.onClose,
  });

  final DaemonClient client;
  final String agentId;
  final String name;
  final CoordinationAgent? agent;
  final VoidCallback? onOpenTasks;
  final VoidCallback? onOpenInbox;
  final VoidCallback? onOpenBoard;
  final VoidCallback? onOpenDesk;
  final VoidCallback? onChanged;
  final VoidCallback? onClose;

  @override
  State<AgentInfoPanel> createState() => _AgentInfoPanelState();
}

class _AgentInfoPanelState extends State<AgentInfoPanel> {
  static const _tabs = ['Info', 'Files', 'Links'];
  int _tab = 0;

  Future<List<CoordinationEvent>> _fetch() async =>
      (await widget.client.agentThreadPage(peerId: widget.agentId)).events;

  void _close() {
    final close = widget.onClose;
    if (close != null) {
      close();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  Future<void> _deleteAgent() async {
    final agent = widget.agent;
    if (agent == null) return;
    final name = agent.displayName.trim().isEmpty
        ? agent.id
        : agent.displayName.trim();
    final ok = await confirmAction(context,
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
        final s = p != null ? PresenceStore.word(p) : fallback;
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

  Widget _infoTab() {
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
        _InfoCard(children: [
          _CopyRow(label: 'Agent ID', value: widget.agentId),
        ]),
        _InfoCard(children: [
          _DangerRow(label: 'Delete agent', onTap: _deleteAgent),
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
          _close();
          widget.onOpenTasks!();
        }),
      if (widget.onOpenInbox != null)
        _CircleAction('inbox', 'Inbox', () {
          _close();
          widget.onOpenInbox!();
        }),
      if (widget.onOpenBoard != null)
        _CircleAction('kanban', 'Board', () {
          _close();
          widget.onOpenBoard!();
        }),
      if (widget.onOpenDesk != null)
        _CircleAction('terminal', 'Desk', () {
          _close();
          widget.onOpenDesk!();
        }),
    ];
    return _InfoFrame(
      onClose: _close,
      edit: agent == null
          ? null
          : _EditPill(onTap: () => showAgentProfileSettings(
                context,
                client: widget.client,
                agent: agent,
                name: widget.name,
                onChanged: widget.onChanged,
              )),
      avatar: MochiDisc(id: widget.agentId, size: 88),
      name: widget.name,
      status: _statusLine(),
      actions: actions,
      tabs: _tabs,
      tab: _tab,
      onTab: (i) => setState(() => _tab = i),
      body: _tab == 0
          ? _infoTab()
          : _ThreadTab(
              client: widget.client,
              cacheKey: 'chat-info-agent:${widget.agentId}',
              fetch: _fetch,
              links: _tab == 2,
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
  static const _tabs = ['Info', 'Members', 'Files', 'Links'];
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
      avatar: AgentCluster(ids: _group.agentIds, size: 88),
      name: title,
      status: Text('${_group.members.length} '
          '${_group.members.length == 1 ? 'member' : 'members'}',
          style: sans(13, color: AppColors.fg3)),
      actions: actions,
      tabs: _tabs,
      tab: _tab,
      onTab: (i) => setState(() => _tab = i),
      body: _tab == 1
          ? _membersSection()
          : _tab == 0
              ? _infoTab()
              : _ThreadTab(
                  client: widget.client,
                  cacheKey: 'chat-info-group:${_group.id}',
                  fetch: () => widget.client.groupEvents(_group.id),
                  links: _tab == 3,
                ),
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

  final VoidCallback onClose;
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
            _GlassCircle(onTap: onClose, icon: 'x', label: 'Close'),
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
              style: sans(26, weight: W.strong, color: AppColors.fg1)),
          const SizedBox(height: S.s4),
          status,
          if (actions.isNotEmpty) ...[
            const SizedBox(height: S.s16),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                for (final a in actions) ...[
                  _ActionCircle(action: a),
                  if (a != actions.last) const SizedBox(width: S.s20),
                ],
              ],
            ),
          ],
          const SizedBox(height: S.s20),
          _Segmented(labels: tabs, index: tab, onSelect: onTab),
          const SizedBox(height: S.s16),
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
        width: 64,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Glass(
            child: SizedBox.square(
              dimension: 48,
              child: Center(
                  child: AppIcon(action.icon,
                      size: 20, color: AppColors.fg1)),
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
    return InkWell(
      onTap: onTap,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 48),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: S.s16),
          child: Row(children: [
            if (icon != null) ...[
              AppIcon(icon!,
                  size: 18, color: accent ? AppColors.accent : AppColors.fg3),
              const SizedBox(width: S.s12),
            ],
            Expanded(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(15, color: labelColor)),
            ),
            if (value != null)
              Flexible(
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
          constraints: const BoxConstraints(minHeight: 48),
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: S.s12),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                AppIcon('trash', size: 16, color: AppColors.danger),
                const SizedBox(width: S.s8),
                Text(label,
                    style:
                        sans(15, weight: W.label, color: AppColors.danger)),
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
// Files and Links tabs
// ---------------------------------------------------------------------------

class _ThreadTab extends StatefulWidget {
  const _ThreadTab({
    required this.client,
    required this.cacheKey,
    required this.fetch,
    required this.links,
  });

  final DaemonClient client;
  final String cacheKey;
  final Future<List<CoordinationEvent>> Function() fetch;
  final bool links;

  @override
  State<_ThreadTab> createState() => _ThreadTabState();
}

class _ThreadTabState extends State<_ThreadTab> {
  late final Swr<List<CoordinationEvent>> _swr;

  @override
  void initState() {
    super.initState();
    _swr = Swr<List<CoordinationEvent>>(
      client: widget.client,
      key: widget.cacheKey,
      fetch: widget.fetch,
      revalidateOn: Swr.coordination,
      onChange: () {
        if (mounted) setState(() {});
      },
    );
  }

  @override
  void dispose() {
    _swr.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final events = _swr.data;
    if (events == null) {
      if (_swr.error != null) {
        return _TabMessage('Couldn\'t load the conversation');
      }
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: S.s40),
        child: Center(
            child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2))),
      );
    }
    return widget.links
        ? _LinksList(client: widget.client, events: events)
        : _FilesList(client: widget.client, events: events);
  }
}

class _TabMessage extends StatelessWidget {
  const _TabMessage(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(vertical: S.s32),
        child: Center(child: Text(text, style: TS.meta())),
      );
}

class _FileEntry {
  const _FileEntry({this.path, this.url, required this.kind, required this.label});

  final String? path;
  final String? url;
  final MediaKind kind;
  final String label;
}

List<_FileEntry> _fileEntries(List<CoordinationEvent> events) {
  final out = <_FileEntry>[];
  final seen = <String>{};
  void add(_FileEntry e) {
    final key = '${e.path}|${e.url}|${e.label}';
    if (seen.add(key)) out.add(e);
  }

  for (final e in events) {
    for (final a in parseSentAttachments(e.body)) {
      add(_FileEntry(path: a.path, kind: a.kind, label: baseName(a.path)));
    }
    final att = e.payload['attachment'];
    if (att is! Map) continue;
    final path = '${att['path'] ?? ''}'.trim();
    final url = '${att['url'] ?? ''}'.trim();
    if (path.isEmpty && url.isEmpty) continue;
    final kind = path.isNotEmpty
        ? mediaKindOf(path)
        : switch ('${att['kind'] ?? ''}') {
            'image' => MediaKind.image,
            'audio' => MediaKind.audio,
            'video' => MediaKind.video,
            _ => MediaKind.other,
          };
    add(_FileEntry(
      path: path.isEmpty ? null : path,
      url: url.isEmpty ? null : url,
      kind: kind,
      label: path.isNotEmpty ? baseName(path) : 'Attachment',
    ));
  }
  return out;
}

String _fileIcon(MediaKind kind) => switch (kind) {
      MediaKind.image => 'image',
      MediaKind.audio => 'file-audio',
      MediaKind.video => 'file-video',
      MediaKind.pdf => 'pdf',
      MediaKind.archive => 'file-archive',
      MediaKind.code => 'file-code',
      MediaKind.text => 'file-text',
      MediaKind.other => 'file',
    };

void _openFile(BuildContext context, DaemonClient client, _FileEntry f,
    List<String> gallery) {
  if (f.path != null) {
    openMedia(context, client, f.path!, gallery: gallery);
    return;
  }
  final url = f.url;
  if (url == null) return;
  final resolved = daemonRelativeUrl(client, url);
  if (resolved.isEmpty) return;
  launchUrl(Uri.parse(resolved), mode: LaunchMode.externalApplication);
}

class _FilesList extends StatelessWidget {
  const _FilesList({required this.client, required this.events});

  final DaemonClient client;
  final List<CoordinationEvent> events;

  @override
  Widget build(BuildContext context) {
    final files = _fileEntries(events);
    if (files.isEmpty) return const _TabMessage('No files in this conversation yet');
    final images = [
      for (final f in files)
        if (f.kind == MediaKind.image && f.path != null) f.path!,
    ];
    final others = [
      for (final f in files)
        if (!(f.kind == MediaKind.image && f.path != null)) f,
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (images.isNotEmpty)
          LayoutBuilder(builder: (_, c) {
            final w = (c.maxWidth - 12) / 3;
            return GridView.count(
              crossAxisCount: 3,
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              mainAxisSpacing: 6,
              crossAxisSpacing: 6,
              children: [
                for (final p in images)
                  ImageThumb(
                      client: client,
                      path: p,
                      width: w,
                      height: w,
                      gallery: images),
              ],
            );
          }),
        if (others.isNotEmpty)
          _InfoCard(children: [
            for (final f in others)
              _InfoRow(
                label: f.label,
                onTap: () => _openFile(context, client, f, images),
                trailing: AppIcon(_fileIcon(f.kind),
                    size: 16, color: AppColors.fg3),
              ),
          ]),
      ],
    );
  }
}

class _LinkEntry {
  const _LinkEntry(this.url, this.host);

  final String url;
  final String host;
}

final _urlRe = RegExp(r'''https?://[^\s<>"'()\[\]]+''');
final _urlTailRe = RegExp(r'''[.,;:!?)\]'"<>]+$''');

List<_LinkEntry> _linkEntries(List<CoordinationEvent> events) {
  final out = <_LinkEntry>[];
  final seen = <String>{};
  for (final e in events) {
    for (final m in _urlRe.allMatches(e.body)) {
      final url = m.group(0)!.replaceAll(_urlTailRe, '');
      if (url.isEmpty || !seen.add(url)) continue;
      final host = Uri.tryParse(url)?.host ?? url;
      out.add(_LinkEntry(url, host.isEmpty ? url : host));
    }
  }
  return out;
}

class _LinksList extends StatelessWidget {
  const _LinksList({required this.client, required this.events});

  final DaemonClient client;
  final List<CoordinationEvent> events;

  @override
  Widget build(BuildContext context) {
    final links = _linkEntries(events);
    if (links.isEmpty) return const _TabMessage('No links in this conversation yet');
    return _InfoCard(children: [
      for (final l in links)
        _InfoRow(
          label: l.url,
          onTap: () => openMarkdownLink(l.url, context),
          trailing: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(l.host,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12, color: AppColors.fg3)),
              AppIcon('external-link', size: 12, color: AppColors.fg4),
            ],
          ),
        ),
    ]);
  }
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
