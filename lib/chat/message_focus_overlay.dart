import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import '../dialog_widgets.dart';
import '../glass.dart';
import '../menu_widgets.dart';
import '../theme.dart';

sealed class FocusOutcome {}

class FocusReply extends FocusOutcome {}

class FocusCopy extends FocusOutcome {}

class FocusReact extends FocusOutcome {
  FocusReact(this.emoji);
  final String emoji;
}

class FocusMore extends FocusOutcome {}

Future<void> showMessageFocusOverlay(
  BuildContext context, {
  required Rect bubbleRect,
  required WidgetBuilder bubbleBuilder,
  required bool mine,
  required String text,
  VoidCallback? onReply,
  ValueChanged<String>? onReact,
  List<String> quickReactions = const [],
  List<(String, String)> moreReactions = const [],
}) async {
  HapticFeedback.lightImpact();
  final hasCopy = text.trim().isNotEmpty;
  final showReactions = onReact != null && quickReactions.isNotEmpty;
  final outcome =
      await Navigator.of(context, rootNavigator: true).push<FocusOutcome>(
    _FocusOverlayRoute<FocusOutcome>(
      builder: (routeContext, animation) => MessageFocusOverlay(
        animation: animation,
        bubbleRect: bubbleRect,
        bubbleBuilder: bubbleBuilder,
        mine: mine,
        showReply: onReply != null,
        showCopy: hasCopy,
        quickReactions: showReactions ? quickReactions : const [],
        showMoreButton: showReactions && moreReactions.isNotEmpty,
        onDismiss: () => Navigator.of(routeContext).pop(),
        onPick: (result) => Navigator.of(routeContext).pop(result),
      ),
    ),
  );
  switch (outcome) {
    case FocusReply():
      onReply?.call();
    case FocusCopy():
      Clipboard.setData(ClipboardData(text: text));
      if (context.mounted) toast(context, 'Copied');
    case FocusReact(:final emoji):
      onReact?.call(emoji);
    case FocusMore():
      if (!context.mounted || onReact == null) return;
      final picked = await showMoreReactionsSheet(
        context,
        reactions: moreReactions,
      );
      if (picked != null) onReact(picked);
    case null:
  }
}

Future<String?> showMoreReactionsSheet(
  BuildContext context, {
  required List<(String, String)> reactions,
}) =>
    showAppSheet<String>(
      context,
      title: 'Reactions',
      maxWidth: 400,
      maxHeight: 520,
      child: MessageReactionGrid(reactions: reactions),
    );

class MessageReactionGrid extends StatelessWidget {
  const MessageReactionGrid({super.key, required this.reactions});

  final List<(String, String)> reactions;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth / 4;
        return Wrap(
          children: [
            for (final (emoji, meaning) in reactions)
              Semantics(
                button: true,
                label: 'React $emoji, $meaning',
                child: InkWell(
                  borderRadius: BorderRadius.circular(10),
                  onTap: () => Navigator.of(context).pop(emoji),
                  child: SizedBox(
                    width: w,
                    height: 68,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(emoji,
                            style: const TextStyle(fontSize: 24, height: 1.1)),
                        const SizedBox(height: 4),
                        Text(
                          meaning,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          textAlign: TextAlign.center,
                          style: sans(11, color: AppColors.fg3),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _FocusOverlayRoute<T> extends PageRoute<T> {
  _FocusOverlayRoute({required this.builder});

  final Widget Function(BuildContext context, Animation<double> animation)
      builder;

  @override
  bool get opaque => false;

  @override
  bool get barrierDismissible => false;

  @override
  Color? get barrierColor => null;

  @override
  String? get barrierLabel => null;

  @override
  bool get maintainState => true;

  @override
  Duration get transitionDuration => const Duration(milliseconds: 260);

  @override
  Duration get reverseTransitionDuration => Motion.close;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) =>
      builder(context, animation);

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) =>
      child;
}

class MessageFocusOverlay extends StatelessWidget {
  const MessageFocusOverlay({
    super.key,
    required this.animation,
    required this.bubbleRect,
    required this.bubbleBuilder,
    required this.mine,
    required this.showReply,
    required this.showCopy,
    required this.quickReactions,
    required this.showMoreButton,
    required this.onDismiss,
    required this.onPick,
  });

  final Animation<double> animation;
  final Rect bubbleRect;
  final WidgetBuilder bubbleBuilder;
  final bool mine;
  final bool showReply;
  final bool showCopy;
  final List<String> quickReactions;
  final bool showMoreButton;
  final VoidCallback onDismiss;
  final ValueChanged<FocusOutcome> onPick;

  static const _springCurve = Cubic(0.22, 1.12, 0.36, 1.0);
  static const _gap = 10.0;
  static const _barHeight = 52.0;
  static const _cardWidth = 220.0;
  static const _rowHeight = 44.0;
  static const _sideMargin = 16.0;

  @override
  Widget build(BuildContext context) {
    final calm = reduceMotion(context);
    final media = MediaQuery.of(context);
    final screen = media.size;
    final pad = media.padding;

    final hasReactions = quickReactions.isNotEmpty;
    final actionCount = (showReply ? 1 : 0) + (showCopy ? 1 : 0);
    final hasActions = actionCount > 0;
    final actionsHeight = actionCount == 0
        ? 0.0
        : actionCount * _rowHeight + (actionCount - 1) * 1.0;

    final barSection = hasReactions ? _barHeight + _gap : 0.0;
    final cardSection = hasActions ? _gap + actionsHeight : 0.0;

    final topMin = pad.top + 12.0;
    final bottomMax = screen.height - pad.bottom - 12.0;
    final maxBubbleH = screen.height * 0.45;
    final availableForBubble =
        math.max(48.0, (bottomMax - topMin) - barSection - cardSection);
    final cappedH = math.min(maxBubbleH, availableForBubble);
    final displayBubbleH = math.min(bubbleRect.height, cappedH);
    final clipped = bubbleRect.height > displayBubbleH + 0.5;

    final minBubbleTop = topMin + barSection;
    final maxBubbleTop =
        math.max(minBubbleTop, bottomMax - displayBubbleH - cardSection);
    final bubbleTop =
        bubbleRect.top.clamp(minBubbleTop, maxBubbleTop).toDouble();

    final bubbleW = math.min(
        bubbleRect.width, math.max(40.0, screen.width - _sideMargin * 2));
    final bubbleLeft = bubbleRect.left
        .clamp(
          _sideMargin,
          math.max(_sideMargin, screen.width - _sideMargin - bubbleW),
        )
        .toDouble();
    final bubbleRight = bubbleLeft + bubbleW;

    final barTop = bubbleTop - _barHeight - _gap;
    final cardTop = bubbleTop + displayBubbleH + _gap;

    final cardLeft = (mine ? bubbleRight - _cardWidth : bubbleLeft)
        .clamp(
          _sideMargin,
          math.max(_sideMargin, screen.width - _sideMargin - _cardWidth),
        )
        .toDouble();

    final estimatedBarW = math.min(
      screen.width - _sideMargin * 2,
      20.0 + quickReactions.length * 42.0 + (showMoreButton ? 40.0 : 0.0),
    );
    final barLeft = (mine ? bubbleRight - estimatedBarW : bubbleLeft)
        .clamp(
          _sideMargin,
          math.max(_sideMargin, screen.width - _sideMargin - estimatedBarW),
        )
        .toDouble();

    return Material(
      type: MaterialType.transparency,
      child: AnimatedBuilder(
        animation: animation,
        builder: (context, _) {
          final raw = animation.value;
          final t = raw.clamp(0.0, 1.0);
          final curveT = animation.status == AnimationStatus.reverse
              ? Motion.exit.transform(t)
              : _springCurve.transform(raw);
          final barOpacity = calm
              ? t
              : const Interval(0.0, 0.72).transform(t);
          final bubbleScale = calm ? 1.0 : 0.96 + 0.04 * curveT;
          final barScale = calm ? 1.0 : 0.84 + 0.16 * curveT;

          Widget bubble = Material(
            type: MaterialType.transparency,
            child: SizedBox(
              width: bubbleW,
              child: Align(
                alignment: mine ? Alignment.topRight : Alignment.topLeft,
                child: bubbleBuilder(context),
              ),
            ),
          );
          if (clipped) {
            bubble = ClipRect(
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  stops: [0.0, 0.78, 1.0],
                  colors: [Colors.white, Colors.white, Colors.transparent],
                ).createShader(bounds),
                child: OverflowBox(
                  alignment: Alignment.topCenter,
                  minWidth: bubbleW,
                  maxWidth: bubbleW,
                  minHeight: 0,
                  maxHeight: double.infinity,
                  child: bubble,
                ),
              ),
            );
          }

          final scrimColor = AppColors.glassScrim
              .withValues(alpha: AppColors.glassScrim.a * t);
          Widget backdrop = ColoredBox(color: scrimColor);
          if (Glass.enabled && t > 0.001) {
            backdrop = BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 20 * t, sigmaY: 20 * t),
              child: backdrop,
            );
          }

          return Stack(
            children: [
              Positioned.fill(
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onDismiss,
                  child: backdrop,
                ),
              ),
              Positioned(
                left: bubbleLeft,
                top: bubbleTop,
                width: bubbleW,
                height: displayBubbleH,
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {},
                  child: IgnorePointer(
                    child: Opacity(
                      opacity: t,
                      child: Transform.scale(
                        scale: bubbleScale,
                        alignment: Alignment.center,
                        child: bubble,
                      ),
                    ),
                  ),
                ),
              ),
              if (hasReactions)
                Positioned(
                  left: barLeft,
                  top: barTop,
                  child: Opacity(
                    opacity: barOpacity,
                    child: Transform.scale(
                      scale: barScale,
                      alignment:
                          mine ? Alignment.bottomRight : Alignment.bottomLeft,
                      child: _ReactionBar(
                        reactions: quickReactions,
                        showMore: showMoreButton,
                        onReact: (emoji) => onPick(FocusReact(emoji)),
                        onMore: () => onPick(FocusMore()),
                      ),
                    ),
                  ),
                ),
              if (hasActions)
                Positioned(
                  left: cardLeft,
                  top: cardTop,
                  width: _cardWidth,
                  child: Opacity(
                    opacity: barOpacity,
                    child: Transform.scale(
                      scale: barScale,
                      alignment: mine ? Alignment.topRight : Alignment.topLeft,
                      child: _ActionsCard(
                        showReply: showReply,
                        showCopy: showCopy,
                        onReply: () => onPick(FocusReply()),
                        onCopy: () => onPick(FocusCopy()),
                      ),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _ReactionBar extends StatelessWidget {
  const _ReactionBar({
    required this.reactions,
    required this.showMore,
    required this.onReact,
    required this.onMore,
  });

  final List<String> reactions;
  final bool showMore;
  final ValueChanged<String> onReact;
  final VoidCallback onMore;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: 52,
      child: Glass(
        radius: BorderRadius.circular(28),
        child: Material(
          type: MaterialType.transparency,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                for (final emoji in reactions)
                  Semantics(
                    button: true,
                    label: 'React $emoji',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(20),
                      onTap: () => onReact(emoji),
                      child: SizedBox(
                        width: 42,
                        height: 44,
                        child: Center(
                          child: Text(
                            emoji,
                            style: const TextStyle(fontSize: 28, height: 1.1),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (showMore)
                  Padding(
                    padding: const EdgeInsets.only(left: 4),
                    child: Semantics(
                      button: true,
                      label: 'More reactions',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(18),
                        onTap: onMore,
                        child: Container(
                          width: 34,
                          height: 34,
                          decoration: BoxDecoration(
                            color: AppColors.fg1.withValues(alpha: 0.08),
                            shape: BoxShape.circle,
                          ),
                          alignment: Alignment.center,
                          child: Icon(
                            LucideIcons.plus,
                            size: 18,
                            color: AppColors.fg2,
                          ),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _ActionsCard extends StatelessWidget {
  const _ActionsCard({
    required this.showReply,
    required this.showCopy,
    required this.onReply,
    required this.onCopy,
  });

  final bool showReply;
  final bool showCopy;
  final VoidCallback onReply;
  final VoidCallback onCopy;

  @override
  Widget build(BuildContext context) {
    final dividerColor = AppColors.fg1.withValues(alpha: 0.08);
    return Glass(
      radius: BorderRadius.circular(16),
      child: Material(
        type: MaterialType.transparency,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showReply)
              _ActionRow(
                label: 'Reply',
                icon: LucideIcons.cornerUpLeft,
                onTap: onReply,
              ),
            if (showReply && showCopy) Container(height: 1, color: dividerColor),
            if (showCopy)
              _ActionRow(
                label: 'Copy',
                icon: LucideIcons.copy,
                onTap: onCopy,
              ),
          ],
        ),
      ),
    );
  }
}

class _ActionRow extends StatelessWidget {
  const _ActionRow({
    required this.label,
    required this.icon,
    required this.onTap,
  });

  final String label;
  final IconData icon;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: SizedBox(
        height: 44,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  label,
                  style: sans(15, color: AppColors.fg1),
                ),
              ),
              Icon(icon, size: 16, color: AppColors.fg1),
            ],
          ),
        ),
      ),
    );
  }
}
