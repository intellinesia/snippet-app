import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'chat/message_focus_overlay.dart';
import 'media_views.dart';
import 'models.dart';
import 'platform.dart';
import 'theme.dart';
import 'widgets.dart';

/// Quick reactions offered on a message; any single emoji is accepted.
const kMessageReactions = <String>['👍', '❤️', '😂', '👀', '✅'];

/// The "+" grid: specific signals for working with agents, with what each means.
const kMoreReactions = <(String, String)>[
  ('🚀', 'Ship it'),
  ('🐛', 'Bug'),
  ('🧪', 'Needs tests'),
  ('🔍', 'Look closer'),
  ('🛑', 'Stop'),
  ('⏳', 'Waiting'),
  ('🫡', 'On it'),
  ('🤝', 'Agreed'),
  ('💡', 'Idea'),
  ('⚠️', 'Careful'),
  ('📌', 'Remember this'),
  ('🎯', 'Spot on'),
  ('🧹', 'Clean up'),
  ('🧠', 'Smart'),
  ('🙏', 'Thanks'),
  ('💯', 'Fully'),
  ('🔥', 'Great'),
  ('🤯', 'Wow'),
];

/// Agents react with names; show them as emoji so both merge into one chip.
String messageReactionEmoji(String name) => switch (name) {
      'check' => '✅',
      'eyes' => '👀',
      'thumbs_up' => '👍',
      'question' => '❓',
      'thinking' => '🤔',
      _ => name,
    };

TextStyle _emojiStyle(double size) => TextStyle(fontSize: size, height: 1.1);

class ReactionGroup {
  const ReactionGroup({
    required this.name,
    required this.count,
    required this.mine,
  });

  final String name;
  final int count;
  final bool mine;
}

bool isReactionEvent(CoordinationEvent e) =>
    e.reaction != null || e.payload['kind'] == 'reaction';

/// Group reactions by target `eventId`, preserving first-seen reaction order
/// and deduplicating repeated identical reactions from the same actor.
Map<String, List<ReactionGroup>> groupMessageReactions(
  List<CoordinationEvent> events,
) {
  final raw = <String, Map<String, Set<String>>>{};
  for (final e in events) {
    final reaction = e.reaction;
    final target = e.replyTo;
    if (reaction == null || target == null) continue;
    final name = messageReactionEmoji(reaction);
    final byName = raw.putIfAbsent(target, () => <String, Set<String>>{});
    final actors = byName.putIfAbsent(name, () => <String>{});
    final actor = '${e.actorKind}:${e.actorId.isEmpty ? e.eventId : e.actorId}';
    actors.add(actor);
  }
  final out = <String, List<ReactionGroup>>{};
  raw.forEach((target, byName) {
    out[target] = [
      for (final entry in byName.entries)
        ReactionGroup(
          name: entry.key,
          count: entry.value.length,
          mine: entry.value.any((a) => a.startsWith('human:')),
        ),
    ];
  });
  return out;
}

String quotePreviewText(String raw) {
  final (_, body) = splitPastedBlocks(raw);
  final clean = hideAttachmentMarkers(body).trim();
  if (clean.isNotEmpty) {
    return clean.replaceAll(RegExp(r'\s+'), ' ');
  }
  final items = parseSentAttachments(raw);
  if (items.isNotEmpty) return 'Attachment';
  return raw.trim();
}

/// Quoted reply line shown above a bubble (2 lines max, muted, 2 px left border
/// in `AppColors.fg4`).
class QuotedReplyLine extends StatelessWidget {
  const QuotedReplyLine({
    super.key,
    required this.text,
    this.mine = false,
    this.onTap,
  });

  final String text;
  final bool mine;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final maxW = mine ? (kMobile ? 280.0 : 440.0) : 460.0;
    final row = Container(
      constraints: BoxConstraints(maxWidth: maxW),
      padding: const EdgeInsets.only(left: 8, top: 2, bottom: 2),
      decoration: BoxDecoration(
        border: Border(left: BorderSide(color: AppColors.fg4, width: 2)),
      ),
      child: Text(
        text,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: sans(12, height: 1.35, color: AppColors.fg3),
      ),
    );
    if (onTap == null) return row;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: row,
      ),
    );
  }
}

/// Composer banner showing the pending `_replyTo` target with a clear button.
class PendingReplyBanner extends StatelessWidget {
  const PendingReplyBanner({
    super.key,
    required this.author,
    required this.text,
    required this.onClear,
  });

  final String author;
  final String text;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 2, 2, 6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(10),
        child: Container(
          padding: const EdgeInsets.fromLTRB(8, 5, 4, 5),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            border: Border(left: BorderSide(color: AppColors.fg4, width: 2)),
          ),
          child: Row(
            children: [
              AppIcon('reply', size: 13, color: AppColors.fg3),
              const SizedBox(width: 6),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Replying to $author',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(11, weight: W.label, color: AppColors.fg2),
                    ),
                    Text(
                      text,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(12, color: AppColors.fg3),
                    ),
                  ],
                ),
              ),
              IconBtn(
                'x',
                size: 24,
                iconSize: 13,
                tooltip: 'Clear reply',
                onTap: onClear,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Grouped reaction chips rendered beneath a target message bubble.
class MessageReactionChips extends StatelessWidget {
  const MessageReactionChips({
    super.key,
    required this.reactions,
    required this.mine,
    required this.onReact,
  });

  final List<ReactionGroup> reactions;
  final bool mine;
  final ValueChanged<String> onReact;

  /// How far the tapback rises above and past the bubble's corner.
  static const double rise = 12;
  static const double overhang = 6;

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();
    final total = reactions.fold<int>(0, (n, r) => n + r.count);
    final active = reactions.any((r) => r.mine);
    final fill = active ? AppColors.accentBg : AppColors.surface2;
    return Semantics(
      container: true,
      child: Stack(clipBehavior: Clip.none, children: [
        Material(
          color: fill,
          shape: StadiumBorder(side: BorderSide(color: AppColors.bg, width: 2)),
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (final r in reactions)
                _ReactionChip(group: r, onTap: () => onReact(r.name)),
              if (total > 1)
                Padding(
                  padding: const EdgeInsets.only(left: 2, right: 2),
                  child: Text('$total',
                      style: sans(11,
                          tabular: true,
                          weight: W.label,
                          color: active ? AppColors.accent : AppColors.fg3)),
                ),
            ]),
          ),
        ),
        // The small trailing bubble that points at the message, as in iMessage.
        Positioned(
          bottom: -3,
          left: mine ? null : 2,
          right: mine ? 2 : null,
          child: IgnorePointer(
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: fill,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.bg, width: 1.5),
              ),
            ),
          ),
        ),
      ]),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({required this.group, required this.onTap});

  final ReactionGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '${group.name} ${group.count}',
        button: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(10),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 2),
            child: Text(group.name, style: _emojiStyle(14)),
          ),
        ),
      );
}

/// Compact row offering `Reply` and the quick emoji reactions.
/// What a hold on a message picked in [showMessageActionsSheet].
sealed class MessageAction {}

class ReplyAction extends MessageAction {}

class ReactAction extends MessageAction {
  ReactAction(this.emoji);
  final String emoji;
}

/// The view a held message opens: a preview, Reply and Copy, then every
/// reaction with what it means.
Future<void> showMessageActionsSheet(
  BuildContext context, {
  required String text,
  VoidCallback? onReply,
  ValueChanged<String>? onReact,
}) async {
  final picked = await showAppSheet<MessageAction>(
    context,
    title: 'Message',
    maxWidth: 400,
    maxHeight: 640,
    child: MessageActionsView(
      text: text,
      showReply: onReply != null,
      showReactions: onReact != null,
    ),
  );
  switch (picked) {
    case ReplyAction():
      onReply?.call();
    case ReactAction(:final emoji):
      onReact?.call(emoji);
    case null:
  }
}

class MessageActionsView extends StatelessWidget {
  const MessageActionsView({
    super.key,
    required this.text,
    this.showReply = true,
    this.showReactions = true,
  });
  final String text;
  final bool showReply;
  final bool showReactions;

  @override
  Widget build(BuildContext context) {
    void pick(MessageAction a) => Navigator.of(context).pop(a);
    final preview = quotePreviewText(text);
    final hasCopy = text.trim().isNotEmpty;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (preview.isNotEmpty)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                preview,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: sans(13, color: AppColors.fg2),
              ),
            ),
          if (showReply || hasCopy) ...[
            const SizedBox(height: 12),
            Row(
              children: [
                if (showReply)
                  Expanded(
                    child: _SheetAction(
                      icon: 'reply',
                      label: 'Reply',
                      onTap: () => pick(ReplyAction()),
                    ),
                  ),
                if (showReply && hasCopy) const SizedBox(width: 8),
                if (hasCopy)
                  Expanded(
                    child: _SheetAction(
                      icon: 'copy',
                      label: 'Copy',
                      onTap: () {
                        Clipboard.setData(ClipboardData(text: text));
                        toast(context, 'Copied');
                        Navigator.of(context).pop();
                      },
                    ),
                  ),
              ],
            ),
          ],
          if (showReactions) ...[
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final emoji in kMessageReactions)
                  Semantics(
                    button: true,
                    label: 'React $emoji',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(12),
                      onTap: () => pick(ReactAction(emoji)),
                      child: SizedBox.square(
                        dimension: 48,
                        child: Center(
                          child: Text(emoji, style: _emojiStyle(26)),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            Text('More', style: sans(12, weight: W.label, color: AppColors.fg3)),
            const SizedBox(height: 8),
            LayoutBuilder(builder: (context, c) {
              final cols = (c.maxWidth / 76).floor().clamp(3, 6);
              final w = c.maxWidth / cols;
              return Wrap(
                children: [
                  for (final (emoji, meaning) in kMoreReactions)
                    Semantics(
                      button: true,
                      label: 'React $emoji, $meaning',
                      child: InkWell(
                        borderRadius: BorderRadius.circular(10),
                        onTap: () => pick(ReactAction(emoji)),
                        child: SizedBox(
                          width: w,
                          height: 64,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(emoji, style: _emojiStyle(24)),
                              const SizedBox(height: 4),
                              Text(
                                meaning,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: sans(11, color: AppColors.fg3),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              );
            }),
          ],
        ],
      ),
    );
  }
}

class _SheetAction extends StatelessWidget {
  const _SheetAction(
      {required this.icon, required this.label, required this.onTap});
  final String icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(12),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: onTap,
        child: SizedBox(
          height: 44,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppIcon(icon, size: 15, color: AppColors.fg2),
              const SizedBox(width: 6),
              Text(label,
                  style: sans(13, weight: W.label, color: AppColors.fg2)),
            ],
          ),
        ),
      ),
    );
  }
}

/// Holding a message opens the focused overlay (phone) or actions sheet
/// (desktop); on phone, swiping right replies.
class MessageBubbleInteractive extends StatefulWidget {
  const MessageBubbleInteractive({
    super.key,
    required this.text,
    this.mine = false,
    this.onReply,
    this.onReact,
    this.focusBuilder,
    required this.builder,
  });

  final String text;
  final bool mine;
  final VoidCallback? onReply;
  final ValueChanged<String>? onReact;
  final WidgetBuilder? focusBuilder;
  final Widget Function(
      BuildContext context, VoidCallback openActions, GlobalKey bubbleKey) builder;

  @override
  State<MessageBubbleInteractive> createState() =>
      _MessageBubbleInteractiveState();
}

class _MessageBubbleInteractiveState extends State<MessageBubbleInteractive>
    with SingleTickerProviderStateMixin {
  static const double _swipeTrigger = 56.0;
  static const double _swipeMax = 72.0;

  final GlobalKey _bubbleKey = GlobalKey();
  final GlobalKey _contentKey = GlobalKey();
  late final AnimationController _spring;

  double _dragOffset = 0;
  double _springStart = 0;
  double? _downGlobalX;
  bool _crossedThreshold = false;

  @override
  void initState() {
    super.initState();
    _spring = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 220),
    )..addListener(() {
        setState(() {
          _dragOffset = _springStart *
              (1.0 - Curves.easeOutCubic.transform(_spring.value));
        });
      });
  }

  @override
  void dispose() {
    _spring.dispose();
    super.dispose();
  }

  double _applyResistance(double fingerDx) {
    if (fingerDx <= 0) return 0;
    if (fingerDx <= 40) return fingerDx;
    return 40.0 +
        (_swipeMax - 40.0) * (1.0 - math.exp(-(fingerDx - 40.0) / 32.0));
  }

  void _updateDrag(double globalX) {
    final fingerDx = globalX - (_downGlobalX ?? globalX);
    final next = _applyResistance(fingerDx);
    if (!_crossedThreshold && next >= _swipeTrigger) {
      _crossedThreshold = true;
      HapticFeedback.selectionClick();
    } else if (_crossedThreshold && next < _swipeTrigger) {
      _crossedThreshold = false;
    }
    setState(() => _dragOffset = next);
  }

  void _endDrag() {
    final triggered = _dragOffset >= _swipeTrigger;
    _downGlobalX = null;
    _crossedThreshold = false;
    if (triggered) widget.onReply?.call();
    if (_dragOffset <= 0 || reduceMotion(context)) {
      if (_dragOffset != 0) setState(() => _dragOffset = 0);
      return;
    }
    _springStart = _dragOffset;
    _spring.forward(from: 0);
  }

  void _open() {
    if (!kMobile) {
      HapticFeedback.selectionClick();
      showMessageActionsSheet(
        context,
        text: widget.text,
        onReply: widget.onReply,
        onReact: widget.onReact,
      );
      return;
    }
    final targetCtx = _bubbleKey.currentContext ?? _contentKey.currentContext;
    final box = targetCtx?.findRenderObject() as RenderBox?;
    if (box == null || !box.hasSize) return;
    final rect = box.localToGlobal(Offset.zero) & box.size;
    final react = widget.onReact;
    showMessageFocusOverlay(
      context,
      bubbleRect: rect,
      bubbleBuilder: widget.focusBuilder ??
          (ctx) => widget.builder(ctx, () {}, GlobalKey()),
      mine: widget.mine,
      text: widget.text,
      onReply: widget.onReply,
      onReact: react,
      quickReactions: react != null ? kMessageReactions : const [],
      moreReactions: react != null ? kMoreReactions : const [],
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSwipe = kMobile && widget.onReply != null;
    final gestures = <Type, GestureRecognizerFactory>{
      LongPressGestureRecognizer:
          GestureRecognizerFactoryWithHandlers<LongPressGestureRecognizer>(
        () => LongPressGestureRecognizer(debugOwner: this),
        (r) => r.onLongPress = _open,
      ),
      if (canSwipe)
        _SwipeRightReplyRecognizer:
            GestureRecognizerFactoryWithHandlers<_SwipeRightReplyRecognizer>(
          () => _SwipeRightReplyRecognizer(debugOwner: this),
          (r) {
            r.onDown = (d) {
              _spring.stop();
              _downGlobalX = d.globalPosition.dx;
            };
            r.onStart = (d) {
              _spring.stop();
              _downGlobalX ??= d.globalPosition.dx;
              _updateDrag(d.globalPosition.dx);
            };
            r.onUpdate = (d) => _updateDrag(d.globalPosition.dx);
            r.onEnd = (_) => _endDrag();
            r.onCancel = _endDrag;
          },
        ),
    };

    final child = KeyedSubtree(
      key: _contentKey,
      child: widget.builder(context, _open, _bubbleKey),
    );
    final progress = (_dragOffset / _swipeTrigger).clamp(0.0, 1.0);
    final armed = _dragOffset >= _swipeTrigger;

    return RawGestureDetector(
      behavior: HitTestBehavior.translucent,
      gestures: gestures,
      child: Stack(
        alignment: Alignment.centerLeft,
        clipBehavior: Clip.none,
        children: [
          if (progress > 0.001)
            Positioned(
              left: 4,
              child: Opacity(
                opacity: progress,
                child: Transform.scale(
                  scale: 0.5 + 0.5 * progress,
                  child: Container(
                    width: 30,
                    height: 30,
                    decoration: BoxDecoration(
                      color: armed ? AppColors.accentBg : AppColors.surface2,
                      shape: BoxShape.circle,
                    ),
                    alignment: Alignment.center,
                    child: Icon(
                      LucideIcons.cornerUpLeft,
                      size: 16,
                      color: armed ? AppColors.accent : AppColors.fg3,
                    ),
                  ),
                ),
              ),
            ),
          Transform.translate(
            offset: Offset(_dragOffset, 0),
            child: child,
          ),
        ],
      ),
    );
  }
}

/// Only claims clearly-horizontal rightward drags away from the left screen edge.
class _SwipeRightReplyRecognizer extends HorizontalDragGestureRecognizer {
  _SwipeRightReplyRecognizer({super.debugOwner});

  static const double _edgeGuard = 24.0;

  final Map<int, Offset> _downPositions = <int, Offset>{};
  Offset _lastTotal = Offset.zero;
  bool _accepted = false;

  @override
  bool isPointerAllowed(PointerEvent event) {
    if (event is PointerDownEvent && event.position.dx < _edgeGuard) {
      return false;
    }
    return super.isPointerAllowed(event);
  }

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _downPositions[event.pointer] = event.position;
    _lastTotal = Offset.zero;
    super.addAllowedPointer(event);
  }

  @override
  void acceptGesture(int pointer) {
    _accepted = true;
    super.acceptGesture(pointer);
  }

  @override
  void rejectGesture(int pointer) {
    _accepted = false;
    _downPositions.remove(pointer);
    super.rejectGesture(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _accepted = false;
    _downPositions.remove(pointer);
    super.didStopTrackingLastPointer(pointer);
  }

  @override
  void handleEvent(PointerEvent event) {
    if (!_accepted && event is PointerMoveEvent) {
      final start = _downPositions[event.pointer];
      if (start != null) {
        final total = event.position - start;
        _lastTotal = total;
        final slop = gestureSettings?.touchSlop ?? kTouchSlop;
        if (total.dx < -slop ||
            (total.dy.abs() > slop && total.dy.abs() * 1.2 >= total.dx)) {
          resolve(GestureDisposition.rejected);
          return;
        }
      }
    }
    super.handleEvent(event);
  }

  @override
  bool hasSufficientGlobalDistanceToAccept(
    PointerDeviceKind pointerDeviceKind,
    double? deviceTouchSlop,
  ) =>
      _lastTotal.dx > _lastTotal.dy.abs() * 1.5 &&
      super.hasSufficientGlobalDistanceToAccept(
          pointerDeviceKind, deviceTouchSlop);
}
