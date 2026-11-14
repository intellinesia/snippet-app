import 'package:flutter/material.dart';

import '../desktop_look.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';

/// Shared parts for cards that sit in a chat: artifacts, approvals and
/// questions. One shell, one headline, one quiet meta line, at most one solid
/// button.
class ChatCard extends StatelessWidget {
  const ChatCard({
    super.key,
    required this.children,
    this.maxWidth = 460,
    this.dimmed = false,
  });

  final List<Widget> children;
  final double maxWidth;

  /// Resolved cards recede.
  final bool dimmed;

  static double get pad => kMobile ? 16 : 14;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        // Without it a height-capped slot centres the card in the cap.
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxWidth: maxWidth),
          child: Tactile(
            radius: BorderRadius.circular(16),
            child: Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              color: AppColors.surface1,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: AppColors.lineStrong),
            ),
            // Own Material so row hovers paint inside the rounded clip.
            child: Material(
              type: MaterialType.transparency,
              child: Opacity(
                opacity: dimmed ? 0.85 : 1,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: children,
                ),
              ),
            ),
          ),
          ),
        ),
      );
}

/// Headline, optional meta line, optional trailing pill or chevron.
class ChatCardHeader extends StatelessWidget {
  const ChatCardHeader({
    super.key,
    required this.title,
    this.subtitle,
    this.subtitleView,
    this.trailing,
    this.eyebrow,
    this.large = true,
    this.padBottom = true,
  });

  final String title;
  final String? subtitle;
  final Widget? subtitleView;
  final Widget? trailing;

  /// Small line above the title, such as "Question 2 of 3".
  final Widget? eyebrow;
  final bool large;
  final bool padBottom;

  @override
  Widget build(BuildContext context) {
    final p = ChatCard.pad;
    final size = large ? (kMobile ? 17.0 : 15.0) : (kMobile ? 15.0 : 14.0);
    return Padding(
      padding: EdgeInsets.fromLTRB(p, p - 2, p, padBottom ? p - 2 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (eyebrow != null) ...[eyebrow!, const SizedBox(height: 8)],
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      style: sans(size,
                          weight: W.strong, height: 1.3, color: AppColors.fg1)),
                  if (subtitleView != null)
                    Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: subtitleView)
                  else if (subtitle != null && subtitle!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Text(subtitle!,
                          style: sans(13, height: 1.4, color: AppColors.fg3)),
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          ]),
        ],
      ),
    );
  }
}

/// Card body inset to the card padding.
class ChatCardBody extends StatelessWidget {
  const ChatCardBody({super.key, required this.child, this.bottom = true});

  final Widget child;
  final bool bottom;

  @override
  Widget build(BuildContext context) {
    final p = ChatCard.pad;
    return Padding(
      padding: EdgeInsets.fromLTRB(p, 0, p, bottom ? p - 2 : 0),
      child: child,
    );
  }
}

class ChatCardDivider extends StatelessWidget {
  const ChatCardDivider({super.key});

  @override
  Widget build(BuildContext context) =>
      Container(height: 1, color: AppColors.line);
}

enum ChatCardButtonKind { primary, secondary, danger }

class ChatCardButton {
  const ChatCardButton(this.label,
      {this.onTap, this.kind = ChatCardButtonKind.primary, this.busy = false});

  final String label;
  final VoidCallback? onTap;
  final ChatCardButtonKind kind;
  final bool busy;
}

/// Full-width pill buttons. Stacked on the phone when [stack] is set (the
/// Duet shape), side by side otherwise; an optional quiet link sits below.
class ChatCardActions extends StatelessWidget {
  const ChatCardActions({
    super.key,
    required this.buttons,
    this.stack = false,
    this.link,
    this.onLink,
  });

  /// Primary last: it sits on the right when side by side and on top when
  /// stacked.
  final List<ChatCardButton> buttons;
  final bool stack;
  final String? link;
  final VoidCallback? onLink;

  @override
  Widget build(BuildContext context) {
    final p = ChatCard.pad;
    final vertical = stack && kMobile;
    final ordered = vertical ? buttons.reversed.toList() : buttons;
    final pills = [for (final b in ordered) _ChatCardPill(b)];
    return Padding(
      padding: EdgeInsets.fromLTRB(p, 2, p, link == null ? p : 4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (vertical)
            for (var i = 0; i < pills.length; i++) ...[
              if (i > 0) const SizedBox(height: 8),
              pills[i],
            ]
          else
            Row(children: [
              for (var i = 0; i < pills.length; i++) ...[
                if (i > 0) const SizedBox(width: 8),
                Expanded(child: pills[i]),
              ],
            ]),
          if (link != null)
            Semantics(
              button: true,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onLink,
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 10),
                  child: Text(link!,
                      textAlign: TextAlign.center,
                      style: sans(13,
                          color: onLink == null
                              ? AppColors.fg4
                              : AppColors.fg3)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ChatCardPill extends StatelessWidget {
  const _ChatCardPill(this.b);

  final ChatCardButton b;

  @override
  Widget build(BuildContext context) {
    final h = kMobile ? 44.0 : 34.0;
    final enabled = b.onTap != null && !b.busy;
    final (bg, fg, border) = switch (b.kind) {
      ChatCardButtonKind.primary => (
          AppColors.accent,
          AppColors.accentFg,
          AppColors.accent
        ),
      ChatCardButtonKind.secondary => (
          Colors.transparent,
          AppColors.fg1,
          AppColors.lineStrong
        ),
      ChatCardButtonKind.danger => (
          AppColors.danger.withValues(alpha: 0.13),
          AppColors.danger,
          AppColors.danger.withValues(alpha: 0.35)
        ),
    };
    return Semantics(
      button: true,
      enabled: enabled,
      label: b.label,
      child: Pressable(
        kind: PressKind.card,
        radius: h / 2,
        enabled: enabled,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? b.onTap : null,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: enabled ? 1 : 0.45,
            child: Container(
              height: h,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(h / 2),
                border: Border.all(color: border),
              ),
              child: ExcludeSemantics(
                child: Text(b.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(kMobile ? 15 : 13,
                        weight: W.strong, color: fg)),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum ChatCardTone { neutral, warn, ok, danger }

/// Small status pill, e.g. "Waiting 2m" or "Recommended".
class ChatCardPill extends StatelessWidget {
  const ChatCardPill(this.text,
      {super.key, this.tone = ChatCardTone.neutral, this.filled = false});

  final String text;
  final ChatCardTone tone;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final c = switch (tone) {
      ChatCardTone.neutral => AppColors.fg3,
      ChatCardTone.warn => AppColors.run,
      ChatCardTone.ok => AppColors.ok,
      ChatCardTone.danger => AppColors.danger,
    };
    final neutral = tone == ChatCardTone.neutral;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: filled
            ? AppColors.surface3
            : neutral
                ? Colors.transparent
                : c.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(10),
        border: filled
            ? null
            : Border.all(
                color: neutral ? AppColors.lineStrong : c.withValues(alpha: 0.35)),
      ),
      child: Text(text,
          maxLines: 1,
          style: sans(12, color: filled ? AppColors.fg2 : c)),
    );
  }
}

/// A choice row: radio or checkbox, label, optional detail and pill.
class ChatCardOption extends StatelessWidget {
  const ChatCardOption({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
    this.detail,
    this.multi = false,
    this.recommended = false,
    this.muted = false,
    this.trailing,
  });

  final String label;
  final String? detail;
  final bool selected;
  final bool multi;
  final bool recommended;

  /// Placeholder-style label, e.g. "Something else…".
  final bool muted;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final p = ChatCard.pad;
    final mark = multi
        ? AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: selected ? AppColors.accent : Colors.transparent,
              borderRadius: BorderRadius.circular(6),
              border: Border.all(
                  color: selected ? AppColors.accent : AppColors.lineStrong,
                  width: 1.5),
            ),
            child: selected
                ? Center(
                    child: AppIcon('check', size: 13, color: AppColors.accentFg))
                : null,
          )
        : AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: selected ? AppColors.accent : AppColors.lineStrong,
                  width: selected ? 6 : 1.5),
            ),
          );
    return Semantics(
      button: true,
      selected: selected,
      label: label,
      child: InkWell(
        onTap: onTap,
        child: ConstrainedBox(
          constraints: BoxConstraints(minHeight: kMobile ? 48 : 38),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: p, vertical: 9),
            child: Row(children: [
              mark,
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label,
                        style: sans(kMobile ? 15 : 13,
                            color: muted ? AppColors.fg3 : AppColors.fg1)),
                    if (detail != null && detail!.isNotEmpty)
                      Text(detail!,
                          style: sans(13, height: 1.35, color: AppColors.fg3)),
                  ],
                ),
              ),
              if (recommended) ...[
                const SizedBox(width: 8),
                const ChatCardPill('Recommended', filled: true),
              ],
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
            ]),
          ),
        ),
      ),
    );
  }
}

/// "Question 2 of 3" with step dashes.
class ChatCardSteps extends StatelessWidget {
  const ChatCardSteps({super.key, required this.index, required this.total});

  /// Zero-based.
  final int index;
  final int total;

  @override
  Widget build(BuildContext context) => Row(children: [
        Text('Question ${index + 1} of $total',
            style: sans(13, color: AppColors.fg3)),
        const Spacer(),
        for (var i = 0; i < total; i++)
          Container(
            width: 16,
            height: 3,
            margin: const EdgeInsets.only(left: 4),
            decoration: BoxDecoration(
              color: i <= index ? AppColors.fg1 : AppColors.lineStrong,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ]);
}

/// One-line record of a decided approval or answered question.
class ChatCardResolved extends StatelessWidget {
  const ChatCardResolved({
    super.key,
    required this.title,
    required this.approved,
    this.subtitle,
  });

  final String title;
  final String? subtitle;
  final bool approved;

  @override
  Widget build(BuildContext context) {
    final p = ChatCard.pad;
    return ChatCard(dimmed: true, children: [
      Padding(
        padding: EdgeInsets.symmetric(horizontal: p, vertical: 12),
        child: Row(children: [
          AppIcon(approved ? 'check' : 'x',
              size: 16, color: approved ? AppColors.ok : AppColors.fg4),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(kMobile ? 15 : 13,
                        weight: W.strong, color: AppColors.fg2)),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(subtitle!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: sans(13, color: AppColors.fg3)),
              ],
            ),
          ),
        ]),
      ),
    ]);
  }
}

/// Footer row for a previewable card: title, meta and a chevron.
class ChatCardFooter extends StatelessWidget {
  const ChatCardFooter({
    super.key,
    required this.title,
    this.meta,
    this.leading,
    this.trailing,
    this.onTap,
    this.divider = true,
  });

  final String title;
  final String? meta;
  final Widget? leading;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool divider;

  @override
  Widget build(BuildContext context) {
    final p = ChatCard.pad;
    return InkWell(
      onTap: onTap,
      child: Container(
        decoration: divider
            ? BoxDecoration(border: Border(top: BorderSide(color: AppColors.line)))
            : null,
        padding: EdgeInsets.symmetric(horizontal: p, vertical: 12),
        child: Row(children: [
          if (leading != null) ...[leading!, const SizedBox(width: 12)],
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(kMobile ? 15 : 13,
                        weight: W.strong, color: AppColors.fg1)),
                if (meta != null && meta!.isNotEmpty)
                  Text(meta!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(13, color: AppColors.fg3)),
              ],
            ),
          ),
          if (trailing != null)
            trailing!
          else if (onTap != null)
            AppIcon('chevron-right', size: 16, color: AppColors.fg4),
        ]),
      ),
    );
  }
}
