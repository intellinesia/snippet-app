import 'package:flutter/material.dart';

import '../app_icons.dart';
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
  const NeedsYouHeader({super.key, this.meta});

  final String? meta;

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
          Text('Needs you',
              style: sans(12,
                  height: 16 / 12,
                  weight: FontWeight.w500,
                  color: AppColors.fg2)),
          const Spacer(),
          if (meta != null && meta!.isNotEmpty)
            Flexible(
              child: Text(meta!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: sans(11, height: 15 / 11, color: AppColors.fg2)),
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

/// Locked desktop action button: 28 high, radius 6, 12.5/500 label.
class AskButton extends StatelessWidget {
  const AskButton(
    this.label, {
    super.key,
    required this.onTap,
    this.variant = AskButtonVariant.secondary,
    this.busy = false,
    this.icon,
  });

  final String label;
  final VoidCallback? onTap;
  final AskButtonVariant variant;
  final bool busy;
  final String? icon;

  @override
  Widget build(BuildContext context) {
    final enabled = !busy && onTap != null;
    final fill = !enabled
        ? (variant == AskButtonVariant.ghost
            ? Colors.transparent
            : AppColors.surface3)
        : switch (variant) {
            AskButtonVariant.primary => AppColors.fg1,
            AskButtonVariant.secondary => AppColors.surface3,
            AskButtonVariant.ghost => Colors.transparent,
          };
    final ink = !enabled
        ? AppColors.fg2
        : switch (variant) {
            AskButtonVariant.primary => AppColors.bg,
            AskButtonVariant.secondary => AppColors.fg1,
            AskButtonVariant.ghost => AppColors.fg2,
          };
    final radius = BorderRadius.circular(6);
    return Semantics(
      button: true,
      enabled: enabled,
      label: label,
      child: MouseRegion(
        cursor:
            enabled ? SystemMouseCursors.click : SystemMouseCursors.forbidden,
        child: Material(
          color: fill,
          borderRadius: radius,
          child: InkWell(
            onTap: enabled ? onTap : null,
            borderRadius: radius,
            child: Container(
              height: 28,
              padding: const EdgeInsets.symmetric(horizontal: 12),
              alignment: Alignment.center,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                if (busy) ...[
                  SizedBox(
                    width: 12,
                    height: 12,
                    child: CircularProgressIndicator(
                        strokeWidth: 1.6,
                        valueColor: AlwaysStoppedAnimation(ink)),
                  ),
                  const SizedBox(width: 6),
                ] else if (icon != null) ...[
                  AskIcon(icon!, size: 13, color: ink),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(12.5,
                          height: 16 / 12.5,
                          weight: FontWeight.w500,
                          color: ink)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }
}

/// Flat s2 card used by every open desktop ask. When its parent caps height,
/// only the payload scrolls; the header and action row remain reachable.
class DesktopAskCard extends StatelessWidget {
  const DesktopAskCard({
    super.key,
    required this.title,
    this.meta,
    this.payload,
    this.actions = const [],
    this.needsYou = true,
    this.margin = EdgeInsets.zero,
  });

  final String title;
  final String? meta;
  final Widget? payload;
  final List<Widget> actions;
  final bool needsYou;
  final EdgeInsetsGeometry margin;

  Widget _title() => Text(title,
      style: sans(13,
          height: 19 / 13, weight: FontWeight.w500, color: AppColors.fg1));

  Widget _actions() => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: Row(children: [
          for (var i = 0; i < actions.length; i++) ...[
            if (i > 0 &&
                actions[i] is! AskActionWideGap &&
                actions[i - 1] is! AskActionWideGap)
              const SizedBox(width: 8),
            if (actions[i] is AskActionWideGap)
              const SizedBox(width: 16)
            else
              actions[i],
          ],
        ]),
      );

  @override
  Widget build(BuildContext context) => Container(
        margin: margin,
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(10),
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(builder: (context, box) {
          final head = <Widget>[
            if (needsYou) NeedsYouHeader(meta: meta),
            if (needsYou)
              const SizedBox(height: 8)
            else
              const SizedBox.shrink(),
            _title(),
          ];
          final tail = actions.isEmpty ? null : _actions();
          final body = payload == null
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(top: 10), child: payload);
          final column = Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ...head,
              if (payload != null)
                box.hasBoundedHeight
                    ? Flexible(child: SingleChildScrollView(child: body))
                    : body,
              if (tail != null) tail,
            ],
          );
          return Padding(padding: const EdgeInsets.all(12), child: column);
        }),
      );
}

/// Permission payload: mono command on the one-step-lift s3 plate.
class AskCommandPlate extends StatelessWidget {
  const AskCommandPlate(this.code, {super.key, this.maxLines});

  final String code;
  final int? maxLines;

  @override
  Widget build(BuildContext context) => Container(
        width: double.infinity,
        constraints: const BoxConstraints(minHeight: 30),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surface3,
          borderRadius: BorderRadius.circular(6),
        ),
        child: SelectableText(code,
            maxLines: maxLines,
            style: codeMono(12, height: 18 / 12, color: AppColors.fg1)),
      );
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
            height: 80,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(children: [
                SizedBox(width: 80, height: 64, child: thumb),
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
        final two = box.maxWidth >= 390 && options.length > 1;
        final width = two ? (box.maxWidth - 10) / 2 : box.maxWidth;
        return Wrap(spacing: 10, runSpacing: 10, children: [
          for (final option in options) SizedBox(width: width, child: option),
        ]);
      });
}

/// Choose-many row: 28 pitch, 14 checkbox, mono label, selected tonal row.
class AskCheckboxRow extends StatelessWidget {
  const AskCheckboxRow({
    super.key,
    required this.label,
    required this.selected,
    this.onTap,
  });

  final String label;
  final bool selected;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(6);
    return Material(
      color: selected ? AppColors.surface3 : Colors.transparent,
      borderRadius: radius,
      child: InkWell(
        onTap: onTap,
        borderRadius: radius,
        child: SizedBox(
          height: 28,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 7),
            child: Row(children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(
                  color: selected ? AppColors.fg1 : Colors.transparent,
                  borderRadius: BorderRadius.circular(3),
                  border: Border.all(
                      color: selected ? AppColors.fg1 : AppColors.fg3,
                      width: 1),
                ),
                child: selected
                    ? AskIcon('check', size: 10, color: AppColors.bg)
                    : null,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: codeMono(12, height: 17 / 12, color: AppColors.fg1)),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Free-text payload plate: s3, radius 6, 34 minimum, 12/400 placeholder.
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
        constraints: const BoxConstraints(minHeight: 34),
        decoration: BoxDecoration(
          color: AppColors.surface3,
          borderRadius: BorderRadius.circular(6),
        ),
        padding: const EdgeInsets.symmetric(horizontal: 10),
        child: TextField(
          controller: controller,
          enabled: enabled,
          minLines: 1,
          maxLines: 4,
          onSubmitted: onSubmitted,
          style: sans(12, height: 17 / 12, color: AppColors.fg1),
          cursorColor: AppColors.fg1,
          decoration: InputDecoration(
            isDense: true,
            border: InputBorder.none,
            hintText: hint,
            hintStyle: sans(12, height: 17 / 12, color: AppColors.fg2),
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
