import 'package:flutter/material.dart';

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
      {super.key,
      required this.mode,
      this.resumeTokens,
      required this.onPick});

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
    final tokens =
        resumeTokens == null ? null : '~${_tokens(resumeTokens!)}';
    final label = switch (mode) {
      'lean' => 'Cold · resumes lean',
      'full' => tokens == null
          ? 'Cold · resumes full'
          : 'Cold · resumes full · $tokens',
      _ => tokens == null ? 'Cold' : 'Cold · $tokens to re-read',
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(10)),
        border: Border(
            bottom: BorderSide(
                color: AppColors.fg1.withValues(alpha: 0.08))),
      ),
      child: Row(children: [
        AppIcon('clock', size: 13, color: AppColors.fg3),
        const SizedBox(width: 7),
        Expanded(
          child: Text(label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(12, color: AppColors.fg3)),
        ),
        if (mode == 'ask') ...[
          Btn('Full',
              small: true,
              variant: BtnVariant.secondary,
              onTap: () => onPick('full')),
          const SizedBox(width: 6),
          Btn('Lean', small: true, onTap: () => onPick('lean')),
        ] else
          TextAction('Change', onTap: () => _changeMode(context)),
      ]),
    );
  }
}
