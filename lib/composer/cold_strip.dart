import 'package:flutter/material.dart';

import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';

String _tokens(int n) => n >= 1000 ? '${(n / 1000).round()}k' : '$n';

/// Shown above the composer while a session's prompt cache has lapsed: the next
/// turn either re-reads the whole history or continues lean from a handover.
class ColdStrip extends StatelessWidget {
  final int? resumeTokens;
  final VoidCallback onLean;
  final VoidCallback onFull;
  const ColdStrip(
      {super.key, this.resumeTokens, required this.onLean, required this.onFull});

  @override
  Widget build(BuildContext context) {
    final full = resumeTokens == null
        ? 'Full re-reads the history'
        : 'Full re-reads ~${_tokens(resumeTokens!)} tokens';
    return Container(
      margin: EdgeInsets.fromLTRB(
          kMobile ? M.gutter : 20, 6, kMobile ? M.gutter : 20, 0),
      padding: const EdgeInsets.fromLTRB(10, 8, 8, 8),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(children: [
        Container(
          width: 30,
          height: 30,
          alignment: Alignment.center,
          decoration: BoxDecoration(
              color: AppColors.surface3, borderRadius: BorderRadius.circular(9)),
          child: AppIcon('clock', size: 15, color: AppColors.fg2),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('Cold', style: sans(13, weight: W.label, color: AppColors.fg1)),
              Text(full,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12, color: AppColors.fg4)),
            ],
          ),
        ),
        const SizedBox(width: 8),
        Btn('Full', small: true, variant: BtnVariant.secondary, onTap: onFull),
        const SizedBox(width: 6),
        Btn('Lean', small: true, onTap: onLean),
      ]),
    );
  }
}
