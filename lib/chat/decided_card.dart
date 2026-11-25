import 'package:flutter/material.dart';

import '../platform.dart';
import '../mochi.dart';
import '../theme.dart';
import '../widgets.dart';
import 'ask_kit.dart';

/// How a desk request ended.
enum DecidedKind {
  approved,
  denied,
  answered,
  skipped,
  outdated,
  expired,
  superseded,
}

extension DecidedKindLook on DecidedKind {
  String get label => switch (this) {
        DecidedKind.approved => 'Approved',
        DecidedKind.denied => 'Denied',
        DecidedKind.answered => 'Answered',
        DecidedKind.skipped => 'Skipped',
        DecidedKind.outdated => 'Outdated',
        DecidedKind.expired => 'Expired',
        DecidedKind.superseded => 'Superseded',
      };

  Tone get tone => Tone.neutral;

  String get icon => switch (this) {
        DecidedKind.approved || DecidedKind.answered => 'check-circle',
        DecidedKind.denied => 'x',
        DecidedKind.skipped => 'x',
        DecidedKind.outdated || DecidedKind.expired => 'clock',
        DecidedKind.superseded => 'layers',
      };

  Color get iconColor => switch (this) {
        DecidedKind.approved || DecidedKind.answered => AppColors.fg2,
        DecidedKind.denied => AppColors.fg1,
        DecidedKind.skipped ||
        DecidedKind.outdated ||
        DecidedKind.expired ||
        DecidedKind.superseded =>
          AppColors.fg3,
      };
}

/// A settled desk request as one compact card: status icon, the command or
/// question on one line, what it was for under it, and the outcome tag.
class DecidedCard extends StatelessWidget {
  const DecidedCard({
    super.key,
    required this.kind,
    required this.title,
    this.subtitle,
    this.code = false,
    this.actionLabel,
    this.onAction,
  });

  final DecidedKind kind;
  final String title;
  final String? subtitle;

  /// The title is a command, shown in the code face.
  final bool code;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final dim = kind == DecidedKind.outdated ||
        kind == DecidedKind.skipped ||
        kind == DecidedKind.expired;
    final titleColor = dim ? AppColors.fg3 : AppColors.fg1;
    if (!kMobile) {
      final shownTitle =
          title.trim().toLowerCase().startsWith(kind.label.toLowerCase())
              ? title
              : title.trim().isEmpty
                  ? kind.label
                  : '${kind.label} $title';
      return Container(
        width: double.infinity,
        margin: EdgeInsets.symmetric(vertical: S.s2),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: AppIcon(kind.icon, size: 14, color: AppColors.fg2),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(shownTitle,
                    style: code
                        ? codeMono(13,
                            height: 19 / 13,
                            weight: FontWeight.w500,
                            color: AppColors.fg1)
                        : sans(13,
                            height: 19 / 13,
                            weight: FontWeight.w500,
                            color: AppColors.fg1)),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: Text(subtitle!,
                        style: sans(12, height: 17 / 12, color: AppColors.fg2)),
                  ),
              ],
            ),
          ),
          if (actionLabel != null) ...[
            const SizedBox(width: 10),
            AskButton(actionLabel!,
                variant: AskButtonVariant.ghost, onTap: onAction),
          ],
        ]),
      );
    }
    return Container(
      width: double.infinity,
      margin: EdgeInsets.symmetric(vertical: S.s2),
      padding: EdgeInsets.symmetric(
          horizontal: S.s12, vertical: kMobile ? S.of(10) : S.s8),
      decoration: BoxDecoration(
        color: kMobile ? AppColors.surface1 : AppColors.surface2,
        borderRadius: BorderRadius.circular(kMobile ? 12 : R.card),
        border: kMobile ? Border.all(color: AppColors.border) : null,
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        SizedBox(
          width: 16,
          height: 20,
          child: Center(
              child: AppIcon(kind.icon, size: 14, color: kind.iconColor)),
        ),
        SizedBox(width: S.of(10)),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: code
                      ? codeMono(12, height: 20 / 12, color: titleColor)
                      : sans(kMobile ? 14 : 13,
                          height: 20 / (kMobile ? 14 : 13), color: titleColor)),
              if (subtitle != null && subtitle!.isNotEmpty)
                Text(subtitle!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(12, height: 16 / 12, color: AppColors.fg3)),
            ],
          ),
        ),
        SizedBox(width: S.of(10)),
        Tag(kind.label, tone: kind.tone),
      ]),
    );
  }
}

/// The open request's head: the asking agent's mini character and the task.
class DeskRequestHead extends StatelessWidget {
  const DeskRequestHead({super.key, required this.agentId, required this.line});

  final String agentId;
  final String line;

  @override
  Widget build(BuildContext context) => Row(children: [
        if (agentId.isNotEmpty) ...[
          AgentMochi(agentId, size: 22),
          SizedBox(width: S.s6),
        ],
        Expanded(
          child: Text(line,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(12, color: AppColors.fg3)),
        ),
      ]);
}
