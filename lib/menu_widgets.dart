import 'dart:async';
import 'package:flutter/material.dart';

import 'platform.dart';
import 'theme.dart';
import 'widgets.dart';

OverlayEntry? _activeToast;
Timer? _toastTimer;

ShapeBorder get appMenuShape => RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(10),
      side: BorderSide(color: AppColors.glassBorder),
    );

PopupMenuItem<T> appMenuItem<T>({
  required T value,
  required String label,
  String? icon,
  String? detail,
  bool danger = false,
  bool selected = false,
  double height = 30,
}) {
  if (kMobile) {
    return PopupMenuItem<T>(
      value: value,
      height: M.minTarget + 8,
      padding: EdgeInsets.zero,
      child: _SheetRowBody(
          icon: icon,
          label: label,
          trailing: detail,
          danger: danger,
          selected: selected),
    );
  }
  final color = danger ? AppColors.danger : AppColors.fg1;
  return PopupMenuItem<T>(
    value: value,
    height: height,
    padding: const EdgeInsets.symmetric(horizontal: 10),
    child: Row(children: [
      if (icon != null) ...[
        AppIcon(icon, size: 14, color: danger ? AppColors.danger : AppColors.fg3),
        const SizedBox(width: 9),
      ],
      Expanded(
        child: Text(label,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: TS.ui(color)),
      ),
      if (detail != null) Text(detail, style: TS.meta()),
      if (selected) ...[
        const SizedBox(width: S.s8),
        AppIcon('check', size: 14, color: AppColors.accent),
      ],
    ]),
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
  double? height,
}) {
  if (kMobile) {
    return PopupMenuItem<T>(
      value: value,
      height: M.minTarget + 8,
      padding: EdgeInsets.zero,
      child: _SheetRowBody(
          icon: icon,
          leading: leading,
          label: label,
          detail: description,
          trailing: trailing,
          trailingWidget: trailingWidget,
          selected: selected),
    );
  }
  return PopupMenuItem<T>(
    value: value,
    height: height ?? (description != null ? 44 : 34),
    padding: const EdgeInsets.symmetric(horizontal: 2),
    child: Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: selected ? AppColors.surface2 : Colors.transparent,
        borderRadius: BorderRadius.circular(R.sm),
      ),
      child: Row(children: [
        leading ??
            AppIcon(icon,
                size: 15, color: selected ? AppColors.accent : AppColors.fg3),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TS.ui(AppColors.fg1)),
              if (description != null) ...[
                const SizedBox(height: 1),
                Text(description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TS.caption()),
              ],
            ],
          ),
        ),
        if (trailingWidget != null) ...[
          const SizedBox(width: 8),
          trailingWidget,
        ],
        if (trailing != null) ...[
          const SizedBox(width: 8),
          Text(trailing, style: TS.caption()),
        ],
        if (selected) ...[
          const SizedBox(width: 8),
          AppIcon('check', size: 14, color: AppColors.accent),
        ],
      ]),
    ),
  );
}

/// A menu title placed above a group of rows (showMenu takes these as disabled
/// items, which is the only way to put non-selectable text in a popup menu).
PopupMenuItem<T> appMenuHeading<T>(String label) => PopupMenuItem<T>(
      enabled: false,
      height: 34,
      // Desktop inset matches the item content edge (10px item padding).
      padding: kMobile
          ? EdgeInsets.zero
          : const EdgeInsets.fromLTRB(10, 8, 10, 2),
      child: Text(label.toUpperCase(), style: TS.overline()),
    );

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
  });

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
                size: 19, color: danger ? AppColors.danger : AppColors.fg3));
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: M.minTarget + 8),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 11),
        child: Row(children: [
          if (lead != null) ...[lead, const SizedBox(width: 14)],
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TS.rowTitle(danger ? AppColors.danger : null)),
                if (detail != null) ...[
                  const SizedBox(height: 2),
                  Text(detail!,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TS.meta()),
                ],
              ],
            ),
          ),
          if (trailingWidget != null) ...[
            const SizedBox(width: 8),
            trailingWidget!,
          ],
          if (trailing != null) ...[
            const SizedBox(width: 8),
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
            const SizedBox(width: 10),
            AppIcon('check', size: 18, color: AppColors.accent),
          ],
        ]),
      ),
    );
  }
}

/// The 36x4 grab handle every phone sheet carries.
class SheetGrabHandle extends StatelessWidget {
  const SheetGrabHandle({super.key});

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(top: S.s8, bottom: S.s8),
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
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.vertical(top: Radius.circular(R.sheetTop)),
        child: ColoredBox(
          color: color ?? AppColors.raised,
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [const SheetGrabHandle(), Flexible(child: child)]),
        ),
      );
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
}) {
  final bg = color ?? AppColors.surface1;

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

  final overlay = Overlay.of(context).context.findRenderObject() as RenderBox?;
  RelativeRect position;
  if (overlay == null) {
    position = const RelativeRect.fromLTRB(16, 80, 16, 80);
  } else if (point != null) {
    position = RelativeRect.fromRect(
      Rect.fromCircle(center: point, radius: 0),
      Offset.zero & overlay.size,
    );
  } else if (anchor != null) {
    final box = anchor.findRenderObject() as RenderBox?;
    if (box == null) {
      position = const RelativeRect.fromLTRB(16, 80, 16, 80);
    } else {
      final origin = box.localToGlobal(Offset.zero, ancestor: overlay);
      final vertBox = verticalAnchor?.findRenderObject() as RenderBox?;
      final vertOrigin = vertBox != null
          ? vertBox.localToGlobal(Offset.zero, ancestor: overlay)
          : origin;
      final topY = below
          ? (vertOrigin.dy + (vertBox?.size.height ?? box.size.height) + 6)
          : (vertOrigin.dy - 6);
      final alignRight = origin.dx + box.size.width;
      final left = alignEnd
          ? (alignRight - minWidth)
              .clamp(12.0, overlay.size.width - minWidth - 12)
          : origin.dx.clamp(12.0, overlay.size.width - minWidth - 12);

      position = RelativeRect.fromLTRB(
        alignEnd ? overlay.size.width : left,
        topY,
        alignEnd ? (overlay.size.width - alignRight) : overlay.size.width,
        below ? overlay.size.height : 0,
      );
    }
  } else {
    position = const RelativeRect.fromLTRB(16, 80, 16, 80);
  }

  final effMin = (point != null && minWidth == 260) ? 156.0 : minWidth;
  final effMax = (point != null && maxWidth == 340) ? 220.0 : maxWidth;
  return showMenu<T>(
    context: context,
    position: position,
    color: bg,
    elevation: 0,
    surfaceTintColor: Colors.transparent,
    shape: appMenuShape,
    menuPadding: const EdgeInsets.symmetric(vertical: 4),
    constraints: BoxConstraints(minWidth: effMin, maxWidth: effMax),
    popUpAnimationStyle: AnimationStyle(
        duration: Motion.fast,
        reverseDuration: Motion.quick,
        curve: Motion.enter,
        reverseCurve: Motion.exit),
    items: items,
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
      out.add(const SizedBox(height: S.s8));
      prevRow = false;
      continue;
    }
    if (entry is! PopupMenuItem<T>) continue;
    if (!entry.enabled) {
      out.add(Padding(
        padding: EdgeInsets.only(top: out.isEmpty ? S.s4 : S.s16, bottom: S.s4),
        child: entry.child,
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

/// A slick, theme-styled toast rendered in the ROOT overlay — so it floats above
/// panels/dialogs instead of a SnackBar buried behind a modal backdrop. A new one
/// replaces the previous (no stacking). Use for transient feedback.
void toast(BuildContext context, String message, {bool danger = false}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _activeToast?.remove();
  _toastTimer?.cancel();
  final entry = OverlayEntry(
    builder: (ctx) => _toastSlot(ctx,
        IgnorePointer(child: _ToastCard(message: message, danger: danger))),
  );
  _activeToast = entry;
  overlay.insert(entry);
  _toastTimer = Timer(const Duration(milliseconds: 2600), () {
    if (_activeToast == entry) {
      entry.remove();
      _activeToast = null;
    }
  });
}

/// A toast with tappable action buttons (e.g. Open / Share after a download).
/// Unlike [toast] it isn't IgnorePointer'd, and it lingers longer so the actions
/// are reachable. Tapping an action dismisses it.
typedef ToastAction = ({String label, String icon, VoidCallback onTap});

void actionToast(BuildContext context, String message,
    {required List<ToastAction> actions}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _activeToast?.remove();
  _toastTimer?.cancel();
  late final OverlayEntry entry;
  void dismiss() {
    if (_activeToast == entry) {
      entry.remove();
      _activeToast = null;
      _toastTimer?.cancel();
    }
  }

  entry = OverlayEntry(
    builder: (ctx) => _toastSlot(
      ctx,
      Center(
        child: _ToastCard(
          message: message,
          danger: false,
          actions: actions
              .map((a) => (
                    label: a.label,
                    icon: a.icon,
                    onTap: () {
                      // Run the action first, then tear the toast down — removing the
                      // overlay entry mid-tap could otherwise swallow the action.
                      a.onTap();
                      dismiss();
                    }
                  ))
              .toList(),
        ),
      ),
    ),
  );
  _activeToast = entry;
  overlay.insert(entry);
  _toastTimer = Timer(const Duration(milliseconds: 6000), dismiss);
}

/// Where toasts sit: under the status bar on phones, so they never cover the
/// composer or the bottom bar; bottom-centre on desktop.
Widget _toastSlot(BuildContext ctx, Widget card) {
  final pad = MediaQuery.of(ctx).padding;
  return Positioned(
    left: 0,
    right: 0,
    top: kMobile ? pad.top + S.s12 : null,
    bottom: kMobile ? null : pad.bottom + 24,
    child: Center(child: card),
  );
}

class _ToastCard extends StatefulWidget {
  final String message;
  final bool danger;
  final List<ToastAction> actions;
  const _ToastCard(
      {required this.message, required this.danger, this.actions = const []});
  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard>
    with SingleTickerProviderStateMixin {
  /// Eager, in initState — a lazy `late final` makes `dispose` the first access
  /// when `build` never runs, constructing a controller on a dead element. Same
  /// defect class as `_StatusDotState`; fixed together so it cannot recur.
  late final AnimationController _c;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: Motion.base)..forward();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    final curve = CurvedAnimation(parent: _c, curve: Motion.enter);
    // Only the icon carries the tone; the message stays readable.
    final tone = widget.danger ? AppColors.danger : AppColors.ok;
    // Material ancestor: without it, text floating in the root Overlay falls back
    // to the debug default style (the yellow underline). It also gives clean ink.
    return Material(
      type: MaterialType.transparency,
      child: FadeTransition(
        opacity: curve,
        child: SlideTransition(
          position:
              Tween(begin: Offset(0, kMobile ? -0.25 : 0.25), end: Offset.zero)
                  .animate(curve),
          child: Container(
            constraints: const BoxConstraints(maxWidth: 420),
            margin: const EdgeInsets.symmetric(horizontal: M.gutter),
            padding: kMobile
                ? const EdgeInsets.fromLTRB(10, 10, 16, 10)
                : const EdgeInsets.fromLTRB(12, 10, 14, 10),
            decoration: BoxDecoration(
              color: kMobile ? AppColors.surface3 : AppColors.surface2,
              borderRadius: BorderRadius.circular(kMobile ? 18 : R.card),
              border: kMobile ? null : Border.all(color: AppColors.lineStrong),
              boxShadow: overlayShadow,
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (kMobile)
                Container(
                  width: 28,
                  height: 28,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: widget.danger ? AppColors.dangerBg : AppColors.okBg,
                    shape: BoxShape.circle,
                  ),
                  child: AppIcon(widget.danger ? 'alert-triangle' : 'check',
                      size: 14, color: tone),
                )
              else
                AppIcon(widget.danger ? 'alert-triangle' : 'check-circle',
                    size: 15, color: tone),
              SizedBox(width: kMobile ? 12 : 10),
              Flexible(
                child: Text(widget.message,
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis,
                    style: sans(kMobile ? 14 : 13,
                            height: kMobile ? 19 / 14 : 1.4,
                            color: AppColors.fg1)
                        .copyWith(decoration: TextDecoration.none)),
              ),
              for (final a in widget.actions) ...[
                const SizedBox(width: 8),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: a.onTap,
                  child: Padding(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                    child: Text(a.label,
                        style: sans(kMobile ? 14 : 13,
                                weight: W.label, color: AppColors.accent)
                            .copyWith(decoration: TextDecoration.none)),
                  ),
                ),
              ],
            ]),
          ),
        ),
      ),
    );
  }
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
