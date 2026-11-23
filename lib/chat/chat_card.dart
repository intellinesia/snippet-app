import 'package:flutter/material.dart';

import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import '../tap_detector.dart';

/// The asking agent's colour for a card's primary button and selections.
class ChatCardAccent extends InheritedWidget {
  const ChatCardAccent({super.key, required this.color, required super.child});

  final Color? color;

  static Color of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChatCardAccent>()?.color ??
      AppColors.accent;

  static Color inkOf(BuildContext context) {
    final set =
        context.dependOnInheritedWidgetOfExactType<ChatCardAccent>()?.color;
    if (set == null) return AppColors.accentFg;
    return set.computeLuminance() > 0.45
        ? const Color(0xFF14141A)
        : Colors.white;
  }

  @override
  bool updateShouldNotify(ChatCardAccent old) => old.color != color;
}

/// Shared parts for cards that sit in a chat: artifacts, approvals and
/// questions. One shell, one headline, one quiet meta line, at most one solid
/// button.
class ChatCard extends StatelessWidget {
  const ChatCard({
    super.key,
    required this.children,
    this.maxWidth,
    this.dimmed = false,
  });

  final List<Widget> children;

  /// Defaults to 460 on phones and the full transcript width on desktop.
  final double? maxWidth;

  /// Resolved cards recede.
  final bool dimmed;

  static double get pad => 16;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerLeft,
        // Without it a height-capped slot centres the card in the cap.
        heightFactor: 1,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxWidth: maxWidth ?? (kMobile ? 460 : double.infinity)),
          child: Container(
              clipBehavior: Clip.antiAlias,
              decoration: BoxDecoration(
                // A surface step, not an outline, sets the card apart.
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(R.of(16)),
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
    final size = large ? (kMobile ? 17.0 : 14.0) : (kMobile ? 15.0 : 13.0);
    return Padding(
      padding: EdgeInsets.fromLTRB(p, p, p, padBottom ? S.s8 : 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (eyebrow != null) ...[eyebrow!, SizedBox(height: S.s8)],
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
                        padding: const EdgeInsets.only(top: 4),
                        child: subtitleView)
                  else if (subtitle != null && subtitle!.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 4),
                      child: Text(subtitle!,
                          style: sans(13, height: 1.4, color: AppColors.fg3)),
                    ),
                ],
              ),
            ),
            if (trailing != null) ...[SizedBox(width: S.of(10)), trailing!],
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
      padding: EdgeInsets.fromLTRB(p, 0, p, bottom ? p : 0),
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
      {this.onTap,
      this.kind = ChatCardButtonKind.primary,
      this.busy = false,
      this.icon});

  final String label;
  final IconData? icon;
  final VoidCallback? onTap;
  final ChatCardButtonKind kind;
  final bool busy;
}

/// Card buttons. On the phone: full-width pills, stacked when [stack] is set
/// (the Duet shape), with an optional quiet link below. On desktop: compact
/// buttons at their own width, right-aligned, with the link on the left.
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
    if (!kMobile) return _desktop(p);
    final vertical = stack && kMobile;
    final ordered = vertical ? buttons.reversed.toList() : buttons;
    final pills = [for (final b in ordered) _ChatCardPill(b)];
    return Padding(
      padding: EdgeInsets.fromLTRB(p, 0, p, link == null ? p : S.s4),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (vertical)
            for (var i = 0; i < pills.length; i++) ...[
              if (i > 0) SizedBox(height: S.s8),
              pills[i],
            ]
          else
            Row(children: [
              for (var i = 0; i < pills.length; i++) ...[
                if (i > 0) SizedBox(width: S.s8),
                Expanded(child: pills[i]),
              ],
            ]),
          if (link != null)
            Semantics(
              button: true,
              child: TapDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onLink,
                child: Padding(
                  padding: EdgeInsets.symmetric(vertical: S.of(10)),
                  child: Text(link!,
                      textAlign: TextAlign.center,
                      style: sans(13,
                          color:
                              onLink == null ? AppColors.fg4 : AppColors.fg3)),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

extension on ChatCardActions {
  // Pointer-sized: 32 tall buttons at their own width, left aligned.
  Widget _desktop(double p) {
    final pills = [for (final b in buttons) _ChatCardPill(b)];
    final linkView = link == null
        ? null
        : ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 260),
            child: Semantics(
              button: true,
              child: TapDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onLink,
                child: Padding(
                  padding: const EdgeInsets.only(left: 12),
                  child: Text(link!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(12,
                          color:
                              onLink == null ? AppColors.fg4 : AppColors.fg3)),
                ),
              ),
            ),
          );
    return Padding(
      padding: EdgeInsets.fromLTRB(p, 0, p, p),
      child: Row(children: [
        Flexible(
          child: Wrap(
            alignment: WrapAlignment.start,
            spacing: 8,
            runSpacing: 8,
            children: pills,
          ),
        ),
        if (linkView != null) linkView,
      ]),
    );
  }
}

class _ChatCardPill extends StatelessWidget {
  const _ChatCardPill(this.b);

  final ChatCardButton b;

  @override
  Widget build(BuildContext context) {
    final h = kMobile ? 44.0 : 32.0;
    final enabled = b.onTap != null && !b.busy;
    final (bg, fg, border) = switch (b.kind) {
      ChatCardButtonKind.primary => (
          ChatCardAccent.of(context),
          ChatCardAccent.inkOf(context),
          ChatCardAccent.of(context)
        ),
      ChatCardButtonKind.secondary => (
          Colors.transparent,
          AppColors.fg1,
          AppColors.fg4
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
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: enabled ? b.onTap : null,
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 150),
            opacity: enabled ? 1 : 0.45,
            child: Container(
              height: h,
              alignment: kMobile ? Alignment.center : null,
              padding:
                  kMobile ? null : const EdgeInsets.symmetric(horizontal: 12),
              decoration: BoxDecoration(
                color: bg,
                borderRadius: BorderRadius.circular(h / 2),
                border: Border.all(color: border),
              ),
              child: ExcludeSemantics(
                // Desktop: as wide as the label, centred in the pill height.
                child: Align(
                  widthFactor: kMobile ? null : 1,
                  child: Row(
                      mainAxisSize: MainAxisSize.min,
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (b.icon != null) ...[
                          Icon(b.icon, size: kMobile ? 16 : 14, color: fg),
                          SizedBox(width: S.s6),
                        ],
                        Flexible(
                          child: Text(b.label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(kMobile ? 15 : 13,
                                  weight: W.strong, color: fg)),
                        ),
                      ]),
                ),
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
      padding: EdgeInsets.symmetric(horizontal: S.s8, vertical: S.s2),
      decoration: BoxDecoration(
        color: filled
            ? AppColors.surface3
            : neutral
                ? AppColors.surface3
                : c.withValues(alpha: 0.13),
        borderRadius: BorderRadius.circular(R.card),
      ),
      child: Text(text,
          maxLines: 1, style: sans(12, color: filled ? AppColors.fg2 : c)),
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
    final accent = ChatCardAccent.of(context);
    final mark = multi
        ? AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: selected ? accent : Colors.transparent,
              borderRadius: BorderRadius.circular(R.sm),
              border: Border.all(
                  color: selected ? accent : AppColors.lineStrong, width: 1.5),
            ),
            child: selected
                ? Center(
                    child: AppIcon('check',
                        size: 13, color: ChatCardAccent.inkOf(context)))
                : null,
          )
        : AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              border: Border.all(
                  color: selected ? accent : AppColors.lineStrong,
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
            padding: EdgeInsets.symmetric(horizontal: p, vertical: S.of(9)),
            child: Row(children: [
              mark,
              SizedBox(width: S.s12),
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
                SizedBox(width: S.s8),
                const ChatCardPill('Recommended', filled: true),
              ],
              if (trailing != null) ...[SizedBox(width: S.s8), trailing!],
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
            margin: EdgeInsets.only(left: S.s4),
            decoration: BoxDecoration(
              color: i <= index ? AppColors.fg1 : AppColors.lineStrong,
              borderRadius: BorderRadius.circular(R.of(2)),
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
    this.icon,
  });

  final String title;
  final String? subtitle;
  final bool approved;
  final String? icon;

  @override
  Widget build(BuildContext context) {
    final p = ChatCard.pad;
    return ChatCard(dimmed: true, children: [
      Padding(
        padding: EdgeInsets.symmetric(horizontal: p, vertical: S.s12),
        child: Row(children: [
          AppIcon(icon ?? (approved ? 'check' : 'x'),
              size: 16, color: approved ? AppColors.ok : AppColors.fg4),
          SizedBox(width: S.s12),
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
            ? BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.line)))
            : null,
        padding: EdgeInsets.symmetric(horizontal: p, vertical: S.s12),
        child: Row(children: [
          if (leading != null) ...[leading!, SizedBox(width: S.s12)],
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
