import 'package:flutter/material.dart';

import '../message_reactions.dart';
import '../models.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';

/// Up to five non-empty choice labels attached to an agent message.
List<String> eventChoices(CoordinationEvent event) {
  if (event.actorKind == 'human') return const [];
  final raw = event.payload['choices'];
  if (raw is! List) return const [];
  final out = <String>[];
  for (final item in raw) {
    if (item is String) {
      final s = item.trim();
      if (s.isNotEmpty) out.add(s);
    }
  }
  if (out.length < 2) return const [];
  return out.length > 5 ? out.sublist(0, 5) : out;
}

String? _eventReplyTo(CoordinationEvent event) {
  final direct = event.replyTo;
  if (direct != null && direct.isNotEmpty) return direct;
  final inReplyTo = event.payload['in_reply_to'];
  if (inReplyTo is String && inReplyTo.isNotEmpty) return inReplyTo;
  return null;
}

/// Trimmed body of the first later human reply targeting [target], if any.
String? chosenReplyFor(
  CoordinationEvent target,
  List<CoordinationEvent> events,
) {
  if (target.eventId.isEmpty) return null;
  final idx = events.indexWhere((e) =>
      identical(e, target) ||
      (e.eventId.isNotEmpty && e.eventId == target.eventId));
  final start = idx >= 0 ? idx + 1 : 0;
  for (var i = start; i < events.length; i++) {
    final e = events[i];
    if (e.actorKind != 'human' || isReactionEvent(e)) continue;
    if (_eventReplyTo(e) != target.eventId) continue;
    final text = e.body.trim();
    if (text.isNotEmpty) return text;
  }
  return null;
}

/// Compact tappable choice pills rendered under an agent message bubble.
class ChatChoices extends StatelessWidget {
  const ChatChoices({
    super.key,
    required this.choices,
    this.chosen,
    this.onPick,
  });

  final List<String> choices;
  final String? chosen;
  final ValueChanged<String>? onPick;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    if (choices.isEmpty) return const SizedBox.shrink();
    final locked = chosen != null;
    final minH = kMobile ? 40.0 : 30.0;
    final vPad = kMobile ? 9.0 : 6.0;
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final choice in choices)
          _ChoicePill(
            label: choice,
            picked: chosen == choice,
            disabled: locked && chosen != choice,
            minHeight: minH,
            verticalPadding: vPad,
            onTap: (!locked && onPick != null) ? () => onPick!(choice) : null,
          ),
      ],
    );
  }
}

class _ChoicePill extends StatelessWidget {
  const _ChoicePill({
    required this.label,
    required this.picked,
    required this.disabled,
    required this.minHeight,
    required this.verticalPadding,
    this.onTap,
  });

  final String label;
  final bool picked;
  final bool disabled;
  final double minHeight;
  final double verticalPadding;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fill = picked
        ? AppColors.accentBg
        : (disabled
            ? AppColors.surface1.withValues(alpha: 0.45)
            : AppColors.surface1);
    final border = picked
        ? AppColors.accentLine
        : (disabled
            ? AppColors.border.withValues(alpha: 0.6)
            : AppColors.border2);
    final ink = picked
        ? AppColors.accent
        : (disabled ? AppColors.fg4 : AppColors.fg1);
    final radius = BorderRadius.circular(R.pill);
    return Pressable(
      kind: PressKind.button,
      enabled: onTap != null,
      child: Material(
        color: fill,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(color: border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: radius,
          onTap: onTap,
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minHeight),
            child: Padding(
              padding: EdgeInsets.symmetric(
                  horizontal: S.of(14), vertical: verticalPadding),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (picked) ...[
                    AppIcon('check', size: 12, color: ink),
                    SizedBox(width: S.s6),
                  ],
                  Flexible(
                    child: Text(
                      label,
                      style: sans(kMobile ? 13 : 12,
                          weight: picked ? W.label : W.body, color: ink),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
