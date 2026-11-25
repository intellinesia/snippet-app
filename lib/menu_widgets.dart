import 'dart:async';

import 'package:flutter/material.dart';

import 'app_popover.dart';
import 'dialog_widgets.dart' show trackMenuTrigger;
import 'platform.dart';
import 'theme.dart';
import 'widgets.dart';

export 'toast.dart' show toast;

ShapeBorder get appMenuShape => RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(R.card),
      side: BorderSide(color: AppColors.glassBorder),
    );

PopupMenuItem<T> appMenuItem<T>({
  required T value,
  required String label,
  String? icon,
  String? detail,
  bool danger = false,
  bool selected = false,
  bool enabled = true,
  double height = 30,
}) {
  if (kMobile) {
    return PopupMenuItem<T>(
      value: value,
      enabled: enabled,
      height: M.minTarget + 8,
      padding: EdgeInsets.zero,
      child: _SheetRowBody(
          icon: icon,
          label: label,
          trailing: detail,
          danger: danger,
          selected: selected,
          disabled: !enabled),
    );
  }
  return AppMenuItem<T>(
    value: value,
    enabled: enabled,
    height: height,
    padding: EdgeInsets.zero,
    searchText: '$label ${detail ?? ''}',
    child: AppPopoverRowBody(
        label: label,
        icon: icon,
        trailing: detail,
        danger: danger,
        selected: selected,
        disabled: !enabled),
  );
}

/// A richer popover row: icon, title, optional one-line description, and a
/// trailing check when selected. Used by the composer's approval and provider
/// menus, where the choice needs explaining rather than just naming.
PopupMenuItem<T> appMenuRow<T>({
  required T value,
  String icon = 'sparkles',
  Widget? leading,
  required String label,
  String? description,
  String? trailing,
  Widget? trailingWidget,
  bool selected = false,
  bool enabled = true,
  double? height,
}) {
  if (kMobile) {
    return PopupMenuItem<T>(
      value: value,
      enabled: enabled,
      height: M.minTarget + 8,
      padding: EdgeInsets.zero,
      child: _SheetRowBody(
          icon: icon,
          leading: leading,
          label: label,
          detail: description,
          trailing: trailing,
          trailingWidget: trailingWidget,
          selected: selected,
          disabled: !enabled),
    );
  }
  return AppMenuItem<T>(
    value: value,
    enabled: enabled,
    height: height ?? (description != null ? 40 : 30),
    padding: EdgeInsets.zero,
    searchText: '$label ${description ?? ''}',
    child: AppPopoverRowBody(
        label: label,
        icon: leading == null ? icon : null,
        leading: leading,
        detail: description,
        trailing: trailing,
        trailingWidget: trailingWidget,
        selected: selected,
        disabled: !enabled),
  );
}

/// A menu title placed above a group of rows (showMenu takes these as disabled
/// items, which is the only way to put non-selectable text in a popup menu).
PopupMenuItem<T> appMenuHeading<T>(String label) => PopupMenuItem<T>(
      enabled: false,
      height: 34,
      // Desktop inset matches the item content edge (10px item padding).
      padding: EdgeInsets.zero,
      child: kMobile ? _MenuHeading(label) : AppMenuHeading(label),
    );

class _MenuHeading extends StatelessWidget {
  const _MenuHeading(this.label);
  final String label;

  @override
  Widget build(BuildContext context) =>
      Text(label.toUpperCase(), style: TS.overline());
}

/// The row body shared by every phone menu entry: the session Actions row
/// (leading icon, [TS.rowTitle] title, quiet detail line, optional value and a
/// check for the selected item), without its own tap target.
class _SheetRowBody extends StatelessWidget {
  const _SheetRowBody({
    this.icon,
    this.leading,
    required this.label,
    this.detail,
    this.trailing,
    this.trailingWidget,
    this.danger = false,
    this.selected = false,
    this.disabled = false,
  });

  final bool disabled;
  final String? icon;
  final Widget? leading;
  final String label;
  final String? detail;
  final String? trailing;
  final Widget? trailingWidget;
  final bool danger;
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final lead = leading ??
        (icon == null
            ? null
            : AppIcon(icon!,
                size: 19,
                color: disabled
                    ? AppColors.fg4
                    : danger
                        ? AppColors.danger
                        : AppColors.fg3));
    return ConstrainedBox(
      constraints: BoxConstraints(minHeight: M.minTarget + 8),
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: S.of(11)),
        child: Row(children: [
          if (lead != null) ...[lead, SizedBox(width: S.of(14))],
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TS.rowTitle(disabled
                        ? AppColors.fg4
                        : danger
                            ? AppColors.danger
                            : null)),
                if (detail != null) ...[
                  SizedBox(height: S.s2),
                  Text(detail!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TS.meta(disabled ? AppColors.fg4 : AppColors.fg2)),
                ],
              ],
            ),
          ),
          if (trailingWidget != null) ...[
            SizedBox(width: S.s8),
            trailingWidget!,
          ],
          if (trailing != null) ...[
            SizedBox(width: S.s8),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 140),
              child: Text(trailing!,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  textAlign: TextAlign.right,
                  style: TS.meta()),
            ),
          ],
          if (selected) ...[
            SizedBox(width: S.of(10)),
            AppIcon('check', size: 18, color: AppColors.accent),
          ],
        ]),
      ),
    );
  }
}

/// The 36x4 grab handle every phone sheet carries.
class SheetGrabHandle extends StatelessWidget {
  const SheetGrabHandle({super.key, this.compact = false});

  /// Tight spacing for a sheet header that is already a fixed-height bar.
  final bool compact;

  @override
  Widget build(BuildContext context) => Padding(
        padding: compact
            ? EdgeInsets.only(top: S.s4)
            : EdgeInsets.only(top: S.s8, bottom: S.s8),
        child: Center(
          child: Container(
            width: 36,
            height: 4,
            decoration: BoxDecoration(
                color: AppColors.lineStrong,
                borderRadius: BorderRadius.circular(R.pill)),
          ),
        ),
      );
}

/// The one phone sheet surface: [R.sheetTop] top corners, raised fill, grab
/// handle. [child] gets the remaining height.
class AppSheetSurface extends StatelessWidget {
  const AppSheetSurface({super.key, required this.child, this.color});

  final Widget child;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final fill = color ?? AppColors.raised;
    final body = DecoratedBox(
      decoration: BoxDecoration(
        color: fill, // spec G: opaque, no backdrop blur
      ),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [const SheetGrabHandle(), Flexible(child: child)]),
    );
    return ClipRRect(
      borderRadius: BorderRadius.vertical(top: Radius.circular(R.sheetTop)),
      child: body,
    );
  }
}

/// Present a menu in the shape the platform expects.
///
/// ONE entry point for every `appMenuItem`/`appMenuRow` menu in the app: a bottom
/// sheet on a phone (full width, rows at real touch height, thumb reachable) and
/// an anchored popover on desktop.
///
/// Callers previously each computed a `RelativeRect` and called `showMenu`
/// directly, which is why the same menu opened as a cramped floating card on a
/// phone — 40px rows, 12px padding, no grab handle, no sheet affordance.
Future<T?> showAppMenu<T>(
  BuildContext context, {
  required List<PopupMenuEntry<T>> items,

  /// The control this menu belongs to; the desktop popover anchors to it.
  BuildContext? anchor,

  /// Optional vertical reference box (e.g. the composer card container).
  /// When provided, the menu positions its top/bottom edge relative to this
  /// box instead of the anchor control, avoiding covering the input area.
  BuildContext? verticalAnchor,

  /// Explicit screen point (long-press / right-click). Wins over [anchor].
  Offset? point,
  double minWidth = 260,
  double maxWidth = 340,
  Color? color,

  /// Open BELOW the anchor instead of above it. Set for controls at the TOP of
  /// the window (the shell menu), where an upward menu would be clipped offscreen.
  bool below = false,

  /// Align the popover's RIGHT edge with the anchor's, instead of its left.
  /// Set for a control at the right end of a narrow bar — a section header's
  /// actions, say — where a left-aligned popover would open away from the button
  /// it belongs to.
  bool alignEnd = false,
  double? sheetHeightFactor,

  /// Overrides the outlined default, for menus drawn as a bare stepped surface.
  ShapeBorder? shape,
}) {
  if (kMobile) {
    return showModalBottomSheet<T>(
      sheetAnimationStyle: sheetMotion,
      context: context,
      backgroundColor: Colors.transparent,
      barrierColor: AppColors.glassScrim,
      isScrollControlled: true,
      builder: (sheet) {
        final media = MediaQuery.of(sheet);
        return AppSheetSurface(
          color: color,
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: sheetHeightFactor == null
                    ? double.infinity
                    : media.size.height * sheetHeightFactor),
            child: SingleChildScrollView(
              padding: EdgeInsets.fromLTRB(
                  M.gutter, 0, M.gutter, media.padding.bottom + S.s12),
              child: Material(
                color: Colors.transparent,
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: _appMenuSheetEntries(sheet, items)),
              ),
            ),
          ),
        );
      },
    );
  }

  final overlay = Overlay.of(context, rootOverlay: true)
      .context
      .findRenderObject() as RenderBox?;
  Rect rectOf(BuildContext c) {
    final box = c.findRenderObject() as RenderBox?;
    if (overlay == null || box == null || !box.attached) {
      return const Rect.fromLTWH(16, 80, 0, 0);
    }
    return box.localToGlobal(Offset.zero, ancestor: overlay) & box.size;
  }

  final Rect control;
  Rect vertical;
  if (point != null) {
    control = Rect.fromLTWH(point.dx, point.dy, 0, 0);
    vertical = control;
  } else if (anchor != null) {
    control = rectOf(anchor);
    vertical = verticalAnchor != null ? rectOf(verticalAnchor) : control;
  } else {
    control = const Rect.fromLTWH(16, 80, 0, 0);
    vertical = control;
  }
  var effMin = (point != null && minWidth == 260)
      ? 200.0
      : (minWidth == 260 ? 280.0 : minWidth);
  // A menu is never narrower than the control it drops from.
  if (point == null && anchor != null && control.width > effMin) {
    effMin = control.width;
  }
  var effMax = (point != null && maxWidth == 340)
      ? 260.0
      : (maxWidth == 340 ? 360.0 : maxWidth);
  if (effMax < effMin) effMax = effMin;
  return trackMenuTrigger<T?>(
    control.expandToInclude(vertical),
    () => showAppPopoverMenu<T>(
      context,
      items: items,
      minWidth: effMin,
      maxWidth: effMax,
      anchor: AppPopoverAnchor(
          control: control,
          vertical: vertical,
          below: below || point != null,
          alignEnd: alignEnd),
    ),
  );
}

/// The phone menu sheet's rows: headings as group labels, hairlines between
/// consecutive rows (as ActionGroup draws them), dividers as group gaps.
List<Widget> _appMenuSheetEntries<T>(
    BuildContext sheet, List<PopupMenuEntry<T>> items) {
  final out = <Widget>[];
  var prevRow = false;
  for (var i = 0; i < items.length; i++) {
    final entry = items[i];
    if (entry is PopupMenuDivider) {
      out.add(SizedBox(height: S.s8));
      prevRow = false;
      continue;
    }
    if (entry is! PopupMenuItem<T>) continue;
    if (!entry.enabled) {
      final child = entry.child;
      if (child is _SheetRowBody) {
        if (prevRow) out.add(Container(height: 1, color: AppColors.line));
        out.add(child);
        prevRow = true;
        continue;
      }
      final heading = child is _MenuHeading;
      out.add(Padding(
        padding: heading
            ? EdgeInsets.only(top: out.isEmpty ? S.s4 : S.s16, bottom: S.s4)
            : EdgeInsets.symmetric(vertical: S.s4),
        child: child,
      ));
      prevRow = false;
      continue;
    }
    if (prevRow) out.add(Container(height: 1, color: AppColors.line));
    out.add(InkWell(
      onTap: () => Navigator.pop(sheet, entry.value),
      child: entry.child,
    ));
    prevRow = true;
  }
  return out;
}

/// Open a markdown link in the external browser (fire-and-forget).
/// Compact relative time like "now", "5m", "3h", "2d", "4mo" (empty for 0).
String relativeTime(int unixSec) {
  if (unixSec == 0) return '';
  final d = DateTime.now()
      .difference(DateTime.fromMillisecondsSinceEpoch(unixSec * 1000));
  if (d.inMinutes < 1) return 'now';
  if (d.inMinutes < 60) return '${d.inMinutes}m';
  if (d.inHours < 24) return '${d.inHours}h';
  if (d.inDays < 30) return '${d.inDays}d';
  if (d.inDays < 365) return '${(d.inDays / 30).floor()}mo';
  return '${(d.inDays / 365).floor()}y';
}

/// Human-readable byte size (B / KB / MB). Accepts an int or anything parseable.
String formatBytes(dynamic n) {
  final b = n is int ? n : int.tryParse(n.toString()) ?? 0;
  if (b < 1024) return '$b B';
  if (b < 1024 * 1024) return '${(b / 1024).toStringAsFixed(1)} KB';
  return '${(b / 1024 / 1024).toStringAsFixed(1)} MB';
}

/// Last non-empty path segment (the folder/file name), or [ifEmpty] when there is none.
String lastPathSegment(String path, {String ifEmpty = ''}) {
  final seg = path.split('/').where((p) => p.isNotEmpty).lastOrNull;
  return seg ?? (path.isEmpty ? ifEmpty : path);
}

/// A row of selectable rounded pills. [items] maps each value to its label;
