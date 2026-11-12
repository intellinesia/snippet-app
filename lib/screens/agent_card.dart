import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api.dart';
import '../models.dart';
import '../platform.dart';
import '../presence.dart';
import '../theme.dart';
import '../widgets.dart';
import '../mochi.dart';
import 'agent_reach_panel.dart';
import 'agent_wake_panel.dart';
import 'agent_appearance.dart';
import 'agent_profile_panel.dart';

/// One agent as a roster row: Mochi with a presence ring, name, time and a
/// two-line preview (what it is doing, else its last message).
class AgentCard extends StatefulWidget {
  final DaemonClient client;
  final CoordinationAgent agent;
  final VoidCallback onOpen;
  final VoidCallback? onDelete;
  final VoidCallback? onChanged;

  /// Unread direct messages; shows the dot left of the avatar.
  final int unread;

  /// Desktop only: the open agent's row sits on a grey selected surface.
  final bool selected;

  const AgentCard({
    super.key,
    required this.client,
    required this.agent,
    required this.onOpen,
    this.onDelete,
    this.onChanged,
    this.unread = 0,
    this.selected = false,
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

  @override
  Widget build(BuildContext context) {
    final agent = widget.agent;
    final name =
        agent.displayName.trim().isEmpty ? agent.id : agent.displayName;
    return ListenableBuilder(
      listenable: widget.client.presence,
      builder: (context, _) => _row(context, name),
    );
  }

  Widget _row(BuildContext context, String name) {
    final agent = widget.agent;
    final p = agentRosterPresence(agent, widget.client.presence);
    final ringColor = agentPresenceRingColor(p?.state);
    final last = agent.lastMessage;
    final preview = agentPresencePreview(p) ??
        (last == null
            ? (agent.available ? 'No messages yet' : 'Paused')
            : (last.fromUser ? 'You: ${last.text}' : last.text));
    final at = last?.at ?? agent.presence?.since;
    final timeText = at == null
        ? ''
        : relativeTime(at.millisecondsSinceEpoch ~/ 1000);
    final content = Row(children: [
      SizedBox(
        width: kMobile ? 14 : 12,
        child: Center(
          child: widget.unread > 0
              ? Container(
                  key: const ValueKey('agent-unread-dot'),
                  width: 10,
                  height: 10,
                  decoration: BoxDecoration(
                      color: AppColors.accent, shape: BoxShape.circle),
                )
              : null,
        ),
      ),
      _avatar(agent.id, kMobile ? 50 : 40, ringColor,
          available: agent.available),
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
                    style: TS.rowTitle(agent.available
                        ? AppColors.fg1
                        : AppColors.fg3)),
              ),
              if (timeText.isNotEmpty) ...[
                const SizedBox(width: 8),
                Text(timeText,
                    maxLines: 1, style: TS.meta(AppColors.fg3)),
                const SizedBox(width: 2),
                AppIcon('chevron-right',
                    size: kMobile ? 11 : 10, color: AppColors.fg4),
              ],
            ]),
            const SizedBox(height: 2),
            Text(preview,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: sans(kMobile ? 14 : 12,
                    color: AppColors.fg3, height: 1.3)),
          ],
        ),
      ),
    ]);
    if (kMobile) {
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
            constraints: const BoxConstraints(minHeight: 74),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 16, 8),
              child: content,
            ),
          ),
        ),
      );
    }
    return HoverSurface(
      selected: widget.selected,
      radius: 8,
      onTap: widget.onOpen,
      onLongPress: () {
        HapticFeedback.selectionClick();
        _actions(null);
      },
      onSecondaryTapDown: (d) => _actions(d.globalPosition),
      child: Container(
        constraints: const BoxConstraints(minHeight: 58),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        alignment: Alignment.centerLeft,
        child: content,
      ),
    );
  }

  Widget _avatar(String id, double size, Color? ringColor,
      {required bool available}) {
    return Opacity(
      opacity: available ? 1 : 0.5,
      child: SizedBox.square(
        dimension: size,
        child: Stack(clipBehavior: Clip.none, children: [
          Center(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(
                  color: AppColors.surface2, shape: BoxShape.circle),
              alignment: Alignment.center,
              child: AgentMochi(id, size: size * 0.76),
            ),
          ),
          if (ringColor != null)
            Positioned(
              left: -3,
              top: -3,
              right: -3,
              bottom: -3,
              child: DecoratedBox(
                key: const ValueKey('agent-working'),
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: ringColor, width: 2),
                ),
              ),
            ),
        ]),
      ),
    );
  }

}

/// Presence for roster rows: live device events win over the /agents snapshot.
({String state, String detail})? agentRosterPresence(
    CoordinationAgent agent, PresenceStore? live) {
  final p = live?.presenceForAgentId(agent.id);
  if (p != null) {
    return (
      state: p.state == 'tool' || p.state == 'running' ? 'working' : p.state,
      detail: p.detail,
    );
  }
  final w = agent.presence;
  if (w == null) return null;
  return (state: w.state, detail: w.detail);
}

/// The 2 px ring round a roster avatar, by presence state.
Color? agentPresenceRingColor(String? state) => switch (state) {
      'working' => AppColors.ok,
      'waiting' => AppColors.run,
      'blocked' => AppColors.danger,
      'thinking' || 'typing' || 'reviewing' => AppColors.accent,
      _ => null,
    };

/// The second roster line while the agent owes the user something or is
/// mid-task; null falls back to the last message.
String? agentPresencePreview(({String state, String detail})? p) {
  final detail = p?.detail ?? '';
  return switch (p?.state) {
    'working' => detail.isEmpty ? 'Working' : 'Working · $detail',
    'waiting' => detail.isEmpty || detail == 'user'
        ? 'Waiting on you'
        : 'Waiting on $detail',
    'blocked' => 'Blocked',
    'reviewing' => 'In review',
    _ => null,
  };
}
