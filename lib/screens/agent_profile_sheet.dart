import 'package:flutter/material.dart';

import '../api.dart';
import '../mochi.dart';
import '../models.dart';
import '../tap_detector.dart';
import '../theme.dart';
import '../widgets.dart';
import 'agent_appearance.dart';
import 'agent_profile_panel.dart';
import 'phone_agent_page.dart' show sessionStateWord;

/// The profile sheet: name, model, where the agent runs and its sessions;
/// pause or delete. Edits save on Done.
Future<void> showAgentProfileSheet(
  BuildContext context, {
  required DaemonClient client,
  required CoordinationAgent agent,
  required List<SessionInfo> sessions,
  required int groups,
  required String machine,
  required bool paused,
  VoidCallback? onAllSessions,
  ValueChanged<bool>? onPauseChanged,
  VoidCallback? onDeleted,
}) =>
    showAppSheet<void>(
      context,
      title: '',
      maxHeight: 760,
      child: _ProfileSheet(
        client: client,
        agent: agent,
        sessions: sessions,
        groups: groups,
        machine: machine,
        paused: paused,
        onAllSessions: onAllSessions,
        onPauseChanged: onPauseChanged,
        onDeleted: onDeleted,
      ),
    );

class _ProfileSheet extends StatefulWidget {
  const _ProfileSheet({
    required this.client,
    required this.agent,
    required this.sessions,
    required this.groups,
    required this.machine,
    required this.paused,
    this.onAllSessions,
    this.onPauseChanged,
    this.onDeleted,
  });

  final DaemonClient client;
  final CoordinationAgent agent;
  final List<SessionInfo> sessions;
  final int groups;
  final String machine;
  final bool paused;
  final VoidCallback? onAllSessions;
  final ValueChanged<bool>? onPauseChanged;
  final VoidCallback? onDeleted;

  @override
  State<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends State<_ProfileSheet> {
  late final TextEditingController _name =
      TextEditingController(text: widget.agent.displayName);
  late bool _paused = widget.paused;

  CoordinationAgent get a => widget.agent;

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  Future<void> _done() async {
    final nav = Navigator.of(context);
    final next = _name.text.trim();
    if (next.isNotEmpty && next != a.displayName) {
      try {
        await widget.client
            .setAgentNickname(a.id, next == a.fullName ? null : next);
      } catch (_) {
        if (mounted) toast(context, 'Could not save the name', danger: true);
        return;
      }
    }
    nav.pop();
  }

  Future<void> _pause() async {
    final next = !_paused;
    setState(() => _paused = next);
    try {
      await widget.client.setAgentStatus(a.id, next ? 'paused' : 'active');
      widget.onPauseChanged?.call(next);
    } catch (_) {
      if (mounted) setState(() => _paused = !next);
    }
  }

  Future<void> _delete() async {
    final nav = Navigator.of(context);
    final ok = await confirmAction(context,
        title: 'Delete ${a.displayName}?',
        body: 'Its sessions stay; the agent, its desk and memory go.',
        confirmLabel: 'Delete agent');
    if (!ok) return;
    try {
      await widget.client.deleteAgent(a.id);
      nav.pop();
      widget.onDeleted?.call();
    } catch (e) {
      if (mounted) toast(context, '$e', danger: true);
    }
  }

  Widget _label(String t) => Padding(
        padding: const EdgeInsets.only(top: 16, bottom: 8),
        child: Text(t, style: sans(13, weight: W.label, color: AppColors.fg2)),
      );

  Widget _link(String icon, String title, String meta, VoidCallback? onTap) =>
      Semantics(
        button: onTap != null,
        label: '$title, $meta',
        excludeSemantics: true,
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Row(children: [
              AppIcon(icon, size: 18, color: AppColors.fg2),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(title, style: sans(14, color: AppColors.fg1))),
              Text(meta, style: sans(13, color: AppColors.fg3)),
              if (onTap != null) ...[
                const SizedBox(width: 4),
                AppIcon('chevron-right', size: 16, color: AppColors.fg3),
              ],
            ]),
          ),
        ),
      );

  Widget _textButton(String text, Color color, VoidCallback onTap) => Semantics(
        button: true,
        label: text,
        excludeSemantics: true,
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
            height: 48,
            child: Center(
                child:
                    Text(text, style: sans(14, weight: W.label, color: color))),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final live = widget.sessions
        .where(
            (s) => const {'Working', 'Needs you'}.contains(sessionStateWord(s)))
        .length;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
          height: 48,
          child: Stack(alignment: Alignment.center, children: [
            Semantics(
                header: true,
                child: Text('Profile',
                    style: sans(15, weight: W.label, color: AppColors.fg1))),
            Align(
              alignment: Alignment.centerRight,
              child: _textButton('Done', AppColors.fg1, _done),
            ),
          ]),
        ),
        Semantics(
          button: true,
          label: 'Change face',
          excludeSemantics: true,
          child: TapDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => showAgentAppearance(
                context, widget.client, a.id, a.displayName),
            child: Column(children: [
              ClipRRect(
                  borderRadius: BorderRadius.circular(R.of(18)),
                  child: AgentMochi(a.id, size: 64)),
              SizedBox(
                height: 32,
                child: Center(
                    child: Text('Change face',
                        style: sans(13, color: AppColors.fg2))),
              ),
            ]),
          ),
        ),
        _label('Name'),
        AppField(controller: _name, hint: a.fullName),
        _label('Model'),
        Semantics(
          button: true,
          label: 'Model, change',
          child: TapDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => showAgentProfileSettings(context,
                client: widget.client, agent: a, name: a.displayName),
            child: Container(
              height: 48,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: BorderRadius.circular(R.of(12))),
              child: Row(children: [
                Expanded(
                    child: Text(a.deskProfile ?? a.profile ?? 'Session default',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(14, color: AppColors.fg1))),
                Text('Change', style: sans(13, color: AppColors.fg2)),
                const SizedBox(width: 4),
                AppIcon('chevron-right', size: 16, color: AppColors.fg3),
              ]),
            ),
          ),
        ),
        _label('Details'),
        _Detail('Machine', widget.machine),
        _Detail('Agent id', a.id, mono: true),
        _link(
            'layers',
            'Sessions',
            '$live active, ${widget.sessions.length} in all',
            widget.onAllSessions == null
                ? null
                : () {
                    Navigator.of(context).pop();
                    widget.onAllSessions!();
                  }),
        _link('users', 'Groups', '${widget.groups}', null),
        const SizedBox(height: 8),
        Row(children: [
          _textButton(
              _paused ? 'Resume agent' : 'Pause agent', AppColors.fg1, _pause),
          const Spacer(),
          _textButton('Delete agent', AppColors.danger, _delete),
        ]),
      ],
    );
  }
}

class _Detail extends StatelessWidget {
  const _Detail(this.label, this.value, {this.mono = false});
  final String label, value;
  final bool mono;

  @override
  Widget build(BuildContext context) => MergeSemantics(
        child: SizedBox(
          height: 44,
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
      );
}
