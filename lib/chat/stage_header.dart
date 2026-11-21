import 'package:flutter/material.dart';

import '../mochi.dart';
import '../theme.dart';
import '../widgets.dart' show AppIcon;
import '../tap_detector.dart';

/// One cast member on the stage.
class StageMember {
  const StageMember(this.agentId,
      {this.state = AgentCharacterState.idle, this.badge});

  final String agentId;
  final AgentCharacterState state;
  final String? badge;
}

/// The phone chat header: the cast on stage with a title chip over their
/// feet, and an optional pill (lanes, members) under the chip.
class StageHeader extends StatelessWidget {
  const StageHeader({
    super.key,
    required this.members,
    required this.title,
    this.subtitle,
    this.subtitleDot,
    this.onTap,
    this.below,
    this.compact = false,
  });

  /// The first member stands in the middle and largest.
  final List<StageMember> members;
  final String title;
  final String? subtitle;

  /// A small status dot before the subtitle, e.g. AppColors.run while working.
  final Color? subtitleDot;
  final VoidCallback? onTap;
  final Widget? below;

  /// Desktop: smaller cast and a one-row chip (title then subtitle).
  final bool compact;

  static const double leadSize = 72;
  static const double sideSize = 52;
  static const double compactLeadSize = 56;
  static const double compactSideSize = 40;
  static const int maxShown = 3;

  @override
  Widget build(BuildContext context) {
    final shown = members.take(maxShown).toList();
    final lead = compact ? compactLeadSize : leadSize;
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          height: lead - S.s12,
          child: OverflowBox(
            alignment: Alignment.topCenter,
            maxHeight: lead,
            child: _cast(shown),
          ),
        ),
        _chip(),
        if (below != null) ...[SizedBox(height: S.s6), below!],
      ],
    );
  }

  Widget _cast(List<StageMember> shown) {
    final leadSize = compact ? compactLeadSize : StageHeader.leadSize;
    final sideSize = compact ? compactSideSize : StageHeader.sideSize;
    if (shown.isEmpty) return SizedBox(height: leadSize);
    Widget char(StageMember m, double size) => AgentMochi(m.agentId,
        size: size, state: m.state, badge: m.badge);
    // Side members stand behind the lead, so they are painted first.
    return SizedBox(
      height: leadSize,
      width: leadSize + (shown.length > 1 ? sideSize * 1.2 : 0),
      child: Stack(
        alignment: Alignment.bottomCenter,
        clipBehavior: Clip.none,
        children: [
          if (shown.length > 1)
            Positioned(left: 0, bottom: 0, child: char(shown[1], sideSize)),
          if (shown.length > 2)
            Positioned(right: 0, bottom: 0, child: char(shown[2], sideSize)),
          char(shown[0], leadSize),
        ],
      ),
    );
  }

  Widget _chip() {
    final hasSub = subtitle != null && subtitle!.isNotEmpty;
    final chip = Container(
      // Sized by its lines: a lone name makes a short pill.
      constraints: BoxConstraints(maxWidth: compact ? 420 : 280),
      padding: EdgeInsets.symmetric(
          horizontal: compact ? S.s12 : S.s16, vertical: compact ? S.s4 : S.s6),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        // Same corner as the transcript cards (lane, approval) beside it.
        borderRadius: BorderRadius.circular(R.of(14)),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(compact ? 13 : 15,
                      weight: FontWeight.w600, color: AppColors.fg1)),
            ),
            if (onTap != null) ...[
              SizedBox(width: S.s4),
              AppIcon('chevron-right', size: 14, color: AppColors.fg3),
            ],
            if (compact && hasSub) ...[
              SizedBox(width: S.s8),
              Flexible(child: _sub()),
            ],
          ]),
          if (!compact && hasSub) _sub(),
        ],
      ),
    );
    if (onTap == null) return chip;
    return Semantics(
      button: true,
      child: TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // The pill can be short; the touch target stays 44 on phones.
        child: compact
            ? chip
            : ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 44),
                child: Center(widthFactor: 1, child: chip)),
      ),
    );
  }

  Widget _sub() => Row(mainAxisSize: MainAxisSize.min, children: [
        if (subtitleDot != null) ...[
          Container(
            width: 6,
            height: 6,
            decoration:
                BoxDecoration(color: subtitleDot, shape: BoxShape.circle),
          ),
          SizedBox(width: S.s6),
        ],
        Flexible(
          child: Text(subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(compact ? 11 : 12, color: AppColors.fg3)),
        ),
      ]);
}

/// The small pill under the chip, e.g. "2 lanes".
class StagePill extends StatelessWidget {
  const StagePill(
      {super.key, required this.label, this.icon, this.leading, this.onTap});

  final String label;
  final IconData? icon;

  /// Shown instead of [icon], e.g. a live progress ring.
  final Widget? leading;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final pill = Container(
      height: 26,
      padding: EdgeInsets.symmetric(horizontal: S.s12),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(R.pill),
        border: Border.all(color: AppColors.border),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (leading != null) ...[
          SizedBox.square(dimension: 13, child: leading),
          SizedBox(width: S.s6),
        ] else if (icon != null) ...[
          Icon(icon, size: 13, color: AppColors.fg3),
          SizedBox(width: S.s6),
        ],
        Text(label, style: sans(12, color: AppColors.fg2)),
      ]),
    );
    if (onTap == null) return pill;
    return Semantics(
      button: true,
      child: TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // Pad the hit area to a touch target without growing the pill.
        child: Padding(padding: EdgeInsets.symmetric(vertical: S.s8), child: pill),
      ),
    );
  }
}
