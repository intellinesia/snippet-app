import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../chat/agent_cluster.dart' show GroupGlyph;
import '../chat/chat_card.dart';
import '../chat/signal_row.dart'
    show prettyModel, prettyProfile, prettyProvider;
import '../mochi.dart';
import '../models.dart';
import '../quiet.dart';
import '../tap_detector.dart';
import '../theme.dart';
import '../widgets.dart';
import 'agent_profile_panel.dart';
import 'mobile_home/wake_reach_phone.dart';
import 'mobile_home/agents_home.dart';
import 'agent_profile_sheet.dart';
import 'group_messaging.dart' show openGroupThread, groupMemberName;
import 'lead/coordination_agent_detail.dart';
import 'session_list_row.dart' show sessionNeedsYou;
import 'shell_nav.dart' show sessionBusy;

/// Phone agent page: what the agent is doing, one-tap actions on it, then
/// its sessions, details and groups. Back from the conversation returns here.
class PhoneAgentPage extends StatefulWidget {
  const PhoneAgentPage({
    super.key,
    required this.agent,
    required this.client,
    required this.sessions,
    required this.onClose,
    required this.onOpenSession,
    required this.onAllSessions,
    this.onDecide,
  });

  final CoordinationAgent agent;
  final DaemonClient client;
  final List<SessionInfo> sessions;
  final VoidCallback onClose;
  final void Function(SessionInfo s) onOpenSession;
  final VoidCallback onAllSessions;
  final Future<bool> Function(SessionInfo s, bool approve)? onDecide;

  @override
  State<PhoneAgentPage> createState() => _PhoneAgentPageState();
}

/// The one-word state a session row and the status line carry.
String sessionStateWord(SessionInfo s) {
  if (sessionNeedsYou(s)) return 'Needs you';
  if (!s.settled && sessionBusy(s)) return 'Working';
  if (s.settled) return 'Done';
  return 'Idle';
}

/// Static mark beside the state word: dot, hand, tick or ring. No motion.
Widget sessionStateMark(SessionInfo s, {double size = 16}) =>
    switch (sessionStateWord(s)) {
      'Needs you' => QuietHand(size: size),
      'Working' => SizedBox.square(
          dimension: size,
          child: Center(
              child: Container(
                  width: 7,
                  height: 7,
                  decoration: BoxDecoration(
                      color: AppColors.fg2, shape: BoxShape.circle)))),
      'Done' => AppIcon('check', size: size, color: AppColors.fg3),
      _ => AppIcon('circle', size: size, color: AppColors.fg3),
    };

class _PhoneAgentPageState extends State<PhoneAgentPage> {
  bool _chat = false;
  bool _busy = false;
  bool? _paused;
  Map<String, InferenceProfile> _profiles = const {};
  List<GroupSummary> _groups = const [];
  Map<String, CoordinationAgent> _agents = const {};
  int? _memory;
  String? _wakes, _reach;

  @override
  void initState() {
    super.initState();
    widget.client.getConfig().then((cfg) {
      if (mounted) {
        setState(() => _profiles = {for (final p in cfg.profiles) p.name: p});
      }
    }).catchError((_) {});
    widget.client.groups().then((g) {
      if (mounted) {
        setState(() => _groups = [
              for (final x in g)
                if (x.agentIds.contains(a.id)) x
            ]);
      }
    }).catchError((_) {});
    widget.client.memoryScopes().then((scopes) {
      final m = scopes
          .where((x) => x.kind == 'agent' && x.key.contains(a.id))
          .firstOrNull;
      if (mounted && m != null) setState(() => _memory = m.entries);
    }).catchError((_) {});
    widget.client.wakes().then((l) {
      final mine = l.wakes.where((w) => w.owner == a.id && w.enabled).toList();
      if (!mounted || mine.isEmpty) return;
      setState(() => _wakes = mine.map((w) => w.scheduleText).join(', '));
    }).catchError((_) {});
    widget.client.agentReach(a.id).then((r) {
      final on = [
        for (final c in AgentReach.channelOrder)
          if (r.channel(c).enabled) reachChannelLabel(c)
      ];
      if (mounted && on.isNotEmpty) setState(() => _reach = on.join(', '));
    }).catchError((_) {});
    widget.client.coordinationAgents().then((all) {
      if (mounted) setState(() => _agents = {for (final x in all) x.id: x});
    }).catchError((_) {});
  }

  CoordinationAgent get a => widget.agent;
  String get _name =>
      a.displayName.trim().isEmpty ? a.id : a.displayName.trim();
  bool get _isPaused => _paused ?? a.status == 'paused';

  List<SessionInfo> get _mine => [
        for (final s in widget.sessions)
          if (s.displayAgentId == a.id) s
      ]..sort((x, y) => y.lastActive.compareTo(x.lastActive));

  String get _machine {
    final host = Uri.tryParse(widget.client.baseUrl)?.host ?? '';
    return host.isEmpty ? 'This machine' : host;
  }

  void _openProfile() => unawaited(showAgentProfileSheet(
        context,
        client: widget.client,
        agent: a,
        sessions: _mine,
        groups: _groups.length,
        machine: _machine,
        paused: _isPaused,
        onAllSessions: widget.onAllSessions,
        onPauseChanged: (p) => setState(() => _paused = p),
        onDeleted: widget.onClose,
      ));

  void _openWake() => unawaited(Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PhoneWakePage(
          client: widget.client, owner: a.id, name: _name))));

  void _openReach() => unawaited(Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => PhoneReachPage(
          client: widget.client, agentId: a.id, name: _name))));

  Future<void> _more() async {
    final pick = await showAppMenu<String>(context, items: [
      appMenuItem(value: 'model', icon: 'sliders', label: 'Model'),
      appMenuItem(
          value: 'pause',
          icon: _isPaused ? 'play' : 'pause',
          label: _isPaused ? 'Resume' : 'Pause'),
      appMenuItem(value: 'rename', icon: 'edit', label: 'Rename'),
      appMenuItem(value: 'delete', icon: 'trash', label: 'Delete'),
    ]);
    if (!mounted) return;
    switch (pick) {
      case 'model':
        unawaited(showAgentProfileSettings(context,
            client: widget.client, agent: a, name: _name));
      case 'pause':
        unawaited(_togglePause());
      case 'rename' || 'delete':
        _openProfile();
    }
  }

  Future<void> _togglePause() async {
    final next = !_isPaused;
    setState(() => _paused = next);
    try {
      await widget.client.setAgentStatus(a.id, next ? 'paused' : 'active');
    } catch (_) {
      if (!mounted) return;
      setState(() => _paused = !next);
      toast(context, next ? 'Could not pause' : 'Could not resume',
          danger: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_chat) {
      return CoordinationAgentDetail(
        key: const ValueKey('agent-detail'),
        agent: a,
        client: widget.client,
        embedded: false,
        onClose: () => setState(() => _chat = false),
      );
    }
    final mine = _mine;
    final ask = mine.where(sessionNeedsYou).firstOrNull;
    final active = [
      for (final s in mine)
        if (const {'Working', 'Needs you'}.contains(sessionStateWord(s))) s
    ];
    final recent = [
      for (final s in mine)
        if (!active.contains(s)) s
    ].take(3).toList();
    final profile = a.deskProfile ?? a.profile;
    final model = (_profiles[profile ?? '']?.model ?? '').trim();
    final live = _isPaused ? null : active.firstOrNull;
    Widget sessionRow(SessionInfo s) => QuietRow(
          title: s.title.isEmpty ? 'Untitled session' : s.title,
          sub: [sessionStateWord(s), relativeTime(s.lastActive)]
              .where((x) => x.isNotEmpty)
              .join(' \u00b7 '),
          leading: sessionStateMark(s),
          trailing: AppIcon('chevron-right', size: 16, color: AppColors.fg3),
          onTap: () => widget.onOpenSession(s),
        );
    final statusWord = _isPaused
        ? 'Paused'
        : live == null
            ? 'Idle'
            : sessionStateWord(live);
    final statusLine = live == null
        ? statusWord
        : '$statusWord \u00b7 ${relativeTime(live.runningSince ?? live.lastActive)}';
    final provider = (_profiles[profile ?? '']?.provider ?? '').trim();
    final providerValue = [
      if (provider.isNotEmpty) prettyProvider(provider),
      if (model.isNotEmpty) prettyModel(model),
    ].join(', ');
    final profileValue = [
      if ((profile ?? '').isNotEmpty) prettyProfile(profile!),
      if (a.maxContextTokens != null)
        '${(a.maxContextTokens! / 1000).round()}k context',
    ].join(', ');
    final sessionTitle = (live ?? mine.firstOrNull)?.title.trim() ?? '';
    final rows = <Widget>[
      if (a.role.isNotEmpty) ProfileRow('Role', a.role),
      if (providerValue.isNotEmpty)
        ProfileRow('Provider', providerValue,
            onTap: () => showAgentProfileSettings(context,
                client: widget.client, agent: a, name: _name)),
      if (profileValue.isNotEmpty)
        ProfileRow('Profile', profileValue,
            onTap: () => showAgentProfileSettings(context,
                client: widget.client, agent: a, name: _name)),
      if (sessionTitle.isNotEmpty)
        ProfileRow('Session', sessionTitle,
            onTap: () => widget.onOpenSession(live ?? mine.first)),
      if (_wakes != null && _wakes!.isNotEmpty)
        ProfileRow('Wake', _wakes!, onTap: _openWake),
      if (_memory != null)
        ProfileRow('Memory', '$_memory ${_memory == 1 ? 'entry' : 'entries'}'),
      if (_reach != null && _reach!.isNotEmpty)
        ProfileRow('Reach', _reach!, onTap: _openReach),
    ];
    return Material(
      color: AppColors.bg,
      child: SafeArea(
        child: Column(children: [
          PushedBar(
            title: _name,
            titleSize: 17,
            onBack: widget.onClose,
            actions: [BarIcon('more-horizontal', 'More', _more)],
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.only(bottom: 32),
              children: [
                const SizedBox(height: 16),
                Center(
                    child: ClipOval(child: AgentMochi(a.id, size: 96))),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
                  child: Text(_name,
                      maxLines: 1,
                      textAlign: TextAlign.center,
                      overflow: TextOverflow.ellipsis,
                      style: sans(20, weight: W.label, color: AppColors.fg1)),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 6, 16, 0),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    live == null
                        ? AppIcon('circle', size: 16, color: AppColors.fg2)
                        : sessionStateMark(live),
                    const SizedBox(width: 6),
                    Flexible(
                      child: Text(statusLine,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(13,
                              weight: statusWord == 'Needs you'
                                  ? W.label
                                  : W.body,
                              color: statusWord == 'Needs you'
                                  ? quietAmber
                                  : AppColors.fg2)),
                    ),
                  ]),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
                  child: Row(children: [
                    Expanded(
                        child: ProfileTile('chat', 'Chat',
                            onTap: () => setState(() => _chat = true))),
                    const SizedBox(width: 8),
                    Expanded(
                        child: ProfileTile('task', 'Tasks',
                            onTap: widget.onAllSessions)),
                    const SizedBox(width: 8),
                    Expanded(
                        child: ProfileTile('clock', 'Wake', onTap: _openWake)),
                  ]),
                ),
                if (ask != null) ...[
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: _askCard(ask),
                  ),
                ],
                const SizedBox(height: 16),
                ...rows,
                if (active.isNotEmpty) ...[
                  QuietSectionLabel('Active', count: active.length),
                  for (final s in active) sessionRow(s),
                ],
                if (recent.isNotEmpty) ...[
                  const QuietSectionLabel('Recent'),
                  for (final s in recent) sessionRow(s),
                ],
                if (mine.isNotEmpty)
                  QuietRow(
                    title: 'All sessions',
                    leading: AppIcon('layers', size: 20, color: AppColors.fg2),
                    meta: '${mine.length}',
                    trailing: AppIcon('chevron-right',
                        size: 16, color: AppColors.fg3),
                    onTap: widget.onAllSessions,
                  ),
            if (_groups.isNotEmpty) ...[
              QuietSectionLabel('Groups', count: _groups.length),
              for (final g in _groups)
                QuietRow(
                  title: g.title.isEmpty ? 'Group' : g.title,
                  sub: _memberLine(g),
                  leading: GroupGlyph(
                      size: 32, ids: g.agentIds, count: g.members.length),
                  onTap: () => openGroupThread(context,
                      client: widget.client, group: g),
                ),
            ],
              ],
            ),
          ),
        ]),
      ),
    );
  }

  String _memberLine(GroupSummary g) {
    final names = [
      for (final m in g.members)
        if (!m.isHuman) groupMemberName(m, _agents)
    ];
    final human = g.members.any((m) => m.isHuman);
    if (names.isEmpty) return '${g.members.length} members';
    if (!human) return names.join(', ');
    return '${names.join(', ')} and you';
  }

  Widget _askCard(SessionInfo s) {
    final text = '${s.attention?['text'] ?? ''}'.trim();
    final approval = s.attention?['type'] == 'approval' && widget.onDecide != null;
    return ChatCard(children: [
      ChatCardHeader(
        title: text.isEmpty ? s.title : text,
        subtitle: text.isEmpty || s.title.isEmpty ? null : s.title,
        eyebrow: Row(children: [
          const QuietHand(size: 16),
          const SizedBox(width: 8),
          Expanded(
              child: Text('$_name asks',
                  style: sans(13, color: AppColors.fg2))),
          Text(relativeTime(s.lastActive),
              style: sans(13, color: AppColors.fg3)),
        ]),
      ),
      ChatCardActions(buttons: [
        if (approval)
          ChatCardButton('Approve', busy: _busy, onTap: _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  await widget.onDecide!(s, true);
                  if (mounted) setState(() => _busy = false);
                }),
        ChatCardButton(approval ? 'Reply' : 'Open',
            kind: ChatCardButtonKind.secondary,
            onTap: () => widget.onOpenSession(s)),
      ]),
    ]);
  }
}

String shortPath(String p) =>
    p.replaceFirst(RegExp(r'^/(home|Users)/[^/]+'), '~');

/// A 44 tall detail line: label fg2 left, value fg1 right.
class DetailRow extends StatelessWidget {
  const DetailRow(this.label, this.value, {super.key, this.mono = false});

  final String label, value;
  final bool mono;

  @override
  Widget build(BuildContext context) => MergeSemantics(
        child: SizedBox(
          height: 44,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(children: [
              Text(label, style: sans(14, color: AppColors.fg2)),
              const SizedBox(width: 16),
              Expanded(
                child: Text(value,
                    textAlign: TextAlign.right,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: mono
                        ? codeMono(13, color: AppColors.fg1)
                        : sans(14, color: AppColors.fg1)),
              ),
            ]),
          ),
        ),
      );
}


/// Profile tile (HM-05): 56 high, radius 12, icon 24 over a 12/400 label.
class ProfileTile extends StatelessWidget {
  const ProfileTile(this.icon, this.label, {super.key, required this.onTap});
  final String icon, label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            constraints: const BoxConstraints(minHeight: 56),
            padding: const EdgeInsets.symmetric(vertical: 6),
            decoration: BoxDecoration(
                color: AppColors.surface1,
                borderRadius: BorderRadius.circular(12)),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              AppIcon(icon, size: 24, color: AppColors.fg2),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12, color: AppColors.fg2)),
            ]),
          ),
        ),
      );
}

/// Detail row (HM-05): 80 wide label at x16, value at x100, chevron at the
/// end. At 1.35x and above the label sits above the value.
class ProfileRow extends StatelessWidget {
  const ProfileRow(this.label, this.value, {super.key, this.onTap});
  final String label, value;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final stacked = bigText(context);
    final labelW = Text(label, style: sans(12, color: AppColors.fg3));
    final valueW = Text(value,
        maxLines: stacked ? 4 : 1,
        overflow: TextOverflow.ellipsis,
        style: sans(14, color: AppColors.fg1));
    return Semantics(
      button: onTap != null,
      label: '$label, $value',
      excludeSemantics: true,
      child: TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 48),
          margin: const EdgeInsets.symmetric(horizontal: 16),
          padding: const EdgeInsets.symmetric(vertical: 8),
          decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: AppColors.border, width: 1))),
          child: Row(children: [
            Expanded(
              child: stacked
                  ? Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [labelW, valueW])
                  : Row(children: [
                      SizedBox(width: 84, child: labelW),
                      Expanded(child: valueW),
                    ]),
            ),
            if (onTap != null) ...[
              const SizedBox(width: 8),
              AppIcon('chevron-right', size: 16, color: AppColors.fg3),
            ],
          ]),
        ),
      ),
    );
  }
}
