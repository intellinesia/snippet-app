import 'package:flutter/material.dart';

import '../mochi.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';

enum GroupNoticeKind { turn, approved, sentBack, plain }

/// A thread event that is not a message: a turn passing, a verdict, a
/// handoff. One quiet line with a small icon and the time on the right.
class GroupNotice extends StatelessWidget {
  const GroupNotice({
    super.key,
    required this.text,
    this.kind = GroupNoticeKind.plain,
    this.time,
    this.fromAgent,
    this.toAgent,
  });

  final String text;
  final GroupNoticeKind kind;
  final String? time;

  /// Turn passes show both agents around the swap icon.
  final String? fromAgent;
  final String? toAgent;

  Widget _badge(String icon, Color fg, Color bg) => Container(
        width: 22,
        height: 22,
        alignment: Alignment.center,
        child: AppIcon(icon, size: 14, color: AppColors.fg2),
      );

  // MSG-22 desktop: a centred 28-high line, icon 14 fg3 and text 12/400 fg2
  // centred as one unit; plain is the text alone.
  Widget _desk() {
    final icon = switch (kind) {
      GroupNoticeKind.approved => 'check',
      GroupNoticeKind.sentBack => 'undo',
      GroupNoticeKind.turn => 'repeat',
      GroupNoticeKind.plain => null,
    };
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 28),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 5.5, horizontal: 8),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            if (icon != null) ...[
              AppIcon(icon, size: 14, color: AppColors.fg3),
              const SizedBox(width: 8),
            ],
            Flexible(
              child: Text(text,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.center,
                  style: sans(12, height: 17 / 12, color: AppColors.fg2)),
            ),
            if (time != null) ...[
              const SizedBox(width: 8),
              Text(time!, style: sans(11, color: AppColors.fg3, tabular: true)),
            ],
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!kMobile) return _desk();
    final style = sans(kMobile ? 13 : 12, color: AppColors.fg2);
    final Widget lead = switch (kind) {
      GroupNoticeKind.approved => _badge('check', AppColors.ok, AppColors.okBg),
      GroupNoticeKind.sentBack =>
        _badge('undo', AppColors.run, AppColors.runBg),
      GroupNoticeKind.turn => Row(mainAxisSize: MainAxisSize.min, children: [
          if (fromAgent != null) AgentMochi(fromAgent!, size: 20),
          SizedBox(width: S.s8),
          AppIcon('repeat', size: 13, color: AppColors.fg2),
          if (toAgent != null) ...[
            SizedBox(width: S.s8),
            AgentMochi(toAgent!, size: 20),
          ],
        ]),
      GroupNoticeKind.plain => const SizedBox.shrink(),
    };
    return Padding(
      padding: EdgeInsets.symmetric(vertical: S.s6, horizontal: S.s4),
      child: Row(children: [
        if (kind != GroupNoticeKind.plain) ...[lead, SizedBox(width: S.s8)],
        Expanded(
          child: Text(text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign:
                  kind == GroupNoticeKind.plain ? TextAlign.center : null,
              style: style),
        ),
        if (time != null) ...[
          SizedBox(width: S.s8),
          Text(time!, style: sans(12, color: AppColors.fg3)),
        ],
      ]),
    );
  }
}

/// Typing as a dots bubble at the end of the thread.
class GroupTypingBubble extends StatelessWidget {
  const GroupTypingBubble({super.key, required this.dots});

  final Widget dots;

  @override
  Widget build(BuildContext context) => Container(
        padding: EdgeInsets.symmetric(horizontal: S.s16, vertical: S.of(14)),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(R.of(18)),
        ),
        child: dots,
      );
}
