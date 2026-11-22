import 'package:flutter/material.dart';
import '../myna_icons.dart';

import '../mochi.dart';
import '../theme.dart';

/// Desktop soft bubbles: avatar column plus gap, so cards and chips line up.
const double kSoftIndent = 36;
const double _avatar = 26;

/// Desktop: a soft grey bubble; runs stack with tighter corners on the avatar side.
class SoftBubble extends StatelessWidget {
  const SoftBubble({
    super.key,
    required this.child,
    this.mine = false,
    this.first = true,
    this.last = true,
  });

  final Widget child;
  final bool mine;
  final bool first;
  final bool last;

  @override
  Widget build(BuildContext context) {
    const big = Radius.circular(16);
    const small = Radius.circular(6);
    final radius = mine
        ? BorderRadius.only(
            topLeft: big,
            bottomLeft: big,
            topRight: first ? big : small,
            bottomRight: small)
        : BorderRadius.only(
            topRight: big,
            bottomRight: big,
            topLeft: first ? big : small,
            bottomLeft: last ? big : small);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 13, vertical: 9),
      decoration: BoxDecoration(
        color: mine
            ? AppColors.accent.withValues(alpha: 0.16)
            : AppColors.surface2,
        borderRadius: radius,
      ),
      child: child,
    );
  }
}

/// Desktop: an agent's lane. The character sits beside the run's last
/// message; the name and time head its first.
class SoftLane extends StatelessWidget {
  const SoftLane({
    super.key,
    required this.agentId,
    required this.child,
    this.name,
    this.time,
    this.lead = false,
    this.first = true,
    this.last = true,
    this.share = 0.82,
  });

  final String agentId;
  final Widget child;

  /// Shown above the first message of a run when set.
  final String? name;
  final String? time;
  final bool lead;
  final bool first;
  final bool last;

  /// Widest the content may grow, as a share of the lane.
  final double share;

  @override
  Widget build(BuildContext context) {
    final head = first && name != null;
    return LayoutBuilder(builder: (_, box) {
      final max = box.maxWidth.isFinite
          ? (box.maxWidth - kSoftIndent) * share
          : 640.0;
      return Row(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
        SizedBox(
          width: _avatar,
          height: _avatar,
          child: last ? AgentMochi(agentId, size: _avatar) : null,
        ),
        const SizedBox(width: kSoftIndent - _avatar),
        Flexible(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (head)
                Padding(
                  padding: const EdgeInsets.only(left: 12, bottom: 4),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Flexible(
                      child: Text(name!,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(12.5,
                              weight: FontWeight.w500, color: AppColors.fg2)),
                    ),
                    if (lead) ...[
                      const SizedBox(width: 6),
                      Text('lead', style: sans(11, color: AppColors.fg4)),
                    ],
                    if (time != null) ...[
                      const SizedBox(width: 8),
                      Text(time!, style: mono(11, color: AppColors.fg4)),
                    ],
                  ]),
                ),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: max),
                child: child,
              ),
            ],
          ),
        ),
      ]);
    });
  }
}

/// Desktop: the time under your last message, a tick once delivered and an
/// accent double tick once read; the detail sits in the tooltip.
class SentMeta extends StatelessWidget {
  const SentMeta(
      {super.key, required this.time, this.delivered = false, this.read});

  final String time;
  final bool delivered;

  /// "Read 9:01 am" or "Read by Snippet"; null while unread.
  final String? read;

  @override
  Widget build(BuildContext context) {
    final r = read;
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Text(time, style: sans(11, color: AppColors.fg4)),
        if (r != null || delivered) ...[
          const SizedBox(width: 4),
          Tooltip(
            message: r ?? 'Delivered',
            child: Icon(r != null ? MynaIcons.checkCircle : MynaIcons.check,
                size: 13, color: r != null ? AppColors.accent : AppColors.fg4),
          ),
        ],
      ]),
    );
  }
}
