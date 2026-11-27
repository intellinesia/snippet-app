import 'dart:async';
import 'dart:math' show max;

import 'package:flutter/material.dart';

import '../api.dart';
import '../glass.dart' show StatusInset;
import '../chat/agent_cluster.dart' show GroupGlyph;
import '../chat/signal_row.dart' show prettyModel;
import '../mobile_kit.dart';
import '../mochi.dart';
import '../models.dart';
import '../tap_detector.dart';
import '../theme.dart';
import '../widgets.dart';
import 'agent_profile_panel.dart';
import 'mobile_home/agent_context_phone.dart';
import 'mobile_home/wake_reach_phone.dart';
import 'mobile_home/agents_home.dart';
import 'agent_profile_sheet.dart';
import 'group_messaging.dart' show openGroupThread, groupMemberName;
import 'lead/coordination_agent_detail.dart';
import 'session_list_row.dart' show projectLabel, sessionNeedsYou;
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
  if (s.settled) return 'Completed';
  return 'Idle';
}

/// Kit state mark for a session row: amber dot, morph, or a tick.
Widget sessionStateMark(SessionInfo s, {double size = 22}) =>
    switch (sessionStateWord(s)) {
      'Needs you' => MkStateMark(MkState.needsYou, size: size),
      'Working' => MkStateMark(MkState.working, size: size),
      _ => MkStateMark(MkState.done, size: size),
    };

class _PhoneAgentPageState extends State<PhoneAgentPage> {
  bool _chat = false;
  bool _busy = false;
  bool _scrolled = false;
  int _wakeCount = 0;
  bool? _paused;
  Map<String, InferenceProfile> _profiles = const {};
  List<GroupSummary> _groups = const [];
  Map<String, CoordinationAgent> _agents = const {};
  int? _memory;
  String? _reach;

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
      setState(() => _wakeCount = mine.length);
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
  String get _name => a.shortName.trim().isEmpty ? a.id : a.shortName.trim();
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

  void _openContext(int tab) =>
      unawaited(Navigator.of(context).push(MaterialPageRoute(
          builder: (_) => AgentContextPage(
              client: widget.client,
              agent: a,
              sessions: widget.sessions,
              initialTab: tab,
              onOpenSession: widget.onOpenSession))));

  void _openWake() => unawaited(Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          PhoneWakePage(client: widget.client, owner: a.id, name: _name))));

  void _openReach() => unawaited(Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          PhoneReachPage(client: widget.client, agentId: a.id, name: _name))));

  Future<void> _more() async {
    Widget tile(String v, String icon, String label) => Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: MkSheetTile(
              icon: icon,
              label: label,
              onTap: () => Navigator.of(context).pop(v)),
        );
    final pick = await showMkSheet<String>(context,
        builder: (_) => Column(mainAxisSize: MainAxisSize.min, children: [
              tile('model', 'sliders', 'Model'),
              tile('pause', _isPaused ? 'play' : 'pause',
                  _isPaused ? 'Resume' : 'Pause'),
              tile('rename', 'edit', 'Rename'),
              tile('delete', 'trash', 'Delete'),
            ]));
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
      return StatusInset.reclaim(
          context,
          CoordinationAgentDetail(
            key: const ValueKey('agent-detail'),
            agent: a,
            client: widget.client,
            embedded: false,
            onClose: () => setState(() => _chat = false),
          ));
    }
    final an = kAndroidLook;
    final mq = MediaQuery.of(context);
    final mine = _mine;
    final ask = mine.where(sessionNeedsYou).firstOrNull;
    final active = [
      for (final s in mine)
        if (const {'Working', 'Needs you'}.contains(sessionStateWord(s))) s
    ];
    final recent = [
      for (final s in mine)
        if (!active.contains(s)) s
    ];
    final shown = [
      ...active,
      ...recent.take((3 - active.length).clamp(0, 3)),
    ];
    final profile = a.deskProfile ?? a.profile;
    final model = (_profiles[profile ?? '']?.model ?? '').trim();
    final live = _isPaused ? null : active.firstOrNull;
    final statusWord = _isPaused
        ? 'Paused'
        : live == null
            ? 'Idle'
            : sessionStateWord(live);
    final since = live != null
        ? relativeTime(live.runningSince ?? live.lastActive)
        : _isPaused || mine.isEmpty
            ? ''
            : relativeTime(mine.first.lastActive);
    final status =
        [statusWord.toLowerCase(), if (since.isNotEmpty) since].join(' ');
    final role = a.role.trim().isNotEmpty ? a.role.trim() : a.nameRole;
    final needs = statusWord == 'Needs you';
    final modelValue = model.isNotEmpty
        ? prettyModel(model)
        // Board: a profile reads as its own name ("swe-2.1").
        : (profile ?? '').isNotEmpty
            ? profile!
            : 'Default';
    final notes = _memory ?? 0;
    final wakes = _wakeCount;
    final inbox = mine.where(sessionNeedsYou).length;
    final barH = an ? 64.0 : 56.0;
    // Board: the Message button sits 22 above the Android inset, the ask bar
    // 26 off the iPhone edge. Measured from the screen, so add back what the
    // host's SafeArea consumed; the header lifts like the chat header.
    final eaten = StatusInset.bottomOf(context);
    final rawBottom = mq.padding.bottom + eaten;
    final bottom = (an ? rawBottom + 22 : max(26.0, rawBottom - 8)) - eaten;
    const lift = mkChatHeaderLift;

    final hero = an
        ? Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Row(children: [
              AgentMochi(a.id, size: 72),
              const SizedBox(width: 16),
              Expanded(child: _heroText(role, status, needs, false)),
            ]),
          )
        : Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
            child: Column(children: [
              AgentMochi(a.id, size: 96),
              const SizedBox(height: 8),
              _heroText(role, status, needs, true),
            ]),
          );

    final views = MkFilterGroup<String>(
      padding: EdgeInsets.fromLTRB(an ? 16 : 20, an ? 14 : 16, an ? 16 : 20, 0),
      options: [
        const MkFilter('chat', 'Chat'),
        MkFilter('inbox', 'Inbox', count: inbox == 0 ? null : inbox),
        const MkFilter('board', 'Board'),
        const MkFilter('desk', 'Desk'),
      ],
      selected: 'chat',
      onSelect: (v) => switch (v) {
        'chat' => setState(() => _chat = true),
        'inbox' => widget.onAllSessions(),
        'board' => _openContext(2),
        _ => _openContext(0),
      },
    );

    final about = an
        ? MkList(children: [
            _aboutRow(
                'brain',
                'Memory',
                '$notes ${notes == 1 ? 'note' : 'notes'}',
                () => _openContext(3)),
            _aboutRow('repeat', 'Wakes',
                wakes == 0 ? 'None scheduled' : '$wakes scheduled', _openWake),
            if (_reach != null && _reach!.isNotEmpty)
              _aboutRow('bell', 'Reach', _reach!, _openReach),
          ])
        : MkGroup(children: [
            MkGroupRow(
                icon: 'brain',
                label: 'Memory',
                value: '$notes ${notes == 1 ? 'note' : 'notes'}',
                onTap: () => _openContext(3)),
            MkGroupRow(
                icon: 'repeat',
                label: 'Wakes',
                value: wakes == 0 ? 'None' : '$wakes',
                onTap: _openWake),
            MkGroupRow(
                icon: 'cpu',
                label: 'Model',
                value: modelValue,
                onTap: () => showAgentProfileSettings(context,
                    client: widget.client, agent: a, name: _name)),
            if (_reach != null && _reach!.isNotEmpty)
              MkGroupRow(
                  icon: 'bell',
                  label: 'Reach',
                  value: _reach!,
                  onTap: _openReach),
          ]);

    final list = NotificationListener<ScrollNotification>(
      onNotification: (n) {
        if (n.depth == 0 && n.metrics.axis == Axis.vertical) {
          final s = n.metrics.pixels > 8;
          if (s != _scrolled) setState(() => _scrolled = s);
        }
        return false;
      },
      child: ListView(
        padding: EdgeInsets.only(
            top: mq.padding.top + barH - lift, bottom: bottom + 56 + 24),
        children: [
          hero,
          // The group's 4 px hit margin should not push the next section down.
          SizedBox(
            height: (an ? 14 : 16) + 40,
            child: OverflowBox(
                alignment: Alignment.topCenter,
                maxHeight: (an ? 14 : 16) + 44,
                child: views),
          ),
          if (ask != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
              child: _askCard(ask),
            ),
          if (shown.isNotEmpty) ...[
            MkSection('Sessions',
                trailing: mine.length > shown.length ? 'See all' : null,
                onTrailing: widget.onAllSessions),
            MkList(children: [
              for (var i = 0; i < shown.length; i++)
                _sessionRow(shown[i], last: i == shown.length - 1),
            ]),
          ],
          if (an)
            const MkSection('About')
          else
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 20, 20, 0),
              child: Semantics(
                  header: true,
                  child: Text('About', style: sans(13, color: AppColors.fg3))),
            ),
          about,
          if (_groups.isNotEmpty) ...[
            const MkSection('Groups'),
            MkList(children: [
              for (var i = 0; i < _groups.length; i++)
                MkRow(
                  title: _groups[i].title.isEmpty ? 'Group' : _groups[i].title,
                  subtitle: _memberLine(_groups[i]),
                  leading: GroupGlyph(
                      size: 32,
                      ids: _groups[i].agentIds,
                      count: _groups[i].members.length),
                  divider: i < _groups.length - 1,
                  onTap: () => openGroupThread(context,
                      client: widget.client, group: _groups[i]),
                ),
            ]),
          ],
        ],
      ),
    );

    final eatenTop = mq.padding.top > 0 ? 0.0 : StatusInset.of(context);
    final bar = Positioned(
      left: 0,
      right: 0,
      // Reach up behind a status bar the host SafeArea consumed so the
      // tonal fill covers it too.
      top: -lift - eatenTop,
      height: mq.padding.top + eatenTop + barH,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 160),
        color: an && _scrolled ? AppColors.surface2 : Colors.transparent,
        padding: EdgeInsets.fromLTRB(
            an ? 4 : 14, mq.padding.top + eatenTop, an ? 4 : 14, 0),
        child: Row(children: [
          MkIconButton(
              icon: an ? 'arrow-left' : 'chevron-left',
              label: 'Back',
              size: an ? null : 44,
              onTap: widget.onClose),
          const Spacer(),
          MkIconButton(
              icon: an ? 'more-vertical' : 'more-horizontal',
              label: 'More',
              size: an ? null : 44,
              onTap: _more),
        ]),
      ),
    );

    final cta = an
        ? Positioned(right: 16, bottom: bottom, child: _messageFab())
        : Positioned(left: 12, right: 12, bottom: bottom, child: _askBar());

    return Material(
      color: AppColors.bg,
      // The bar lifts and the ask bar dips past the page box, by design.
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(child: list),
        bar,
        cta,
      ]),
    );
  }

  Widget _heroText(String role, String status, bool needs, bool centre) {
    final nameW = Text(_name,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        textAlign: centre ? TextAlign.center : TextAlign.start,
        style: sans(24, weight: FontWeight.w600, color: AppColors.fg1));
    final sub = Text.rich(
      TextSpan(children: [
        if (role.isNotEmpty) TextSpan(text: '$role · '),
        TextSpan(
            text: status,
            style: needs ? sans(13.5, weight: W.label, color: MK.amber) : null),
      ]),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: centre ? TextAlign.center : TextAlign.start,
      style: sans(13.5, color: AppColors.fg3),
    );
    return Column(
      crossAxisAlignment:
          centre ? CrossAxisAlignment.center : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [nameW, const SizedBox(height: 2), sub],
    );
  }

  Widget _sessionRow(SessionInfo s, {required bool last}) {
    final word = sessionStateWord(s);
    final branch = (s.branch ?? '').trim();
    final base = branch.isNotEmpty ? branch : projectLabel(s);
    final Widget sub = switch (word) {
      'Needs you' => Text('Needs you',
          style: sans(13.5, weight: W.label, color: AppColors.fg2)),
      'Working' => Text(
          'working · ${relativeTime(s.runningSince ?? s.lastActive)}',
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: mkRowSub()),
      'Completed' => Text('Completed', style: mkRowSub()),
      _ => Text.rich(
          TextSpan(children: [
            TextSpan(text: base, style: mkMonoSub()),
            const TextSpan(text: ' · idle'),
          ]),
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: mkRowSub()),
    };
    return MkRow(
      title: s.title.isEmpty ? 'Untitled session' : s.title,
      subtitleWidget: sub,
      time: relativeTime(s.lastActive),
      leading: sessionStateMark(s),
      divider: !last,
      onTap: () => widget.onOpenSession(s),
    );
  }

  Widget _aboutRow(
          String icon, String label, String value, VoidCallback onTap) =>
      MkRow(
        title: label,
        subtitle: value,
        leading: AppIcon(icon, size: 22, color: AppColors.fg2),
        onTap: onTap,
      );

  Widget _messageFab() => Semantics(
        button: true,
        label: 'Message',
        excludeSemantics: true,
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _chat = true),
          child: Container(
            height: 56,
            padding: const EdgeInsets.fromLTRB(16, 0, 20, 0),
            decoration: BoxDecoration(
              color: AppColors.fg1,
              borderRadius: BorderRadius.circular(16),
              boxShadow: const [
                BoxShadow(
                    color: Color(0x66000000),
                    blurRadius: 18,
                    offset: Offset(0, 6)),
              ],
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              AppIcon('sessions', size: 20, color: MK.onPrimary),
              const SizedBox(width: 10),
              Text('Message',
                  style: sans(15, weight: W.label, color: MK.onPrimary)),
            ]),
          ),
        ),
      );

  // A stand-in for the composer: tapping it opens the chat with this agent.
  Widget _askBar() {
    Widget circ(String icon, {bool send = false}) => Container(
          width: 44,
          height: 44,
          decoration: send
              ? BoxDecoration(color: AppColors.surface3, shape: BoxShape.circle)
              : null,
          child: Center(
              child: AppIcon(icon,
                  size: send ? 19 : 21,
                  color: send ? AppColors.fg3 : AppColors.fg2)),
        );
    return Semantics(
      button: true,
      label: 'Ask $_name',
      excludeSemantics: true,
      child: TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => setState(() => _chat = true),
        child: MkGlass(
          radius: 28,
          child: SizedBox(
            height: 56,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 6),
              child: Row(children: [
                circ('plus'),
                const SizedBox(width: 4),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(left: 6),
                    child: Text('Ask $_name…',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(15.5, color: AppColors.fg3)),
                  ),
                ),
                const SizedBox(width: 4),
                circ('mic'),
                const SizedBox(width: 4),
                circ('arrow-up', send: true),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  String _memberLine(GroupSummary g) {
    final names = [
      for (final m in g.members)
        if (!m.isHuman) shortAgentName(groupMemberName(m, _agents))
    ];
    final human = g.members.any((m) => m.isHuman);
    if (names.isEmpty) return '${g.members.length} members';
    if (!human) return names.join(', ');
    return '${names.join(', ')} and you';
  }

  Widget _askCard(SessionInfo s) {
    final text = '${s.attention?['text'] ?? ''}'.trim();
    final approval =
        s.attention?['type'] == 'approval' && widget.onDecide != null;
    return MkAskCard(
      avatar: AgentMochi(a.id, size: 28),
      who: _name,
      question: text.isEmpty ? s.title : text,
      time: relativeTime(s.lastActive),
      primary: approval ? 'Approve' : 'Open',
      secondary: approval ? 'Reply' : null,
      onPrimary: !approval
          ? () => widget.onOpenSession(s)
          : _busy
              ? null
              : () async {
                  setState(() => _busy = true);
                  await widget.onDecide!(s, true);
                  if (mounted) setState(() => _busy = false);
                },
      onSecondary: () => widget.onOpenSession(s),
      onOpen: () => widget.onOpenSession(s),
    );
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
