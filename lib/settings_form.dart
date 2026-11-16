import 'package:flutter/material.dart';
import 'desktop_look.dart';
import 'package:flutter/services.dart';

import 'platform.dart';
import 'theme.dart';
import 'widgets.dart';

/// v5 phone group caption: 13px sentence-case text indented past the card edge.
class SettingsGroupLabel extends StatelessWidget {
  const SettingsGroupLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(S.s16, S.s16, 0, S.s4),
        child: Text(text, style: sans(13, color: AppColors.fg3)),
      );
}

/// v5 30px rounded icon tile on `surface2` with `R.md` corners.
class V5IconTile extends StatelessWidget {
  const V5IconTile(this.icon, {super.key, this.color, this.iconData})
      : assert(icon != null || iconData != null);

  final String? icon;
  final IconData? iconData;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
        width: 30,
        height: 30,
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(R.md),
        ),
        child: Center(
          child: iconData != null
              ? Icon(iconData, size: 17, color: color ?? AppColors.fg2)
              : AppIcon(icon!, size: 16, color: color ?? AppColors.fg2),
        ),
      );
}

/// v5 `.pgi` row: minHeight 46, optional 30px leading tile, 15px label,
/// 14px muted value, trailing widget or chevron when tappable.
class V5SettingsRow extends StatelessWidget {
  const V5SettingsRow({
    super.key,
    required this.label,
    this.leading,
    this.value,
    this.valueColor,
    this.subtitle,
    this.trailing,
    this.onTap,
    this.chevron,
    this.danger = false,
    this.labelWidget,
  });

  final String label;
  final Widget? leading;
  final String? value;
  final Color? valueColor;
  final String? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool? chevron;
  final bool danger;
  final Widget? labelWidget;

  @override
  Widget build(BuildContext context) {
    final v = value;
    final showChevron = trailing == null && (chevron ?? onTap != null);
    final body = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 46),
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: S.of(14), vertical: S.s8),
        child: Row(children: [
          if (leading != null) ...[leading!, SizedBox(width: S.s12)],
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                labelWidget ??
                    Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(15,
                            color: danger ? AppColors.danger : AppColors.fg1)),
                if (subtitle != null && subtitle!.isNotEmpty)
                  Text(subtitle!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(13, color: AppColors.fg3)),
              ],
            ),
          ),
          if (v != null && v.isNotEmpty) ...[
            SizedBox(width: S.s8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 150),
              child: Text(v,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(14, color: valueColor ?? AppColors.fg3)),
            ),
          ],
          if (trailing != null) ...[
            SizedBox(width: S.s6),
            trailing!,
          ] else if (showChevron) ...[
            SizedBox(width: S.s6),
            AppIcon('chevron-right', size: 14, color: AppColors.fg3),
          ],
        ]),
      ),
    );
    if (onTap == null) return body;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: body),
    );
  }
}

class SettingsGroup extends StatelessWidget {
  const SettingsGroup(
      {super.key, this.header, this.footer, required this.children});
  final String? header;
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      rows.add(children[i]);
      if (i < children.length - 1) {
        rows.add(Padding(
          padding: EdgeInsets.only(left: kMobile ? S.s16 : S.of(14)),
          child: Container(height: 1, color: AppColors.line),
        ));
      }
    }
    return Padding(
      padding: EdgeInsets.only(bottom: kMobile ? S.of(26) : S.s24),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (header != null)
          Padding(
            padding: EdgeInsets.fromLTRB(kMobile ? S.s16 : S.s4, 0, S.s4, S.s6),
            child: Text(header!.toUpperCase(), style: TS.overline()),
          ),
        Tactile(
          radius: BorderRadius.circular(kMobile ? 14 : 10),
          child: Container(
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: AppColors.surface1,
            borderRadius: BorderRadius.circular(kMobile ? 14 : 10),
          ),
          foregroundDecoration: BoxDecoration(
            borderRadius: BorderRadius.circular(kMobile ? 14 : 10),
            border: Border.all(color: AppColors.line),
          ),
          // Ink must paint inside the clip, not on a Material further up.
          child: Material(
            type: MaterialType.transparency,
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch, children: rows),
          ),
        ),
        ),
        if (footer != null)
          Padding(
            padding: EdgeInsets.fromLTRB(kMobile ? S.s16 : S.s4, S.of(7), S.s4, 0),
            child: Text(footer!, style: TS.meta()),
          ),
      ]),
    );
  }
}

class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.label,
    this.sub,
    this.trailing,
    this.leading,
    this.onTap,
    this.chevron = false,
    this.danger = false,
    this.labelWidget,
  });
  final String label;
  final String? sub;
  final Widget? trailing;
  final Widget? leading;
  final VoidCallback? onTap;
  final bool chevron;
  final bool danger;
  final Widget? labelWidget;

  @override
  Widget build(BuildContext context) {
    final content = ConstrainedBox(
      constraints: BoxConstraints(minHeight: kMobile ? 52 : 40),
      child: Padding(
        padding: kMobile
            ? EdgeInsets.symmetric(horizontal: S.s16, vertical: S.s12)
            : EdgeInsets.symmetric(horizontal: S.of(14), vertical: S.of(9)),
        child: Row(children: [
          if (leading != null) ...[leading!, SizedBox(width: S.s12)],
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  labelWidget ??
                      Text(label,
                          style: TS.rowTitle(
                              danger ? AppColors.danger : AppColors.fg1)),
                  if (sub != null && sub!.isNotEmpty) ...[
                    SizedBox(height: S.s2),
                    Text(sub!, style: TS.meta()),
                  ],
                ]),
          ),
          if (trailing != null) ...[SizedBox(width: S.s12), trailing!],
          if (chevron) ...[
            SizedBox(width: S.s8),
            AppIcon('chevron-right', size: 14, color: AppColors.fg3),
          ],
        ]),
      ),
    );
    if (onTap == null) return content;
    return Material(
      color: Colors.transparent,
      child: InkWell(onTap: onTap, child: content),
    );
  }
}

class SettingsSwitch extends StatelessWidget {
  const SettingsSwitch({super.key, required this.value, this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      toggled: value,
      child: GestureDetector(
        onTap: onChanged == null ? null : () => onChanged!(!value),
        child: MouseRegion(
          cursor: onChanged == null
              ? SystemMouseCursors.basic
              : SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            width: kMobile ? 44 : 34,
            height: kMobile ? 26 : 20,
            padding: EdgeInsets.all(S.s2),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            decoration: BoxDecoration(
              color: value ? AppColors.accent : AppColors.surface3,
              borderRadius: BorderRadius.circular(R.of(13)),
            ),
            child: Container(
              width: kMobile ? 22 : 16,
              height: kMobile ? 22 : 16,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: value ? AppColors.bg : AppColors.fg3,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class SettingsPopup<T> extends StatelessWidget {
  const SettingsPopup({
    super.key,
    required this.label,
    required this.items,
    required this.selected,
    required this.onSelected,
    this.leading,
    this.sheetHeightFactor,
  });
  final double? sheetHeightFactor;
  final String label;
  final List<(T, String)> items;
  final T selected;
  final ValueChanged<T> onSelected;
  final Widget? leading;

  @override
  Widget build(BuildContext context) {
    return Builder(
      builder: (anchor) => Material(
        color: kMobile ? Colors.transparent : AppColors.surface2,
        borderRadius: BorderRadius.circular(R.of(7)),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.of(7)),
          onTap: () async {
            final picked = await showAppMenu<T>(context,
                anchor: anchor,
                sheetHeightFactor: sheetHeightFactor,
                items: [
                  for (final (v, l) in items)
                    appMenuItem(value: v, label: l, selected: v == selected),
                ]);
            if (picked != null) onSelected(picked);
          },
          child: Container(
            height: kMobile ? 32 : 26,
            padding:
                EdgeInsets.fromLTRB(kMobile ? S.s4 : S.of(10), 0, kMobile ? 0 : S.s8, 0),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (leading != null) ...[leading!, SizedBox(width: S.of(7))],
              Text(label,
                  style: sans(kMobile ? 15 : 13,
                      color: kMobile ? AppColors.fg3 : AppColors.fg1)),
              SizedBox(width: S.s6),
              AppIcon(kMobile ? 'chevron-right' : 'chevrons-up-down',
                  size: 14, color: AppColors.fg3),
            ]),
          ),
        ),
      ),
    );
  }
}

class SettingsField extends StatelessWidget {
  const SettingsField({
    super.key,
    required this.controller,
    this.hint,
    this.width = 240,
    this.mono = false,
    this.obscure = false,
    this.number = false,
    this.onChanged,
    this.onSubmitted,
    this.suffix,
    this.focusNode,
  });
  final TextEditingController controller;
  final String? hint;
  final double width;
  final bool mono;
  final bool obscure;
  final bool number;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final Widget? suffix;
  final FocusNode? focusNode;

  @override
  Widget build(BuildContext context) {
    final style = mono
        ? sans(kMobile ? 15 : 13, color: AppColors.fg1)
        : sans(kMobile ? 15 : 13, color: AppColors.fg1);
    return SizedBox(
      width: kMobile ? (width > 210 ? 210 : width) : width,
      child: Container(
        height: kMobile ? 34 : 28,
        padding: kMobile
            ? EdgeInsets.zero
            : EdgeInsets.symmetric(horizontal: S.of(9)),
        decoration: kMobile
            ? null
            : BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(R.of(7)),
                border: Border.all(color: AppColors.border),
              ),
        child: Row(children: [
          Expanded(
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              obscureText: obscure,
              onChanged: onChanged,
              onSubmitted: onSubmitted,
              textAlign: kMobile ? TextAlign.right : TextAlign.left,
              keyboardType: number ? TextInputType.number : null,
              inputFormatters:
                  number ? [FilteringTextInputFormatter.digitsOnly] : null,
              style: style,
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: style.copyWith(color: AppColors.fg4),
              ),
            ),
          ),
          if (suffix != null) ...[SizedBox(width: S.s6), suffix!],
        ]),
      ),
    );
  }
}

class SettingsPill extends StatelessWidget {
  const SettingsPill(this.label,
      {super.key, required this.onTap, this.danger = false});
  final String label;
  final VoidCallback? onTap;
  final bool danger;

  @override
  Widget build(BuildContext context) => Material(
        color: danger ? Colors.transparent : AppColors.surface2,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kMobile ? R.pill : R.sm),
            side: BorderSide(
                color: danger
                    ? AppColors.danger.withValues(alpha: 0.3)
                    : Colors.transparent)),
        child: InkWell(
          borderRadius: BorderRadius.circular(kMobile ? R.pill : R.sm),
          onTap: onTap,
          child: Container(
            height: 28,
            padding: EdgeInsets.symmetric(horizontal: S.s12),
            alignment: Alignment.center,
            child: Text(label,
                style: sans(13,
                    color: danger ? AppColors.danger : AppColors.fg2)),
          ),
        ),
      );
}
