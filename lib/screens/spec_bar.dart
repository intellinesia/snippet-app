import 'package:flutter/material.dart';

import '../tap_detector.dart';
import '../theme.dart';
import '../widgets.dart';

/// Spec A SH-10 bar B: back 48 x 48 at x0, 16/500 title at x56, optional
/// 12/400 fg3 subtitle, trailing 48 x 48 actions, hairline under. Min height,
/// never fixed, so 200 percent text grows it.
class SpecBar extends StatelessWidget {
  const SpecBar(
      {super.key,
      required this.title,
      this.subtitle,
      this.actions = const [],
      this.onBack});
  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) => Container(
        constraints: const BoxConstraints(minHeight: 52),
        decoration: BoxDecoration(
            color: AppColors.bg,
            border: Border(bottom: BorderSide(color: AppColors.border))),
        padding: const EdgeInsets.only(right: 4),
        child: Row(children: [
          Semantics(
            button: true,
            label: 'Back',
            child: TapDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onBack ?? () => Navigator.of(context).maybePop(),
              child: SizedBox(
                  width: 48,
                  height: 48,
                  child: Center(
                      child: AppIcon('chevron-left',
                          size: 20, color: AppColors.fg1))),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(16, weight: W.label, color: AppColors.fg1)),
                    if (subtitle != null && subtitle!.isNotEmpty)
                      Text(subtitle!,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: sans(12,
                              height: 16.2 / 12, color: AppColors.fg3)),
                  ]),
            ),
          ),
          ...actions,
        ]),
      );
}

/// A 20 icon in fg2 inside a 48 x 48 target.
class SpecIconAction extends StatelessWidget {
  const SpecIconAction(this.icon, this.label, this.onTap, {super.key});
  final String icon, label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
              width: 48,
              height: 48,
              child:
                  Center(child: AppIcon(icon, size: 20, color: AppColors.fg2))),
        ),
      );
}

/// Section label 12/500 fg3 at x16.
class SpecLabel extends StatelessWidget {
  const SpecLabel(this.text, {super.key, this.top = 20});
  final String text;
  final double top;
  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(16, top, 16, 8),
        child: Text(text,
            style: sans(12, weight: W.label, color: AppColors.fg3)),
      );
}

/// Segment chip: 44 high, radius 22, selected surface3 13/500 fg1, else
/// surface2 13/400 fg2. Label scaler clamps at 1.35.
class SpecChip extends StatelessWidget {
  const SpecChip(this.label, this.selected, this.onTap, {super.key});
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final mq = MediaQuery.of(context);
    return MediaQuery(
      data: mq.copyWith(textScaler: mq.textScaler.clamp(maxScaleFactor: 1.35)),
      child: Semantics(
        button: true,
        selected: selected,
        label: label,
        child: ExcludeSemantics(
          child: TapDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              height: 44,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                  color: selected ? AppColors.surface3 : AppColors.surface2,
                  borderRadius: BorderRadius.circular(22)),
              child: Text(label,
                  style: sans(13,
                      weight: selected ? W.label : W.body,
                      color: selected ? AppColors.fg1 : AppColors.fg2)),
            ),
          ),
        ),
      ),
    );
  }
}

/// Chips at x16, gap 8, wrapping to a second line at large text.
class SpecChipWrap extends StatelessWidget {
  const SpecChipWrap({super.key, required this.chips});
  final List<Widget> chips;
  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Wrap(spacing: 8, runSpacing: 8, children: chips),
      );
}

/// The selected-row mark shared by radio-like lists: surface2 fill, radius 8,
/// a 2 wide fg1 bar at x8 inset 4, and the word "Selected" (not colour alone).
class SpecSelectRow extends StatelessWidget {
  const SpecSelectRow({
    super.key,
    required this.label,
    this.sub,
    required this.selected,
    required this.onTap,
    this.leading,
    this.minHeight = 48,
    this.barHeight = 40,
  });
  final String label;
  final String? sub;
  final bool selected;
  final VoidCallback onTap;
  final Widget? leading;
  final double minHeight, barHeight;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        selected: selected,
        label: selected ? '$label, Selected' : label,
        child: ExcludeSemantics(
          child: TapDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 8),
              constraints: BoxConstraints(minHeight: minHeight),
              decoration: BoxDecoration(
                  color: selected ? AppColors.surface2 : Colors.transparent,
                  borderRadius: BorderRadius.circular(8)),
              child: Stack(alignment: Alignment.centerLeft, children: [
                if (selected)
                  Container(
                      width: 2,
                      height: barHeight - 8,
                      margin: const EdgeInsets.only(left: 0),
                      color: AppColors.fg1),
                Padding(
                  padding: const EdgeInsets.fromLTRB(12, 6, 8, 6),
                  child: Row(children: [
                    if (leading != null) ...[
                      leading!,
                      const SizedBox(width: 12)
                    ],
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(label,
                                style: sans(15,
                                    weight: selected ? W.label : W.body,
                                    color: AppColors.fg1)),
                            if (sub != null)
                              Text(sub!,
                                  style: sans(13,
                                      color: selected
                                          ? AppColors.fg2
                                          : AppColors.fg3)),
                          ]),
                    ),
                    if (selected)
                      Padding(
                        padding: const EdgeInsets.only(left: 8, right: 4),
                        child: Text('Selected',
                            style: sans(11, color: AppColors.fg2)),
                      ),
                  ]),
                ),
              ]),
            ),
          ),
        ),
      );
}
