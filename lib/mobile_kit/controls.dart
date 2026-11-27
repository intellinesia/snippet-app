import 'package:flutter/material.dart';

import '../glass.dart';
import '../tap_detector.dart';
import '../theme.dart';
import '../widgets.dart';
import 'tokens.dart';

/// The control layer surface. iPhone: frosted glass with a soft lift.
/// Android: a flat tonal container. [radius] null means a circle.
class MkGlass extends StatelessWidget {
  const MkGlass({super.key, required this.child, this.radius, this.tonal});
  final Widget child;
  final double? radius;

  /// Android fill; defaults to surface2.
  final Color? tonal;

  @override
  Widget build(BuildContext context) {
    final shape = radius == null ? BoxShape.circle : BoxShape.rectangle;
    final br = radius == null ? null : BorderRadius.circular(radius!);
    if (kAndroidLook) {
      return DecoratedBox(
        decoration: BoxDecoration(
            color: tonal ?? AppColors.surface2, shape: shape, borderRadius: br),
        child: child,
      );
    }
    return DecoratedBox(
      decoration: BoxDecoration(
        shape: shape,
        borderRadius: br,
        boxShadow: const [
          BoxShadow(
              color: Color(0x59000000), blurRadius: 24, offset: Offset(0, 8)),
        ],
      ),
      child: Glass(
        radius: br,
        tint: MK.glassFill,
        blur: 22,
        child: child,
      ),
    );
  }
}

/// A round header button: glass on iPhone, a bare 48 icon button on Android.
class MkIconButton extends StatelessWidget {
  const MkIconButton(
      {super.key,
      required this.icon,
      required this.label,
      this.onTap,
      this.size,
      this.bare = false});
  final String icon;
  final String label;
  final VoidCallback? onTap;
  final double? size;

  /// No surface even on iPhone (inside a cluster or the composer).
  final bool bare;

  @override
  Widget build(BuildContext context) {
    final d = size ?? (kAndroidLook ? 48.0 : MK.glassButton);
    Widget face = SizedBox(
      width: d,
      height: d,
      child: Center(
          child: AppIcon(icon,
              size: kAndroidLook ? 22 : 19,
              color: onTap == null ? AppColors.fg4 : AppColors.fg1)),
    );
    if (!kAndroidLook && !bare) face = MkGlass(child: face);
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: Tooltip(
        message: label,
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          // Keeps a 44 target around a 40 face.
          child: Padding(
            padding: EdgeInsets.all(d < 44 ? (44 - d) / 2 : 0),
            child: face,
          ),
        ),
      ),
    );
  }
}

/// One action in a header cluster.
class MkAction {
  const MkAction(this.icon, this.label, this.onTap);
  final String icon;
  final String label;
  final VoidCallback? onTap;
}

/// Two or three header actions in one glass capsule (iPhone) or a row of
/// 48 icon buttons (Android).
class MkActionCluster extends StatelessWidget {
  const MkActionCluster({super.key, required this.actions});
  final List<MkAction> actions;

  @override
  Widget build(BuildContext context) {
    final buttons = [
      for (final a in actions)
        MkIconButton(icon: a.icon, label: a.label, onTap: a.onTap, bare: true)
    ];
    if (kAndroidLook || actions.length == 1) {
      return actions.length == 1 && !kAndroidLook
          ? MkIconButton(
              icon: actions.first.icon,
              label: actions.first.label,
              onTap: actions.first.onTap)
          : Row(mainAxisSize: MainAxisSize.min, children: buttons);
    }
    return MkGlass(
      radius: 22,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 2),
        child: Row(mainAxisSize: MainAxisSize.min, children: buttons),
      ),
    );
  }
}

/// One option in a [MkFilterGroup].
class MkFilter<T> {
  const MkFilter(this.value, this.label, {this.count});
  final T value;
  final String label;
  final int? count;
}

/// Connected button group used for every list filter. Unselected segments
/// share 8 inner corners; the selected one becomes a full pill in the
/// primary ink. Android gaps the segments a little wider.
class MkFilterGroup<T> extends StatelessWidget {
  const MkFilterGroup(
      {super.key,
      required this.options,
      required this.selected,
      required this.onSelect,
      this.padding = const EdgeInsets.fromLTRB(20, 10, 20, 0)});
  final List<MkFilter<T>> options;
  final T selected;
  final ValueChanged<T> onSelect;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final gap = kAndroidLook ? 4.0 : 2.0;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: padding,
      child: Row(children: [
        for (var i = 0; i < options.length; i++) ...[
          if (i > 0) SizedBox(width: gap),
          _segment(options[i], i),
        ]
      ]),
    );
  }

  Widget _segment(MkFilter<T> o, int i) {
    final on = o.value == selected;
    const outer = Radius.circular(18);
    final inner = Radius.circular(kAndroidLook ? 6 : 8);
    final first = i == 0, last = i == options.length - 1;
    final radius = on
        ? const BorderRadius.all(outer)
        : BorderRadius.horizontal(
            left: first ? outer : inner, right: last ? outer : inner);
    return Semantics(
      button: true,
      selected: on,
      label: o.count == null ? o.label : '${o.label}, ${o.count}',
      excludeSemantics: true,
      child: TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => onSelect(o.value),
        // 36 face inside a 44 target.
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: on ? AppColors.fg1 : AppColors.surface2,
                borderRadius: radius),
            child: Text.rich(
              TextSpan(children: [
                TextSpan(text: o.label),
                if (o.count != null)
                  TextSpan(
                      text: '  ${o.count}',
                      style: sans(13.5,
                          color: on
                              ? MK.onPrimary.withValues(alpha: 0.6)
                              : AppColors.fg4)),
              ]),
              maxLines: 1,
              style: sans(13.5,
                  weight: W.label, color: on ? MK.onPrimary : AppColors.fg2),
            ),
          ),
        ),
      ),
    );
  }
}

enum MkPillTone { primary, secondary, quiet }

/// 40 high answer and action pill.
class MkPill extends StatelessWidget {
  const MkPill(this.label,
      {super.key,
      this.onTap,
      this.tone = MkPillTone.secondary,
      this.icon,
      this.expand = false});
  final String label;
  final VoidCallback? onTap;
  final MkPillTone tone;
  final String? icon;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final (bg, fg) = switch (tone) {
      MkPillTone.primary => (AppColors.fg1, MK.onPrimary),
      MkPillTone.secondary => (AppColors.surface3, AppColors.fg1),
      MkPillTone.quiet => (Colors.transparent, AppColors.fg3),
    };
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        // 48 target around the 40 pill.
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 4),
          child: Container(
            height: MK.pill,
            padding: EdgeInsets.symmetric(
                horizontal: tone == MkPillTone.quiet ? 10 : 20),
            alignment: Alignment.center,
            decoration: BoxDecoration(
                color: onTap == null && tone != MkPillTone.quiet
                    ? bg.withValues(alpha: 0.5)
                    : bg,
                borderRadius: BorderRadius.circular(20)),
            child: Row(
              mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  AppIcon(icon!, size: 17, color: fg),
                  const SizedBox(width: 6),
                ],
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(14.5, weight: W.label, color: fg)),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-width primary or secondary button for a page's one main action
/// (50 on iPhone, 56 on Android).
class MkBigButton extends StatelessWidget {
  const MkBigButton(this.label,
      {super.key, this.onTap, this.icon, this.secondary = false});
  final String label;
  final VoidCallback? onTap;
  final String? icon;
  final bool secondary;

  @override
  Widget build(BuildContext context) {
    final h = MK.bigButton;
    final fg = secondary ? AppColors.fg1 : MK.onPrimary;
    return Semantics(
      button: true,
      label: label,
      excludeSemantics: true,
      child: TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Opacity(
          opacity: onTap == null ? 0.5 : 1,
          child: Container(
            height: h,
            decoration: BoxDecoration(
              color: secondary ? AppColors.surface2 : AppColors.fg1,
              borderRadius: BorderRadius.circular(h / 2),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (icon != null) ...[
                  AppIcon(icon!, size: 18, color: fg),
                  const SizedBox(width: 8),
                ],
                Text(label,
                    style: sans(16,
                        weight: kAndroidLook ? W.label : FontWeight.w600,
                        color: fg)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Split primary button (New task plus a menu chevron).
class MkSplitButton extends StatelessWidget {
  const MkSplitButton(
      {super.key,
      required this.label,
      required this.icon,
      required this.onTap,
      this.onMenu,
      this.menuLabel = 'More options'});
  final String label;
  final String icon;
  final VoidCallback onTap;
  final VoidCallback? onMenu;
  final String menuLabel;

  @override
  Widget build(BuildContext context) {
    const outer = Radius.circular(20);
    final inner = Radius.circular(kAndroidLook ? 4 : 6);
    Widget part(Widget child, BorderRadius r, VoidCallback? tap, String sem,
            EdgeInsets pad) =>
        Semantics(
          button: true,
          label: sem,
          excludeSemantics: true,
          child: TapDetector(
            behavior: HitTestBehavior.opaque,
            onTap: tap,
            child: Container(
              height: 40,
              padding: pad,
              decoration: BoxDecoration(color: AppColors.fg1, borderRadius: r),
              child: child,
            ),
          ),
        );
    return Row(mainAxisSize: MainAxisSize.min, children: [
      part(
          Row(mainAxisSize: MainAxisSize.min, children: [
            AppIcon(icon, size: 17, color: MK.onPrimary),
            const SizedBox(width: 6),
            Text(label, style: sans(14, weight: W.label, color: MK.onPrimary)),
          ]),
          BorderRadius.horizontal(
              left: outer, right: onMenu == null ? outer : inner),
          onTap,
          label,
          EdgeInsets.fromLTRB(12, 0, onMenu == null ? 16 : 14, 0)),
      if (onMenu != null) ...[
        const SizedBox(width: 2),
        part(
            Center(
                child: AppIcon('chevron-down', size: 16, color: MK.onPrimary)),
            BorderRadius.horizontal(left: inner, right: outer),
            onMenu,
            menuLabel,
            const EdgeInsets.symmetric(horizontal: 10)),
      ],
    ]);
  }
}

/// iOS-style switch on iPhone (51x31), Material 3 switch on Android (52x32).
class MkToggle extends StatelessWidget {
  const MkToggle(
      {super.key, required this.value, required this.onChanged, this.label});
  final bool value;
  final ValueChanged<bool>? onChanged;
  final String? label;

  @override
  Widget build(BuildContext context) {
    final a = kAndroidLook;
    final w = a ? 52.0 : 51.0, h = a ? 32.0 : 31.0;
    final knob = a ? (value ? 24.0 : 16.0) : 27.0;
    return Semantics(
      toggled: value,
      label: label,
      excludeSemantics: true,
      child: TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 6),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 180),
            width: w,
            height: h,
            decoration: BoxDecoration(
              color: value
                  ? AppColors.fg1
                  : (a ? Colors.transparent : AppColors.surface3),
              borderRadius: BorderRadius.circular(h / 2),
              border: a && !value
                  ? Border.all(color: AppColors.fg4, width: 2)
                  : null,
            ),
            child: AnimatedAlign(
              duration: const Duration(milliseconds: 180),
              curve: Curves.easeOutCubic,
              alignment: value ? Alignment.centerRight : Alignment.centerLeft,
              child: Padding(
                // Android's off track spends 2 of its 6 on the border.
                padding: EdgeInsets.all(a ? 4 : 2),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  width: knob,
                  height: knob,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: value
                        ? MK.onPrimary
                        : (a ? AppColors.fg4 : AppColors.fg3),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
