import 'package:flutter/material.dart';

import '../tap_detector.dart';
import '../theme.dart';
import '../widgets.dart';
import 'shell_rail.dart' show ShellSection;

/// SH-10 bar type B: 48 back target at x0, 16/500 title at x56, optional 12/400
/// subtitle, trailing 20 icon actions in 48 targets. Hairline 1 at the bottom,
/// fill = page background, min height so large text never clips.
class PhoneBar extends StatelessWidget {
  const PhoneBar({
    super.key,
    required this.title,
    this.subtitle,
    this.onBack,
    this.trailing = const [],
    this.fill,
  });
  final String title;
  final String? subtitle;
  final VoidCallback? onBack;
  final List<Widget> trailing;
  final Color? fill;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: fill ?? AppColors.bg,
          border: Border(bottom: BorderSide(color: AppColors.border)),
        ),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 52),
          child: Row(children: [
            if (onBack != null)
              Semantics(
                button: true,
                label: 'Back',
                excludeSemantics: true,
                child: TapDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onBack,
                  child: SizedBox(
                      width: 48,
                      height: 48,
                      child: Center(
                          child: AppIcon('chevron-left',
                              size: 20, color: AppColors.fg1))),
                ),
              )
            else
              const SizedBox(width: 48),
            const SizedBox(width: 8),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(16,
                              weight: W.label, color: AppColors.fg1)),
                      if (subtitle != null && subtitle!.isNotEmpty)
                        Text(subtitle!,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: sans(12,
                                height: 16.2 / 12, color: AppColors.fg3)),
                    ]),
              ),
            ),
            ...trailing,
            const SizedBox(width: 4),
          ]),
        ),
      );
}

/// A 48 x 48 target with a 20 icon in fg2.
class PhoneBarAction extends StatelessWidget {
  const PhoneBarAction(this.icon, this.label, this.onTap, {super.key});
  final String icon, label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        label: label,
        excludeSemantics: true,
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: SizedBox(
              width: 48,
              height: 48,
              child: Center(
                  child: AppIcon(icon, size: 20, color: AppColors.fg2))),
        ),
      );
}

/// SH-04 chips: Files, Git, Terminals at 44 high, radius 22, gap 8, x16.
/// Selected surface3 13/500 fg1, unselected surface2 13/400 fg2; label scaler
/// clamps at 1.35 and the row scrolls when wider than the content.
class PhoneToolChips extends StatelessWidget {
  const PhoneToolChips({super.key, required this.current, this.onSection});
  final ShellSection current;
  final ValueChanged<ShellSection>? onSection;

  static const items = [
    (ShellSection.files, 'Files', 56.0),
    (ShellSection.git, 'Git', 56.0),
    (ShellSection.terminal, 'Terminals', 81.6),
  ];

  @override
  Widget build(BuildContext context) {
    final scaler = MediaQuery.textScalerOf(context).clamp(maxScaleFactor: 1.35);
    return SizedBox(
      height: 44 + 16,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        itemCount: items.length,
        separatorBuilder: (_, __) => const SizedBox(width: 8),
        itemBuilder: (context, i) {
          final (section, label, w) = items[i];
          final sel = section == current;
          return Semantics(
            button: true,
            selected: sel,
            label: label,
            excludeSemantics: true,
            child: TapDetector(
              behavior: HitTestBehavior.opaque,
              onTap: () => onSection?.call(section),
              child: Container(
                constraints: BoxConstraints(minWidth: w, minHeight: 44),
                padding: const EdgeInsets.symmetric(horizontal: 12),
                decoration: BoxDecoration(
                  color: sel ? AppColors.surface3 : AppColors.surface2,
                  borderRadius: BorderRadius.circular(22),
                ),
                alignment: Alignment.center,
                child: Text(label,
                    textScaler: scaler,
                    maxLines: 1,
                    style: sans(13,
                        weight: sel ? W.label : W.body,
                        color: sel ? AppColors.fg1 : AppColors.fg2)),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Bar B plus the chip row, shown above Files, Git and Terminals on the phone.
class PhoneToolHeader extends StatelessWidget {
  const PhoneToolHeader({
    super.key,
    required this.section,
    required this.subtitle,
    this.onSection,
    this.onBack,
    this.onMore,
  });
  final ShellSection section;
  final String subtitle;
  final ValueChanged<ShellSection>? onSection;
  final VoidCallback? onBack;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) {
    final title = switch (section) {
      ShellSection.files => 'Files',
      ShellSection.git => 'Git',
      _ => 'Terminals',
    };
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      PhoneBar(
        title: title,
        subtitle: subtitle,
        onBack: onBack ?? () => onSection?.call(ShellSection.sessions),
        trailing: [if (onMore != null) PhoneBarAction('more', 'More', onMore)],
      ),
      PhoneToolChips(current: section, onSection: onSection),
    ]);
  }
}
