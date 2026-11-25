import 'motion_routes.dart' show BackSwipeYield;
import 'dart:math' as math;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'phosphor_icons.dart';

import 'chat/message_focus_overlay.dart';
import 'media_views.dart';
import 'models.dart';
import 'platform.dart';
import 'tap_detector.dart' show HitArea;
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
    this.actors = const [],
  });

  final String name;
  final int count;
  final bool mine;

  /// `kind:id` of everyone who reacted, first first.
  final List<String> actors;
}

String reactionActorLabel(String actor) {
  final i = actor.indexOf(':');
  if (i < 0) return actor;
  if (actor.substring(0, i) == 'human') return 'You';
  return actor.substring(i + 1);
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
    if (e.payload['removed'] == true) {
      actors.removeWhere((a) =>
          a == actor || (e.actorKind == 'human' && a.startsWith('human:')));
    } else {
      actors.add(actor);
    }
  }
  final out = <String, List<ReactionGroup>>{};
  raw.forEach((target, byName) {
    final groups = [
      for (final entry in byName.entries)
        if (entry.value.isNotEmpty)
          ReactionGroup(
            name: entry.key,
            count: entry.value.length,
            mine: entry.value.any((a) => a.startsWith('human:')),
            actors: entry.value.toList(),
          ),
    ];
    if (groups.isNotEmpty) out[target] = groups;
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
    this.author,
    this.deleted = false,
  });

  final String text;
  final bool mine;
  final VoidCallback? onTap;

  /// Desktop: who wrote the original, 12/500 fg2 before the text.
  final String? author;

  /// Desktop: the original is gone; shows "Original message deleted".
  final bool deleted;

  // MSG-06: s2 card radius 8, 2pt fg3 bar, 34 high, one line.
  Widget _desk(double maxW) => Container(
        constraints: BoxConstraints(maxWidth: maxW),
        height: 34,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Container(width: 2, color: AppColors.fg3),
          const SizedBox(width: 10),
          if (deleted) ...[
            Icon(PhIcons.x, size: 12, color: AppColors.fg3),
            const SizedBox(width: 6),
            Flexible(
              child: Text('Original message deleted',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12, color: AppColors.fg3)),
            ),
          ] else ...[
            if (author != null) ...[
              Text('Replying to $author:',
                  maxLines: 1,
                  style:
                      sans(12, weight: FontWeight.w500, color: AppColors.fg2)),
              const SizedBox(width: 6),
            ],
            Flexible(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12, color: AppColors.fg3)),
            ),
          ],
          const SizedBox(width: 10),
        ]),
      );

  @override
  Widget build(BuildContext context) {
    final maxW = mine ? (kMobile ? 280.0 : 440.0) : 460.0;
    final row = !kMobile
        ? _desk(maxW)
        : Container(
            constraints: BoxConstraints(maxWidth: maxW),
            padding: EdgeInsets.only(left: S.s8, top: S.s2, bottom: S.s2),
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
    if (onTap == null || (deleted && !kMobile)) return row;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: HitArea(child: row),
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

  // MSG-07: one s2 strip, 32 high at rest, "Replying to X: ..." 12/400 fg2
  // and a 12 x in a 28 target at the right.
  Widget _desk() => Padding(
        padding: const EdgeInsets.only(bottom: 6),
        child: Container(
          constraints: const BoxConstraints(minHeight: 32, maxHeight: 40),
          padding: const EdgeInsets.only(left: 12, right: 2),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Row(children: [
            Expanded(
              child: Text('Replying to $author: $text',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12, height: 17 / 12, color: AppColors.fg2)),
            ),
            Tooltip(
              message: 'Clear reply',
              child: Semantics(
                button: true,
                label: 'Clear reply',
                child: HoverSurface(
                  radius: 6,
                  hoverColor: AppColors.surface3,
                  onTap: onClear,
                  child: SizedBox.square(
                    dimension: 28,
                    child: Center(
                        child: Icon(PhIcons.x, size: 12, color: AppColors.fg3)),
                  ),
                ),
              ),
            ),
          ]),
        ),
      );

  @override
  Widget build(BuildContext context) {
    if (!kMobile) return _desk();
    return Padding(
      padding: EdgeInsets.fromLTRB(S.s4, S.s2, S.s2, S.s6),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(R.card),
        child: Container(
          padding: EdgeInsets.fromLTRB(S.s8, S.of(5), S.s4, S.of(5)),
          decoration: BoxDecoration(
            color: AppColors.surface2,
            border: Border(left: BorderSide(color: AppColors.fg4, width: 2)),
          ),
          child: Row(
            children: [
              AppIcon('reply', size: 13, color: AppColors.fg3),
              SizedBox(width: S.s6),
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
    if (!kMobile) {
      return DeskReactionRow(
        reactions: reactions,
        onReact: onReact,
        alignment: mine ? WrapAlignment.end : WrapAlignment.start,
      );
    }
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
            padding: EdgeInsets.symmetric(horizontal: S.s6, vertical: S.of(3)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (final r in reactions)
                _ReactionChip(
                  group: r,
                  onTap: () => onReact(r.name),
                  onLongPress: () => showReactionPeople(context, reactions),
                ),
              if (total > 1)
                Padding(
                  padding: EdgeInsets.only(left: S.s2, right: S.s2),
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
  const _ReactionChip({
    required this.group,
    required this.onTap,
    required this.onLongPress,
  });

  final ReactionGroup group;
  final VoidCallback onTap;
  final VoidCallback onLongPress;

  @override
  Widget build(BuildContext context) => Semantics(
        label: '${group.name} ${group.count}',
        button: true,
        child: InkWell(
          borderRadius: BorderRadius.circular(R.card),
          onTap: onTap,
          onLongPress: onLongPress,
          onSecondaryTap: onLongPress,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: S.s2),
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

/// Selected text inside a message, reported up by [MessageSelectionArea] so the
/// right-click menu can offer "Copy selection".
class _MessageMenuScope extends InheritedWidget {
  const _MessageMenuScope({required this.selection, required super.child});
  final ValueNotifier<String> selection;

  @override
  bool updateShouldNotify(_MessageMenuScope old) => old.selection != selection;
}

/// Desktop text selection for a message body, with the app's message menu in
/// place of the system Copy / Select All one.
class MessageSelectionArea extends StatelessWidget {
  const MessageSelectionArea({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final holder = context
        .dependOnInheritedWidgetOfExactType<_MessageMenuScope>()
        ?.selection;
    return SelectionArea(
      onSelectionChanged: holder == null
          ? null
          : (content) => holder.value = content?.plainText ?? '',
      contextMenuBuilder: (_, __) => const SizedBox.shrink(),
      child: child,
    );
  }
}

bool _messageMenuOpen = false;

/// Right-click menu on a desktop message: quick reactions, Reply, Copy.
Future<void> showMessageContextMenu(
  BuildContext context, {
  required Offset point,
  required String text,
  String selection = '',
  VoidCallback? onReply,
  ValueChanged<String>? onReact,
}) async {
  // One menu at a time: a second right-click while open must not stack another.
  if (_messageMenuOpen) return;
  _messageMenuOpen = true;
  final String? picked;
  try {
    picked = await _showSplitMenu(context,
        point: point,
        react: onReact != null,
        actions: [
          if (onReply != null) ('reply', 'reply', 'Reply'),
          if (selection.trim().isNotEmpty)
            ('copy-selection', 'copy', 'Copy selection'),
          if (text.trim().isNotEmpty) ('copy', 'copy', 'Copy message'),
        ]);
  } finally {
    _messageMenuOpen = false;
  }
  if (picked == null) return;
  if (picked == 'reply') {
    onReply?.call();
  } else if (picked == 'copy' || picked == 'copy-selection') {
    await Clipboard.setData(
        ClipboardData(text: picked == 'copy' ? text : selection));
    if (context.mounted) toast(context, 'Copied');
  } else if (picked == 'more') {
    if (!context.mounted) return;
    final more = await _showSplitMenu(context, point: point, grid: true);
    if (more != null && more.startsWith('react:')) {
      onReact?.call(more.substring(6));
    }
  } else if (picked.startsWith('react:')) {
    onReact?.call(picked.substring(6));
  }
}

/// Desktop: a reaction pill floating above a separate card of actions.
Future<String?> _showSplitMenu(
  BuildContext context, {
  Offset? point,
  BuildContext? anchor,
  bool react = true,
  bool grid = false,
  List<(String, String, String)> actions = const [],
}) =>
    showAppMenu<String>(context,
        point: point,
        anchor: anchor,
        below: anchor != null,
        minWidth: grid ? 236 : 208,
        maxWidth: grid ? 236 : 208,
        color: Colors.transparent,
        shape: const RoundedRectangleBorder(),
        items: [_SplitMenuEntry(react: react, grid: grid, actions: actions)]);

class _SplitMenuEntry extends PopupMenuEntry<String> {
  const _SplitMenuEntry(
      {required this.react, required this.grid, required this.actions});
  final bool react;
  final bool grid;
  final List<(String, String, String)> actions;

  @override
  double get height => 120;

  @override
  bool represents(String? value) => false;

  @override
  State<_SplitMenuEntry> createState() => _SplitMenuEntryState();
}

class _SplitMenuEntryState extends State<_SplitMenuEntry> {
  void _pick(String v) => Navigator.of(context).pop(v);

  // DL-02 desktop menu: flat s2 with the single overlay shadow.
  BoxDecoration _surface(double radius) => BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(radius),
        boxShadow: overlayShadow,
      );

  Widget _emoji(String emoji, {String? tip}) {
    final b = HoverSurface(
      radius: 6,
      hoverColor: AppColors.surface3,
      onTap: () => _pick('react:$emoji'),
      child: SizedBox(
          width: 28,
          height: 28,
          child: Center(child: Text(emoji, style: _emojiStyle(15)))),
    );
    return Semantics(
        label: 'React ${tip ?? emoji}',
        button: true,
        child: tip == null ? b : Tooltip(message: tip, child: b));
  }

  @override
  Widget build(BuildContext context) {
    if (widget.grid) {
      return Container(
        padding: const EdgeInsets.all(4),
        decoration: _surface(8),
        child: Wrap(children: [
          for (final (e, label) in kMoreReactions) _emoji(e, tip: label),
        ]),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (widget.react)
          Container(
            padding: const EdgeInsets.all(4),
            decoration: _surface(8),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              for (final e in kMessageReactions) _emoji(e),
              Semantics(
                label: 'More reactions',
                button: true,
                child: HoverSurface(
                  radius: 6,
                  hoverColor: AppColors.surface3,
                  onTap: () => _pick('more'),
                  child: SizedBox(
                      width: 28,
                      height: 28,
                      child: Center(
                          child:
                              AppIcon('plus', size: 14, color: AppColors.fg4))),
                ),
              ),
            ]),
          ),
        if (widget.react && widget.actions.isNotEmpty)
          const SizedBox(height: 6),
        if (widget.actions.isNotEmpty)
          Container(
            width: 208,
            padding: const EdgeInsets.all(4),
            decoration: _surface(8),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              for (final (value, icon, label) in widget.actions)
                HoverSurface(
                  radius: 6,
                  hoverColor: AppColors.surface3,
                  onTap: () => _pick(value),
                  child: SizedBox(
                    height: 28,
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Row(children: [
                        AppIcon(icon, size: 14, color: AppColors.fg3),
                        const SizedBox(width: 8),
                        Text(label, style: sans(12, color: AppColors.fg1)),
                      ]),
                    ),
                  ),
                ),
            ]),
          ),
      ],
    );
  }
}

/// The reaction pill on its own, under the control that opened it.
Future<void> showReactionPicker(BuildContext anchor,
    {required ValueChanged<String> onReact}) async {
  var picked = await _showSplitMenu(anchor, anchor: anchor);
  if (picked == 'more' && anchor.mounted) {
    picked = await _showSplitMenu(anchor, anchor: anchor, grid: true);
  }
  if (picked != null && picked.startsWith('react:')) {
    onReact(picked.substring(6));
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
      padding: EdgeInsets.fromLTRB(S.s16, 0, S.s16, S.s16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (preview.isNotEmpty)
            Container(
              padding:
                  EdgeInsets.symmetric(horizontal: S.s12, vertical: S.of(10)),
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(R.lg),
              ),
              child: Text(
                preview,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: sans(13, color: AppColors.fg2),
              ),
            ),
          if (showReply || hasCopy) ...[
            SizedBox(height: S.s12),
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
                if (showReply && hasCopy) SizedBox(width: S.s8),
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
            SizedBox(height: S.s16),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                for (final emoji in kMessageReactions)
                  Semantics(
                    button: true,
                    label: 'React $emoji',
                    child: InkWell(
                      borderRadius: BorderRadius.circular(R.lg),
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
            SizedBox(height: S.s12),
            Text('More',
                style: sans(12, weight: W.label, color: AppColors.fg3)),
            SizedBox(height: S.s8),
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
                        borderRadius: BorderRadius.circular(R.card),
                        onTap: () => pick(ReactAction(emoji)),
                        child: SizedBox(
                          width: w,
                          height: 64,
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Text(emoji, style: _emojiStyle(24)),
                              SizedBox(height: S.s4),
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
      borderRadius: BorderRadius.circular(R.lg),
      child: InkWell(
        borderRadius: BorderRadius.circular(R.lg),
        onTap: onTap,
        child: SizedBox(
          height: 44,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              AppIcon(icon, size: 15, color: AppColors.fg2),
              SizedBox(width: S.s6),
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
          BuildContext context, VoidCallback openActions, GlobalKey bubbleKey)
      builder;

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
  final ValueNotifier<String> _selection = ValueNotifier('');
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
    _selection.dispose();
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

  void _openMenuAt(Offset point) {
    // Let a right-click's own word selection land first.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showMessageContextMenu(
        context,
        point: point,
        text: widget.text,
        selection: _selection.value,
        onReply: widget.onReply,
        onReact: widget.onReact,
      );
    });
  }

  // A hold opens the focus overlay on both form factors (MSG-08); desktop
  // sizes it to 28 targets. Right-click keeps the context menu (MSG-09).
  void _open() {
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

    final detector = RawGestureDetector(
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
                      PhIcons.arrowElbowUpLeft,
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
    // Bubbles keep swipe-to-reply; back swipe still works from the edge and gaps.
    if (kMobile) return canSwipe ? BackSwipeYield(child: detector) : detector;
    return _MessageMenuScope(
      selection: _selection,
      child: Listener(
        onPointerDown: (e) {
          if (e.buttons == kSecondaryMouseButton) _openMenuAt(e.position);
        },
        child: detector,
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

/// Who reacted with what; tapping your own chip removes it.
void showReactionPeople(BuildContext context, List<ReactionGroup> reactions) {
  showAppSheet(context,
      title: 'Reactions',
      subtitle: reactions.any((r) => r.mine)
          ? 'Tap your reaction to remove it'
          : null,
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        for (final r in reactions)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: S.s16, vertical: S.s8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              SizedBox(width: 32, child: Text(r.name, style: _emojiStyle(18))),
              Expanded(
                child: Text(
                  r.actors.map(reactionActorLabel).join(', '),
                  style: sans(14, height: 1.4, color: AppColors.fg2),
                ),
              ),
            ]),
          ),
      ]));
}

/// Desktop reaction chip (MSG-05): 24 high, radius 12, s2; icon 14 and
/// count 12/400 fg2. Your own reaction steps up to s3 (a tone, not a
/// colour). Hover or press shows who reacted in an s3 tooltip.
class DeskReactionChip extends StatelessWidget {
  const DeskReactionChip({super.key, required this.group, required this.onTap})
      : _add = false,
        more = 0;
  const DeskReactionChip.add({super.key, required this.onTap})
      : group = null,
        _add = true,
        more = 0;

  /// The "+3" pill, 24 x 40, standing in for chips past the cap.
  const DeskReactionChip.more(
      {super.key, required this.more, required this.onTap})
      : group = null,
        _add = false;

  final ReactionGroup? group;
  final VoidCallback onTap;
  final bool _add;
  final int more;

  static const _icons = {
    '\u2705': 'check',
    '\u{1F44D}': 'thumbs-up',
    '\u{1F440}': 'eye',
    '\u2753': 'help-circle',
  };

  Widget _face() {
    final g = group;
    if (_add) {
      return SizedBox(
        width: 18,
        height: 16,
        child: Stack(clipBehavior: Clip.none, children: [
          Icon(Icons.sentiment_satisfied_outlined,
              size: 14, color: AppColors.fg2),
          Positioned(
              right: 0,
              top: 0,
              child: Icon(PhIcons.plus, size: 9, color: AppColors.fg2)),
        ]),
      );
    }
    if (g == null) {
      return Text('+$more',
          style: sans(12, tabular: true, color: AppColors.fg2));
    }
    final icon = _icons[g.name];
    return Row(mainAxisSize: MainAxisSize.min, children: [
      if (icon != null)
        AppIcon(icon, size: 14, color: AppColors.fg2)
      else
        Text(g.name, style: _emojiStyle(13)),
      const SizedBox(width: 4),
      Text('${g.count}', style: sans(12, tabular: true, color: AppColors.fg2)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final g = group;
    final mine = g?.mine ?? false;
    final fill = mine ? AppColors.surface3 : AppColors.surface2;
    final label = _add
        ? 'Add reaction'
        : g == null
            ? '$more more reactions'
            : '${g.name} ${g.count}';
    Widget chip = Semantics(
      button: true,
      selected: mine,
      label: label,
      excludeSemantics: true,
      child: HoverSurface(
        radius: 12,
        rest: fill,
        hoverColor: mine ? AppColors.line : AppColors.surface3,
        onTap: onTap,
        child: SizedBox(
          height: 24,
          width: g == null && !_add ? 40 : null,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: g == null ? 0 : 8),
            child: Center(widthFactor: 1, child: _face()),
          ),
        ),
      ),
    );
    if (g != null && g.actors.isNotEmpty) {
      chip = Tooltip(
        message: g.actors.map(reactionActorLabel).join(', '),
        triggerMode: TooltipTriggerMode.longPress,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: AppColors.surface3,
          borderRadius: BorderRadius.circular(6),
          boxShadow: overlayShadow,
        ),
        textStyle: sans(12, height: 16 / 12, color: AppColors.fg1),
        child: chip,
      );
    }
    return chip;
  }
}

/// Desktop reactions under a message (MSG-05): chips 8 apart, at most
/// [cap] shown with the rest folded into a "+n" pill, then the add chip.
class DeskReactionRow extends StatefulWidget {
  const DeskReactionRow({
    super.key,
    required this.reactions,
    required this.onReact,
    this.cap = 5,
    this.alignment = WrapAlignment.start,
  });

  final List<ReactionGroup> reactions;
  final ValueChanged<String> onReact;
  final int cap;
  final WrapAlignment alignment;

  @override
  State<DeskReactionRow> createState() => _DeskReactionRowState();
}

class _DeskReactionRowState extends State<DeskReactionRow> {
  bool _all = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.reactions;
    final fold = !_all && r.length > widget.cap;
    final shown = fold ? r.take(widget.cap - 1).toList() : r;
    return Wrap(
      spacing: 8,
      runSpacing: 8,
      alignment: widget.alignment,
      children: [
        for (final g in shown)
          DeskReactionChip(group: g, onTap: () => widget.onReact(g.name)),
        if (fold)
          DeskReactionChip.more(
              more: r.length - shown.length,
              onTap: () => setState(() => _all = true)),
        Builder(
            builder: (anchor) => DeskReactionChip.add(
                onTap: () =>
                    showReactionPicker(anchor, onReact: widget.onReact))),
      ],
    );
  }
}
