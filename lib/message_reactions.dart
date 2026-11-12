import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'media_views.dart';
import 'models.dart';
import 'platform.dart';
import 'theme.dart';
import 'widgets.dart';

const kMessageReactions = <String>[
  'check',
  'eyes',
  'thumbs_up',
  'question',
  'thinking',
];

String messageReactionIcon(String name) => switch (name) {
      'check' => 'check',
      'eyes' => 'eye',
      'thumbs_up' => 'thumbs-up',
      'question' => 'help-circle',
      'thinking' => 'brain',
      _ => 'sparkles',
    };

String messageReactionLabel(String name) => switch (name) {
      'check' => 'Check',
      'eyes' => 'Eyes',
      'thumbs_up' => 'Thumbs up',
      'question' => 'Question',
      'thinking' => 'Thinking',
      _ => name,
    };

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
    final name = e.reaction;
    final target = e.replyTo;
    if (name == null || target == null) continue;
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

  @override
  Widget build(BuildContext context) {
    if (reactions.isEmpty) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 6,
        runSpacing: 4,
        alignment: mine ? WrapAlignment.end : WrapAlignment.start,
        children: [
          for (final r in reactions)
            _ReactionChip(
              group: r,
              onTap: () => onReact(r.name),
            ),
        ],
      ),
    );
  }
}

class _ReactionChip extends StatelessWidget {
  const _ReactionChip({required this.group, required this.onTap});

  final ReactionGroup group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final active = group.mine;
    return Tooltip(
      message: messageReactionLabel(group.name),
      child: Material(
        color: active ? AppColors.accentBg : AppColors.surface2,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: onTap,
          child: Container(
            height: 24,
            padding: const EdgeInsets.symmetric(horizontal: 8),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: active ? AppColors.accentLine : AppColors.border,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AppIcon(
                  messageReactionIcon(group.name),
                  size: 13,
                  color: active ? AppColors.accent : AppColors.fg2,
                ),
                const SizedBox(width: 4),
                Text(
                  '${group.count}',
                  style: sans(
                    11,
                    tabular: true,
                    weight: W.label,
                    color: active ? AppColors.accent : AppColors.fg3,
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

/// Compact row offering `Reply` and the five icon reactions (never emoji).
class MessageActionRow extends StatelessWidget {
  const MessageActionRow({
    super.key,
    required this.onReply,
    required this.onReact,
  });

  final VoidCallback onReply;
  final ValueChanged<String> onReact;

  @override
  Widget build(BuildContext context) {
    final btnSize = kMobile ? 36.0 : 28.0;
    final iconSize = kMobile ? 16.0 : 14.0;
    return Material(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: kMobile ? 6 : 4,
          vertical: kMobile ? 4 : 3,
        ),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: AppColors.border2),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _ReplyBtn(onTap: onReply),
            Container(
              width: 1,
              height: kMobile ? 18 : 14,
              margin: const EdgeInsets.symmetric(horizontal: 4),
              color: AppColors.border2,
            ),
            for (final name in kMessageReactions)
              Tooltip(
                message: messageReactionLabel(name),
                child: InkWell(
                  borderRadius: BorderRadius.circular(8),
                  onTap: () => onReact(name),
                  child: SizedBox.square(
                    dimension: btnSize,
                    child: Center(
                      child: AppIcon(
                        messageReactionIcon(name),
                        size: iconSize,
                        color: AppColors.fg2,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _ReplyBtn extends StatelessWidget {
  const _ReplyBtn({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return InkWell(
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: EdgeInsets.symmetric(
          horizontal: kMobile ? 8 : 6,
          vertical: kMobile ? 7 : 5,
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            AppIcon('reply', size: kMobile ? 15 : 13, color: AppColors.fg2),
            const SizedBox(width: 4),
            Text(
              'Reply',
              style: sans(12, weight: W.label, color: AppColors.fg2),
            ),
          ],
        ),
      ),
    );
  }
}

/// Show a floating action row anchored to [anchor] (used on long-press).
Future<void> showMessageActionsPopover(
  BuildContext anchor, {
  required bool alignRight,
  required VoidCallback onReply,
  required ValueChanged<String> onReact,
}) {
  final box = anchor.findRenderObject() as RenderBox?;
  final overlay = Overlay.of(anchor, rootOverlay: true)
      .context
      .findRenderObject() as RenderBox?;
  if (box == null || overlay == null) return Future<void>.value();
  final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
  final screen = overlay.size;
  final above = origin.dy > 80;
  final top = above ? null : (origin.dy + box.size.height + 6);
  final bottom = above ? (screen.height - origin.dy + 6) : null;
  final left = alignRight ? null : origin.dx.clamp(12.0, screen.width - 260);
  final right = alignRight
      ? (screen.width - (origin.dx + box.size.width))
          .clamp(12.0, screen.width - 260)
      : null;
  return showGeneralDialog<void>(
    context: anchor,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 140),
    pageBuilder: (ctx, _, __) => CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.escape): () =>
            Navigator.of(ctx).pop(),
      },
      child: Focus(
        autofocus: true,
        child: Stack(
          children: [
            Positioned(
              left: left,
              right: right,
              top: top,
              bottom: bottom,
              child: MessageActionRow(
                onReply: () {
                  Navigator.of(ctx).pop();
                  onReply();
                },
                onReact: (name) {
                  Navigator.of(ctx).pop();
                  onReact(name);
                },
              ),
            ),
          ],
        ),
      ),
    ),
  );
}

/// Wraps a message bubble row with long-press (mobile & desktop) and desktop
/// hover action row for `Reply` and the five icon reactions.
class MessageBubbleInteractive extends StatefulWidget {
  const MessageBubbleInteractive({
    super.key,
    required this.mine,
    required this.onReply,
    required this.onReact,
    required this.builder,
  });

  final bool mine;
  final VoidCallback onReply;
  final ValueChanged<String> onReact;
  final Widget Function(BuildContext context, VoidCallback openActions) builder;

  @override
  State<MessageBubbleInteractive> createState() =>
      _MessageBubbleInteractiveState();
}

class _MessageBubbleInteractiveState extends State<MessageBubbleInteractive> {
  bool _hover = false;

  void _openPopover() {
    if (!mounted) return;
    HapticFeedback.selectionClick();
    showMessageActionsPopover(
      context,
      alignRight: widget.mine,
      onReply: widget.onReply,
      onReact: widget.onReact,
    );
  }

  @override
  Widget build(BuildContext context) {
    final child = GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: _openPopover,
      child: widget.builder(context, _openPopover),
    );
    if (kMobile) return child;
    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          child,
          if (_hover)
            Positioned(
              top: -6,
              right: 0,
              child: MessageActionRow(
                onReply: widget.onReply,
                onReact: widget.onReact,
              ),
            ),
        ],
      ),
    );
  }
}
