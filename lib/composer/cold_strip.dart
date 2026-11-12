import 'package:flutter/material.dart';

import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';

String _tokens(int n) => n >= 1000 ? '${(n / 1000).round()}k' : '$n';

String _modeLabel(String mode) => switch (mode) {
      'lean' => 'Lean',
      'full' => 'Full',
      _ => 'Ask',
    };

/// Slim tab attached to the top edge of the composer while a session's prompt
/// cache has lapsed. In 'ask' mode it offers the one-off Lean/Full choice; in
/// 'lean'/'full' it shows the persisted mode and a Change menu.
class ColdTab extends StatelessWidget {
  /// The session's persisted resume mode: 'ask', 'lean' or 'full'.
  final String mode;
  final int? resumeTokens;
  final ValueChanged<String> onPick;
  const ColdTab(
      {super.key, required this.mode, this.resumeTokens, required this.onPick});

  Future<void> _changeMode(BuildContext context) async {
    final picked = await showAppMenu<String>(
      context,
      anchor: context,
      alignEnd: true,
      minWidth: 180,
      maxWidth: 220,
      items: [
        for (final m in const ['ask', 'lean', 'full'])
          appMenuItem<String>(
              value: m, label: _modeLabel(m), selected: m == mode),
      ],
    );
    if (picked != null) onPick(picked);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = resumeTokens == null ? null : '~${_tokens(resumeTokens!)}';
    final label = switch (mode) {
      'lean' => 'Cache cold · resumes lean',
      'full' => tokens == null
          ? 'Cache cold · resumes full'
          : 'Cache cold · resumes full, $tokens',
      _ => 'Cache cold · resume',
    };
    return Container(
      height: kMobile ? 36 : 30,
      padding: const EdgeInsets.only(left: 12, right: 2),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(10)),
        border: Border(
            bottom: BorderSide(color: AppColors.fg1.withValues(alpha: 0.08))),
      ),
      child: Row(children: [
        AppIcon('clock', size: 13, color: AppColors.fg3),
        const SizedBox(width: 8),
        Expanded(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(12, color: AppColors.fg3)),
        ),
        if (mode == 'ask') ...[
          _Choice('Lean', strong: true, onTap: () => onPick('lean')),
          _Choice(tokens == null ? 'Full' : 'Full $tokens',
              onTap: () => onPick('full')),
        ] else
          _Choice('Change', onTap: () => _changeMode(context)),
      ]),
    );
  }
}

class _Choice extends StatelessWidget {
  final String label;
  final bool strong;
  final VoidCallback onTap;
  const _Choice(this.label, {this.strong = false, required this.onTap});

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10),
          child: Center(
            child: Text(label,
                style: sans(12,
                    weight: FontWeight.w500,
                    color: strong ? AppColors.accent : AppColors.fg2)),
          ),
        ),
      );
}
