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
  Widget build(BuildContext context) => Text(label,
      style: sans(13, weight: FontWeight.w500, color: AppColors.fg3));
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
                size: 20,
                color: disabled
                    ? AppColors.fg4
                    : danger
                        ? AppColors.danger
                        : AppColors.fg1));
    final reason = trailing;
    return Semantics(
      hint: detail,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        // Icon at x26, label at x64, trailing text at viewport minus 20.
        child: Padding(
          padding: const EdgeInsets.fromLTRB(26, 8, 20, 8),
          child: Row(children: [
            SizedBox(width: 20, child: lead),
            const SizedBox(width: 18),
            Expanded(
              child: Text(label,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                  style: sans(15,
                      weight: FontWeight.w400,
                      color: disabled
                          ? AppColors.fg3
                          : danger
                              ? AppColors.danger
                              : AppColors.fg1)),
            ),
            if (trailingWidget != null) ...[
              const SizedBox(width: 8),
              trailingWidget!,
            ],
            if (reason != null) ...[
              const SizedBox(width: 8),
              ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 140),
                child: Text(reason,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.right,
                    style: sans(12, color: AppColors.fg3)),
              ),
            ],
            if (selected) ...[
              const SizedBox(width: 10),
              AppIcon('check', size: 18, color: AppColors.fg1),
            ],
          ]),
        ),
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
                color: AppColors.surface3,
                borderRadius: BorderRadius.circular(2)),
          ),
        ),
      );
}

/// The one phone sheet surface: [R.sheetTop] top corners, raised fill, grab
/// handle. [child] gets the remaining height.
class AppSheetSurface extends StatelessWidget {
  const AppSheetSurface(
      {super.key,
      required this.child,
      this.color,
      this.expand = false,
      this.handle = true});

  /// False when the child draws [SheetGrabHandle] itself (inside a target).
  final bool handle;

  /// Fill the height the route gives (medium and large sheets).
  final bool expand;

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
          mainAxisSize: expand ? MainAxisSize.max : MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (handle) const SheetGrabHandle(),
            expand ? Expanded(child: child) : Flexible(child: child)
          ]),
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
      barrierColor: AppColors.scrim,
      isScrollControlled: true,
      builder: (sheet) {
        final media = MediaQuery.of(sheet);
        return AppSheetSurface(
          color: color,
          child: ConstrainedBox(
            constraints: BoxConstraints(
                maxHeight: media.size.height * (sheetHeightFactor ?? 0.85)),
            child: SingleChildScrollView(
              padding: EdgeInsets.only(bottom: media.padding.bottom),
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
  // A menu is never narrower than the control it drops from, unless that
  // "control" is a whole pane passed as a fallback anchor.
  if (point == null &&
      anchor != null &&
      control.width > effMin &&
      control.width <= 480) {
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
  var first = true;
  Widget hairline() => Container(
      height: 1,
      margin: const EdgeInsets.only(left: 64, right: 16),
      color: AppColors.line);
  for (var i = 0; i < items.length; i++) {
    final entry = items[i];
    if (entry is PopupMenuDivider) {
      out.add(Container(
          height: 1,
          margin: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          color: AppColors.line));
      prevRow = false;
      continue;
    }
    if (entry is! PopupMenuItem<T>) continue;
    if (!entry.enabled) {
      final child = entry.child;
      if (child is _SheetRowBody) {
        if (prevRow) out.add(hairline());
        out.add(child);
        prevRow = true;
        continue;
      }
      out.add(Padding(
        padding: const EdgeInsets.fromLTRB(20, 4, 20, 8),
        child: child,
      ));
      prevRow = false;
      continue;
    }
    if (prevRow) out.add(hairline());
    out.add(InkWell(
      autofocus: first,
      onTap: () => Navigator.pop(sheet, entry.value),
      splashFactory: NoSplash.splashFactory,
      hoverColor: Colors.transparent,
      highlightColor: AppColors.surface2,
      focusColor: AppColors.surface2,
      child: entry.child,
    ));
    first = false;
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
