import 'package:flutter/material.dart';

import '../app_icons.dart';
import '../components.dart' show Spinner;
import '../platform.dart';
import '../theme.dart';

/// Desktop Quiet asks share one locked treatment: tonal surfaces, one 6px
/// amber dot, neutral type, and compact 28pt actions. These primitives are
/// desktop-only; phone surfaces keep their existing larger touch geometry.
class AskIcon extends StatelessWidget {
  const AskIcon(this.name, {super.key, this.size = 14, this.color});

  final String name;
  final double size;
  final Color? color;

  @override
  Widget build(BuildContext context) => SizedBox.square(
        dimension: size,
        child: Center(
          child: Icon(appIcons[name] ?? appIcons['circle']!,
              size: size, color: color ?? AppColors.fg2),
        ),
      );
}

/// The locked needs-you header: the surface stays tonal; only this dot is amber.
class NeedsYouHeader extends StatelessWidget {
  const NeedsYouHeader({super.key, this.meta, this.label = 'Needs you'});

  final String? meta;
  final String label;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 18,
        child: Row(children: [
          Container(
            width: 6,
            height: 6,
            margin: const EdgeInsets.only(top: 1),
            decoration:
                BoxDecoration(color: AppColors.run, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(label,
              style: sans(kMobile ? 13 : 11.5,
                  height: kMobile ? 18 / 13 : 16 / 11.5,
                  weight: FontWeight.w500,
                  color: AppColors.fg2)),
          const Spacer(),
          if (meta != null && meta!.isNotEmpty)
            Flexible(
              child: Text(meta!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: sans(11.5, height: 16 / 11.5, color: AppColors.fg3)),
            ),
        ]),
      );
}

/// Marker for the wider separation before a secondary canvas link action.
class AskActionWideGap extends StatelessWidget {
  const AskActionWideGap({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

enum AskButtonVariant { primary, secondary, ghost }

/// Locked desktop action button: 28 high, radius 6, crisp hairline on secondary.
class AskButton extends StatelessWidget {
  const AskButton(
    this.label, {
    super.key,
    required this.onTap,
    this.variant = AskButtonVariant.secondary,
    this.busy = false,
    this.icon,
    this.shortcut,
  });

  final String label;
  final VoidCallback? onTap;
  final AskButtonVariant variant;
  final bool busy;
  final String? icon;
  final String? shortcut;

  @override
  Widget build(BuildContext context) {
    final enabled = !busy && onTap != null;
    final fill = !enabled
        ? (variant == AskButtonVariant.ghost
            ? Colors.transparent
            : AppColors.surface2)
        : switch (variant) {
            AskButtonVariant.primary => AppColors.fg1,
            AskButtonVariant.secondary =>
              kMobile ? AppColors.surface3 : AppColors.surface2,
            AskButtonVariant.ghost => Colors.transparent,
          };
    final ink = !enabled
        ? AppColors.fg4
        : switch (variant) {
            AskButtonVariant.primary => AppColors.bg,
            AskButtonVariant.secondary => AppColors.fg1,
            AskButtonVariant.ghost => AppColors.fg3,
          };
    final borderSide = !kMobile && variant == AskButtonVariant.secondary
        ? BorderSide(color: enabled ? AppColors.border2 : AppColors.border)
        : !kMobile && variant == AskButtonVariant.primary && enabled
            ? BorderSide(color: AppColors.fg1)
            : BorderSide.none;
    final radius = BorderRadius.circular(kMobile ? 8 : 6);
    final hPad = kMobile
        ? 10.0
        : (variant == AskButtonVariant.ghost ? 8.0 : 11.0);
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: MouseRegion(
        cursor:
            enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
        child: Material(
          color: fill,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: borderSide,
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: radius,
            child: Container(
              height: kMobile ? 36 : 28,
              padding: EdgeInsets.symmetric(horizontal: hPad),
              alignment: Alignment.center,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (busy) ...[
                  Spinner(size: 12, color: ink),
                  const SizedBox(width: 6),
                ] else if (icon != null) ...[
                  AskIcon(icon!, size: 13, color: ink),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(kMobile ? 12.5 : 12,
                          height: 16 / (kMobile ? 12.5 : 12),
                          weight: FontWeight.w500,
                          color: ink)),
                ),
                if (shortcut != null && shortcut!.isNotEmpty && !busy) ...[
                  const SizedBox(width: 6),
                  Text(shortcut!,
                      style: codeMono(10,
                          height: 14 / 10,
                          color: ink.withValues(alpha: 0.6))),
                ],
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Hairline-framed s1 card used by every open desktop ask. When its parent caps
/// height, only the payload scrolls; the header and action bar remain reachable.
class DesktopAskCard extends StatelessWidget {
  const DesktopAskCard({
    super.key,
    required this.title,
    this.kindLabel,
    this.meta,
    this.payload,
    this.actions = const [],
    this.footerLeft,
    this.needsYou = true,
    this.margin = EdgeInsets.zero,
  });

  final String title;
  final String? kindLabel;
  final String? meta;
  final Widget? payload;
  final List<Widget> actions;
  final Widget? footerLeft;
  final bool needsYou;
  final EdgeInsetsGeometry margin;

  Widget _title() => Text(title,
      style: sans(kMobile ? 15 : 13.5,
          height: kMobile ? 21 / 15 : 19 / 13.5,
          weight: FontWeight.w500,
          color: AppColors.fg1));

  Widget _footer() {
    final left = <Widget>[if (footerLeft != null) footerLeft!];
    final right = <Widget>[];
    for (final a in actions) {
      if (a is AskActionWideGap) continue;
      if (a is AskButton && a.variant == AskButtonVariant.ghost) {
        left.add(a);
      } else {
        right.add(a);
      }
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        border: Border(top: BorderSide(color: AppColors.border)),
      ),
      child: Row(children: [
        if (left.isNotEmpty)
          Expanded(
            child: Wrap(
              spacing: 6,
              runSpacing: 6,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: left,
            ),
          ),
        if (left.isEmpty) const Spacer(),
        if (right.isNotEmpty) ...[
          const SizedBox(width: 8),
          Row(mainAxisSize: MainAxisSize.min, children: [
            for (var i = 0; i < right.length; i++) ...[
              if (i > 0) const SizedBox(width: 6),
              right[i],
            ],
          ]),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final hasFooter = actions.isNotEmpty || footerLeft != null;
    if (kMobile) {
      return Container(
        margin: margin,
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(builder: (context, box) {
          final body = payload == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 10), child: payload);
          return Padding(
            padding: const EdgeInsets.all(14),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (needsYou) ...[
                  NeedsYouHeader(label: kindLabel ?? 'Needs you', meta: meta),
                  const SizedBox(height: 8),
                ],
                _title(),
                if (payload != null)
                  box.hasBoundedHeight
                      ? Flexible(child: SingleChildScrollView(child: body))
                      : body,
                if (actions.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Wrap(spacing: 8, runSpacing: 8, children: [
                      for (final a in actions)
                        if (a is! AskActionWideGap) a,
                    ]),
                  ),
              ],
            ),
          );
        }),
      );
    }

    return Container(
      margin: margin,
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: AppColors.border2),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(builder: (context, box) {
        final body = Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _title(),
              if (payload != null) ...[
                const SizedBox(height: 10),
                payload!,
              ],
            ],
          ),
        );
        return Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (needsYou)
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  border: Border(bottom: BorderSide(color: AppColors.border)),
                ),
                child: NeedsYouHeader(
                  label: kindLabel ?? 'Needs you',
                  meta: meta,
                ),
              ),
            if (box.hasBoundedHeight)
              Flexible(child: SingleChildScrollView(child: body))
            else
              body,
            if (hasFooter) _footer(),
          ],
        );
      }),
    );
  }
}

/// Permission payload: recessed dark code well with hairline border and `$` cue.
class AskCommandPlate extends StatelessWidget {
  const AskCommandPlate(this.code, {super.key, this.maxLines});

  final String code;
  final int? maxLines;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 34),
        padding: const EdgeInsets.symmetric(horizontal: 11, vertical: 9),
        decoration: BoxDecoration(
          color: kMobile ? AppColors.surface3 : AppColors.bg,
          borderRadius: BorderRadius.circular(7),
          border: kMobile ? null : Border.all(color: AppColors.border),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          if (!kMobile) ...[
            Text('\$',
                style: codeMono(12, height: 18 / 12, color: AppColors.fg4)),
            const SizedBox(width: 8),
          ],
          Expanded(
            child: SelectableText(code,
                maxLines: maxLines,
                style: codeMono(12, height: 18 / 12, color: AppColors.fg1)),
          ),
        ]),
      );
}

/// Vault secret badge shown inside approval cards when a command references a secret.
class AskVaultChip extends StatelessWidget {
  const AskVaultChip(this.name, {super.key});

  final String name;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: AppColors.run.withValues(alpha: 0.11),
          borderRadius: BorderRadius.circular(5),
          border: Border.all(color: AppColors.run.withValues(alpha: 0.28)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AskIcon('lock', size: 11, color: AppColors.run),
          const SizedBox(width: 5),
          Text(name,
              style: codeMono(11, height: 15 / 11, color: AppColors.run)),
        ]),
      );
}

/// Structured desktop single-choice row with optional keycap, description, and
/// Recommended tag.
class AskChoiceRow extends StatelessWidget {
  const AskChoiceRow({
    super.key,
    required this.label,
    required this.selected,
    this.description,
    this.keyHint,
    this.recommended = false,
    this.custom = false,
    this.disabled = false,
    this.onTap,
  });

  final String label;
  final String? description;
  final String? keyHint;
  final bool selected;
  final bool recommended;
  final bool custom;
  final bool disabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = !disabled && onTap != null;
    final radius = BorderRadius.circular(7);
    final fill = selected ? AppColors.surface2 : Colors.transparent;
    final borderColor = selected ? AppColors.fg2 : AppColors.border;
    final desc = description?.trim() ?? '';
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      child: MouseRegion(
        cursor:
            enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
        child: Material(
          color: fill,
          shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: borderColor),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: radius,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (keyHint != null && keyHint!.isNotEmpty)
                  Container(
                    width: 18,
                    height: 18,
                    margin: const EdgeInsets.only(top: 1),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: selected ? AppColors.fg1 : AppColors.bg,
                      borderRadius: BorderRadius.circular(4),
                      border: Border.all(
                          color: selected ? AppColors.fg1 : AppColors.border2),
                    ),
                    child: Text(keyHint!,
                        style: codeMono(10.5,
                            height: 1,
                            weight: FontWeight.w500,
                            color: selected ? AppColors.bg : AppColors.fg3)),
                  )
                else
                  Container(
                    width: 15,
                    height: 15,
                    margin: const EdgeInsets.only(top: 2),
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? AppColors.fg1 : AppColors.bg,
                      border: Border.all(
                          color: selected ? AppColors.fg1 : AppColors.border2),
                    ),
                    child: selected
                        ? Center(
                            child: Container(
                              width: 5,
                              height: 5,
                              decoration: BoxDecoration(
                                color: AppColors.bg,
                                shape: BoxShape.circle,
                              ),
                            ),
                          )
                        : null,
                  ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Row(children: [
                        Flexible(
                          child: Text(label,
                              style: sans(12.5,
                                  height: 18 / 12.5,
                                  weight: custom && !selected
                                      ? FontWeight.w400
                                      : FontWeight.w500,
                                  color: disabled
                                      ? AppColors.fg3
                                      : (custom && !selected
                                          ? AppColors.fg3
                                          : AppColors.fg1))),
                        ),
                        if (recommended) ...[
                          const SizedBox(width: 7),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 1),
                            decoration: BoxDecoration(
                              color: AppColors.surface3,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text('Recommended',
                                style: sans(10.5,
                                    height: 15 / 10.5,
                                    weight: FontWeight.w500,
                                    color: AppColors.fg2)),
                          ),
                        ],
                      ]),
                      if (desc.isNotEmpty)
                        Padding(
                          padding: const EdgeInsets.only(top: 2),
                          child: Text(desc,
                              style: sans(12,
                                  height: 17 / 12, color: AppColors.fg3)),
                        ),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// ASK-06 choice pill: selection is glyph + weight on the same tonal fill.
class AskChoicePill extends StatelessWidget {
  const AskChoicePill({
    super.key,
    required this.label,
    required this.selected,
    this.disabled = false,
    this.onTap,
  });

  final String label;
  final bool selected;
  final bool disabled;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final enabled = !disabled && onTap != null;
    final fill = disabled ? AppColors.surface2 : AppColors.surface3;
    final ink = disabled ? AppColors.fg2 : AppColors.fg1;
    final radius = BorderRadius.circular(6);
    return Semantics(
      button: true,
      selected: selected,
      enabled: enabled,
      label: label,
      child: Material(
        color: fill,
        borderRadius: radius,
        child: InkWell(
          onTap: enabled ? onTap : null,
          borderRadius: radius,
          child: Container(
            height: 28,
            padding: EdgeInsets.symmetric(horizontal: selected ? 10 : 14),
            alignment: Alignment.center,
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (selected) ...[
                AskIcon('check', size: 13, color: ink),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(12,
                        height: 16 / 12,
                        weight: selected ? FontWeight.w500 : FontWeight.w400,
                        color: ink)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Side-by-side choose-one card. Selection always carries the border, check
/// glyph and the word “Selected”; never colour alone.
class AskOptionCard extends StatelessWidget {
  const AskOptionCard({
    super.key,
    required this.title,
    required this.selected,
    this.subtitle,
    this.thumbnail,
    this.onTap,
  });

  final String title;
  final String? subtitle;
  final bool selected;
  final Widget? thumbnail;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final thumb = thumbnail ??
        Container(
          width: 80,
          height: 64,
          decoration: BoxDecoration(
            color: selected ? AppColors.surface2 : AppColors.surface3,
            borderRadius: BorderRadius.circular(6),
          ),
          alignment: Alignment.center,
          child: AskIcon(selected ? 'check-circle' : 'circle',
              size: 18, color: selected ? AppColors.fg1 : AppColors.fg3),
        );
    return Semantics(
      button: true,
      selected: selected,
      label: title,
      child: Material(
        color: selected ? AppColors.surface3 : AppColors.surface1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(8),
          side: selected ? BorderSide(color: AppColors.fg1) : BorderSide.none,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: SizedBox(
            height: kMobile ? 74 : 80,
            child: Padding(
              padding: EdgeInsets.all(kMobile ? 7 : 8),
              child: Row(children: [
                SizedBox(width: kMobile ? 64 : 80, height: kMobile ? 60 : 64, child: thumb),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Row(children: [
                        if (selected) ...[
                          AskIcon('check-circle',
                              size: 13, color: AppColors.fg1),
                          const SizedBox(width: 5),
                        ],
                        Expanded(
                          child: Text(title,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: sans(12.5,
                                  height: 17 / 12.5,
                                  weight: FontWeight.w500,
                                  color: AppColors.fg1)),
                        ),
                      ]),
                      if (subtitle != null && subtitle!.isNotEmpty)
                        Text(subtitle!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(11,
                                height: 15 / 11, color: AppColors.fg2)),
                      Text(selected ? 'Selected' : 'Click to pick',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(11,
                              height: 15 / 11,
                              weight:
                                  selected ? FontWeight.w500 : FontWeight.w400,
                              color: selected ? AppColors.fg1 : AppColors.fg3)),
                    ],
                  ),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Two-column grid for choose-one cards; one column when the pane is narrow.
class AskOptionGrid extends StatelessWidget {
  const AskOptionGrid({super.key, required this.options});

  final List<AskOptionCard> options;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        final two = !kMobile && box.maxWidth >= 390 && options.length > 1;
        final width = two ? (box.maxWidth - 10) / 2 : box.maxWidth;
        return Wrap(
            spacing: 10,
            runSpacing: kMobile ? 8 : 10,
            children: [
              for (final option in options) SizedBox(width: width, child: option),
            ]);
      });
}

/// Choose-many row: hairline-bordered Geist Sans row with optional description.
class AskCheckboxRow extends StatelessWidget {
  const AskCheckboxRow({
    super.key,
    required this.label,
    required this.selected,
    this.description,
    this.onTap,
  });

  final String label;
  final String? description;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(7);
    final desc = description?.trim() ?? '';
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Material(
        color: selected ? AppColors.surface2 : Colors.transparent,
        shape: RoundedRectangleBorder(
          borderRadius: radius,
          side: BorderSide(
              color: selected ? AppColors.fg2 : AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          borderRadius: radius,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 15,
                height: 15,
                margin: const EdgeInsets.only(top: 2),
                decoration: BoxDecoration(
                  color: selected ? AppColors.fg1 : AppColors.bg,
                  borderRadius: BorderRadius.circular(4),
                  border: Border.all(
                      color: selected ? AppColors.fg1 : AppColors.border2,
                      width: 1),
                ),
                child: selected
                    ? AskIcon('check', size: 10, color: AppColors.bg)
                    : null,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(label,
                        style: sans(12.5,
                            height: 18 / 12.5,
                            weight: FontWeight.w500,
                            color: AppColors.fg1)),
                    if (desc.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 2),
                        child: Text(desc,
                            style: sans(12,
                                height: 17 / 12, color: AppColors.fg3)),
                      ),
                  ],
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Free-text payload plate: recessed bg with crisp border2 outline.
class AskTextInput extends StatelessWidget {
  const AskTextInput({
    super.key,
    required this.controller,
    this.hint = 'Write your answer',
    this.enabled = true,
    this.onSubmitted,
  });

  final TextEditingController controller;
  final String hint;
  final bool enabled;
  final ValueChanged<String>? onSubmitted;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 36),
        decoration: BoxDecoration(
          color: kMobile ? AppColors.surface3 : AppColors.bg,
          borderRadius: BorderRadius.circular(7),
          border: kMobile ? null : Border.all(color: AppColors.border2),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: TextField(
          controller: controller,
          enabled: enabled,
          minLines: 1,
          maxLines: 4,
          onSubmitted: onSubmitted,
          style: sans(12.5, height: 18 / 12.5, color: AppColors.fg1),
          cursorColor: AppColors.fg1,
          decoration: InputDecoration(
            isDense: true,
            border: InputBorder.none,
            hintText: hint,
            hintStyle: sans(12.5, height: 18 / 12.5, color: AppColors.fg3),
            contentPadding: const EdgeInsets.symmetric(vertical: 8),
          ),
        ),
      );
}

/// ASK-18 attention strip: s1, 28–32 high, hidden by the caller at zero.
class AskAttentionStrip extends StatelessWidget {
  const AskAttentionStrip({
    super.key,
    required this.count,
    this.avatars = const [],
    this.onReview,
  });

  final int count;
  final List<Widget> avatars;
  final VoidCallback? onReview;

  @override
  Widget build(BuildContext context) => Container(
        height: 30,
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 9),
        child: Row(children: [
          Container(
            width: 6,
            height: 6,
            decoration:
                BoxDecoration(color: AppColors.run, shape: BoxShape.circle),
          ),
          const SizedBox(width: 7),
          Text(count == 1 ? '1 thing needs you' : '$count things need you',
              style: sans(12,
                  height: 16 / 12,
                  weight: FontWeight.w500,
                  color: AppColors.fg2)),
          if (avatars.isNotEmpty) ...[
            const SizedBox(width: 8),
            for (final avatar in avatars.take(3))
              Padding(
                padding: const EdgeInsets.only(right: 3),
                child: SizedBox(width: 20, height: 20, child: avatar),
              ),
          ],
          const Spacer(),
          _ReviewTarget(onTap: onReview),
        ]),
      );
}

class _ReviewTarget extends StatelessWidget {
  const _ReviewTarget({this.onTap});
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => SizedBox(
        height: 28,
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(6),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: Center(
                child: Text('Review',
                    style: sans(12,
                        height: 16 / 12,
                        weight: FontWeight.w500,
                        color: AppColors.fg1)),
              ),
            ),
          ),
        ),
      );
}
