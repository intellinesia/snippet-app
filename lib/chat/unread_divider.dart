import 'package:flutter/material.dart';

import '../tap_detector.dart';
import '../theme.dart';
import '../widgets.dart';

/// MSG-19: hairline, centred unread count, and the tonal jump affordance.
class UnreadDivider extends StatelessWidget {
  const UnreadDivider({super.key, required this.count, this.onJump});

  final int count;
  final VoidCallback? onJump;

  @override
  Widget build(BuildContext context) {
    final label = count == 1 ? '1 new message' : '$count new messages';
    return Column(mainAxisSize: MainAxisSize.min, children: [
      SizedBox(
        height: 32,
        child: Row(children: [
          Expanded(child: Container(height: 1, color: AppColors.line)),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Text(label,
                maxLines: 1,
                style: sans(13,
                    height: 18 / 13,
                    weight: FontWeight.w500,
                    color: AppColors.fg2)),
          ),
          Expanded(child: Container(height: 1, color: AppColors.line)),
        ]),
      ),
      if (onJump != null) ...[
        const SizedBox(height: 8),
        Center(
          child: TapDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onJump,
            child: Container(
              width: 154,
              height: 36,
              decoration: BoxDecoration(
                color: AppColors.surface3,
                borderRadius: BorderRadius.circular(22),
              ),
              child: Row(children: [
                const SizedBox(width: 14),
                AppIcon('arrow-down', size: 14, color: AppColors.fg1),
                const SizedBox(width: 5),
                Expanded(
                  child: Text('Jump to latest',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(13,
                          height: 18 / 13,
                          weight: FontWeight.w500,
                          color: AppColors.fg1)),
                ),
                Container(
                  width: 20,
                  height: 18,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surface2,
                    borderRadius: BorderRadius.circular(9),
                  ),
                  child: Text('$count',
                      style: sans(11,
                          height: 15 / 11,
                          weight: FontWeight.w500,
                          color: AppColors.fg1)),
                ),
                const SizedBox(width: 8),
              ]),
            ),
          ),
        ),
      ],
    ]);
  }
}
