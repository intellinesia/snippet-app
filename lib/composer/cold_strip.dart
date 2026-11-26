import 'package:flutter/material.dart';

import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'desktop_composer.dart' show DeskButton;

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
    if (kMobile) {
      final action = mode == 'ask' ? 'Resume lean' : 'Change';
      return Container(
        margin: const EdgeInsets.only(bottom: 8),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(children: [
              AppIcon('clock', size: 18, color: AppColors.fg2),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text('Session is cold',
                        style: sans(15,
                            height: 21 / 15,
                            weight: FontWeight.w500,
                            color: AppColors.fg1)),
                    Text(
                        tokens == null
                            ? 'Choose how much context to restore'
                            : 'Choose how much context to restore · $tokens',
                        maxLines: 2,
                        style: sans(13, height: 18 / 13, color: AppColors.fg2)),
                  ],
                ),
              ),
            ]),
            const SizedBox(height: 12),
            InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => mode == 'ask' ? onPick('lean') : _changeMode(context),
              child: Container(
                height: 36,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: AppColors.fg1,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(action,
                    style: sans(12.5,
                        weight: FontWeight.w500, color: AppColors.bg)),
              ),
            ),
          ],
        ),
      );
    }
    return Container(
      height: kMobile ? 32 : 28,
      margin: EdgeInsets.symmetric(horizontal: S.s20),
      transform: Matrix4.translationValues(0, 1, 0),
      padding: EdgeInsets.only(left: S.s12, right: S.s2),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.lg)),
      ),
      child: Row(children: [
        AppIcon('clock', size: 13, color: AppColors.fg3),
        SizedBox(width: S.s8),
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
        borderRadius: BorderRadius.circular(R.md),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: S.of(10)),
          child: Center(
            child: Text(label,
                style: sans(12,
                    weight: FontWeight.w500,
                    color: strong ? AppColors.accent : AppColors.fg2)),
          ),
        ),
      );
}

/// Desktop: the cold-cache state as a chip beside the model chip. It opens the
/// Ask / Lean / Full menu; in 'ask' mode picking Lean or Full is the one-off
/// choice, as on the phone's tab.
class ColdChip extends StatelessWidget {
  final String mode;
  final int? resumeTokens;
  final ValueChanged<String> onPick;
  const ColdChip(
      {super.key, required this.mode, this.resumeTokens, required this.onPick});

  Future<void> _menu(BuildContext context, String? tokens) async {
    final picked = await showAppMenu<String>(
      context,
      anchor: context,
      minWidth: 180,
      maxWidth: 220,
      items: [
        appMenuItem<String>(
            value: 'ask', label: 'Ask each time', selected: mode == 'ask'),
        appMenuItem<String>(
            value: 'lean', label: 'Lean', selected: mode == 'lean'),
        appMenuItem<String>(
            value: 'full',
            label: tokens == null ? 'Full' : 'Full $tokens',
            selected: mode == 'full'),
      ],
    );
    if (picked != null) onPick(picked);
  }

  @override
  Widget build(BuildContext context) {
    final tokens = resumeTokens == null ? null : '~${_tokens(resumeTokens!)}';
    final label = switch (mode) {
      'lean' => 'Cold · lean',
      'full' => tokens == null ? 'Cold · full' : 'Cold · full $tokens',
      _ => 'Cold · resume',
    };
    return Builder(
      builder: (ctx) => DeskButton(
        tooltip: 'Prompt cache is cold: choose how the next turn resumes',
        onTap: () => _menu(ctx, tokens),
        fill: AppColors.fg1.withValues(alpha: 0.05),
        hoverFill: AppColors.fg1.withValues(alpha: 0.09),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AppIcon('clock', size: 13, color: AppColors.fg3),
          const SizedBox(width: 6),
          Text(label, style: sans(12.5, color: AppColors.fg2)),
          const SizedBox(width: 4),
          AppIcon('chevron-down', size: 12, color: AppColors.fg4),
        ]),
      ),
    );
  }
}

/// Desktop CMP-10 cold state. The composer card is replaced by words and one
/// 28-high action; the action opens the same resume-depth choice as the chip.
class DeskColdComposerStrip extends StatelessWidget {
  const DeskColdComposerStrip({
    super.key,
    required this.mode,
    this.resumeTokens,
    required this.onPick,
  });

  final String mode;
  final int? resumeTokens;
  final ValueChanged<String> onPick;

  Future<void> _menu(BuildContext context) async {
    final tokens = resumeTokens == null ? null : '~${_tokens(resumeTokens!)}';
    final picked = await showAppMenu<String>(
      context,
      anchor: context,
      minWidth: 180,
      maxWidth: 220,
      items: [
        appMenuItem<String>(
            value: 'ask', label: 'Ask each time', selected: mode == 'ask'),
        appMenuItem<String>(
            value: 'lean', label: 'Lean', selected: mode == 'lean'),
        appMenuItem<String>(
            value: 'full',
            label: tokens == null ? 'Full' : 'Full $tokens',
            selected: mode == 'full'),
      ],
    );
    if (picked != null) onPick(picked);
  }

  @override
  Widget build(BuildContext context) => Container(
        height: 36,
        padding: const EdgeInsets.only(left: 12, right: 8),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(R.of(10)),
        ),
        child: Row(children: [
          Expanded(
            child: Text('Session is cold',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(12, height: 17 / 12, color: AppColors.fg2)),
          ),
          Builder(
            builder: (ctx) => SizedBox(
              height: 28,
              child: DeskButton(
                padding: const EdgeInsets.symmetric(horizontal: 9),
                fill: AppColors.surface2,
                hoverFill: AppColors.surface3,
                onTap: () => _menu(ctx),
                child: Text('Warm up',
                    style: sans(12,
                        weight: FontWeight.w500,
                        height: 17 / 12,
                        color: AppColors.fg1)),
              ),
            ),
          ),
        ]),
      );
}

/// Desktop CMP-11 offline state above an enabled composer. No red treatment;
/// the queued count is spelled out in words.
class DeskOfflineComposerNotice extends StatelessWidget {
  const DeskOfflineComposerNotice({
    super.key,
    required this.message,
    required this.queued,
    required this.onRetry,
  });

  final String message;
  final int queued;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final text = [
      message,
      if (queued > 0)
        '$queued message${queued == 1 ? '' : 's'} will send on reconnect',
    ].join(' · ');
    return Semantics(
      liveRegion: true,
      label: text,
      child: Container(
        height: 28,
        margin: const EdgeInsets.only(bottom: 6),
        padding: const EdgeInsets.only(left: 12, right: 8),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(R.of(8)),
        ),
        child: Row(children: [
          Container(
            width: 6,
            height: 6,
            decoration:
                BoxDecoration(color: AppColors.fg2, shape: BoxShape.circle),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(11, height: 15 / 11, color: AppColors.fg2)),
          ),
          DeskButton(
            height: 28,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            fill: Colors.transparent,
            hoverFill: AppColors.surface3,
            onTap: onRetry,
            child: Text('Retry now',
                style: sans(11,
                    weight: FontWeight.w500,
                    height: 15 / 11,
                    color: AppColors.fg1)),
          ),
        ]),
      ),
    );
  }
}
