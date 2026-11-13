import 'dart:async';

import '../chat/chat_info.dart' show GroupInfoPanel, showGroupInfo;
import '../motion_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../composer/composer_card.dart';
import '../message_reactions.dart';
import '../models.dart';
import '../mochi.dart';
import '../panel.dart';
import '../platform.dart';
import '../pull_refresh.dart';
import '../swr.dart';
import '../glass.dart' show TopFadeMask;
import '../theme.dart';
import '../widgets.dart';
import '../chat/agent_cluster.dart';
import '../chat/chat_style.dart';
import 'agent_card.dart' show agentRowTime;
import 'tasks/tasks_panel.dart' show openTasksPage, openTaskCountFor;

/// An `@token` in a group message: the boundary keeps `mail@fable` from
/// counting as a mention.
final RegExp _mentionToken =
    RegExp(r'(?:^|[\s(\[{])@([A-Za-z0-9][A-Za-z0-9_-]*)');

/// The `@id` tokens in [body] that name a member or `everyone`, in order.
List<String> extractGroupMentions(String body, Set<String> memberIds) {
  final out = <String>[];
  for (final m in _mentionToken.allMatches(body)) {
    final id = m.group(1)!;
    if ((memberIds.contains(id) || id == 'everyone') && !out.contains(id)) {
      out.add(id);
    }
  }
  return out;
}

/// The `@query` fragment ending at the cursor, for the completion list.
({int start, String query})? mentionQueryAt(String text, int cursor) {
  if (cursor <= 0 || cursor > text.length) return null;
  final before = text.substring(0, cursor);
  final at = before.lastIndexOf('@');
  if (at < 0) return null;
  if (at > 0 && !' \t\n([{'.contains(before[at - 1])) return null;
  final query = before.substring(at + 1);
  if (query.isNotEmpty && !RegExp(r'^[A-Za-z0-9_-]*$').hasMatch(query)) {
    return null;
  }
  return (start: at, query: query);
}

/// Text spans for a group message: `@member` and `@everyone` in accent.
List<TextSpan> groupMentionSpans(String text, Set<String> memberIds) {
  final spans = <TextSpan>[];
  var at = 0;
  for (final m in _mentionToken.allMatches(text)) {
    final id = m.group(1)!;
    if (!memberIds.contains(id) && id != 'everyone') continue;
    final tokenStart = m.end - id.length - 1;
    if (tokenStart > at) {
      spans.add(TextSpan(text: text.substring(at, tokenStart)));
    }
    spans.add(TextSpan(
      text: text.substring(tokenStart, m.end),
      style: TextStyle(color: AppColors.accent, fontWeight: W.label),
    ));
    at = m.end;
  }
  if (at < text.length) spans.add(TextSpan(text: text.substring(at)));
  return spans;
}

String groupMemberName(GroupMember m, Map<String, CoordinationAgent> agents) {
  if (m.isHuman) return 'You';
  final a = agents[m.id];
  if (a == null) return m.id;
  final name = a.displayName.trim();
  return name.isEmpty ? m.id : name;
}

/// Open a group thread, the same way openAgentThread opens a direct one.
void openGroupThread(
  BuildContext context, {
  required DaemonClient client,
  required GroupSummary group,
}) {
  if (kMobile) {
    Widget page(BuildContext _) => GroupThreadScreen(
          client: client,
          group: group,
          onClose: () => Navigator.pop(context),
        );
    Navigator.of(context).push<void>(AppPageRoute<void>(builder: page));
    return;
  }
  presentScreen(
    context,
    style: PanelStyle.drawer,
    purpose: ShellPanelPurpose.conversation,
    panelId: 'group:${group.id}',
    originClient: client,
    maxWidth: 720,
    maxHeight: 720,
    title: group.title.trim().isEmpty ? 'Group' : group.title.trim(),
    iconAgentIds: group.agentIds,
    sidePanel: (ctx, closeTab) => GroupInfoPanel(
      key: ValueKey('group-info-${group.id}'),
      client: client,
      group: group,
      docked: true,
      onOpenTasks: () =>
          openTasksPage(ctx, client, agentIds: group.agentIds.toSet()),
      onClose: closeTab,
    ),
    builder: (_, close) => GroupThreadScreen(
      client: client,
      group: group,
      onClose: close,
      showBack: false,
    ),
  );
}

/// Confirm, then delete the group. Returns whether it was deleted.
Future<bool> confirmDeleteGroup(
    BuildContext context, DaemonClient client, GroupSummary group) async {
  final name = group.title.trim().isEmpty ? 'this group' : group.title.trim();
  final ok = await confirmAction(context,
      title: 'Delete $name?',
      body: 'This removes the group chat and its messages for everyone in it. '
          'The agents stay. This can\'t be undone.',
      confirmLabel: 'Delete group');
  if (!ok || !context.mounted) return false;
  try {
    await client.deleteGroup(group.id);
    if (context.mounted) toast(context, 'Deleted $name');
    return true;
  } catch (e) {
    if (context.mounted) toast(context, '$e', danger: true);
    return false;
  }
}

/// Create a group chat, then open it. Returns the group, or null if cancelled.
Future<GroupSummary?> createAndOpenGroup(
    BuildContext context, DaemonClient client) async {
  final group = await showCreateGroupSheet(context, client: client);
  if (group == null || !context.mounted) return null;
  openGroupThread(context, client: client, group: group);
  return group;
}

class GroupRow extends StatelessWidget {
  const GroupRow(
      {super.key, required this.group, required this.onTap, this.onLongPress});

  final GroupSummary group;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final agents = group.agentIds;
    final name = group.title.trim().isEmpty ? 'Group' : group.title.trim();
    final members = group.members.length;
    final line = [
      '$members ${members == 1 ? 'member' : 'members'}',
      if (group.lead != null) 'lead ${group.lead}',
    ].join(' · ');
    final sub = group.preview ?? line;
    final shown = agents.take(4).toList();
    final extra = agents.length - shown.length;
    final unread = group.unread;
    if (kMobile) {
      final at = DateTime.tryParse(group.lastEventAt ?? '')?.toLocal();
      final time = agentRowTime(at);
      return Pressable(
        kind: PressKind.row,
        child: InkWell(
          splashFactory: NoSplash.splashFactory,
          highlightColor: Colors.transparent,
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(
            padding:
                const EdgeInsets.symmetric(horizontal: M.gutter, vertical: 8),
            child: Row(children: [
              SizedBox.square(
                dimension: 52,
                child: Stack(alignment: Alignment.center, children: [
                  if (unread > 0)
                    Container(
                      width: 52,
                      height: 52,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.accent, width: 2),
                      ),
                    ),
                  if (shown.isEmpty)
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: AppColors.surface2,
                        shape: BoxShape.circle,
                      ),
                      alignment: Alignment.center,
                      child: const AppIcon('users', size: 20),
                    )
                  else
                    AgentCluster(ids: agents, size: 48),
                ]),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(children: [
                      Expanded(
                        child: Text(name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TS.rowTitle(AppColors.fg1)),
                      ),
                      if (time.isNotEmpty) ...[
                        const SizedBox(width: 8),
                        Text(time, style: TS.meta()),
                      ],
                    ]),
                    const SizedBox(height: 2),
                    Text(sub,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(13,
                            color: unread > 0
                                ? AppColors.fg2
                                : AppColors.fg3)),
                  ],
                ),
              ),
            ]),
          ),
        ),
      );
    }
    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(8),
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(8, 7, 10, 7),
          child: Row(children: [
            SizedBox(
              width: 32,
              height: 32,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    decoration: BoxDecoration(
                        color: AppColors.surface2, shape: BoxShape.circle),
                    alignment: Alignment.center,
                    child: shown.isEmpty
                        ? const AppIcon('users', size: 15)
                        : AgentMochi(shown.first, size: 20),
                  ),
                  if (shown.length > 1 || extra > 0)
                    Positioned(
                      right: -4,
                      bottom: -4,
                      child: Container(
                        width: 16,
                        height: 16,
                        decoration: BoxDecoration(
                          color: AppColors.surface3,
                          shape: BoxShape.circle,
                          border:
                              Border.all(color: AppColors.windowBg, width: 1),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                            '${shown.length - 1 + (extra > 0 ? extra : 0)}',
                            style: sans(8, color: AppColors.fg2)),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(children: [
                    Expanded(
                      child: Text(name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              sans(13, weight: W.body, color: AppColors.fg1)),
                    ),
                    if (unread > 0) ...[
                      const SizedBox(width: 6),
                      Text('$unread',
                          style:
                              sans(11, color: AppColors.accent, tabular: true)),
                    ],
                  ]),
                  const SizedBox(height: 2),
                  Text(sub,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(11, color: AppColors.fg3)),
                ],
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Create a group: a title, the agents in it, and an optional lead.
Future<GroupSummary?> showCreateGroupSheet(
  BuildContext context, {
  required DaemonClient client,
}) =>
    showAppSheet<GroupSummary>(
      context,
      title: 'New group',
      maxWidth: 380,
      child: _CreateGroupSheet(client: client),
    );

class _CreateGroupSheet extends StatefulWidget {
  const _CreateGroupSheet({required this.client});

  final DaemonClient client;

  @override
  State<_CreateGroupSheet> createState() => _CreateGroupSheetState();
}

class _CreateGroupSheetState extends State<_CreateGroupSheet> {
  final _title = TextEditingController();
  List<CoordinationAgent> _agents = const [];
  final Set<String> _selected = {};
  String? _lead;
  bool _loading = true;
  bool _creating = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _title.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final all = await widget.client.coordinationAgents();
      if (!mounted) return;
      setState(() {
        _agents = all
            .where((a) => !a.isMissionControl && a.status != 'archived')
            .toList()
          ..sort((a, b) => a.displayName.compareTo(b.displayName));
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  String _name(CoordinationAgent a) {
    final n = a.displayName.trim();
    return n.isEmpty ? a.id : n;
  }

  Future<void> _create() async {
    final title = _title.text.trim();
    if (title.isEmpty || _selected.isEmpty || _creating) return;
    setState(() {
      _creating = true;
      _error = null;
    });
    try {
      final group = await widget.client.createGroup(
        title: title,
        members: _selected.toList(),
        lead: _lead,
      );
      if (mounted) Navigator.pop(context, group);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _creating = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final canCreate =
        _title.text.trim().isNotEmpty && _selected.isNotEmpty && !_creating;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        TextField(
          controller: _title,
          autofocus: true,
          cursorColor: AppColors.accent,
          onChanged: (_) => setState(() {}),
          style: TS.body(AppColors.fg1),
          decoration: ComposerCard.decoration('Group name'),
        ),
        const SizedBox(height: 14),
        if (_loading)
          const Padding(
            padding: EdgeInsets.symmetric(vertical: 20),
            child: Center(child: Spinner(size: 20)),
          )
        else if (_error != null && _agents.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Column(children: [
              Text(_error!, style: TS.meta(AppColors.danger)),
              const SizedBox(height: 8),
              Btn('Retry', small: true, onTap: _load),
            ]),
          )
        else if (_agents.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('No agents available.', style: TS.meta()),
          )
        else ...[
          Text('Agents', style: TS.label(AppColors.fg3)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in _agents)
                _AgentPickChip(
                  agent: a,
                  name: _name(a),
                  selected: _selected.contains(a.id),
                  onTap: () => setState(() {
                    if (!_selected.remove(a.id)) _selected.add(a.id);
                    if (_lead != null && !_selected.contains(_lead)) {
                      _lead = null;
                    }
                  }),
                ),
            ],
          ),
          if (_selected.length > 1) ...[
            const SizedBox(height: 14),
            Text('Lead', style: TS.label(AppColors.fg3)),
            const SizedBox(height: 6),
            DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: _lead,
                isExpanded: true,
                hint: Text('No lead', style: TS.body(AppColors.fg3)),
                items: [
                  for (final id in _selected)
                    DropdownMenuItem<String>(
                      value: id,
                      child: Text(
                        _agents
                                .where((a) => a.id == id)
                                .map(_name)
                                .firstOrNull ??
                            id,
                        style: TS.body(AppColors.fg1),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                ],
                onChanged: (v) => setState(() => _lead = v),
              ),
            ),
          ],
        ],
        const SizedBox(height: 16),
        if (_error != null && _agents.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(_error!, style: TS.meta(AppColors.danger)),
          ),
        Btn(_creating ? 'Creating…' : 'Create group',
            full: true, disabled: !canCreate, onTap: _create),
      ],
    );
  }
}

class _AgentPickChip extends StatelessWidget {
  const _AgentPickChip({
    required this.agent,
    required this.name,
    required this.selected,
    required this.onTap,
  });

  final CoordinationAgent agent;
  final String name;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: Motion.fast,
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: selected ? AppColors.accentFill : AppColors.surface2,
            borderRadius: BorderRadius.circular(16),
            border:
                Border.all(color: selected ? AppColors.accent : AppColors.line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AgentMochi(agent.id, size: 16),
            const SizedBox(width: 6),
            Text(name,
                style: sans(12,
                    weight: W.label,
                    color: selected ? AppColors.accentFg : AppColors.fg1)),
          ]),
        ),
      );
}

/// The members sheet: who is in the group, the lead, and add/remove.
class GroupMembersSheet extends StatefulWidget {
  const GroupMembersSheet({
    super.key,
    required this.client,
    required this.group,
    this.onChanged,
    this.onDeleted,
  });

  final DaemonClient client;
  final GroupSummary group;

  /// Called with the group as the daemon last returned it.
  final ValueChanged<GroupSummary>? onChanged;
  final VoidCallback? onDeleted;

  @override
  State<GroupMembersSheet> createState() => _GroupMembersSheetState();
}

class _GroupMembersSheetState extends State<GroupMembersSheet> {
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

  Future<void> _update(Future<GroupSummary> Function() call) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      final g = await call();
      if (!mounted) return;
      setState(() => _group = g);
      widget.onChanged?.call(g);
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

  List<CoordinationAgent> get _addable => [
        for (final a in _agents)
          if (!_group.agentIds.contains(a.id)) a,
      ];

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final m in _group.members)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 4),
            child: Row(children: [
              if (m.isAgent)
                AgentMochi(m.id, size: 22)
              else
                AppIcon('user', size: 18, color: AppColors.fg3),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(_name(m.id, m.kind),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TS.body(AppColors.fg1)),
                    if (m.id == _group.lead)
                      Text('Lead', style: TS.caption(AppColors.accent)),
                  ],
                ),
              ),
              if (m.isAgent && m.id != _group.lead)
                TextButton(
                  onPressed: _busy
                      ? null
                      : () => _update(() =>
                          widget.client.updateGroup(_group.id, lead: m.id)),
                  child: Text('Make lead', style: TS.label(AppColors.accent)),
                ),
              if (!m.isHuman)
                TextButton(
                  key: ValueKey('remove-${m.id}'),
                  onPressed: _busy
                      ? null
                      : () => _update(() => widget.client
                          .updateGroup(_group.id, removeMembers: [m.id])),
                  child: Text('Remove', style: TS.label(AppColors.danger)),
                ),
            ]),
          ),
        if (_addable.isNotEmpty) ...[
          const SizedBox(height: 10),
          Text('Add agents', style: TS.label(AppColors.fg3)),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: [
              for (final a in _addable)
                _AgentPickChip(
                  agent: a,
                  name: () {
                    final n = a.displayName.trim();
                    return n.isEmpty ? a.id : n;
                  }(),
                  selected: false,
                  onTap: _busy
                      ? () {}
                      : () => _update(() => widget.client
                          .updateGroup(_group.id, addMembers: [a.id])),
                ),
            ],
          ),
        ],
        const SizedBox(height: 16),
        Align(
          alignment: Alignment.centerLeft,
          child: TextAction('Delete group',
              icon: 'trash',
              danger: true,
              onTap: _busy
                  ? null
                  : () async {
                      if (await confirmDeleteGroup(
                          context, widget.client, _group)) {
                        widget.onDeleted?.call();
                      }
                    }),
        ),
      ],
    );
  }
}

/// A group conversation: agents and the local human, with `@` mentions.
/// Built on the same structure as AgentThreadScreen — a [Swr] feed
/// revalidated on coordination pushes, bubbles, pull to refresh — but the
/// roster, sender names and mentions are the group's own.
class GroupThreadScreen extends StatefulWidget {
  const GroupThreadScreen({
    super.key,
    required this.client,
    required this.group,
    this.onClose,
    this.embedded = false,
    this.showBack = true,
  });

  final DaemonClient client;
  final GroupSummary group;
  final VoidCallback? onClose;

  /// Nested under a host that already draws `NavBackRow`.
  final bool embedded;
  final bool showBack;

  @override
  State<GroupThreadScreen> createState() => _GroupThreadScreenState();
}

class _GroupThreadScreenState extends State<GroupThreadScreen> {
  void _closePage() {
    if (widget.onClose != null) {
      widget.onClose!();
    } else {
      Navigator.of(context).maybePop();
    }
  }

  late GroupSummary _group = widget.group;
  late final Swr<List<CoordinationEvent>> _thread;
  final _input = TextEditingController();
  final _inputFocus = FocusNode();
  final _scroll = ScrollController();
  List<CoordinationEvent> _events = const [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  /// Sent but not yet in a fetched list; merged back so a refetch can't hide.
  final List<CoordinationEvent> _pending = [];

  Map<String, CoordinationAgent> _agents = const {};

  /// The `@query` under the cursor, when the completion list should show.
  ({int start, String query})? _mention;

  @override
  void initState() {
    super.initState();
    _loadAgents();
    _thread = Swr<List<CoordinationEvent>>(
      client: widget.client,
      key: 'group-thread:${widget.group.id}',
      fetch: () => widget.client.groupEvents(widget.group.id),
      revalidateOn: Swr.coordination,
      onChange: _sync,
    );
    _events = _thread.data ?? const [];
    _loading = _thread.data == null;
    if (_events.isNotEmpty) _jumpToBottom();
    _input.addListener(_onInputChanged);
    _inputFocus.addListener(_onInputChanged);
  }

  @override
  void dispose() {
    _thread.dispose();
    _input.removeListener(_onInputChanged);
    _input.dispose();
    _inputFocus.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadAgents() async {
    try {
      final all = await widget.client.coordinationAgents();
      if (!mounted) return;
      setState(() => _agents = {for (final a in all) a.id: a});
    } catch (_) {}
    try {
      final n = await openTaskCountFor(widget.client, _groupAgentIds);
      if (mounted) setState(() => _openTaskCount = n);
    } catch (_) {}
  }

  int? _openTaskCount;

  Set<String> get _groupAgentIds => {
        for (final m in _group.members)
          if (m.isAgent) m.id,
      };

  /// Member agent ids plus `everyone`, for mentions and highlighting.
  Set<String> get _mentionIds => {
        for (final m in _group.members)
          if (m.isAgent) m.id,
        'everyone',
      };

  void _onInputChanged() {
    final sel = _input.selection;
    final next = sel.isValid && sel.isCollapsed
        ? mentionQueryAt(_input.text, sel.baseOffset)
        : null;
    if (next?.query != _mention?.query || next?.start != _mention?.start) {
      setState(() => _mention = next);
    }
  }

  List<({String id, String label, String? name})> get _mentionCandidates {
    final q = _mention?.query.toLowerCase() ?? '';
    final out = <({String id, String label, String? name})>[];
    void add(String id, String label, String? name) {
      if (q.isNotEmpty &&
          !id.toLowerCase().contains(q) &&
          !(name ?? '').toLowerCase().contains(q)) {
        return;
      }
      out.add((id: id, label: label, name: name));
    }

    for (final m in _group.members) {
      if (!m.isAgent) continue;
      final a = _agents[m.id];
      final display = a?.displayName.trim() ?? '';
      add(m.id, display.isEmpty ? m.id : display, m.id);
    }
    add('everyone', 'everyone', 'the whole group');
    return out.take(8).toList();
  }

  void _applyMention(String id) {
    final m = _mention;
    if (m == null) return;
    final text = _input.text;
    final cursor = _input.selection.baseOffset.clamp(0, text.length);
    final insert = '@$id ';
    final next = text.replaceRange(m.start, cursor, insert);
    _input.value = TextEditingValue(
      text: next,
      selection: TextSelection.collapsed(offset: m.start + insert.length),
    );
    setState(() => _mention = null);
    _inputFocus.requestFocus();
  }

  Future<void> _load({bool silent = false}) => _thread.refresh();

  void _sync() {
    if (!mounted) return;
    final next = _thread.data;
    if (next != null) {
      final ids = {for (final e in next) e.eventId};
      final keys = {for (final e in next) e.idempotencyKey};
      _pending.removeWhere(
          (p) => ids.contains(p.eventId) || keys.contains(p.idempotencyKey));
    }
    final merged = next == null ? null : [...next, ..._pending];
    final hadNew = merged != null && merged.length > _events.length;
    final first = _events.isEmpty;
    setState(() {
      if (merged != null) _events = merged;
      _loading = _thread.loading;
      _error =
          next == null && _thread.error != null ? '${_thread.error}' : null;
    });
    if (hadNew) _jumpToBottom(animated: !first);
  }

  void _jumpToBottom({bool animated = false}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scroll.hasClients) {
        if (animated) {
          _scroll.animateTo(
            _scroll.position.maxScrollExtent,
            duration: Motion.fast,
            curve: Motion.enter,
          );
        } else {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      }
    });
  }

  Future<void> _send() async {
    final body = _input.text.trim();
    if (body.isEmpty || _sending) return;
    setState(() => _sending = true);
    try {
      final mentions = extractGroupMentions(_input.text, _mentionIds);
      final ev = await widget.client.postGroup(
        widget.group.id,
        body: body,
        mentions: mentions.isEmpty ? null : mentions,
      );
      if (!mounted) return;
      _pending.add(ev);
      _input.clear();
      setState(() => _mention = null);
      _thread.refresh();
      _jumpToBottom();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  Future<void> _reloadGroup() async {
    final List<GroupSummary> all;
    try {
      all = await widget.client.groups();
    } catch (_) {
      return;
    }
    if (!mounted) return;
    final g = all.where((g) => g.id == _group.id).firstOrNull;
    if (g == null) {
      _closePage();
      return;
    }
    setState(() => _group = g);
  }

  String get _title =>
      _group.title.trim().isEmpty ? 'Group' : _group.title.trim();

  /// Names while they fit the header line, else the member count.
  String _memberLine(double width) {
    final n = _group.members.length;
    final fallback = '$n ${n == 1 ? 'member' : 'members'}';
    final names = [for (final id in _group.agentIds) _agentName(id)];
    if (names.isEmpty) return fallback;
    bool fits(String s) {
      final painter = TextPainter(
        text: TextSpan(
            text: s,
            style: sans(kMobile ? 12 : 11, color: ChatColors.meta)),
        maxLines: 1,
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: width);
      return painter.width <= width;
    }

    if (names.length <= 2) {
      final s = names.length == 1
          ? names.first
          : '${names[0]} and ${names[1]}';
      return fits(s) ? s : fallback;
    }
    final pair = '${names[0]}, ${names[1]} and ${names.length - 2} more';
    if (fits(pair)) return pair;
    final single = '${names.first} and ${names.length - 1} more';
    return fits(single) ? single : fallback;
  }

  Widget _statusLine() {
    final typing = _typingStatus();
    if (typing != null) return ChatHeader.statusText(typing);
    return LayoutBuilder(
        builder: (_, box) =>
            ChatHeader.statusText(_memberLine(box.maxWidth)));
  }

  String _agentName(String id) => groupMemberName(
      GroupMember.fromJson({'kind': 'agent', 'id': id}), _agents);

  String? _typingStatus() {
    final store = widget.client.presence;
    for (final id in _group.agentIds) {
      final p = store.presenceForAgentId(id);
      if (p != null && (p.state == 'typing' || p.state == 'thinking')) {
        return '${_agentName(id)} is typing';
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final hideChrome = widget.embedded;
    return Material(
      color: kMobile ? readingBg : Colors.transparent,
      child: SafeArea(
        top: !hideChrome,
        bottom: false,
        child: Column(
          children: [
            Expanded(
              child: Stack(
                children: [
                  Positioned.fill(
                      child: kMobile || hideChrome
                          ? _body(hideChrome: hideChrome)
                          : TopFadeMask(
                              clear: ChatHeader.overlap - 24,
                              child: _body(hideChrome: hideChrome))),
                  if (!hideChrome)
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: _header(),
                    ),
                ],
              ),
            ),
            _composer(),
          ],
        ),
      ),
    );
  }

  Widget _header() {
    final canPop = Navigator.maybeOf(context)?.canPop() ?? false;
    final canGoBack = kMobile
        ? (widget.onClose != null || canPop)
        : (!widget.embedded &&
            widget.showBack &&
            (widget.onClose != null || canPop));
    final tasksBtn = ChatGlassButton(
      icon: 'task',
      tooltip: 'Tasks',
      badge: (_openTaskCount ?? 0) > 0 ? _openTaskCount : null,
      onTap: () => openTasksPage(context, widget.client,
          agentIds: _groupAgentIds),
    );
    final docked = kMobile ? null : ShellRequestScope.maybeOf(context);
    final toggleSide = docked?.sidePanel != null ? docked?.toggleSide : null;
    // Docked in a shell tab, the group name toggles the info panel.
    final Widget? trailing = toggleSide != null
        ? null
        : !kMobile && !widget.embedded && widget.onClose != null
        ? Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              tasksBtn,
              const SizedBox(width: 6),
              ChatGlassButton(
                icon: 'x',
                tooltip: 'Close',
                onTap: widget.onClose!,
              ),
            ],
          )
        : tasksBtn;
    return ListenableBuilder(
      listenable: widget.client.presence,
      builder: (_, __) => ChatHeader(
        agentIds: _group.agentIds,
        title: _title,
        status: _statusLine(),
        onTitleTap: () {
          if (toggleSide != null) {
            toggleSide();
            return;
          }
          unawaited(showGroupInfo(
            context,
            client: widget.client,
            group: _group,
            onOpenTasks: () => openTasksPage(context, widget.client,
                agentIds: _groupAgentIds),
            onChanged: () => unawaited(_reloadGroup()),
          ));
        },
        titleHint: 'Members',
        onBack: canGoBack ? _closePage : null,
        trailing: trailing,
      ),
    );
  }

  static const _weekdays = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  static bool _sameDay(DateTime a, DateTime b) =>
      a.year == b.year && a.month == b.month && a.day == b.day;

  static DateTime? _eventTime(CoordinationEvent e) =>
      DateTime.tryParse(e.createdAt)?.toLocal();

  static (String, String) _dayTimeStamp(DateTime t) {
    final now = DateTime.now();
    final days = DateTime(now.year, now.month, now.day)
        .difference(DateTime(t.year, t.month, t.day))
        .inDays;
    final day = switch (days) {
      0 => 'Today',
      1 => 'Yesterday',
      > 1 && < 7 => _weekdays[t.weekday - 1],
      _ => t.year == now.year
          ? '${t.day} ${_months[t.month - 1]}'
          : '${t.day} ${_months[t.month - 1]} ${t.year}',
    };
    final hour = t.hour.toString().padLeft(2, '0');
    final minute = t.minute.toString().padLeft(2, '0');
    return (day, '$hour:$minute');
  }

  String? _systemText(CoordinationEvent e) {
    final body = e.body.trim();
    if (e.payload['auto'] == 'ack') return body.isEmpty ? null : body;
    final kind = e.payload['kind'];
    if (e.actorKind == 'system' ||
        kind == 'system' ||
        kind == 'handoff' ||
        kind == 'handoff_note' ||
        e.eventType == 'group.system' ||
        e.eventType == 'group.handoff' ||
        e.eventType.startsWith('system.')) {
      return body.isEmpty ? null : body;
    }
    if (e.eventType == 'task.lease_transferred') {
      if (body.isNotEmpty) return body;
      final from =
          _agentName(e.payload['from_agent_id']?.toString() ?? e.actorId);
      final toId = e.payload['to_agent_id']?.toString() ?? '';
      return toId.isEmpty
          ? '$from passed the turn'
          : '$from passed the turn to ${_agentName(toId)}';
    }
    return null;
  }

  String? _readByLine(CoordinationEvent e) {
    final ids = <String>[];
    final readBy = e.payload['read_by'];
    if (readBy is List) {
      for (final item in readBy) {
        final s = item?.toString().trim() ?? '';
        if (s.isNotEmpty && s != 'human' && s != 'local' && !ids.contains(s)) {
          ids.add(s);
        }
      }
    }
    final deliveries = e.payload['deliveries'];
    if (deliveries is Map) {
      for (final entry in deliveries.entries) {
        final k = entry.key.toString().trim();
        final v = entry.value;
        if (k.isNotEmpty &&
            k != 'human' &&
            k != 'local' &&
            v is Map &&
            v['read_at'] != null &&
            !ids.contains(k)) {
          ids.add(k);
        }
      }
    } else if (deliveries is List) {
      for (final item in deliveries) {
        if (item is Map && item['read_at'] != null) {
          final k =
              (item['recipient_id'] ?? item['agent_id'] ?? '').toString().trim();
          if (k.isNotEmpty &&
              k != 'human' &&
              k != 'local' &&
              !ids.contains(k)) {
            ids.add(k);
          }
        }
      }
    }
    if (ids.isEmpty) return null;
    final names = [for (final id in ids) _agentName(id)];
    if (names.length == 1) return 'Read by ${names.first}';
    if (names.length == 2) return 'Read by ${names[0]} and ${names[1]}';
    return 'Read by ${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
  }

  Widget _body({required bool hideChrome}) {
    final topPad = hideChrome ? 12.0 : ChatHeader.overlap;
    if (_loading) {
      return const Center(child: Spinner(size: 24));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon('alert-circle', size: 24, color: AppColors.danger),
              const SizedBox(height: 10),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: sans(13, color: AppColors.danger)),
              const SizedBox(height: 14),
              Btn('Retry', small: true, onTap: () => _load(silent: false)),
            ],
          ),
        ),
      );
    }
    final visible = [
      for (final e in _events)
        if (!isReactionEvent(e) &&
            (e.body.isNotEmpty || _systemText(e) != null))
          e
    ];
    if (visible.isEmpty) {
      return PullToRefresh(
        onRefresh: () => _load(silent: true),
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.only(top: topPad),
          children: [
            SizedBox(
              height: MediaQuery.sizeOf(context).height * 0.45,
              child: Center(
                child: EmptyState(
                  icon: 'users',
                  title: _title,
                  body: 'Say hello — everyone in the group sees it.',
                ),
              ),
            ),
          ],
        ),
      );
    }
    final runs = chatRuns<CoordinationEvent>(
      visible,
      sender: (e) => e.actorKind == 'human' ? 'human' : e.actorId,
      at: _eventTime,
      breaks: (e) => _systemText(e) != null,
    );
    int? lastHumanIndex;
    for (var i = visible.length - 1; i >= 0; i--) {
      if (visible[i].actorKind == 'human' && _systemText(visible[i]) == null) {
        lastHumanIndex = i;
        break;
      }
    }
    return PullToRefresh(
      onRefresh: () => _load(silent: true),
      child: ListView.builder(
        controller: _scroll,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(16, topPad, 16, 16),
        itemCount: visible.length,
        itemBuilder: (_, i) {
          final e = visible[i];
          final run = runs[i];
          final at = _eventTime(e);
          final prevAt = i > 0 ? _eventTime(visible[i - 1]) : null;
          final showStamp = at != null &&
              (prevAt == null ||
                  !_sameDay(prevAt, at) ||
                  (run.first &&
                      at.difference(prevAt).abs() >=
                          const Duration(minutes: 15)));
          final stamp = showStamp ? _dayTimeStamp(at) : null;
          final readLine = i == lastHumanIndex ? _readByLine(e) : null;
          return _wideCap(
            _item(
              e,
              index: i,
              run: run,
              stamp: stamp,
              readLine: readLine,
            ),
          );
        },
      ),
    );
  }

  Widget _senderAvatar(String actorId) {
    final size = ChatBubbleRow.avatarSize;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: ChatColors.cardButton,
        shape: BoxShape.circle,
      ),
      alignment: Alignment.center,
      child: AgentMochi(actorId, size: size * 0.6),
    );
  }

  Widget _item(
    CoordinationEvent e, {
    required int index,
    required ({bool first, bool last}) run,
    required (String, String)? stamp,
    required String? readLine,
  }) {
    final sys = _systemText(e);
    final topGap =
        index == 0 ? 0.0 : (run.first ? ChatColors.groupGap : ChatColors.runGap);
    if (sys != null) {
      return Padding(
        padding: EdgeInsets.only(top: topGap),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (stamp != null) ChatSystemLine(stamp.$2, bold: stamp.$1),
            ChatSystemLine(sys),
          ],
        ),
      );
    }
    final mine = e.actorKind == 'human';
    Widget buildBubble() => ChatBubble(
          mine: mine,
          tail: run.last,
          child: _mentionText(e.body, mine: mine),
        );
    return Padding(
      padding: EdgeInsets.only(top: topGap),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (stamp != null) ChatSystemLine(stamp.$2, bold: stamp.$1),
          if (!mine && run.first)
            ChatSenderName(
              _agentName(e.actorId),
              indent: ChatBubbleRow.avatarSize + 6,
            ),
          MessageBubbleInteractive(
            text: e.body,
            mine: mine,
            focusBuilder: (_) => buildBubble(),
            builder: (_, __, bubbleKey) => ChatBubbleRow(
              mine: mine,
              avatar: !mine && run.last ? _senderAvatar(e.actorId) : null,
              avatarSlot: !mine && !run.last,
              child: KeyedSubtree(
                key: bubbleKey,
                child: buildBubble(),
              ),
            ),
          ),
          if (readLine != null)
            ChatSystemLine(readLine, align: Alignment.centerRight),
        ],
      ),
    );
  }

  Widget _mentionText(String body, {required bool mine}) {
    final mentionStyle = mine
        ? TextStyle(
            color: ChatColors.sentText,
            fontWeight: weightFor(W.strong),
          )
        : TextStyle(
            color: ChatColors.receivedText,
            fontWeight: FontWeight.w500,
          );
    final richText = Text.rich(
      TextSpan(
        style: chatText(mine: mine),
        children: [
          for (final s in groupMentionSpans(body, _mentionIds))
            s.style == null ? s : TextSpan(text: s.text, style: mentionStyle),
        ],
      ),
    );
    return kMobile ? richText : MessageSelectionArea(child: richText);
  }

  Widget _wideCap(Widget child) => kMobile
      ? child
      : Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 740),
              child: SizedBox(width: double.infinity, child: child)));

  Widget _composer() {
    final mq = MediaQuery.of(context);
    final keyboard = mq.viewInsets.bottom;
    return AnimatedPadding(
      duration: Motion.fast,
      curve: Motion.enter,
      padding: EdgeInsets.only(bottom: keyboard),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          16,
          8,
          16,
          10 + (keyboard > 0 ? 8 : mq.padding.bottom),
        ),
        child: _wideCap(
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (_mention != null && _mentionCandidates.isNotEmpty)
                _mentionList(),
              ComposerCard(
                field: CallbackShortcuts(
                  bindings: {
                    const SingleActivator(LogicalKeyboardKey.enter): () {
                      if (!kMobile) _send();
                    },
                    const SingleActivator(LogicalKeyboardKey.enter, meta: true):
                        _send,
                    const SingleActivator(LogicalKeyboardKey.enter,
                        control: true): _send,
                  },
                  child: TextField(
                    controller: _input,
                    focusNode: _inputFocus,
                    minLines: 1,
                    maxLines: 8,
                    cursorColor: AppColors.accent,
                    onSubmitted: (_) {
                      if (!kMobile) _send();
                    },
                    style: TS.body(AppColors.fg1),
                    decoration: ComposerCard.decoration('Message the group…'),
                  ),
                ),
                send: ValueListenableBuilder<TextEditingValue>(
                  valueListenable: _input,
                  builder: (_, val, __) {
                    final canSend = val.text.trim().isNotEmpty && !_sending;
                    return ComposerSendButton(
                      enabled: canSend,
                      sending: _sending,
                      onTap: canSend ? _send : null,
                    );
                  },
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _mentionList() {
    final candidates = _mentionCandidates;
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final c in candidates)
            InkWell(
              onTap: () => _applyMention(c.id),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                child: Row(children: [
                  if (c.id == 'everyone')
                    AppIcon('users', size: 16, color: AppColors.fg3)
                  else
                    AgentMochi(c.id, size: 16),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(c.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TS.body(AppColors.fg1)),
                  ),
                  if (c.name != null && c.name != c.label)
                    Text('@${c.id}', style: TS.meta(AppColors.fg3)),
                ]),
              ),
            ),
        ],
      ),
    );
  }
}
