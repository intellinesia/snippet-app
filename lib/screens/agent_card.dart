import 'package:flutter/material.dart';

import '../ambient_loop.dart';
import '../api.dart';
import '../clock.dart';
import '../crew_status.dart';
import '../markdown_preview.dart';
import '../models.dart';
import '../pins.dart';
import '../platform.dart';
import '../presence.dart';
import '../theme.dart';
import '../widgets.dart';
import '../motion.dart';
import '../mochi.dart';
import 'agent_reach_panel.dart';
import 'agent_wake_panel.dart';
import 'agent_appearance.dart';
import 'agent_profile_panel.dart';

/// Which section of the phone's Agents page an agent belongs to.
enum AgentGroup { needsYou, working, recent }

/// Group an agent for the phone list: waiting on the user, busy, or recent.
AgentGroup agentGroupFor(CoordinationAgent agent, {Presence? presence}) {
  final p = presence;
  final waitingYou = p != null &&
      p.state == 'waiting' &&
      (p.detail.isEmpty || p.detail == 'user');
  final blocked = agent.tasksIn({'blocked', 'failed'});
  if (agent.available && (waitingYou || blocked > 0)) {
    return AgentGroup.needsYou;
  }
  final open = agent.tasksIn({'in_progress', 'todo'});
  if (agent.available && (open > 0 || (p?.active ?? false))) {
    return AgentGroup.working;
  }
  return AgentGroup.recent;
}

final _uuidToken = RegExp(
    r'\b[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}\b');

/// Strip raw ids out of an agent's last-message text so the status line never
/// shows `group:<uuid>`, task uuids or other ids. A `group:` reference becomes
/// the group's title when known, otherwise it is dropped.
String cleanAgentStatusText(String text,
    {Map<String, String> groupTitles = const {}}) {
  var t = flattenMarkdown(text);
  t = t.replaceAllMapped(
      RegExp(r'\bgroup:([0-9A-Za-z][0-9A-Za-z-]*)', caseSensitive: false),
      (m) {
    final title = groupTitles[m[1] ?? '']?.trim() ?? '';
    return title.isEmpty ? '' : title;
  });
  t = t.replaceAll(RegExp(r'\btask\s+' + _uuidToken.pattern), '');
  t = t.replaceAll(_uuidToken, '');
  t = t
      .replaceAll(RegExp(r'\(\s*[,·]?\s*\)'), '')
      .replaceAll(RegExp(r'\(\s*,\s*'), '(')
      .replaceAll(RegExp(r'\s{2,}'), ' ')
      .replaceAll(RegExp(r'\s*·\s*'), ' · ')
      .replaceAll(RegExp(r'^[\s·\-–—:,→]+'), '')
      .replaceAll(RegExp(r'[\s·\-–—:,→]+$'), '')
      .trim();
  return t;
}

/// The readable second line under an agent's name on the phone list.
String agentStatusLine(CoordinationAgent agent,
    {Presence? presence, Map<String, String> groupTitles = const {}}) {
  final last = agent.lastMessage;
  var context = last == null
      ? ''
      : cleanAgentStatusText(last.text, groupTitles: groupTitles);
  if (last?.fromUser ?? false) {
    if (context.isNotEmpty) context = 'You: $context';
  } else if (context.endsWith('?')) {
    context = 'Asked: $context';
  }
  return switch (agentGroupFor(agent, presence: presence)) {
    AgentGroup.needsYou =>
      context.isEmpty ? 'Waiting on you' : 'Waiting on you · $context',
    AgentGroup.working => context.isEmpty ? 'Working' : context,
    AgentGroup.recent => context.isEmpty ? 'No messages yet' : context,
  };
}

/// v5 row time: 'now', clock today, weekday this week, 'd MMM' older.
String agentRowTime(DateTime? at, {DateTime? now}) {
  if (at == null) return '';
  at = at.toLocal();
  final n = (now ?? DateTime.now()).toLocal();
  if (n.difference(at) < const Duration(minutes: 1)) return 'now';
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'
  ];
  if (at.year == n.year && at.month == n.month && at.day == n.day) {
    return clock12(at);
  }
  if (n.difference(at).inDays < 7) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    return days[at.weekday - 1];
  }
  return '${at.day} ${months[at.month - 1]}';
}

/// One agent on the phone's Agents page, in the Mission Control card's shape:
/// who it is, whether it is working, and its task counts.
class AgentCard extends StatefulWidget {
  final DaemonClient client;
  final CoordinationAgent agent;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;
  final VoidCallback? onChanged;

  /// Group id → title, so `group:<id>` refs in the status line can be named.
  final Map<String, String>? groupTitles;
  final bool pinned;
  final VoidCallback? onTogglePin;

  /// Phone: the agent's sessions, for the ask or the work in its line.
  final CrewEntry? crew;

  /// Phone: the section it sits in, when the list already decided it.
  final AgentGroup? group;

  const AgentCard({
    super.key,
    required this.client,
    required this.agent,
    required this.onOpen,
    this.onDelete,
    this.onChanged,
    this.groupTitles,
    this.pinned = false,
    this.onTogglePin,
    this.crew,
    this.group,
  });

  @override
  State<AgentCard> createState() => _AgentCardState();
}

class _AgentCardState extends State<AgentCard> {
  Future<void> _pickProfile(String name, {Offset? point}) =>
      showAgentProfileSettings(
        context,
        client: widget.client,
        agent: widget.agent,
        name: name,
        point: point,
        onChanged: widget.onChanged,
      );

  String get _nicknameLabel =>
      widget.agent.nickname == null ? 'Set nickname' : 'Edit nickname';

  Future<void> _editNickname({Offset? point}) async {
    final agent = widget.agent;
    final full =
        agent.fullName.trim().isEmpty ? agent.id : agent.fullName.trim();
    final next = await promptText(context,
        title: 'Nickname for $full',
        initial: agent.nickname ?? '',
        hint: 'Leave empty to use the name',
        anchored: true,
        point: point);
    if (next == null || next == (agent.nickname ?? '') || !mounted) return;
    try {
      await widget.client
          .setAgentNickname(agent.id, next.isEmpty ? null : next);
      widget.onChanged?.call();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    }
  }

  Future<void> _openWakes(String name, Offset? point) =>
      showAgentWakeSettings(context,
          client: widget.client,
          owner: widget.agent.id,
          name: name,
          point: point,
          onChanged: widget.onChanged);

  bool get _isPinned =>
      widget.pinned ||
      Pins.instance
          .isPinned(Pins.agent, widget.agent.id, host: widget.client.baseUrl);

  void _togglePin() {
    if (widget.onTogglePin != null) {
      widget.onTogglePin!();
    } else {
      Pins.instance
          .toggle(Pins.agent, widget.agent.id, host: widget.client.baseUrl);
    }
  }

  Future<void> _actions(Offset? point) async {
    final name = widget.agent.displayName.trim().isEmpty
        ? widget.agent.id
        : widget.agent.displayName.trim();
    final pinned = _isPinned;
    if (kMobile) {
      showAppSheet(context,
          title: name,
          subtitle: 'Agent',
          child: SheetActions([
            if (!widget.agent.isMissionControl)
              SheetAction(
                pinned ? 'pin-off' : 'pin',
                pinned ? 'Unpin' : 'Pin',
                () {
                  Navigator.pop(context);
                  _togglePin();
                },
                detail: pinned
                    ? 'Remove from the top of the list'
                    : 'Keep at the top of the list',
              ),
            if (!widget.agent.isMissionControl)
              SheetAction('edit', _nicknameLabel, () {
                Navigator.pop(context);
                _editNickname();
              }, detail: 'What it is called here'),
            SheetAction('sparkles', 'Appearance', () {
              Navigator.pop(context);
              showAgentAppearance(
                  context, widget.client, widget.agent.id, name);
            }, detail: 'Avatar and colour across the app'),
            if (!widget.agent.isMissionControl)
              SheetAction('calendar-clock', 'Wakes and reporting', () {
                Navigator.pop(context);
                _openWakes(name, null);
              }, detail: 'When it wakes and where it reports'),
            if (!widget.agent.isMissionControl)
              SheetAction('cpu', 'Change inference profile', () {
                Navigator.pop(context);
                _pickProfile(name);
              }, detail: 'The model it runs on'),
            if (widget.onDelete != null)
              SheetAction('trash', 'Delete agent', () {
                Navigator.pop(context);
                widget.onDelete?.call();
              },
                  danger: true,
                  detail: 'Remove the agent, its identity and notes'),
          ]));
      return;
    }
    final picked = await showAppMenu<String>(
      context,
      point: point,
      anchor: point == null ? context : null,
      items: [
        if (!widget.agent.isMissionControl)
          appMenuItem(
              value: 'pin',
              icon: pinned ? 'pin-off' : 'pin',
              label: pinned ? 'Unpin' : 'Pin'),
        if (!widget.agent.isMissionControl)
          appMenuItem(value: 'nickname', icon: 'edit', label: _nicknameLabel),
        appMenuItem(value: 'appearance', icon: 'sparkles', label: 'Appearance'),
        if (!widget.agent.isMissionControl)
          appMenuItem(
              value: 'model', icon: 'cpu', label: 'Change inference profile'),
        if (!widget.agent.isMissionControl)
          appMenuItem(
              value: 'wakes',
              icon: 'calendar-clock',
              label: 'Wakes and reporting'),
        appMenuItem(value: 'reach', icon: 'bell', label: 'How it reaches you'),
        if (widget.onDelete != null)
          appMenuItem(
              value: 'delete',
              icon: 'trash',
              label: 'Delete agent',
              danger: true),
      ],
    );
    if (picked == 'pin') _togglePin();
    if (picked == 'delete') widget.onDelete?.call();
    if (picked == 'nickname' && mounted) _editNickname(point: point);
    if (picked == 'wakes' && mounted) _openWakes(name, point);
    if (picked == 'reach' && mounted) {
      showAgentReachSettings(context,
          client: widget.client,
          agentId: widget.agent.id,
          name: name,
          point: point);
    }
    if (picked == 'model' && mounted) _pickProfile(name, point: point);
    if (picked == 'appearance' && mounted) {
      showAgentAppearance(context, widget.client, widget.agent.id, name,
          point: point);
    }
  }

  List<TaskItem> _tasks = const [];

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(AgentCard old) {
    super.didUpdateWidget(old);
    if (old.client != widget.client || old.agent.id != widget.agent.id) _load();
  }

  Future<void> _load() async {
    if (widget.agent.taskCounts != null) return;
    final id = widget.agent.id;
    try {
      final tasks = await widget.client.tasks(agentId: id, limit: 100);
      if (mounted) setState(() => _tasks = tasks);
    } catch (_) {}
  }

  int _count(Set<TaskStatus> statuses, Set<String> keys) =>
      widget.agent.taskCounts != null
          ? widget.agent.tasksIn(keys)
          : _tasks.where((t) => statuses.contains(t.status)).length;

  /// The ask, else the session it works in, else the last message.
  String _phoneLine(
      CoordinationAgent agent, CrewEntry? crew, Presence? presence) {
    final titles = widget.groupTitles ?? const {};
    if (crew != null && crew.state != CrewState.standingBy) {
      final text = cleanAgentStatusText(crew.line, groupTitles: titles);
      if (crew.state == CrewState.working) return text;
      final kind = crew.attention?['type'];
      return kind == 'approval'
          ? 'Approval: $text'
          : kind == 'question'
              ? 'Asked: $text'
              : 'Waiting on you · $text';
    }
    final line =
        agentStatusLine(agent, presence: presence, groupTitles: titles);
    if (line == 'No messages yet' && crew?.lead != null) {
      return cleanAgentStatusText(crew!.line, groupTitles: titles);
    }
    return line;
  }

  @override
  Widget build(BuildContext context) {
    final agent = widget.agent;
    final name =
        agent.displayName.trim().isEmpty ? agent.id : agent.displayName;
    final working = _count({TaskStatus.inProgress}, {'in_progress'});
    final blocked =
        _count({TaskStatus.blocked, TaskStatus.failed}, {'blocked', 'failed'});
    final last = agent.lastMessage;
    final line = last == null
        ? 'No messages yet'
        : (last.fromUser ? 'You: ${last.text}' : last.text);
    final (String, Color)? summary = !agent.available
        ? ('Paused', AppColors.fg3)
        : blocked > 0
            ? ('$blocked blocked', AppColors.danger)
            : null;
    final summaryText = summary?.$1 ?? '';
    final summaryColor = summary?.$2 ?? AppColors.fg4;
    final nameSize = kMobile ? 15.5 : 13.0;
    final metaSize = kMobile ? 13.0 : 11.5;
    if (kMobile) {
      final presence = widget.client.presence.presenceForAgentId(agent.id);
      final crew = widget.crew;
      final group = widget.group ?? agentGroupFor(agent, presence: presence);
      final status = _phoneLine(agent, crew, presence);
      final lead = crew?.lead;
      final time = crew != null && crew.state != CrewState.standingBy && lead != null
          ? agentRowTime(
              DateTime.fromMillisecondsSinceEpoch(lead.lastActive * 1000))
          : agentRowTime(agent.lastMessage?.at);
      final needs = group == AgentGroup.needsYou;
      final busy = group == AgentGroup.working;
      final characterState = !agent.available
          ? AgentCharacterState.sleeping
          : needs
              ? AgentCharacterState.needs
              : busy
                  ? AgentCharacterState.working
                  : AgentCharacterState.sleeping;
      final plan = busy ? lead?.plan : null;
      final hasPlan = plan != null && plan.total > 0;
      final step = hasPlan ? (plan.done + 1).clamp(1, plan.total) : 0;
      final sub = [
        status,
        if (hasPlan && !status.contains(' of ${plan.total}'))
          'plan $step of ${plan.total}',
      ].join(' · ');
      final subStyle = TeamRow.subtitleStyle();
      return TeamRow(
        tall: hasPlan,
        onTap: () {
          tapHaptic();
          widget.onOpen();
        },
        onLongPress: () {
          holdHaptic();
          _actions(null);
        },
        child: Opacity(
          opacity: agent.available ? 1 : 0.55,
          child: Row(children: [
            SizedBox.square(
              key: ValueKey('agent-avatar-${characterState.name}'),
              dimension: 40,
              child: AgentMochi(agent.id,
                  size: 40, state: characterState, badge: needs ? '?' : null),
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
                          style: TeamRow.titleStyle(agent.available
                              ? AppColors.fg1
                              : AppColors.fg3)),
                    ),
                    if (_isPinned) ...[
                      SizedBox(width: S.s6),
                      AppIcon('pin', size: 14, color: AppColors.fg3),
                    ],
                  ]),
                  SizedBox(height: S.of(1)),
                  Row(children: [
                    if (busy) ...[
                      Container(
                        key: const ValueKey('agent-working-dot'),
                        width: 7,
                        height: 7,
                        decoration: BoxDecoration(
                          color: AppColors.accent,
                          shape: BoxShape.circle,
                        ),
                      ),
                      SizedBox(width: S.of(7)),
                    ],
                    Flexible(
                      child: Text.rich(markdownPreviewSpan(sub, subStyle),
                          maxLines: 1, overflow: TextOverflow.ellipsis),
                    ),
                    if (time.isNotEmpty && !busy)
                      Text(', $time', maxLines: 1, style: subStyle),
                  ]),
                  if (hasPlan) ...[
                    SizedBox(height: S.s6),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(2),
                      child: SizedBox(
                        height: 3,
                        child: LinearProgressIndicator(
                          key: const ValueKey('agent-plan-bar'),
                          value: (plan.done / plan.total).clamp(0.0, 1.0),
                          backgroundColor: AppColors.surface1,
                          color: AppColors.accent,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            SizedBox(width: S.s8),
            AppIcon('chevron-right', size: 16, color: AppColors.fg4),
          ]),
        ),
      );
    }
    final deskTime = agentRowTime(last?.at);
    final ring = agent.available && working > 0;
    final dot = !agent.available
        ? AppColors.fg4
        : blocked > 0
            ? AppColors.danger
            : null;
    return GestureDetector(
      onSecondaryTapUp: (d) => _actions(d.globalPosition),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(R.md),
        child: InkWell(
          onTap: widget.onOpen,
          onLongPress: () {
            holdHaptic();
            _actions(null);
          },
          borderRadius: BorderRadius.circular(R.md),
          child: Padding(
            padding: EdgeInsets.fromLTRB(S.s8, S.of(7), S.of(10), S.of(7)),
            child: Row(children: [
              Opacity(
                opacity: agent.available ? 1 : 0.5,
                child: SizedBox.square(
                  dimension: 32,
                  child: Stack(clipBehavior: Clip.none, children: [
                    Container(
                      decoration:
                          avatarDecoration(32, color: AppColors.surface2),
                      alignment: Alignment.center,
                      child: AgentMochi(agent.id, size: 20),
                    ),
                    if (ring)
                      const Positioned(
                          left: -3,
                          top: -3,
                          right: -3,
                          bottom: -3,
                          child: WorkingRing(key: ValueKey('agent-working'))),
                    if (dot != null)
                      Positioned(
                        right: -1,
                        bottom: -1,
                        child: Container(
                          width: 10,
                          height: 10,
                          decoration: BoxDecoration(
                            color: dot,
                            shape: BoxShape.circle,
                            border:
                                Border.all(color: AppColors.windowBg, width: 2),
                          ),
                        ),
                      ),
                  ]),
                ),
              ),
              SizedBox(width: S.of(10)),
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
                            style: sans(nameSize,
                                weight: W.body,
                                color: agent.available
                                    ? AppColors.fg1
                                    : AppColors.fg3)),
                      ),
                      if (_isPinned) ...[
                        SizedBox(width: S.s6),
                        AppIcon('pin', size: 11, color: AppColors.fg3),
                      ],
                      if (deskTime.isNotEmpty) ...[
                        SizedBox(width: S.s6),
                        Text(deskTime,
                            style: sans(metaSize,
                                color: AppColors.fg4, tabular: true)),
                      ],
                    ]),
                    SizedBox(height: S.s2),
                    Row(children: [
                      Expanded(
                        child: Text.rich(
                            markdownPreviewSpan(
                                line, sans(metaSize, color: AppColors.fg3)),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis),
                      ),
                      if (summary != null) ...[
                        SizedBox(width: S.s8),
                        SwapText(summaryText,
                            style: sans(metaSize,
                                color: summaryColor, tabular: true)),
                      ],
                    ]),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// A short accent arc turning round an avatar while its agent works.
class WorkingRing extends StatefulWidget {
  const WorkingRing({super.key});

  @override
  State<WorkingRing> createState() => _WorkingRingState();
}

class _WorkingRingState extends State<WorkingRing> {
  final _spin = AmbientLoop(const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _spin.bind(context);
    if (reduceMotion(context)) {
      _spin.stop();
    } else {
      _spin.start();
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: CustomPaint(
          painter: _RingPainter(_spin, AppColors.accent),
        ),
      );
}

class _RingPainter extends CustomPainter {
  _RingPainter(this.turn, this.color) : super(repaint: turn);

  final Animation<double> turn;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = (Offset.zero & size).deflate(1);
    final outline = avatarBorder(rect.width).getOuterPath(rect);
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color.withValues(alpha: 0.18);
    canvas.drawPath(outline, track);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = color;
    // Same sweep as the old 1.9 rad arc, traced along whatever outline the theme uses.
    final metric = outline.computeMetrics().first;
    final len = metric.length;
    final start = turn.value * len;
    final end = start + len * 1.9 / (2 * 3.141592653589793);
    canvas.drawPath(metric.extractPath(start, end.clamp(0, len)), arc);
    if (end > len) canvas.drawPath(metric.extractPath(0, end - len), arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.color != color;
}

/// Phone grouped rows: each row its own surface on the page, 2px apart, the
/// group rounded 20 at its ends and 4 inside.
class TeamRows extends StatelessWidget {
  const TeamRows({super.key, required this.children});

  final List<Widget> children;

  static const ends = 20.0;
  static const inner = 4.0;

  @override
  Widget build(BuildContext context) {
    final n = children.length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < n; i++) ...[
          if (i > 0) const SizedBox(height: 2),
          ClipRRect(
            borderRadius: BorderRadius.vertical(
              top: Radius.circular(i == 0 ? ends : inner),
              bottom: Radius.circular(i == n - 1 ? ends : inner),
            ),
            child: ColoredBox(color: TeamRow.surface, child: children[i]),
          ),
        ],
      ],
    );
  }
}

/// One row inside [TeamRows]: min 64 (76 when tall), padding 12/16.
class TeamRow extends StatelessWidget {
  const TeamRow({
    super.key,
    required this.child,
    this.onTap,
    this.onLongPress,
    this.tall = false,
  });

  final Widget child;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool tall;

  static Color get surface => AppColors.surface3;

  static TextStyle titleStyle([Color? c]) =>
      sans(17, height: 22 / 17, color: c ?? AppColors.fg1);

  static TextStyle subtitleStyle([Color? c]) =>
      sans(15, height: 20 / 15, color: c ?? AppColors.fg3);

  @override
  Widget build(BuildContext context) => Material(
        type: MaterialType.transparency,
        child: InkWell(
          splashFactory: NoSplash.splashFactory,
          highlightColor: AppColors.hover,
          onTap: onTap,
          onLongPress: onLongPress,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: tall ? 76 : 64),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Align(alignment: Alignment.centerLeft, child: child),
            ),
          ),
        ),
      );
}
