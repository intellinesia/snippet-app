import 'dart:async';

import 'package:flutter/material.dart';

import '../api.dart';
import '../chat/agent_cluster.dart' show GroupGlyph;
import '../chat/chat_card.dart';
import '../chat/signal_row.dart' show profileMeta, prettyModel;
import '../mochi.dart';
import '../models.dart';
import '../quiet.dart';
import '../tap_detector.dart';
import '../theme.dart';
import '../widgets.dart';
import 'agent_profile_panel.dart';
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
    widget.client.coordinationAgents().then((all) {
      if (mounted) setState(() => _agents = {for (final x in all) x.id: x});
    }).catchError((_) {});
  }

  CoordinationAgent get a => widget.agent;
  String get _name =>
      a.displayName.trim().isEmpty ? a.id : a.displayName.trim();
  String get _handle => a.fullName.trim().isEmpty ? a.id : a.fullName.trim();
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
    final meta = profileMeta(_profiles, profile);
    final model = (_profiles[profile ?? '']?.model ?? '').trim();
    final folder = mine
            .map((s) => s.projectFolder.trim())
            .where((f) => f.isNotEmpty)
            .firstOrNull ??
        '';
    final live = _isPaused ? null : active.firstOrNull;
    Widget sessionRow(SessionInfo s) => QuietRow(
          title: s.title.isEmpty ? 'Untitled session' : s.title,
          sub: [sessionStateWord(s), relativeTime(s.lastActive)]
              .where((x) => x.isNotEmpty)
              .join(' · '),
          leading: sessionStateMark(s),
          trailing: AppIcon('chevron-right', size: 16, color: AppColors.fg3),
          onTap: () => widget.onOpenSession(s),
        );
    return Material(
      color: AppColors.bg,
      child: SafeArea(
        child: ListView(
          padding: const EdgeInsets.only(bottom: 32),
          children: [
            Row(children: [
              IconBtn('chevron-left',
                  size: 48, iconSize: 22, tooltip: 'Back', onTap: widget.onClose),
              const Spacer(),
              IconBtn('more-horizontal',
                  size: 48, iconSize: 20, tooltip: 'More', onTap: _openProfile),
            ]),
            // Identity: the whole block opens the profile sheet.
            Semantics(
              button: true,
              label: '$_name, $_handle, profile',
              excludeSemantics: true,
              child: TapDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _openProfile,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                  child: Row(children: [
                    ClipRRect(
                        borderRadius: BorderRadius.circular(R.of(18)),
                        child: AgentMochi(a.id, size: 64)),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(children: [
                              Flexible(
                                child: Text(_name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: sans(22,
                                        weight: W.label, color: AppColors.fg1)),
                              ),
                              const SizedBox(width: 4),
                              AppIcon('chevron-right',
                                  size: 16, color: AppColors.fg3),
                            ]),
                            const SizedBox(height: 2),
                            Text(_handle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: sans(13, color: AppColors.fg2)),
                          ]),
                    ),
                  ]),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: _StatusLine(
                word: _isPaused
                    ? 'Paused'
                    : live == null
                        ? 'Idle'
                        : sessionStateWord(live),
                detail: live?.title,
                time: live != null
                    ? relativeTime(live.runningSince ?? live.lastActive)
                    : mine.isEmpty
                        ? ''
                        : relativeTime(mine.first.lastActive),
                mark: live == null ? null : sessionStateMark(live),
                onTap: live == null ? null : () => widget.onOpenSession(live),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: Row(children: [
                Expanded(
                    child: _Action('chat', 'Message',
                        primary: true,
                        onTap: () => setState(() => _chat = true))),
                const SizedBox(width: 8),
                Expanded(
                    child: _Action('sliders', 'Model',
                        onTap: () => showAgentProfileSettings(context,
                            client: widget.client, agent: a, name: _name))),
                const SizedBox(width: 8),
                Expanded(
                    child: _Action(_isPaused ? 'play' : 'pause',
                        _isPaused ? 'Resume' : 'Pause',
                        onTap: _togglePause)),
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
                trailing:
                    AppIcon('chevron-right', size: 16, color: AppColors.fg3),
                onTap: widget.onAllSessions,
              ),
            const QuietSectionLabel('Details'),
            if (model.isNotEmpty)
              DetailRow('Model', prettyModel(model))
            else if ((meta.provider ?? '').isNotEmpty)
              DetailRow('Model', meta.provider!),
            DetailRow('Machine', _machine),
            if (folder.isNotEmpty) DetailRow('Workspace', shortPath(folder)),
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

/// The agent's live line on s1: mark, state word, the task, elapsed time.
class _StatusLine extends StatelessWidget {
  const _StatusLine(
      {required this.word, this.detail, this.time = '', this.mark, this.onTap});

  final String word;
  final String? detail;
  final String time;
  final Widget? mark;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: onTap != null,
        label: [
          word,
          if (detail != null && detail!.isNotEmpty) detail!,
          if (time.isNotEmpty) time
        ].join(', '),
        excludeSemantics: true,
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
                color: AppColors.surface1,
                borderRadius: BorderRadius.circular(R.of(12))),
            child: Row(children: [
              if (mark != null) ...[mark!, const SizedBox(width: 6)],
              Text(word, style: sans(14, weight: W.label, color: AppColors.fg1)),
              if (detail != null && detail!.isNotEmpty) ...[
                const SizedBox(width: 6),
                Expanded(
                  child: Text(detail!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(14, color: AppColors.fg2)),
                ),
              ] else
                const Spacer(),
              if (time.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(time,
                    style: sans(13, color: AppColors.fg3, tabular: true)),
              ],
            ]),
          ),
        ),
      );
}

/// One of the three quick actions: 44 tall, an icon and a word.
class _Action extends StatelessWidget {
  const _Action(this.icon, this.label,
      {required this.onTap, this.primary = false});

  final String icon, label;
  final bool primary;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final fg = primary ? AppColors.accentFg : AppColors.fg1;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Padding(
          // 44 visible, 48 to touch.
          padding: const EdgeInsets.symmetric(vertical: 2),
          child: Container(
            height: 44,
            decoration: BoxDecoration(
              color: primary ? AppColors.accentFill : AppColors.surface2,
              borderRadius: BorderRadius.circular(999),
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              AppIcon(icon, size: 16, color: fg),
              const SizedBox(width: 6),
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(14, weight: W.label, color: fg)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

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
