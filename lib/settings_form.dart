import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lucide_icons_flutter/lucide_icons.dart';

import 'platform.dart';
import 'theme.dart';
import 'desktop_look.dart';
import 'widgets.dart';

// ---------------------------------------------------------------------------
// Grouped rows, design language v7 (option A).
//
// A page is a column of [SettingsGroup]s on the page colour. Each group is an
// optional [SettingsSectionLabel], a stack of row tiles ([GroupedTiles]: every
// row on its own surface, 2px apart, radius 20 at the group's ends and 4
// inside) and an optional [SettingsFootnote]. Rows are [SettingsRow]; a row
// whose job is to pick a value is a [SettingsPickerRow], which shows the
// choice under the title on phones so it is never truncated.
// ---------------------------------------------------------------------------

/// Design language v7 tokens for grouped pages; phone values, then desktop.
abstract final class Grouped {
  static bool get _phone => kMobile;

  /// One step smaller rows and type on the phone.
  static bool compact = true;
  static double _ph(double full, double small) => compact ? small : full;

  // Geometry.
  static const double gutter = 12;
  static double get rowMin => _phone ? _ph(64, 56) : 48;
  static double get rowMinTwoLine => _phone ? _ph(76, 66) : 56;
  static double get padX => _phone ? 16 : 14;
  static double get padY => _phone ? _ph(10, 8) : 9;
  static double get icon => _phone ? _ph(22, 20) : 16;
  static double get iconGap => _phone ? _ph(14, 12) : 12;
  static const double chevron = 16;
  static double get radiusEnd => _phone ? _ph(20, 18) : 10;
  static const double radiusInner = 4;
  static const double gap = 2;
  static double get sectionGap => _phone ? 28 : 36;
  static double get labelGap => _phone ? 8 : 10;
  static const double footGap = 8;
  static const double headerHeight = 56;
  static const double circle = 40;
  static const double pillHeight = 40;
  static const double avatar = 112;
  static const double avatarCharacter = 84;
  static const double leadCharacter = 32;
  static const double contentMaxWidth = 680;
  static const double sidebarWidth = 224;
  static const double navRowHeight = 30;

  // Type: whole-pixel sizes with their line heights.
  static const double pageTitleSize = 17;
  static double get heroSize => _phone ? 24 : 20;
  static double get titleSize => _phone ? _ph(17, 16) : 13;
  static double get titleLine => _phone ? _ph(22, 21) : 18;
  static double get subSize => _phone ? _ph(15, 14) : 12;
  static double get subLine => _phone ? _ph(20, 19) : 16;
  static double get valueSize => _phone ? _ph(15, 14) : 12;
  static double get labelSize => _phone ? _ph(15, 14) : 12;
  static double get footSize => _phone ? 14 : 12;
  static double get footLine => _phone ? 20 : 16;

  // Colours, derived from the active theme so every palette keeps working.
  static Color _over(double a) =>
      Color.alphaBlend(AppColors.fg1.withValues(alpha: a), AppColors.bg);

  /// Row surface: the page plus about 9% of the text colour. Translucent on
  /// desktop, where the settings pane sits over the window's own tint.
  static Color get row =>
      _phone ? _over(0.09) : AppColors.fg1.withValues(alpha: 0.075);

  /// Avatar plate and pill fill: between the page and a row.
  static Color get plate =>
      _phone ? _over(0.07) : AppColors.fg1.withValues(alpha: 0.06);
  static Color get pillBorder => AppColors.fg1.withValues(alpha: 0.16);
  static Color get label => Color.lerp(AppColors.fg2, AppColors.fg3, 0.5)!;
  static Color get muted => AppColors.fg3;
  static Color get faint => AppColors.fg4;
  static Color get iconColor => AppColors.fg2;
  static Color get toggleOn =>
      _phone ? Color.lerp(AppColors.fg1, AppColors.fg2, 0.4)! : AppColors.accent;
  static Color get toggleOff => _over(0.17);

  /// Corner radii of tile [index] of [count]: round at the group's ends.
  static BorderRadius tileRadius(int index, int count) {
    final end = Radius.circular(R.of(radiusEnd));
    final inner = Radius.circular(R.of(radiusInner));
    final first = index == 0;
    final last = index == count - 1;
    return BorderRadius.only(
      topLeft: first ? end : inner,
      topRight: first ? end : inner,
      bottomLeft: last ? end : inner,
      bottomRight: last ? end : inner,
    );
  }

  static TextStyle titleStyle([Color? color]) =>
      sans(titleSize, height: titleLine / titleSize, color: color ?? AppColors.fg1);
  static TextStyle subStyle([Color? color]) =>
      sans(subSize, height: subLine / subSize, color: color ?? muted);
  static TextStyle valueStyle([Color? color]) =>
      sans(valueSize, color: color ?? muted);
  static TextStyle labelStyle() => _phone
      ? sans(labelSize, height: 20 / labelSize, color: label)
      : sans(13, weight: FontWeight.w500, height: 20 / 13, color: AppColors.fg1);

  /// Desktop group card: one bordered surface, rows split by hairlines.
  static Color get card => AppColors.fg1.withValues(alpha: 0.028);
  static Color get cardBorder => AppColors.fg1.withValues(alpha: 0.075);
  static Color get hairline => AppColors.fg1.withValues(alpha: 0.06);
  static TextStyle footStyle() =>
      sans(footSize, height: footLine / footSize, color: muted);
  static TextStyle pageTitleStyle() =>
      sans(pageTitleSize, weight: FontWeight.w600, color: AppColors.fg1);
  static TextStyle heroStyle() =>
      sans(heroSize, weight: FontWeight.w600, color: AppColors.fg1);
}

/// Stroke-1.5 Lucide glyphs for the names grouped rows use; others fall back
/// to [AppIcon]. Const so release builds can still tree-shake the icon fonts.
const Map<String, IconData> _thinIcons = {
  'activity': LucideIcons.activity300,
  'agent': LucideIcons.bot300,
  'archive': LucideIcons.archive300,
  'audio-lines': LucideIcons.audioLines300,
  'bell': LucideIcons.bell300,
  'book': LucideIcons.book300,
  'book-marked': LucideIcons.bookMarked300,
  'calendar-clock': LucideIcons.calendarClock300,
  'chat-thread': LucideIcons.messageSquare300,
  'clock': LucideIcons.clock300,
  'columns-3': LucideIcons.columns3300,
  'cpu': LucideIcons.cpu300,
  'crown': LucideIcons.crown300,
  'ear': LucideIcons.ear300,
  'edit': LucideIcons.pencil300,
  'folder': LucideIcons.folder300,
  'gauge': LucideIcons.gauge300,
  'globe': LucideIcons.globe300,
  'inbox': LucideIcons.inbox300,
  'key': LucideIcons.keyRound300,
  'key-round': LucideIcons.keyRound300,
  'laptop': LucideIcons.laptop300,
  'list-checks': LucideIcons.listChecks300,
  'lock': LucideIcons.lock300,
  'map-pin': LucideIcons.mapPin300,
  'message-circle': LucideIcons.messageCircle300,
  'mic': LucideIcons.mic300,
  'pencil': LucideIcons.pencil300,
  'plus': LucideIcons.plus300,
  'repeat': LucideIcons.repeat300,
  'route': LucideIcons.route300,
  'scheduled': LucideIcons.calendarClock300,
  'shield-check': LucideIcons.shieldCheck300,
  'sliders': LucideIcons.slidersHorizontal300,
  'sliders-horizontal': LucideIcons.slidersHorizontal300,
  'star': LucideIcons.star300,
  'task': LucideIcons.listChecks300,
  'timer': LucideIcons.timer300,
  'trash': LucideIcons.trash2300,
  'trash-2': LucideIcons.trash2300,
  'user': LucideIcons.user300,
  'user-plus': LucideIcons.userPlus300,
  'users': LucideIcons.users300,
  'zap': LucideIcons.zap300,
};

/// A bare leading icon in the row's icon column: no tile, 22 on phones.
class SettingsIcon extends StatelessWidget {
  const SettingsIcon(this.name, {super.key, this.iconData, this.color})
      : assert(name != null || iconData != null);

  final String? name;
  final IconData? iconData;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final size = Grouped.icon;
    final c = color ?? Grouped.iconColor;
    final data = iconData ?? _thinIcons[name];
    if (!kMobile) {
      // Desktop list rows lead with a small tile, as in the device lists.
      return Container(
        width: 28,
        height: 28,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.fg1.withValues(alpha: 0.05),
          borderRadius: BorderRadius.circular(R.of(7)),
        ),
        child: data != null
            ? Icon(data, size: 15, color: c)
            : AppIcon(name!, size: 15, color: c),
      );
    }
    return SizedBox(
      width: size + 2,
      height: size + 2,
      child: Center(
        child: data != null
            ? Icon(data, size: size, color: c)
            : AppIcon(name!, size: size, color: c),
      ),
    );
  }
}

/// Centres any leading widget (a character, an avatar) in the icon column so
/// row titles line up with icon rows; a larger child spills into the gap.
class SettingsLeading extends StatelessWidget {
  const SettingsLeading({super.key, required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final box = kMobile ? Grouped.icon + 2 : 28.0;
    return SizedBox(
      width: box,
      height: box,
      child: OverflowBox(
        maxWidth: box + 24,
        maxHeight: box + 24,
        child: Center(child: child),
      ),
    );
  }
}

/// A group caption: 15 on phones, inset to the row text, 8 above its rows.
class SettingsSectionLabel extends StatelessWidget {
  const SettingsSectionLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
            Grouped.padX, 0, Grouped.padX, Grouped.labelGap),
        child: Semantics(
          header: true,
          child: Text(text, style: Grouped.labelStyle()),
        ),
      );
}

/// A standalone caption with the section gap above it, for a page that lays
/// out its own tiles instead of using [SettingsGroup].
class SettingsGroupLabel extends StatelessWidget {
  const SettingsGroupLabel(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(top: Grouped.sectionGap),
        child: SettingsSectionLabel(text),
      );
}

/// Muted text under a group, inset to the row text.
class SettingsFootnote extends StatelessWidget {
  const SettingsFootnote(this.text, {super.key});
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(
            Grouped.padX, Grouped.footGap, Grouped.padX, 0),
        child: Text(text, style: Grouped.footStyle()),
      );
}

/// One tile of a group: the row surface, clipped so ink stays inside.
class GroupedTile extends StatelessWidget {
  const GroupedTile(
      {super.key, required this.radius, required this.child, this.color});
  final BorderRadius radius;
  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: radius,
        child: Material(color: color ?? Grouped.row, child: child),
      );
}

/// The rows of a group, each on its own tile, [Grouped.gap] apart.
class GroupedTiles extends StatelessWidget {
  const GroupedTiles({super.key, required this.children, this.color});
  final List<Widget> children;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final n = children.length;
    if (!kMobile) {
      final radius = BorderRadius.circular(Grouped.radiusEnd);
      return Container(
        decoration: BoxDecoration(
          color: color ?? Grouped.card,
          borderRadius: radius,
          border: Border.all(color: Grouped.cardBorder),
        ),
        child: ClipRRect(
          borderRadius: radius,
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < n; i++) ...[
                  if (i > 0) Container(height: 1, color: Grouped.hairline),
                  children[i],
                ],
              ],
            ),
          ),
        ),
      );
    }
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < n; i++) ...[
          if (i > 0) const SizedBox(height: Grouped.gap),
          GroupedTile(
              radius: Grouped.tileRadius(i, n),
              color: color,
              child: children[i]),
        ],
      ],
    );
  }
}

/// A group: optional caption, the row tiles, optional footnote, then the gap
/// to the next group.
class SettingsGroup extends StatelessWidget {
  const SettingsGroup(
      {super.key, this.header, this.footer, required this.children});
  final String? header;
  final String? footer;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(bottom: Grouped.sectionGap),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (header != null && header!.isNotEmpty)
              SettingsSectionLabel(header!),
            if (children.isNotEmpty) GroupedTiles(children: children),
            if (footer != null && footer!.isNotEmpty) SettingsFootnote(footer!),
          ],
        ),
      );
}

/// A grouped row: bare icon or [leading], 17px title over an optional muted
/// line, an optional value on the right, then [trailing] or a chevron.
/// Min height 64 single-line and 76 two-line on phones (52/60 on desktop).
class SettingsRow extends StatelessWidget {
  const SettingsRow({
    super.key,
    required this.label,
    this.sub,
    this.subWidget,
    this.subMaxLines,
    this.icon,
    this.iconData,
    this.iconColor,
    this.leading,
    this.value,
    this.valueColor,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.chevron = false,
    this.danger = false,
    this.accent = false,
    this.labelWidget,
  });

  final String label;

  /// The muted line under the title; wraps unless [subMaxLines] is set.
  final String? sub;
  final Widget? subWidget;
  final int? subMaxLines;

  /// Leading glyph by [AppIcon] name or [IconData]; [leading] wins over both.
  final String? icon;
  final IconData? iconData;
  final Color? iconColor;
  final Widget? leading;

  /// Right-hand value, muted, never wider than about 45% of the row.
  final String? value;
  final Color? valueColor;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final bool chevron;

  /// Danger and accent tint the title and icon; one accent row per screen.
  final bool danger;
  final bool accent;
  final Widget? labelWidget;

  @override
  Widget build(BuildContext context) {
    final tint = danger
        ? AppColors.danger
        : accent
            ? AppColors.accent
            : null;
    final lead = leading ??
        (icon != null || iconData != null
            ? SettingsIcon(icon, iconData: iconData, color: iconColor ?? tint)
            : null);
    final s = sub;
    final hasSub = subWidget != null || (s != null && s.isNotEmpty);
    final text = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        labelWidget ??
            Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Grouped.titleStyle(tint)),
        if (hasSub)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: subWidget ??
                Text(s!,
                    maxLines: subMaxLines,
                    overflow:
                        subMaxLines == null ? null : TextOverflow.ellipsis,
                    style: Grouped.subStyle()),
          ),
      ],
    );
    final v = value;
    Widget row(double? valueMax) => Row(children: [
          if (lead != null) ...[lead, SizedBox(width: Grouped.iconGap)],
          Expanded(child: text),
          if (v != null && v.isNotEmpty) ...[
            const SizedBox(width: 12),
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: valueMax ?? 200),
              child: Text(v,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.end,
                  style: Grouped.valueStyle(valueColor)),
            ),
          ],
          if (trailing != null) ...[const SizedBox(width: 12), trailing!],
          if (chevron)
            Transform.translate(
              offset: const Offset(4, 0),
              child: Padding(
                padding: const EdgeInsets.only(left: 8),
                child: AppIcon('chevron-right',
                    size: Grouped.chevron, color: Grouped.faint),
              ),
            ),
        ]);
    final content = ConstrainedBox(
      constraints: BoxConstraints(
          minHeight: hasSub ? Grouped.rowMinTwoLine : Grouped.rowMin),
      child: Padding(
        padding: EdgeInsets.symmetric(
            horizontal: Grouped.padX, vertical: Grouped.padY),
        child: v == null || v.isEmpty
            ? row(null)
            : LayoutBuilder(
                builder: (context, c) => row(c.maxWidth.isFinite
                    ? c.maxWidth * 0.45
                    : null)),
      ),
    );
    if (onTap == null && onLongPress == null) return content;
    return Material(
      type: MaterialType.transparency,
      child: InkWell(onTap: onTap, onLongPress: onLongPress, child: content),
    );
  }
}

/// A row that picks a value. Phones show the choice under the title, never
/// truncated; desktop shows it on the right. Tapping opens [items] as the
/// app menu, or calls [onTap] for a custom picker.
class SettingsPickerRow<T> extends StatelessWidget {
  const SettingsPickerRow({
    super.key,
    required this.label,
    required this.value,
    this.detail,
    this.icon,
    this.iconData,
    this.items,
    this.selected,
    this.onSelected,
    this.onTap,
    this.sheetHeightFactor,
    this.valueColor,
    this.enabled = true,
  }) : assert(items == null || onSelected != null);

  final String label;

  /// The current choice.
  final String value;

  /// Extra context after the choice ("Normal listening").
  final String? detail;
  final String? icon;
  final IconData? iconData;
  final List<(T, String)>? items;
  final T? selected;
  final ValueChanged<T>? onSelected;
  final VoidCallback? onTap;
  final double? sheetHeightFactor;
  final Color? valueColor;
  final bool enabled;

  @override
  Widget build(BuildContext context) => Builder(builder: (anchor) {
        VoidCallback? tap;
        if (enabled) {
          final list = items;
          tap = list == null
              ? onTap
              : () async {
                  final picked = await showAppMenu<T>(context,
                      anchor: anchor,
                      sheetHeightFactor: sheetHeightFactor,
                      items: [
                        for (final (v, l) in list)
                          appMenuItem(
                              value: v, label: l, selected: v == selected),
                      ]);
                  if (picked != null) onSelected!(picked);
                };
        }
        final d = detail;
        final hasDetail = d != null && d.isNotEmpty;
        if (kMobile) {
          final line = hasDetail ? '$value · $d' : value;
          return SettingsRow(
            label: label,
            icon: icon,
            iconData: iconData,
            sub: valueColor == null ? line : null,
            subWidget: valueColor == null
                ? null
                : Text(line, style: Grouped.subStyle(valueColor)),
            chevron: true,
            onTap: tap,
          );
        }
        return SettingsRow(
          label: label,
          icon: icon,
          iconData: iconData,
          sub: hasDetail ? d : null,
          trailing: items == null
              ? null
              : SettingsDropdownBox(label: value, color: valueColor),
          value: items == null ? value : null,
          valueColor: valueColor,
          chevron: items == null,
          onTap: tap,
        );
      });
}

/// Desktop select: an outlined box with the choice and a down chevron.
class SettingsDropdownBox extends StatelessWidget {
  const SettingsDropdownBox(
      {super.key, required this.label, this.leading, this.color});
  final String label;
  final Widget? leading;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
        height: 28,
        constraints: const BoxConstraints(minWidth: 112, maxWidth: 240),
        padding: const EdgeInsets.fromLTRB(10, 0, 8, 0),
        decoration: BoxDecoration(
          color: AppColors.fg1.withValues(alpha: 0.035),
          borderRadius: BorderRadius.circular(R.of(6)),
          border: Border.all(color: AppColors.fg1.withValues(alpha: 0.1)),
        ),
        child: Row(
            mainAxisSize: MainAxisSize.min,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  if (leading != null) ...[leading!, const SizedBox(width: 7)],
                  Flexible(
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(12.5, color: color ?? AppColors.fg1)),
                  ),
                ]),
              ),
              Padding(
                padding: const EdgeInsets.only(left: 10),
                child: AppIcon('chevron-down', size: 12, color: AppColors.fg3),
              ),
            ]),
      );
}

/// Compatibility name for the round 5 icon tile: now a bare icon, no tile.
class V5IconTile extends StatelessWidget {
  const V5IconTile(this.icon, {super.key, this.color, this.iconData})
      : assert(icon != null || iconData != null);

  final String? icon;
  final IconData? iconData;
  final Color? color;

  @override
  Widget build(BuildContext context) =>
      SettingsIcon(icon, iconData: iconData, color: color);
}

/// Compatibility wrapper for the round 5 row API; renders a [SettingsRow].
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
  Widget build(BuildContext context) => SettingsRow(
        label: label,
        leading: leading,
        value: value,
        valueColor: valueColor,
        sub: subtitle,
        trailing: trailing,
        onTap: onTap,
        chevron: trailing == null && (chevron ?? onTap != null),
        danger: danger,
        labelWidget: labelWidget,
      );
}

/// The 40px round header button on the row surface (back, close).
class GroupedCircleButton extends StatelessWidget {
  const GroupedCircleButton(
      {super.key, required this.icon, required this.onTap, this.tooltip});
  final String icon;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final button = Semantics(
      button: true,
      label: tooltip,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Container(
          width: Grouped.circle,
          height: Grouped.circle,
          decoration: BoxDecoration(color: Grouped.row, shape: BoxShape.circle),
          child: Center(
            child: AppIcon(icon, size: kMobile ? 20 : 18, color: AppColors.fg1),
          ),
        ),
      ),
    );
    return tooltip == null ? button : Tooltip(message: tooltip!, child: button);
  }
}

/// The 40px header pill (Edit, Done): plate fill, 1px border, 17/500 label.
class GroupedPillButton extends StatelessWidget {
  const GroupedPillButton(this.label, {super.key, required this.onTap});
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => Semantics(
        button: true,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            height: Grouped.pillHeight,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: Grouped.plate,
              borderRadius: BorderRadius.circular(Grouped.pillHeight / 2),
              border: Border.all(color: Grouped.pillBorder),
            ),
            child: Text(label,
                style: sans(kMobile ? 17 : 15,
                    weight: FontWeight.w500, color: AppColors.fg1)),
          ),
        ),
      );
}

/// An entity page's centred hero: [avatar] on a 112 plate circle (or bare
/// when [plate] is false), the name at 24/600 and a muted line.
class SettingsHero extends StatelessWidget {
  const SettingsHero({
    super.key,
    required this.avatar,
    required this.name,
    this.sub,
    this.plate = true,
    this.onLongPress,
  });

  final Widget avatar;
  final String name;
  final String? sub;
  final bool plate;
  final VoidCallback? onLongPress;

  @override
  Widget build(BuildContext context) {
    final size = kMobile ? Grouped.avatar : 88.0;
    final s = sub;
    return Padding(
      padding: const EdgeInsets.fromLTRB(0, 4, 0, 8),
      child: Column(mainAxisSize: MainAxisSize.min, children: [
        GestureDetector(
          onLongPress: onLongPress,
          child: plate
              ? Container(
                  width: size,
                  height: size,
                  clipBehavior: Clip.antiAlias,
                  decoration:
                      BoxDecoration(color: Grouped.plate, shape: BoxShape.circle),
                  child: Center(child: avatar),
                )
              : avatar,
        ),
        const SizedBox(height: 14),
        Text(name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: Grouped.heroStyle()),
        if (s != null && s.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text(s,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Grouped.subStyle()),
        ],
      ]),
    );
  }
}

/// On/off switch. Phones: 52 x 32 with a 24 knob; on is a light neutral, not
/// the accent, so the accent stays free for a screen's one primary action.
class SettingsSwitch extends StatelessWidget {
  const SettingsSwitch({super.key, required this.value, this.onChanged});
  final bool value;
  final ValueChanged<bool>? onChanged;

  @override
  Widget build(BuildContext context) {
    final w = kMobile ? 52.0 : 30.0;
    final h = kMobile ? 32.0 : 18.0;
    final knob = kMobile ? 24.0 : 14.0;
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
            width: w,
            height: h,
            padding: EdgeInsets.all((h - knob) / 2),
            alignment: value ? Alignment.centerRight : Alignment.centerLeft,
            decoration: BoxDecoration(
              color: value ? Grouped.toggleOn : Grouped.toggleOff,
              borderRadius: BorderRadius.circular(h / 2),
            ),
            child: Container(
              width: knob,
              height: knob,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                // Desktop rows are translucent; the knob must be opaque.
                color: value
                    ? (kMobile ? Grouped.row : Colors.white)
                    : (kMobile ? AppColors.fg1 : AppColors.fg2),
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

  Future<void> _open(BuildContext context, BuildContext anchor) async {
    final picked = await showAppMenu<T>(context,
        anchor: anchor,
        sheetHeightFactor: sheetHeightFactor,
        items: [
          for (final (v, l) in items)
            appMenuItem(value: v, label: l, selected: v == selected),
        ]);
    if (picked != null) onSelected(picked);
  }

  @override
  Widget build(BuildContext context) {
    if (!kMobile) {
      return Builder(
        builder: (anchor) => MouseRegion(
          cursor: SystemMouseCursors.click,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _open(context, anchor),
            child: SettingsDropdownBox(label: label, leading: leading),
          ),
        ),
      );
    }
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
      child: Tactile(
        radius: BorderRadius.circular(R.of(6)),
        kind: TactileKind.inset,
        child: Container(
        height: kMobile ? 34 : 28,
        padding: kMobile
            ? EdgeInsets.zero
            : EdgeInsets.symmetric(horizontal: S.of(9)),
        decoration: kMobile
            ? null
            : BoxDecoration(
                color: AppColors.fg1.withValues(alpha: 0.035),
                borderRadius: BorderRadius.circular(R.of(6)),
                border: Border.all(color: AppColors.fg1.withValues(alpha: 0.1)),
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
