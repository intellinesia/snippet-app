import 'package:flutter/material.dart';

import '../chat/signal_row.dart' show prettyProfile;
import '../models.dart';
import '../tap_detector.dart';
import '../theme.dart';
import '../widgets.dart';

/// The agent's profile as a small popover under the header button: where it
/// runs and what it holds, each row opening its own page. Replaces the old
/// About column.
Future<void> showAgentProfilePopover(
  BuildContext anchor, {
  required CoordinationAgent agent,
  required ValueChanged<String> onAction,
}) =>
    showAnchoredPanel<void>(
      anchor,
      width: 300,
      alignRight: true,
      child: _ProfileCard(agent: agent, onAction: onAction),
    );

class _ProfileCard extends StatelessWidget {
  const _ProfileCard({required this.agent, required this.onAction});

  final CoordinationAgent agent;
  final ValueChanged<String> onAction;

  void _go(BuildContext context, String action) {
    Navigator.of(context).pop();
    onAction(action);
  }

  @override
  Widget build(BuildContext context) {
    final profile = agent.deskProfile ?? agent.profile;
    final skills = agent.capabilities.join(', ');
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _row(context, 'Runs on', 'model', profile == null ? 'Session model' : null,
              lead: profile == null
                  ? null
                  : Row(mainAxisSize: MainAxisSize.min, children: [
                      ProviderLogo(profile, size: 14, color: AppColors.fg2),
                      const SizedBox(width: 6),
                      Flexible(
                        child: Text(prettyProfile(profile),
                            overflow: TextOverflow.ellipsis,
                            style: sans(13, color: AppColors.fg1)),
                      ),
                    ])),
          _row(context, 'Reaches you', 'reach', 'Channels and sound'),
          _row(context, 'Memory', 'memory', 'Topics it keeps'),
          _row(context, 'Wakes', 'wakes', 'Schedule'),
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
          width: 92,
          child: Text(label, style: sans(12, color: AppColors.fg3)),
        ),
        Expanded(
          child: lead ??
              Text(value ?? '',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13, color: AppColors.fg1)),
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
