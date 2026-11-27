import 'package:flutter/material.dart';

import '../tap_detector.dart';
import '../theme.dart';
import '../widgets.dart';
import 'controls.dart';
import 'morph.dart';
import 'tokens.dart';

/// An agent asking the user something: who, an amber dot, the question as
/// prose and two answer pills. Never collapsed.
class MkAskCard extends StatelessWidget {
  const MkAskCard({
    super.key,
    required this.avatar,
    required this.who,
    required this.question,
    this.time,
    this.primary = 'Go ahead',
    this.secondary = 'Not yet',
    this.onPrimary,
    this.onSecondary,
    this.onOpen,
    this.inThread = false,
    this.extra,
  });
  final Widget avatar;
  final String who;
  final String question;
  final String? time;
  final String primary;

  /// Null leaves one full-width primary pill.
  final String? secondary;
  final VoidCallback? onPrimary;
  final VoidCallback? onSecondary;
  final VoidCallback? onOpen;

  /// Inside a chat thread: surface2, 16.5 prose, no outer margin.
  final bool inThread;

  /// Optional widget under the question (a reply field, options).
  final Widget? extra;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      padding: EdgeInsets.fromLTRB(16, 16, 16, inThread ? 14 : 14),
      decoration: BoxDecoration(
        color: inThread ? AppColors.surface2 : AppColors.surface1,
        borderRadius: BorderRadius.circular(inThread ? 22 : MK.cardRadius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            SizedBox.square(dimension: inThread ? 22 : 28, child: avatar),
            const SizedBox(width: 8),
            Flexible(
              child: Text(who,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13.5, color: AppColors.fg2)),
            ),
            const SizedBox(width: 8),
            Container(
                width: 7,
                height: 7,
                decoration:
                    BoxDecoration(color: MK.amber, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text('needs you', style: sans(13.5, color: AppColors.fg3)),
            const Spacer(),
            if (time != null) Text(time!, style: mkTime()),
          ]),
          const SizedBox(height: 10),
          Text(question, style: mkAskProse(size: inThread ? 16.5 : 18.5)),
          if (extra != null) ...[const SizedBox(height: 10), extra!],
          const SizedBox(height: 12),
          Row(children: [
            if (secondary != null) ...[
              Expanded(
                  child: MkPill(secondary!, onTap: onSecondary, expand: true)),
              const SizedBox(width: 8),
            ],
            Expanded(
                child: MkPill(primary,
                    tone: MkPillTone.primary, onTap: onPrimary, expand: true)),
          ]),
        ],
      ),
    );
    return Semantics(
      container: true,
      label: '$who needs you',
      child: TapDetector(
        behavior: HitTestBehavior.deferToChild,
        onTap: onOpen,
        child: card,
      ),
    );
  }
}

/// A working agent as a 150 wide tile: character, name, what it is doing
/// and the morphing indicator in the corner.
class MkWorkingTile extends StatelessWidget {
  const MkWorkingTile({
    super.key,
    required this.avatar,
    required this.name,
    this.subtitle,
    this.working = true,
    this.needsYou = false,
    this.onTap,
    this.onLongPress,
  });
  final Widget avatar;
  final String name;
  final String? subtitle;
  final bool working;
  final bool needsYou;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: [name, if (subtitle != null) subtitle!, if (working) 'working']
          .join(', '),
      excludeSemantics: true,
      child: TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        onLongPress: onLongPress,
        child: Container(
          width: 150,
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(22),
          ),
          child: Stack(children: [
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SizedBox.square(dimension: 44, child: avatar),
                const SizedBox(height: 8),
                Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(14.5, weight: W.label, color: AppColors.fg1)),
                const SizedBox(height: 3),
                Text(subtitle ?? '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(12.5, color: AppColors.fg3)),
              ],
            ),
            Positioned(
              top: 0,
              right: 0,
              child: needsYou
                  ? Container(
                      width: 8,
                      height: 8,
                      margin: const EdgeInsets.all(4),
                      decoration: BoxDecoration(
                          color: MK.amber, shape: BoxShape.circle))
                  : working
                      ? const MkMorph(size: 14)
                      : const SizedBox.shrink(),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Leading state mark for session and task rows: morph while working, a
/// tick in a surface3 disc when completed, an x ring when failed, an empty
/// ring when open, amber dot when it needs the user.
enum MkState { working, done, failed, open, needsYou, idle }

class MkStateMark extends StatelessWidget {
  const MkStateMark(this.state, {super.key, this.size = 22});
  final MkState state;
  final double size;

  @override
  Widget build(BuildContext context) {
    final s = size;
    return switch (state) {
      MkState.working => MkMorph(size: s * 0.82),
      MkState.needsYou => Container(
          width: 9,
          height: 9,
          decoration: BoxDecoration(color: MK.amber, shape: BoxShape.circle)),
      MkState.done => Container(
          width: s,
          height: s,
          decoration:
              BoxDecoration(color: AppColors.surface3, shape: BoxShape.circle),
          child: Center(
              child: AppIcon('check', size: s * 0.58, color: AppColors.fg2)),
        ),
      MkState.failed => Container(
          width: s,
          height: s,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.fg4, width: 1.5)),
          child:
              Center(child: AppIcon('x', size: s * 0.55, color: AppColors.fg3)),
        ),
      MkState.open => Container(
          width: s,
          height: s,
          decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(color: AppColors.fg3, width: 1.5)),
        ),
      MkState.idle => SizedBox.square(dimension: s),
    };
  }
}
