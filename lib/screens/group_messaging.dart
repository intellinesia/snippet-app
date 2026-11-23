import 'group_rail.dart';
import '../composer/desktop_composer.dart' show DeskIconButton;
import 'agent_transcript_head.dart';
import '../quiet.dart' show QuietHand;
import 'dart:async';

import '../chat/chat_info.dart' show showGroupInfo;
import '../motion_routes.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../chat/choices.dart';
import '../composer/chat_composer.dart';
import '../composer/composer_attachments.dart';
import '../composer/thread_composer_kit.dart';
import '../composer/voice_note.dart';
import '../drafts.dart';
import '../desktop_pick.dart';
import '../markdown_preview.dart';
import '../chat/message_body.dart';
import '../message_reactions.dart';
import '../models.dart';
import '../chat/anchored_scroll.dart';
import '../chat/message_enter.dart';
import '../chat/send_flight.dart';
import '../mochi.dart';
import '../motion.dart';
import '../panel.dart';
import '../platform.dart';
import '../pull_refresh.dart';
import '../swr.dart';
import '../glass.dart' show StatusInset, TopFadeMask;
import '../theme.dart';
import '../widgets.dart';
import '../chat/agent_cluster.dart';
import '../chat/chat_style.dart';
import '../chat/group_notice.dart';
import '../chat/stage_bar.dart';
import '../chat/stage_header.dart';
import '../chat/run_head.dart';
import '../chat/chat_empty_intro.dart';
import 'agent_card.dart'
    show AgentRowShell, LitTile, TeamRow, agentRowAgo, agentRowTime;
import 'agent_questions_card.dart' show questionAnswerSystemLine;
import 'agent_thread_cards.dart' show agentThreadEventCard;
import 'tasks/tasks_panel.dart' show openTasksPage, openTaskCountFor;
import '../chat_scene.dart' show SceneBackdrop;
import '../tap_detector.dart';

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

/// Tokens agents use to mention the user.
const _humanMentions = {'human'};

/// Text spans for a group message: `@member`, `@everyone` and `@human` in
/// accent.
List<TextSpan> groupMentionSpans(String text, Set<String> memberIds) {
  final spans = <TextSpan>[];
  var at = 0;
  for (final m in _mentionToken.allMatches(text)) {
    final id = m.group(1)!;
    if (!memberIds.contains(id) &&
        id != 'everyone' &&
        !_humanMentions.contains(id.toLowerCase())) {
      continue;
    }
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

final RegExp _codeSegment = RegExp(r'```[\s\S]*?(?:```|$)|`[^`\n]*`');

/// [body] as markdown with member `@id` mentions bolded, leaving code alone.
String groupMarkdownWithMentions(String body, Set<String> memberIds) {
  String bold(String text) => [
        for (final s in groupMentionSpans(text, memberIds))
          s.style == null ? s.text! : '**${s.text}**',
      ].join();
  final out = StringBuffer();
  var at = 0;
  for (final m in _codeSegment.allMatches(body)) {
    out
      ..write(bold(body.substring(at, m.start)))
      ..write(m[0]);
    at = m.end;
  }
  out.write(bold(body.substring(at)));
  return out.toString();
}

String groupMemberName(GroupMember m, Map<String, CoordinationAgent> agents) {
  if (m.isHuman) return 'You';
  final a = agents[m.id];
  if (a == null) return m.id;
  final name = a.displayName.trim();
  return name.isEmpty ? m.id : name;
}

/// The one-line status a group header or sidebar row shows for live work:
/// the turn holder on a task room, else who is still replying.
String? groupActivityStatus(
    GroupSummary group, String Function(String id) nameOf) {
  final turn = group.turnAgent;
  // With one agent on the task the turn is never in question.
  if (turn != null && turn.isNotEmpty && group.agentIds.length > 1) {
    return '${nameOf(turn)} has the turn';
  }
  final replying = group.replying;
  if (replying.isEmpty) return null;
  String names(int n) => replying.take(n).map(nameOf).join(', ');
  if (replying.length == 1) return '${nameOf(replying.first)} is replying';
  if (replying.length == 2) {
    return '${nameOf(replying[0])} and ${nameOf(replying[1])} are replying';
  }
  return '${names(2)} and ${replying.length - 2} more are replying';
}

/// Open a group thread, the same way openAgentThread opens a direct one.
Future<void> openGroupThread(
  BuildContext context, {
  required DaemonClient client,
  required GroupSummary group,
}) async {
  if (kMobile) {
    Widget page(BuildContext _) => GroupThreadScreen(
          client: client,
          group: group,
          onClose: () => Navigator.pop(context),
        );
    await Navigator.of(context).push<void>(AppPageRoute<void>(builder: page));
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
    sidePanel: (ctx, closeTab) => GroupRail(
      key: ValueKey('group-rail-${group.id}'),
      client: client,
      group: group,
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
    BuildContext context, DaemonClient client,
    {BuildContext? anchorContext}) async {
  final group = await showCreateGroupSheet(context,
      client: client, anchorContext: anchorContext);
  if (group == null || !context.mounted) return null;
  final entry = client.swr.entry<List<GroupSummary>>('groups');
  entry.revalidate(client.groups, force: true);
  await openGroupThread(context, client: client, group: group);
  entry.revalidate(client.groups, force: true);
  return group;
}

class GroupRow extends StatelessWidget {
  const GroupRow(
      {super.key,
      required this.group,
      required this.onTap,
      this.onLongPress,
      this.pinned = false,
      this.needsYou = false,
      this.nameOf});

  final GroupSummary group;
  final bool pinned;

  /// Any member is waiting on you: the one amber mark on the row.
  final bool needsYou;
  final VoidCallback onTap;
  final VoidCallback? onLongPress;

  /// Resolves an agent id to a display name for the activity status line.
  final String Function(String id)? nameOf;

  @override
  Widget build(BuildContext context) {
    final agents = group.agentIds;
    final name = group.title.trim().isEmpty ? 'Group' : group.title.trim();
    final members = group.members.length;
    final line = [
      '$members ${members == 1 ? 'member' : 'members'}',
      if (group.lead != null) 'lead ${group.lead}',
    ].join(' · ');
    final nameOf = this.nameOf;
    final status = nameOf == null ? null : groupActivityStatus(group, nameOf);
    final sub = status ?? group.preview ?? line;
    final shown = agents.take(4).toList();
    final unread = group.unread;
    if (kMobile) {
      final at = DateTime.tryParse(group.lastEventAt ?? '')?.toLocal();
      final time = agentRowTime(at);
      // Same shape as the agent rows it sits among on the Agents tab.
      final subStyle = TeamRow.subtitleStyle(unread > 0 ? AppColors.fg2 : null);
      return TeamRow(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Row(children: [
          SizedBox.square(
            dimension: 40,
            child: shown.isEmpty
                ? Center(
                    child: AppIcon('users', size: 22, color: AppColors.fg3))
                : AgentCluster(ids: agents, size: 40),
          ),
          SizedBox(width: S.of(14)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(children: [
                  Flexible(
                    child: Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TeamRow.titleStyle()),
                  ),
                  if (pinned) ...[
                    SizedBox(width: S.s6),
                    AppIcon('pin', size: 14, color: AppColors.fg3),
                  ],
                ]),
                SizedBox(height: S.of(1)),
                Row(children: [
                  Flexible(
                    child: Text.rich(markdownPreviewSpan(sub, subStyle),
                        maxLines: 1, overflow: TextOverflow.ellipsis),
                  ),
                  if (time.isNotEmpty)
                    Text(', $time', maxLines: 1, style: subStyle),
                ]),
              ],
            ),
          ),
          SizedBox(width: S.s8),
          AppIcon('chevron-right', size: 16, color: AppColors.fg4),
        ]),
      );
    }
    // Same single line as the agent rows above it.
    return AgentRowShell(
      onTap: onTap,
      onLongPress: onLongPress,
      time: agentRowAgo(DateTime.tryParse(group.lastEventAt ?? '')),
      avatar: shown.isEmpty
          ? const Center(child: AppIcon('users', size: 14))
          : shown.length == 1
              ? AgentMochi(shown.first, size: 28)
              : SizedBox(
                  width: 36,
                  height: 22,
                  // Bare characters, no disc behind each.
                  child: Stack(children: [
                    AgentMochi(shown[0], size: 22),
                    Positioned(left: 14, child: AgentMochi(shown[1], size: 22)),
                  ]),
                ),
      wideAvatar: shown.length > 1,
      // Desktop: two overlapping lit tiles, plus a count past two.
      avatarFor: kMobile || shown.length < 2
          ? null
          : (backdrop) => Stack(clipBehavior: Clip.none, children: [
                Positioned(
                    left: 0,
                    top: 1,
                    child: LitTile.agent(shown[0],
                        size: rowAvatarSize(34) - 2)),
                Positioned(
                    left: 9,
                    top: 1,
                    child: LitTile.agent(shown[1],
                        size: rowAvatarSize(34) - 2, ring: backdrop)),
                if (agents.length > 2)
                  Positioned(
                    right: -8,
                    bottom: -3,
                    child: Container(
                      height: 12,
                      constraints: const BoxConstraints(minWidth: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 2),
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.surface3,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(color: backdrop, width: 1.5),
                      ),
                      child: Text('+${agents.length - 2}',
                          style: sans(8,
                              weight: FontWeight.w600, color: AppColors.fg2)),
                    ),
                  ),
              ]),
      tint: kMobile || shown.length != 1 ? null : agentTintFor(shown.first),
      name: name,
      pinned: pinned,
      preview: sub,
      needs: unread > 0,
      trailing: needsYou
          ? const QuietHand(size: 14)
          : unread > 0
              ? Container(
                  key: const ValueKey('group-unread'),
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                      color: AppColors.fg2, shape: BoxShape.circle),
                )
              : null,
    );
  }
}

/// Create a group: a title, the agents in it, and an optional lead.
Future<GroupSummary?> showCreateGroupSheet(
  BuildContext context, {
  required DaemonClient client,
  BuildContext? anchorContext,
}) =>
    kMobile
        ? showAppSheet<GroupSummary>(
            context,
            title: 'New group',
            maxWidth: 380,
            maxHeight: 720,
            child: _CreateGroupSheet(client: client),
          )
        : showSidePopover<GroupSummary>(context,
            anchorContext: anchorContext,
            title: 'New group',
            popoverKey: const ValueKey('create-group-popover'),
            width: 360,
            child: _CreateGroupSheet(client: client));

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
            .where((a) => !a.isLead && a.status != 'archived')
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
    final n = _selected.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text('Several agents in one conversation. A lead answers first.',
            style: sans(13, height: 1.45, color: AppColors.fg3)),
        SizedBox(height: S.of(14)),
        FieldWell(
          minHeight: kMobile ? 48 : 38,
          alignment: Alignment.centerLeft,
          padding:
              EdgeInsets.symmetric(horizontal: S.of(14), vertical: S.of(10)),
          child: TextField(
            controller: _title,
            autofocus: true,
            cursorColor: AppColors.accent,
            onChanged: (_) => setState(() {}),
            style: sans(kMobile ? 15 : 13, color: AppColors.fg1),
            decoration: InputDecoration.collapsed(
              hintText: 'Group name',
              hintStyle: sans(kMobile ? 15 : 13, color: AppColors.fg4),
            ),
          ),
        ),
        SizedBox(height: S.s16),
        if (_loading)
          Padding(
            padding: EdgeInsets.symmetric(vertical: S.s20),
            child: Center(child: Spinner(size: 20)),
          )
        else if (_error != null && _agents.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: S.s12),
            child: Column(children: [
              Text(_error!, style: TS.meta(AppColors.danger)),
              SizedBox(height: S.s8),
              Btn('Retry', small: true, onTap: _load),
            ]),
          )
        else if (_agents.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(vertical: S.s12),
            child: Text('No agents available.', style: TS.meta()),
          )
        else ...[
          Padding(
            padding: EdgeInsets.symmetric(horizontal: S.s2),
            child: Row(children: [
              Text('Agents', style: sans(13, color: AppColors.fg3)),
              const Spacer(),
              if (n > 0)
                Text('$n selected', style: sans(13, color: AppColors.fg4)),
            ]),
          ),
          SizedBox(height: S.s8),
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.surface2,
              borderRadius: BorderRadius.circular(R.of(14)),
            ),
            child: Material(
              color: Colors.transparent,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < _agents.length; i++) ...[
                  if (i > 0) Container(height: 1, color: AppColors.line),
                  _AgentPickRow(
                    agent: _agents[i],
                    name: _name(_agents[i]),
                    selected: _selected.contains(_agents[i].id),
                    showLead: n > 1 && _selected.contains(_agents[i].id),
                    lead: _lead == _agents[i].id,
                    onTap: () => setState(() {
                      final id = _agents[i].id;
                      if (!_selected.remove(id)) _selected.add(id);
                      if (_lead != null && !_selected.contains(_lead)) {
                        _lead = null;
                      }
                    }),
                    onLead: () => setState(() {
                      final id = _agents[i].id;
                      _lead = _lead == id ? null : id;
                    }),
                  ),
                ],
              ]),
            ),
          ),
        ],
        SizedBox(height: S.of(18)),
        if (_error != null && _agents.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(bottom: S.s8),
            child: Text(_error!, style: TS.meta(AppColors.danger)),
          ),
        Btn(
            _creating
                ? 'Creating…'
                : n == 0
                    ? 'Create group'
                    : 'Create group · $n ${n == 1 ? 'agent' : 'agents'}',
            full: true,
            small: !kMobile,
            disabled: !canCreate,
            onTap: _create),
      ],
    );
  }
}

class _AgentPickRow extends StatelessWidget {
  const _AgentPickRow({
    required this.agent,
    required this.name,
    required this.selected,
    required this.showLead,
    required this.lead,
    required this.onTap,
    required this.onLead,
  });

  final CoordinationAgent agent;
  final String name;
  final bool selected;
  final bool showLead;
  final bool lead;
  final VoidCallback onTap;
  final VoidCallback onLead;

  @override
  Widget build(BuildContext context) {
    final profile = (agent.profile ?? '').trim();
    return Semantics(
      button: true,
      selected: selected,
      label: name,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: kMobile ? 56 : 44),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: S.s12, vertical: S.s8),
            child: Row(children: [
              kMobile
                  ? AgentMochi(agent.id, size: rowAvatarSize(56, max: 40))
                  : LitTile.agent(agent.id, size: rowAvatarSize(44, max: 28)),
              SizedBox(width: S.s12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(kMobile ? 15 : 13, color: AppColors.fg1)),
                    if (profile.isNotEmpty)
                      Text(profile,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(13, color: AppColors.fg3)),
                  ],
                ),
              ),
              if (showLead) ...[
                Semantics(
                  button: true,
                  selected: lead,
                  label: lead ? '$name is lead' : 'Make $name lead',
                  child: TapDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: onLead,
                    child: Padding(
                      padding: EdgeInsets.symmetric(vertical: S.s6),
                      child: ExcludeSemantics(
                        child: Container(
                          padding: EdgeInsets.symmetric(
                              horizontal: S.s8, vertical: S.of(3)),
                          decoration: BoxDecoration(
                            color: lead ? AppColors.accent : Colors.transparent,
                            borderRadius: BorderRadius.circular(R.card),
                            border: Border.all(
                                color: lead
                                    ? AppColors.accent
                                    : AppColors.lineStrong),
                          ),
                          child: Text(lead ? 'Lead' : 'Make lead',
                              style: sans(12,
                                  weight: lead ? W.strong : W.body,
                                  color: lead
                                      ? AppColors.accentFg
                                      : AppColors.fg3)),
                        ),
                      ),
                    ),
                  ),
                ),
                SizedBox(width: S.of(10)),
              ],
              AnimatedContainer(
                duration: const Duration(milliseconds: 150),
                width: 22,
                height: 22,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: selected ? AppColors.accent : Colors.transparent,
                  border: Border.all(
                      color: selected ? AppColors.accent : AppColors.lineStrong,
                      width: 1.5),
                ),
                child: selected
                    ? Center(
                        child: AppIcon('check',
                            size: 13, color: AppColors.accentFg))
                    : null,
              ),
            ]),
          ),
        ),
      ),
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
        borderRadius: BorderRadius.circular(R.of(16)),
        child: AnimatedContainer(
          duration: Motion.fast,
          padding: EdgeInsets.symmetric(horizontal: S.of(10), vertical: S.s6),
          decoration: BoxDecoration(
            color: selected ? AppColors.accent : AppColors.surface2,
            borderRadius: BorderRadius.circular(R.of(16)),
            border:
                Border.all(color: selected ? AppColors.accent : AppColors.line),
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            AgentMochi(agent.id, size: 16),
            SizedBox(width: S.s6),
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
            .where((a) => !a.isLead && a.status != 'archived')
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
            padding: EdgeInsets.symmetric(vertical: S.s4),
            child: Row(children: [
              if (m.isAgent)
                kMobile
                    ? AgentMochi(m.id, size: 22)
                    : LitTile.agent(m.id, size: 22)
              else
                AppIcon('user', size: 18, color: AppColors.fg3),
              SizedBox(width: S.of(10)),
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
          SizedBox(height: S.of(10)),
          Text('Add agents', style: TS.label(AppColors.fg3)),
          SizedBox(height: S.s8),
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
        SizedBox(height: S.s16),
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
    @visibleForTesting this.voiceController,
    @visibleForTesting this.pickFiles,
  });

  final DaemonClient client;
  final GroupSummary group;
  final VoidCallback? onClose;

  /// Nested under a host that already draws `NavBackRow`.
  final bool embedded;
  final bool showBack;

  @visibleForTesting
  final VoiceNoteController? voiceController;

  @visibleForTesting
  final Future<List<PickedLocalFile>> Function()? pickFiles;

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
  final _scroll = AnchoredScrollController();
  final ChatBottomTracker _bottom = ChatBottomTracker();
  final Set<String> _shownIds = {};
  bool _rowsSeeded = false;
  List<CoordinationEvent> _events = const [];
  bool _loading = true;
  bool _sending = false;
  String? _error;

  /// Sent but not yet in a fetched list; merged back so a refetch can't hide.
  final List<CoordinationEvent> _pending = [];
  // Sent here this session: their bubble gets the text-flight animation.
  final Set<String> _sendInIds = {};
  final GlobalKey _inputFieldKey = GlobalKey();

  Map<String, CoordinationAgent> _agents = const {};

  /// The `@query` under the cursor, when the completion list should show.
  ({int start, String query})? _mention;

  late final ComposerAttachmentController _attachments =
      ComposerAttachmentController(
    client: widget.client,
    onToast: (msg, {bool danger = false}) {
      if (mounted) toast(context, msg, danger: danger);
    },
    pickFilesOverride: widget.pickFiles,
  );

  late final VoiceNoteController _voice = widget.voiceController ??
      VoiceNoteController(
        client: widget.client,
        filePrefix: 'snippet-group-voice',
        onToast: (msg, {bool danger = false}) {
          if (mounted) toast(context, msg, danger: danger);
        },
      );

  late final ThreadComposerKit _kit = ThreadComposerKit(
    input: _input,
    attachments: _attachments,
    voice: _voice,
    draftKey: Drafts.keyFor(widget.client.baseUrl, 'thread:${widget.group.id}'),
    onToast: (msg) {
      if (mounted) toast(context, msg);
    },
  );

  @override
  void initState() {
    super.initState();
    _kit.start();
    _loadAgents();
    _thread = Swr<List<CoordinationEvent>>(
      client: widget.client,
      key: 'group-thread:${widget.group.id}',
      fetch: () => widget.client.groupEventsAll(widget.group.id),
      revalidateOn: (e) =>
          Swr.coordinationForThread(e, widget.group.id) ||
          e['kind'] == 'session_decision',
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
    _kit.dispose();
    _attachments.dispose();
    if (widget.voiceController == null) {
      _voice.dispose();
    }
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
    if (hadNew && !first && _bottom.stickToBottom) {
      _jumpToBottom(animated: true);
    }
  }

  String _rowIdFor(CoordinationEvent e) =>
      e.eventId.isNotEmpty ? e.eventId : 'seq-${e.sequence}';

  bool _onScroll(ScrollNotification n) {
    _bottom.handleScroll(n, _scroll);
    return false;
  }

  void _rowResized(double delta, double? bottomInViewport) =>
      _bottom.rowResized(_scroll, delta, bottomInViewport);

  void _jumpToBottom({bool animated = true}) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _bottom.scrollToBottom(_scroll, context, animated: animated);
    });
  }

  Future<void> _send() async {
    if (_sending) return;
    if (_voice.isRecording) {
      await _voice.stop();
    }
    if (_voice.hasTake && !await _voice.confirmTake(_attachVoiceBytes)) {
      return;
    }
    if (_attachments.isUploading) {
      if (mounted) toast(context, 'Please wait for attachments to upload');
      return;
    }
    final typed = _input.text.trim();
    if (typed.isEmpty && _attachments.isEmpty) return;
    setState(() => _sending = true);
    try {
      var body = typed;
      final extraMarkers = <String>[
        ..._attachments.markers(),
      ];
      if (extraMarkers.isNotEmpty) {
        final joined = extraMarkers.join('\n\n');
        body = body.isEmpty ? joined : '$body\n\n$joined';
      }
      final mentions = extractGroupMentions(_input.text, _mentionIds);
      final ev = await widget.client.postGroup(
        widget.group.id,
        body: body,
        mentions: mentions.isEmpty ? null : mentions,
      );
      if (!mounted) return;
      _pending.add(ev);
      _sendInIds.add(ev.eventId);
      SendFlight.arm(_inputFieldKey);
      _input.clear();
      _attachments.clear();
      await _voice.discard();
      if (!mounted) return;
      _rowsSeeded = true;
      _bottom.stickToBottom = true;
      setState(() => _mention = null);
      _thread.refresh();
      _jumpToBottom(animated: true);
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

  String _agentName(String id) => groupMemberName(
      GroupMember.fromJson({'kind': 'agent', 'id': id}), _agents);

  /// The member a working line shows: typing first, then the first replying.
  String? _typingAgentId() {
    final store = widget.client.presence;
    for (final id in _group.agentIds) {
      final p = store.presenceForAgentId(id);
      if (p != null && (p.state == 'typing' || p.state == 'thinking')) return id;
    }
    return _group.replying.firstOrNull;
  }

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

  // The scene sits outside the SafeArea so the header frost can reach
  // up behind the status bar, as on the session screen.
  Widget _chrome(Widget body, bool hideChrome) => kMobile
      ? SceneBackdrop(
          child: StatusInset(
              top: hideChrome ? 0 : StatusInset.page(context),
              child: body),
        )
      : body;

  @override
  Widget build(BuildContext context) {
    // Desktop: the tab, bar and panel carry the identity; no stage.
    final hideChrome = widget.embedded || !kMobile;
    return _kit.dropTarget(Material(
      color: kMobile ? AppColors.pageCanvas : Colors.transparent,
      child: _chrome(
          SafeArea(
            top: !hideChrome,
            bottom: false,
            child: Column(
              children: [
                // Desktop: the group's identity stays above the conversation.
                if (!kMobile && !widget.embedded) _deskHead(),
                Expanded(
                  child: Stack(
                    clipBehavior: Clip.none,
                    children: [
                      Positioned.fill(
                          child: kMobile
                              ? _body(hideChrome: hideChrome)
                              : hideChrome
                                  ? _body(hideChrome: hideChrome)
                                  : TopFadeMask(
                                      clear: StageBar.height - 24,
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
          hideChrome),
    ));
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
      onTap: () =>
          openTasksPage(context, widget.client, agentIds: _groupAgentIds),
    );
    final docked = kMobile ? null : ShellRequestScope.maybeOf(context);
    final toggleSide = docked?.sidePanel != null ? docked?.toggleSide : null;
    // Docked in a shell tab, the group name toggles the info panel.
    final Widget? trailing = toggleSide != null || kMobile
        ? null
        : !kMobile && !widget.embedded && widget.onClose != null
            ? Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  tasksBtn,
                  SizedBox(width: S.s6),
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
      builder: (_, __) => StageBar(
        members: _stageMembers(),
        title: _title,
        subtitle: _stageSubtitle(),
        subtitleHand: _groupNeedsYou,
        onTap: () {
          if (toggleSide != null) {
            toggleSide();
            return;
          }
          unawaited(showGroupInfo(
            context,
            client: widget.client,
            group: _group,
            onOpenTasks: () =>
                openTasksPage(context, widget.client, agentIds: _groupAgentIds),
            onChanged: () => unawaited(_reloadGroup()),
          ));
        },
        onBack: canGoBack ? _closePage : null,
        trailing: trailing,
      ),
    );
  }

  /// Desktop: the group's identity pinned over the conversation, like an
  /// agent page: stacked faces, name, one meta line, a dots menu.
  Widget _deskHead() {
    final ids = _group.agentIds;
    final body = AgentTranscriptHead(
      agentId: ids.isEmpty ? 'snippet' : ids.first,
      agentIds: ids,
      name: _title,
      meta: _stageSubtitle(),
      actions: [
        DeskIconButton('more-horizontal',
            tooltip: 'Group options',
            iconSize: 16,
            onTap: () => unawaited(showGroupInfo(
                  context,
                  client: widget.client,
                  group: _group,
                  onOpenTasks: () => openTasksPage(context, widget.client,
                      agentIds: _groupAgentIds),
                  onChanged: () => unawaited(_reloadGroup()),
                ))),
      ],
    );
    return ColoredBox(
      color: AppColors.bg,
      child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0), child: body),
    );
  }

  /// Who is typing, replying or holding the turn stands first on the stage.
  List<String> _activeIds() {
    final store = widget.client.presence;
    final out = <String>[];
    final turn = _group.turnAgent;
    if (turn != null && turn.isNotEmpty) out.add(turn);
    for (final id in _group.agentIds) {
      final p = store.presenceForAgentId(id);
      if (p != null && (p.state == 'typing' || p.state == 'thinking')) {
        out.add(id);
      }
    }
    out.addAll(_group.replying);
    return out;
  }

  List<StageMember> _stageMembers() {
    final active = _activeIds();
    final ids = [
      ...{...active.where(_group.agentIds.contains)},
    ];
    final ordered = [
      ...ids,
      for (final id in _group.agentIds)
        if (!ids.contains(id)) id,
    ];
    return [
      for (final id in ordered)
        StageMember(id,
            state: active.contains(id)
                ? AgentCharacterState.working
                : AgentCharacterState.idle),
    ];
  }

  /// Who is typing or holds the turn, else the member count.
  String _stageSubtitle() {
    final status = groupActivityStatus(_group, _agentName);
    if (status != null) return status;
    final typing = _typingStatus();
    if (typing != null) return typing;
    // Members by name: "X Scout, Buddy and you".
    final names = [for (final id in _group.agentIds) _agentName(id)];
    if (_group.members.any((m) => m.kind == 'human')) names.add('you');
    if (names.length <= 1) return names.join();
    return '${names.sublist(0, names.length - 1).join(', ')} and ${names.last}';
  }

  /// Any agent in the group is waiting on you.
  bool get _groupNeedsYou {
    final store = widget.client.presence;
    return _group.agentIds.any((id) {
      final p = store.presenceForAgentId(id);
      return p != null && p.state == 'waiting' && (p.detail == 'user' || p.detail.isEmpty);
    });
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
    final answerLine = questionAnswerSystemLine(e);
    if (answerLine != null) return answerLine;
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
    if (e.eventType == 'task.verdict') {
      final verdict = e.payload['verdict']?.toString() ?? '';
      final by = e.payload['by']?.toString() ?? e.actorId;
      final taskId = e.payload['task_id']?.toString() ?? '';
      final who = by == 'human' || by == 'user' || by == 'local'
          ? 'You'
          : _agentName(by);
      return switch (verdict) {
        'approved' => '$who approved $taskId',
        'sent_back' => '$who sent back $taskId',
        _ => body.isEmpty ? null : body,
      };
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
          final k = (item['recipient_id'] ?? item['agent_id'] ?? '')
              .toString()
              .trim();
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
    final topPad = hideChrome ? 12.0 : StageBar.height;
    if (_loading) {
      return const Center(child: Spinner(size: 24));
    }
    if (_error != null) {
      return Center(
        child: Padding(
          padding: EdgeInsets.all(S.s24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              AppIcon('hand', size: 24, color: AppColors.run, filled: true),
              SizedBox(height: S.of(10)),
              Text(_error!,
                  textAlign: TextAlign.center,
                  style: sans(13, color: AppColors.fg2)),
              SizedBox(height: S.of(14)),
              Btn('Retry', small: true, onTap: () => _load(silent: false)),
            ],
          ),
        ),
      );
    }
    final cards = Map<CoordinationEvent, Widget>.identity();
    for (final e in _events) {
      if (isReactionEvent(e) || _systemText(e) != null) continue;
      if (e.actorKind == 'human') continue;
      final card = agentThreadEventCard(
        e,
        client: widget.client,
        agentId: e.actorId,
        events: _events,
      );
      if (card != null) cards[e] = card;
    }
    final visible = [
      for (final e in _events)
        if (!isReactionEvent(e) &&
            (cards.containsKey(e) ||
                e.body.isNotEmpty ||
                _systemText(e) != null ||
                eventChoices(e).isNotEmpty))
          e
    ];
    final reactionsByTarget = groupMessageReactions(_events);
    if (visible.isEmpty && !kMobile) {
      final ids = _group.agentIds;
      final names = [for (final id in ids) _agentName(id)];
      final who = names.length <= 1
          ? names.join()
          : '${names.take(names.length - 1).join(', ')} and ${names.last}';
      final lead = _group.lead;
      return LayoutBuilder(
        builder: (_, c) => SingleChildScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          child: SizedBox(
            height: c.maxHeight,
            child: ChatEmptyIntro(
              ids: ids,
              name: _title,
              purpose: [
                if (who.isNotEmpty) '$who.',
                if (lead != null && lead.isNotEmpty) '${_agentName(lead)} leads.',
              ].join(' '),
              note: 'Everyone in the group sees what you send',
            ),
          ),
        ),
      );
    }
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
      breaks: (e) =>
          _systemText(e) != null ||
          cards.containsKey(e) ||
          eventChoices(e).isNotEmpty,
    );
    int? lastHumanIndex;
    for (var i = visible.length - 1; i >= 0; i--) {
      if (visible[i].actorKind == 'human' && _systemText(visible[i]) == null) {
        lastHumanIndex = i;
        break;
      }
    }
    final typing = _typingStatus() != null || _group.replying.isNotEmpty;
    if (!_rowsSeeded) {
      _rowsSeeded = true;
      for (final e in visible) {
        _shownIds.add(_rowIdFor(e));
      }
    }
    final offset = typing ? 1 : 0;
    final rowIndex = <Key, int>{
      for (var i = 0; i < visible.length; i++)
        ValueKey(_rowIdFor(visible[i])): visible.length - 1 - i + offset,
    };
    // Reversed so the thread opens at its newest post with no jump.
    return NotificationListener<ScrollNotification>(
      onNotification: _onScroll,
      child: ListView.builder(
        controller: _scroll,
        reverse: true,
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.fromLTRB(S.s16, topPad, S.s16, S.s16),
        itemCount: visible.length + offset,
        findChildIndexCallback: (key) => rowIndex[key],
        itemBuilder: (_, raw) {
          if (typing && raw == 0 && !kMobile) {
            final id = _typingAgentId();
            return _wideCap(Padding(
              padding: EdgeInsets.only(top: ChatColors.groupGap),
              child: Align(
                alignment: Alignment.centerLeft,
                child: id == null
                    ? const WorkingBars()
                    : SoftLane(
                        agentId: id,
                        child: SoftBubble(
                            child: Padding(
                                padding:
                                    const EdgeInsets.symmetric(vertical: 3),
                                child: const WorkingBars()))),
              ),
            ));
          }
          if (typing && raw == 0) {
            return _wideCap(Padding(
              padding: EdgeInsets.only(
                  top: ChatColors.groupGap,
                  left: ChatBubbleRow.avatarSize + S.s6),
              child: Align(
                alignment: Alignment.centerLeft,
                child: GroupTypingBubble(
                    dots: WorkingDots(color: ChatColors.meta, size: 6)),
              ),
            ));
          }
          final index = typing ? raw - 1 : raw;
          final i = visible.length - 1 - index;
          final e = visible[i];
          final rowId = _rowIdFor(e);
          final fresh = _rowsSeeded && _shownIds.add(rowId);
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
          return KeyedSubtree(
            key: ValueKey(rowId),
            child: RowSizeWatch(
              onResize: _rowResized,
              child: MessageEnter(
                animate: fresh &&
                    _bottom.stickToBottom &&
                    !(kMobile && _sendInIds.contains(rowId)),
                child: _wideCap(
                  _item(
                    e,
                    card: cards[e],
                    index: i,
                    run: run,
                    stamp: stamp,
                    readLine: readLine,
                    reactions: reactionsByTarget[e.eventId] ?? const [],
                  ),
                ),
              ),
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
      decoration: avatarDecoration(size, color: ChatColors.cardButton),
      alignment: Alignment.center,
      child: AgentMochi(actorId, size: size * 0.6),
    );
  }

  Future<void> _sendReaction(CoordinationEvent target, String reaction) async {
    if (target.eventId.isEmpty) return;
    final shown = messageReactionEmoji(reaction);
    final remove = (groupMessageReactions(_events)[target.eventId] ?? const [])
        .any((r) => r.mine && r.name == shown);
    final key = 'local-react-${DateTime.now().microsecondsSinceEpoch}';
    final local = CoordinationEvent.fromJson({
      'event_id': key,
      'thread_id': widget.group.id,
      'event_type': 'group_message',
      'actor_kind': 'human',
      'actor_id': 'human',
      'payload': {
        'body': '',
        'kind': 'reaction',
        'reply_to': target.eventId,
        'in_reply_to': target.eventId,
        'reaction': reaction,
        if (remove) 'removed': true,
      },
      'idempotency_key': key,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    _pending.add(local);
    setState(() => _events = [..._events, local]);
    try {
      final ev = await widget.client.postGroup(
        widget.group.id,
        body: '',
        inReplyTo: target.eventId,
        reaction: reaction,
        remove: remove,
      );
      if (!mounted) return;
      _pending.removeWhere((p) => p.eventId == key);
      _pending.add(ev);
      _thread.refresh();
    } catch (e) {
      _pending.removeWhere((p) => p.eventId == key);
      if (!mounted) return;
      setState(() => _events = [
            for (final ev in _events)
              if (ev.eventId != key) ev
          ]);
      toast(context, '$e', danger: true);
    }
  }

  Future<void> _sendChoice(CoordinationEvent target, String choice) async {
    if (target.eventId.isEmpty) return;
    final key = 'local-choice-${DateTime.now().microsecondsSinceEpoch}';
    final local = CoordinationEvent.fromJson({
      'event_id': key,
      'thread_id': widget.group.id,
      'event_type': 'group_message',
      'actor_kind': 'human',
      'actor_id': 'human',
      'payload': {
        'body': choice,
        'reply_to': target.eventId,
        'in_reply_to': target.eventId,
      },
      'idempotency_key': key,
      'created_at': DateTime.now().toUtc().toIso8601String(),
    });
    _pending.add(local);
    setState(() => _events = [..._events, local]);
    _jumpToBottom(animated: true);
    try {
      final ev = await widget.client.postGroup(
        widget.group.id,
        body: choice,
        inReplyTo: target.eventId,
      );
      if (!mounted) return;
      _pending.removeWhere((p) => p.eventId == key);
      _pending.add(ev);
      _thread.refresh();
    } catch (e) {
      _pending.removeWhere((p) => p.eventId == key);
      if (!mounted) return;
      setState(() => _events = [
            for (final ev in _events)
              if (ev.eventId != key) ev
          ]);
      toast(context, '$e', danger: true);
    }
  }


  // Desktop runs sit flush under their head, as in the agent chat.
  Widget _indented({required bool mine, required Widget child}) => child;

  /// Desktop: reactions as chips under the message, plus a quiet add chip.
  Widget _deskReactions(CoordinationEvent e, List<ReactionGroup> reactions,
      {required bool mine}) {
    if (reactions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: EdgeInsets.only(top: S.s6, left: mine ? 0 : kSoftIndent),
      child: Align(
        alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
        child: Wrap(spacing: S.s4, runSpacing: S.s4, children: [
          for (final r in reactions)
            DeskReactionChip(
                group: r, onTap: () => unawaited(_sendReaction(e, r.name))),
          Builder(
              builder: (anchor) => DeskReactionChip.add(
                  onTap: () => showReactionPicker(anchor,
                      onReact: (name) => unawaited(_sendReaction(e, name))))),
        ]),
      ),
    );
  }

  Widget _withTapback(Widget bubble, Widget? chips, {required bool mine}) {
    if (chips == null) return bubble;
    return Padding(
      padding: const EdgeInsets.only(top: MessageReactionChips.rise),
      child: Stack(clipBehavior: Clip.none, children: [
        bubble,
        Positioned(
          top: -MessageReactionChips.rise,
          left: mine ? -MessageReactionChips.overhang : null,
          right: mine ? null : -MessageReactionChips.overhang,
          child: chips,
        ),
      ]),
    );
  }

  Widget _item(
    CoordinationEvent e, {
    Widget? card,
    required int index,
    required ({bool first, bool last}) run,
    required (String, String)? stamp,
    required String? readLine,
    List<ReactionGroup> reactions = const [],
  }) {
    final sys = _systemText(e);
    final topGap = index == 0
        ? 0.0
        : (run.first ? ChatColors.groupGap : ChatColors.runGap);
    if (sys != null) {
      final at = _eventTime(e);
      final time = at == null ? null : _dayTimeStamp(at).$2;
      final isVerdict = e.eventType == 'task.verdict';
      final verdict = e.payload['verdict']?.toString() ?? '';
      final turn = e.eventType == 'task.lease_transferred';
      final toId = e.payload['to_agent_id']?.toString() ?? '';
      final kind = isVerdict && verdict == 'approved'
          ? GroupNoticeKind.approved
          : isVerdict && verdict == 'sent_back'
              ? GroupNoticeKind.sentBack
              : turn && toId.isNotEmpty
                  ? GroupNoticeKind.turn
                  : GroupNoticeKind.plain;
      return Padding(
        padding: EdgeInsets.only(top: topGap),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (stamp != null) ChatSystemLine(stamp.$2, bold: stamp.$1),
            GroupNotice(
              text: sys,
              kind: kind,
              time: kind == GroupNoticeKind.plain ? null : time,
              fromAgent: kind == GroupNoticeKind.turn
                  ? (e.payload['from_agent_id']?.toString() ?? e.actorId)
                  : null,
              toAgent: kind == GroupNoticeKind.turn ? toId : null,
            ),
          ],
        ),
      );
    }
    final mine = e.actorKind == 'human';
    final choices = eventChoices(e);
    final chosen = choices.isEmpty ? null : chosenReplyFor(e, _events);
    final body = ChatMessageBody(
      client: widget.client,
      body: e.body,
      mine: mine,
      markdown: (text) => groupMarkdownWithMentions(text, _mentionIds),
    );
    // Desktop soft bubbles, as in the agent chat.
    Widget buildContent() =>
        card ??
        (kMobile
            ? ChatBubble(mine: mine, tail: run.last, child: body)
            : mine
                ? ConstrainedBox(
                    constraints: BoxConstraints(
                        maxWidth: MediaQuery.sizeOf(context).width * 0.5),
                    child: SoftBubble(
                        mine: true,
                        first: run.first,
                        last: run.last,
                        child: body),
                  )
                : SoftBubble(first: run.first, last: run.last, child: body));
    final at = _eventTime(e);
    Widget lane(Widget child) => SoftLane(
          agentId: e.actorId,
          name: _agentName(e.actorId),
          time: at == null ? null : _dayTimeStamp(at).$2,
          lead: e.actorId == _group.lead,
          first: run.first,
          last: run.last,
          share: card != null ? 1 : 0.82,
          child: child,
        );
    final mineAt = !kMobile && mine && run.last ? _eventTime(e) : null;
    return Padding(
      padding: EdgeInsets.only(top: topGap),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (stamp != null) ChatSystemLine(stamp.$2, bold: stamp.$1),
          if (!mine && run.first && kMobile)
            Row(mainAxisSize: MainAxisSize.min, children: [
              Flexible(
                child: ChatSenderName(
                  _agentName(e.actorId),
                  indent: ChatBubbleRow.avatarSize + 6,
                ),
              ),
            ]),
          _indented(
              mine: mine,
              child: _sendFlight(
                  e.eventId,
                  MessageBubbleInteractive(
                    text: e.body,
                    mine: mine,
                    onReact: (name) => unawaited(_sendReaction(e, name)),
                    focusBuilder: (_) => buildContent(),
                    builder: (_, __, bubbleKey) => _rowFor(
                      lane: lane,
                      card: card,
                      mine: mine,
                      avatar: kMobile && !mine && run.last
                          ? _senderAvatar(e.actorId)
                          : null,
                      avatarSlot: kMobile && !mine && !run.last,
                      child: !kMobile
                          ? KeyedSubtree(key: bubbleKey, child: buildContent())
                          : _withTapback(
                              KeyedSubtree(
                                key: bubbleKey,
                                child: buildContent(),
                              ),
                              reactions.isEmpty
                                  ? null
                                  : MessageReactionChips(
                                      reactions: reactions,
                                      mine: mine,
                                      onReact: (name) =>
                                          unawaited(_sendReaction(e, name)),
                                    ),
                              mine: mine,
                            ),
                    ),
                  ))),
          if (mineAt != null)
            SentMeta(time: _dayTimeStamp(mineAt).$2, read: readLine),
          if (!kMobile) _deskReactions(e, reactions, mine: mine),
          if (choices.isNotEmpty)
            LayoutBuilder(
              builder: (_, box) {
                final max = box.maxWidth.isFinite
                    ? box.maxWidth * ChatColors.maxShare
                    : 520.0;
                return Padding(
                  padding: EdgeInsets.only(
                    top: S.s6,
                    left: mine
                        ? 0
                        : kMobile
                            ? ChatBubbleRow.avatarSize + S.s6 + S.of(5)
                            : kSoftIndent,
                    right: mine ? S.of(5) : 0,
                  ),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: max),
                    child: ChatChoices(
                      choices: choices,
                      chosen: chosen,
                      onPick: (choice) => unawaited(_sendChoice(e, choice)),
                    ),
                  ),
                );
              },
            ),
          if (readLine != null && kMobile)
            ChatSystemLine(readLine, align: Alignment.centerRight),
        ],
      ),
    );
  }

  // Cards share the bubbles' lane: same avatar column, same width cap.
  Widget _rowFor({
    required Widget Function(Widget) lane,
    required Widget? card,
    required bool mine,
    required Widget? avatar,
    required bool avatarSlot,
    required Widget child,
  }) =>
      // Desktop: received runs take the whole column, as in the agent chat.
      !kMobile && !mine
          ? Align(
              alignment: Alignment.centerLeft,
              child: lane(card != null
                  ? SizedBox(width: double.infinity, child: child)
                  : child))
          : ChatBubbleRow(
              mine: mine,
              avatar: avatar,
              avatarSlot: avatarSlot,
              fill: card != null,
              child: child);

  Widget _wideCap(Widget child) => kMobile
      ? child
      : Center(
          child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 960),
              child: SizedBox(width: double.infinity, child: child)));

  Widget _sendFlight(String id, Widget child) =>
      kMobile && _sendInIds.contains(id)
          ? SendFlightTarget(child: child)
          : child;

  Future<void> _attachVoiceBytes(Uint8List bytes, String name) =>
      _attachments.ingest([
        (name: name, localPath: null, readBytes: () async => bytes)
      ], upload: _voice.uploadTake);

  bool _canSend() =>
      (_input.text.trim().isNotEmpty ||
          _attachments.isNotEmpty ||
          _voice.isActive) &&
      !_sending;

  // Enter picks the first match while the mention list is open.
  void _enter() {
    final c = _mention != null ? _mentionCandidates : const [];
    if (c.isNotEmpty) {
      _applyMention(c.first.id);
    } else if (!kMobile && _canSend()) {
      unawaited(_send());
    }
  }

  Widget _composer() => ValueListenableBuilder<bool>(
      valueListenable: _kit.dragging,
      builder: (context, dragging, _) => ChatComposer(
        input: _input,
        focus: _inputFocus,
        fieldKey: _inputFieldKey,
        hint: kMobile
            ? 'Reply to $_title'
            : 'Message $_title, @ to address one',
        highlight: dragging,
        shortcuts: _kit.shortcuts(
            canSend: _canSend,
            onSend: () => unawaited(_send()),
            extra: {const SingleActivator(LogicalKeyboardKey.enter): _enter}),
        contentInsertion: _kit.keyboardContent,
        voice: _voice,
        listen: _attachments,
        above: [
          if (_mention != null && _mentionCandidates.isNotEmpty) _mentionList(),
        ],
        attachments: () =>
            _attachments.isNotEmpty ? _attachments.buildBar(context,
                onInsertText: (t) => appendToInput(_input, t)) : null,
        onAttach: () => unawaited(_attachments.pickFromSheet(context)),
        onRecordMore: () => unawaited(_voice.recordMore(_attachVoiceBytes)),
        deskHint: () => Padding(
          padding: EdgeInsets.only(right: S.s8),
          // Everyone by default; typing @ narrows it to one member.
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            SizedBox(
                width: 28,
                height: 16,
                child: AgentCluster(ids: _group.agentIds, size: 16)),
            const SizedBox(width: 6),
            Text('Everyone', style: sans(12, color: AppColors.fg2)),
          ]),
        ),
        sending: _sending,
        hasDraft: () =>
            _input.text.trim().isNotEmpty || _attachments.isNotEmpty,
        canSend: _canSend,
        onSend: () => unawaited(_send()),
      ));

  Widget _mentionList() {
    final candidates = _mentionCandidates;
    return Container(
      margin: EdgeInsets.only(bottom: S.s6),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(R.lg),
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
                    EdgeInsets.symmetric(horizontal: S.s12, vertical: S.s8),
                child: Row(children: [
                  if (c.id == 'everyone')
                    AppIcon('users', size: 16, color: AppColors.fg3)
                  else if (kMobile)
                    AgentMochi(c.id, size: 16)
                  else
                    LitTile.agent(c.id, size: 18),
                  SizedBox(width: S.s8),
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
