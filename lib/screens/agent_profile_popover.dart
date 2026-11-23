import 'package:flutter/material.dart';

import '../chat/signal_row.dart'
    show prettyModel, prettyProfile, prettyProvider;
import '../api.dart';
import '../models.dart';
import '../tap_detector.dart';
import '../theme.dart';
import '../widgets.dart';

/// The agent's profile as a small popover under the header button (V5): where
/// it runs and what it holds, each row opening its own page.
Future<void> showAgentProfilePopover(
  BuildContext anchor, {
  required DaemonClient client,
  required CoordinationAgent agent,
  required ValueChanged<String> onAction,
  String? workspace,
}) =>
    showAnchoredPanel<void>(
      anchor,
      width: 340,
      alignRight: true,
      borderColor: AppColors.line,
      child: AgentProfilePopoverCard(
        client: client,
        agent: agent,
        workspace: workspace,
        onAction: onAction,
      ),
    );

class AgentProfilePopoverCard extends StatefulWidget {
  const AgentProfilePopoverCard({
    super.key,
    required this.client,
    required this.agent,
    required this.onAction,
    this.workspace,
  });

  final DaemonClient client;
  final CoordinationAgent agent;
  final ValueChanged<String> onAction;
  final String? workspace;

  @override
  State<AgentProfilePopoverCard> createState() =>
      _AgentProfilePopoverCardState();
}

class _AgentProfilePopoverCardState extends State<AgentProfilePopoverCard> {
  CoordinationAgent get agent => widget.agent;
  ValueChanged<String> get onAction => widget.onAction;

  // Null until loaded; '' when the call failed, so the row reads as unknown.
  String? _reach, _memory, _wakes, _worksIn;
  InferenceProfile? _profileInfo;

  @override
  void initState() {
    super.initState();
    _worksIn = widget.workspace;
    final c = widget.client;
    final profileName = agent.deskProfile ?? agent.profile;
    c.getConfig().then((cfg) {
      final match = profileName == null
          ? cfg.profiles.where((p) => p.active).firstOrNull
          : cfg.profiles.where((p) => p.name == profileName).firstOrNull;
      if (mounted) setState(() => _profileInfo = match);
    }).catchError((_) {});
    if (_worksIn == null) {
      c.sessions().then((all) {
        final mine = [
          for (final s in all)
            if (s.displayAgentId == agent.id &&
                s.projectFolder.trim().isNotEmpty)
              s
        ]..sort((a, b) => b.lastActive.compareTo(a.lastActive));
        final folder = mine.isEmpty
            ? ''
            : lastPathSegment(mine.first.projectFolder,
                ifEmpty: mine.first.projectFolder);
        if (mounted) {
          setState(() => _worksIn = folder.isEmpty ? 'Any folder' : folder);
        }
      }).catchError((_) {
        if (mounted) setState(() => _worksIn = 'Any folder');
      });
    }
    c.agentReach(agent.id).then((r) {
      final on = [
        for (final ch in r.policy['question'] ?? const <String>[])
          if (r.channel(ch).enabled) _channelName(ch)
      ];
      if (mounted) {
        setState(() => _reach = on.isEmpty ? 'Chat only' : on.join(', '));
      }
    }).catchError((_) {
      if (mounted) setState(() => _reach = '');
    });
    c.memoryScopes().then((all) {
      final s = all.where((x) => x.key == 'agent:${agent.id}').firstOrNull;
      final n = s?.entries ?? 0;
      if (mounted) {
        setState(() => _memory = n == 0
            ? 'Nothing saved yet'
            : '$n ${n == 1 ? 'entry' : 'entries'}');
      }
    }).catchError((_) {
      if (mounted) setState(() => _memory = '');
    });
    c.wakes().then((all) {
      final mine = [
        for (final w in all.wakes)
          if (w.owner == agent.id && w.enabled) w
      ];
      final text = mine.isEmpty
          ? 'None set'
          : mine.length == 1
              ? mine.first.scheduleText
              : '${mine.first.scheduleText} and ${mine.length - 1} more';
      if (mounted) setState(() => _wakes = text);
    }).catchError((_) {
      if (mounted) setState(() => _wakes = '');
    });
  }

  static String _channelName(String c) => switch (c) {
        'push' => 'Push',
        'chat' => 'Chat',
        'voice' => 'Voice',
        'task_room' => 'Task room',
        _ => c,
      };

  void _go(BuildContext context, String action) {
    Navigator.of(context).pop();
    onAction(action);
  }

  String _runsOnText(String profile) {
    final p = _profileInfo;
    if (p != null) {
      final prov = prettyProvider(p.provider);
      final mod = prettyModel(p.model);
      if (prov.isNotEmpty && mod.isNotEmpty) return '$prov \u00b7 $mod';
      if (prov.isNotEmpty) return prov;
      if (mod.isNotEmpty) return mod;
    }
    return prettyProfile(profile);
  }

  @override
  Widget build(BuildContext context) {
    final profile = agent.deskProfile ?? agent.profile;
    final providerKey = _profileInfo?.provider ?? profile;
    final skills = agent.capabilities.join(', ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _row(context, 'Runs on', 'model',
              profile == null ? 'Session model' : null,
              lead: profile == null
                  ? null
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      ProviderLogo(providerKey, size: 14, color: AppColors.fg2),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(_runsOnText(profile),
                            overflow: TextOverflow.ellipsis,
                            style: sans(13, color: AppColors.fg1)),
                      ),
                    ])),
          _row(context, 'Works in', null, _worksIn),
          _row(context, 'Reaches you', 'reach', _reach),
          _row(context, 'Memory', 'memory', _memory),
          _row(context, 'Wakes', 'wakes', _wakes),
          if (skills.isNotEmpty) _row(context, 'Skills', null, skills),
          const SizedBox(height: 12),
          Align(
            alignment: Alignment.centerLeft,
            child: Btn('Edit profile',
                small: true,
                variant: BtnVariant.secondary,
                onTap: () => _go(context, 'model')),
          ),
        ],
      ),
    );
  }

  Widget _row(BuildContext context, String label, String? action, String? value,
      {Widget? lead}) {
    final row = Container(
      constraints: const BoxConstraints(minHeight: 32),
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
        SizedBox(
          width: 96,
          child: Text(label, style: sans(12, color: AppColors.fg2)),
        ),
        Expanded(
          child: lead ??
              Text(value == null ? 'Loading' : (value.isEmpty ? 'Open' : value),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13,
                      color: value == null || value.isEmpty
                          ? AppColors.fg3
                          : AppColors.fg1)),
        ),
      ]),
    );
    if (action == null) return row;
    return TapDetector(
      behavior: HitTestBehavior.opaque,
      onTap: () => _go(context, action),
      child: row,
    );
  }
}
