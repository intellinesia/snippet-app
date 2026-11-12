import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../crew_widgets.dart' show AgentProviderMark;
import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import '../motion.dart';
import '../mochi.dart';
import 'agent_reach_panel.dart';
import 'agent_wake_panel.dart';
import 'agent_appearance.dart';
import 'agent_profile_panel.dart';

/// One agent on the phone's Agents page, in the Mission Control card's shape:
/// who it is, whether it is working, and its task counts.
class AgentCard extends StatefulWidget {
  final DaemonClient client;
  final CoordinationAgent agent;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;
  final VoidCallback? onChanged;

  const AgentCard({
    super.key,
    required this.client,
    required this.agent,
    required this.onOpen,
    this.onDelete,
    this.onChanged,
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

  Future<void> _actions(Offset? point) async {
    final name = widget.agent.displayName.trim().isEmpty
        ? widget.agent.id
        : widget.agent.displayName.trim();
    if (kMobile) {
      showAppSheet(context,
          title: name,
          subtitle: 'Agent',
          child: SheetActions([
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

  @override
  Widget build(BuildContext context) {
    final agent = widget.agent;
    final name =
        agent.displayName.trim().isEmpty ? agent.id : agent.displayName;
    final working = _count({TaskStatus.inProgress}, {'in_progress'});
    final queued = _count({TaskStatus.todo}, {'todo'});
    final blocked =
        _count({TaskStatus.blocked, TaskStatus.failed}, {'blocked', 'failed'});
    final open = working + queued + blocked;
    final done = _count({TaskStatus.done}, {'done'});
    final profile = agent.profile;
    final last = agent.lastMessage;
    final line = last == null
        ? 'No messages yet'
        : (last.fromUser ? 'You: ${last.text}' : last.text);
    final (String, Color)? summary = !agent.available
        ? ('Paused', AppColors.fg3)
        : blocked > 0
            ? ('$blocked blocked', AppColors.danger)
            : open > 0
                ? ('$open open', AppColors.fg3)
                : done > 0
                    ? ('$done done', AppColors.fg3)
                    : null;
    final summaryText = summary?.$1 ?? '';
    final summaryColor = summary?.$2 ?? AppColors.fg4;
    final nameSize = kMobile ? 15.5 : 13.0;
    final metaSize = kMobile ? 13.0 : 11.5;
    if (kMobile) {
      final ring = agent.available && working > 0;
      final dot = !agent.available
          ? AppColors.fg4
          : blocked > 0
              ? AppColors.danger
              : null;
      return Pressable(
          kind: PressKind.row,
          child: InkWell(
            splashFactory: NoSplash.splashFactory,
            highlightColor: Colors.transparent,
            onTap: widget.onOpen,
            onLongPress: () {
              HapticFeedback.selectionClick();
              _actions(null);
            },
            child: ConstrainedBox(
              constraints: const BoxConstraints(minHeight: 68),
              child: Row(
                children: [
                  const SizedBox(width: M.gutter),
                  Opacity(
                    opacity: agent.available ? 1 : 0.5,
                    child: SizedBox.square(
                      dimension: 40,
                      child: Stack(clipBehavior: Clip.none, children: [
                        Container(
                          decoration: BoxDecoration(
                            color: AppColors.surface2,
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: AgentMochi(agent.id, size: 26),
                        ),
                        if (ring)
                          const Positioned(
                              left: -3,
                              top: -3,
                              right: -3,
                              bottom: -3,
                              child:
                                  WorkingRing(key: ValueKey('agent-working'))),
                        if (dot != null)
                          Positioned(
                            right: -1,
                            bottom: -1,
                            child: Container(
                              width: 12,
                              height: 12,
                              decoration: BoxDecoration(
                                color: dot,
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: AppColors.bg, width: 2),
                              ),
                            ),
                          ),
                      ]),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(vertical: 10),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TS.rowTitle(agent.available
                                  ? AppColors.fg1
                                  : AppColors.fg3)),
                          const SizedBox(height: 2),
                          Row(children: [
                            Flexible(
                              child: Text(line,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: TS.meta(AppColors.fg3)),
                            ),
                          ]),
                        ],
                      ),
                    ),
                  ),
                  if (summary != null || profile != null) ...[
                    const SizedBox(width: 12),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 20,
                          child: profile == null
                              ? null
                              : Center(
                                  child: AgentProviderMark(
                                      key: const ValueKey('agent-provider'),
                                      client: widget.client,
                                      profile: profile)),
                        ),
                        const SizedBox(height: 2),
                        SwapText(summary?.$1 ?? '',
                            style: TS
                                .meta(summary?.$2 ?? AppColors.fg3)
                                .copyWith(fontFeatures: const [
                              FontFeature.tabularFigures()
                            ])),
                      ],
                    ),
                  ],
                  const SizedBox(width: M.gutter),
                ],
              ),
            ),
          ));
    }
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
        borderRadius: BorderRadius.circular(8),
        child: InkWell(
          onTap: widget.onOpen,
          onLongPress: () {
            HapticFeedback.selectionClick();
            _actions(null);
          },
          borderRadius: BorderRadius.circular(8),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(8, 7, 10, 7),
            child: Row(children: [
              Opacity(
                opacity: agent.available ? 1 : 0.5,
                child: SizedBox.square(
                  dimension: 32,
                  child: Stack(clipBehavior: Clip.none, children: [
                    Container(
                      decoration: BoxDecoration(
                          color: AppColors.surface2, shape: BoxShape.circle),
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
                            style: sans(nameSize,
                                weight: W.body,
                                color: agent.available
                                    ? AppColors.fg1
                                    : AppColors.fg3)),
                      ),
                      if (profile != null) ...[
                        const SizedBox(width: 6),
                        AgentProviderMark(
                            key: const ValueKey('agent-provider'),
                            client: widget.client,
                            profile: profile,
                            size: 12),
                      ],
                    ]),
                    const SizedBox(height: 2),
                    Row(children: [
                      Expanded(
                        child: Text(line,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(metaSize, color: AppColors.fg3)),
                      ),
                      if (summary != null) ...[
                        const SizedBox(width: 8),
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

class _WorkingRingState extends State<WorkingRing>
    with SingleTickerProviderStateMixin {
  late final _spin = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1400));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _spin.stop();
    } else if (!_spin.isAnimating) {
      _spin.repeat();
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
    final track = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = color.withValues(alpha: 0.18);
    canvas.drawOval(rect, track);
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round
      ..color = color;
    canvas.drawArc(
        rect, turn.value * 2 * 3.141592653589793 - 1.5707963, 1.9, false, arc);
  }

  @override
  bool shouldRepaint(_RingPainter old) => old.color != color;
}
