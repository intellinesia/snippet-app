import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'dialog_widgets.dart';
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
    return Semantics(
      label: '${group.name} ${group.count}',
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
                Text(group.name, style: _emojiStyle(13)),
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
  required VoidCallback onReply,
  required ValueChanged<String> onReact,
}) async {
  final picked = await showAppSheet<MessageAction>(
    context,
    title: 'Message',
    maxWidth: 400,
    maxHeight: 640,
    child: MessageActionsView(text: text),
  );
  switch (picked) {
    case ReplyAction():
      onReply();
    case ReactAction(:final emoji):
      onReact(emoji);
    case null:
  }
}

class MessageActionsView extends StatelessWidget {
  const MessageActionsView({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) {
    void pick(MessageAction a) => Navigator.of(context).pop(a);
    final preview = quotePreviewText(text);
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
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: _SheetAction(
                  icon: 'reply',
                  label: 'Reply',
                  onTap: () => pick(ReplyAction()),
                ),
              ),
              if (text.trim().isNotEmpty) ...[
                const SizedBox(width: 8),
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
            ],
          ),
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

/// Holding a message opens the actions view; there is no hover row.
class MessageBubbleInteractive extends StatelessWidget {
  const MessageBubbleInteractive({
    super.key,
    required this.text,
    required this.onReply,
    required this.onReact,
    required this.builder,
  });

  final String text;
  final VoidCallback onReply;
  final ValueChanged<String> onReact;
  final Widget Function(BuildContext context, VoidCallback openActions) builder;

  @override
  Widget build(BuildContext context) {
    void open() {
      HapticFeedback.selectionClick();
      showMessageActionsSheet(context,
          text: text, onReply: onReply, onReact: onReact);
    }

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onLongPress: open,
      child: builder(context, open),
    );
  }
}
