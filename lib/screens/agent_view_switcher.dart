import 'package:flutter/material.dart';

import '../platform.dart';
import '../theme.dart';

enum AgentView { thread, inbox, board }

/// Thread, Inbox and Board as one segmented control; the thumb slides between
/// them.
class AgentViewSwitcher extends StatelessWidget {
  const AgentViewSwitcher({
    super.key,
    required this.value,
    required this.onChanged,
    this.unread = 0,
    bool? compact,
  }) : _compact = compact;

  final AgentView value;
  final ValueChanged<AgentView> onChanged;
  final int unread;
  final bool? _compact;

  static const _labels = {
    AgentView.thread: 'Thread',
    AgentView.inbox: 'Inbox',
    AgentView.board: 'Board',
  };

  @override
  Widget build(BuildContext context) {
    final desktop = _compact ?? !kMobile;
    final height = desktop ? 28.0 : 36.0;
    final dur = reduceMotion(context) ? Duration.zero : Motion.fast;
    const inset = 2.0;
    final style = desktop
        ? sans(12, weight: W.title)
        : sans(13, weight: W.title);
    final selected = AgentView.values.indexOf(value);
    final track = Container(
      height: height,
      padding: const EdgeInsets.all(inset),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(R.md),
      ),
      child: Stack(children: [
        AnimatedAlign(
          duration: dur,
          curve: Motion.enter,
          alignment: Alignment(selected - 1.0, 0),
          child: FractionallySizedBox(
            widthFactor: 1 / AgentView.values.length,
            heightFactor: 1,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surface3,
                borderRadius: BorderRadius.circular(R.md - 2),
              ),
            ),
          ),
        ),
        Row(children: [
          for (final v in AgentView.values)
            Expanded(
              child: Semantics(
                button: true,
                selected: v == value,
                label: _labels[v],
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: v == value ? null : () => onChanged(v),
                  child: Center(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: AnimatedDefaultTextStyle(
                            duration: dur,
                            curve: Motion.exit,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: style.copyWith(
                                color: v == value
                                    ? AppColors.fg1
                                    : AppColors.fg3),
                            child: Text(_labels[v]!),
                          ),
                        ),
                        if (v == AgentView.inbox && unread > 0) ...[
                          const SizedBox(width: 5),
                          _Badge(unread),
                        ],
                      ],
                    ),
                  ),
                ),
              ),
            ),
        ]),
      ]),
    );
    return desktop ? SizedBox(width: 216, child: track) : track;
  }
}

class _Badge extends StatelessWidget {
  const _Badge(this.count);
  final int count;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minWidth: 16),
        height: 16,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.accent,
          borderRadius: BorderRadius.circular(R.pill),
        ),
        child: Text(count > 99 ? '99+' : '$count',
            style: sans(11, weight: W.title, color: AppColors.accentFg)
                .copyWith(height: 1)),
      );
}
