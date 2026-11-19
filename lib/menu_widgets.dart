import 'dart:async';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import 'platform.dart';
import 'glass.dart';
import 'theme.dart';
import 'widgets.dart';

OverlayEntry? _activeToast;

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
  final color = !enabled
      ? AppColors.fg4
      : danger
          ? AppColors.danger
          : AppColors.fg1;
  return PopupMenuItem<T>(
    value: value,
    enabled: enabled,
    height: height,
    padding: EdgeInsets.symmetric(horizontal: S.of(10)),
    child: Row(children: [
      if (icon != null) ...[
        AppIcon(icon, size: 14, color: danger ? AppColors.danger : AppColors.fg3),
        SizedBox(width: S.of(9)),
      ],
      Expanded(
        child: Text(label,
            maxLines: 1, overflow: TextOverflow.ellipsis, style: TS.ui(color)),
      ),
      if (detail != null) Text(detail, style: TS.meta()),
      if (selected) ...[
        SizedBox(width: S.s8),
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
  return PopupMenuItem<T>(
    value: value,
    enabled: enabled,
    height: height ?? (description != null ? 44 : 34),
    padding: EdgeInsets.symmetric(horizontal: S.s2),
    child: Container(
      padding: EdgeInsets.symmetric(horizontal: S.s8, vertical: S.of(5)),
      decoration: BoxDecoration(
        color: selected ? AppColors.surface2 : Colors.transparent,
        borderRadius: BorderRadius.circular(R.sm),
      ),
      child: Row(children: [
        leading ??
            AppIcon(icon,
                size: 15, color: selected ? AppColors.accent : AppColors.fg3),
        SizedBox(width: S.of(10)),
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
                SizedBox(height: S.of(1)),
                Text(description,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TS.caption()),
              ],
            ],
          ),
        ),
        if (trailingWidget != null) ...[
          SizedBox(width: S.s8),
          trailingWidget,
        ],
        if (trailing != null) ...[
          SizedBox(width: S.s8),
          Text(trailing, style: TS.caption()),
        ],
        if (selected) ...[
          SizedBox(width: S.s8),
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
          : EdgeInsets.fromLTRB(S.of(10), S.s8, S.of(10), S.s2),
      child: _MenuHeading(label),
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
                      style: TS.meta(disabled ? AppColors.fg4 : null)),
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
    final glass = kMobile && Glass.effectiveEnabled;
    final body = DecoratedBox(
      decoration: BoxDecoration(
        color: glass ? fill.withValues(alpha: 0.72) : fill,
        border: glass
            ? Border(
                top: BorderSide(color: AppColors.fg1.withValues(alpha: 0.08)))
            : null,
      ),
      child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [const SheetGrabHandle(), Flexible(child: child)]),
    );
    return ClipRRect(
      borderRadius: BorderRadius.vertical(top: Radius.circular(R.sheetTop)),
      child: glass
          ? BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 28, sigmaY: 28), child: body)
          : body,
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
  final bg = color ?? AppColors.surface1;

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
    shape: shape ?? appMenuShape,
    menuPadding: EdgeInsets.symmetric(vertical: S.s4),
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

/// A theme-styled toast rendered in the ROOT overlay, so it floats above
/// panels and dialogs. A new one replaces the previous (no stacking). Normal
/// toasts leave after ~3s; danger toasts stay until tapped, swiped away or
/// their action is taken (capped at 8s when there is no action).
void toast(BuildContext context, String message,
    {bool danger = false, String? actionLabel, VoidCallback? onAction}) {
  final overlay = Overlay.maybeOf(context, rootOverlay: true);
  if (overlay == null) return;
  _activeToast?.remove();
  final hold = danger
      ? (actionLabel != null ? null : const Duration(seconds: 8))
      : const Duration(seconds: 3);
  final closing = ValueNotifier<bool>(false);
  late final OverlayEntry entry;
  void remove() {
    if (_activeToast == entry) {
      entry.remove();
      _activeToast = null;
    }
  }

  entry = OverlayEntry(
    builder: (ctx) => _toastSlot(
        ctx,
        _ToastCard(
          message: message,
          danger: danger,
          actionLabel: actionLabel,
          onAction: onAction,
          closing: closing,
          hold: hold,
          onGone: remove,
        )),
  );
  _activeToast = entry;
  overlay.insert(entry);
}

/// Phones: rises from just above the composer or keyboard. Desktop: top-right.
Widget _toastSlot(BuildContext ctx, Widget card) {
  final mq = MediaQuery.of(ctx);
  if (kMobile) {
    final base = mq.viewInsets.bottom > mq.padding.bottom
        ? mq.viewInsets.bottom
        : mq.padding.bottom;
    return Positioned(
      left: S.s12,
      right: S.s12,
      bottom: base + 112,
      child: Align(alignment: Alignment.bottomCenter, child: card),
    );
  }
  return Positioned(
    left: S.s12,
    right: S.s12,
    top: mq.padding.top + 44 + S.s8,
    child: Align(alignment: Alignment.topRight, child: card),
  );
}

class _ToastCard extends StatefulWidget {
  final String message;
  final bool danger;
  final String? actionLabel;
  final VoidCallback? onAction;
  final ValueNotifier<bool> closing;
  final Duration? hold;
  final VoidCallback onGone;
  const _ToastCard({
    this.hold,
    required this.message,
    required this.danger,
    required this.closing,
    required this.onGone,
    this.actionLabel,
    this.onAction,
  });
  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard>
    with SingleTickerProviderStateMixin {
  /// Eager, in initState: a lazy `late final` makes `dispose` the first access
  /// when `build` never runs, constructing a controller on a dead element.
  late final AnimationController _c;
  // Owned by the card so it dies with the overlay instead of outliving it.
  Timer? _hold;
  double _drag = 0;
  bool _leaving = false;

  @override
  void initState() {
    super.initState();
    _c = AnimationController(
        vsync: this,
        duration: const Duration(milliseconds: 200),
        reverseDuration: const Duration(milliseconds: 200))
      ..forward();
    widget.closing.addListener(_onClosing);
    final hold = widget.hold;
    if (hold != null) _hold = Timer(hold, _dismiss);
  }

  @override
  void dispose() {
    _hold?.cancel();
    widget.closing.removeListener(_onClosing);
    _c.dispose();
    super.dispose();
  }

  void _onClosing() {
    if (widget.closing.value) _dismiss();
  }

  Future<void> _dismiss() async {
    if (_leaving) return;
    _leaving = true;
    if (!mounted) return;
    if (!reduceMotion(context)) {
      try {
        await _c.reverse().orCancel;
      } on TickerCanceled {
        // Disposed mid-flight; the entry is already gone.
      }
    }
    widget.onGone();
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context); // Rebuild on theme change
    if (reduceMotion(context)) _c.value = 1;
    final curve = CurvedAnimation(
        parent: _c,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic);
    final tone = widget.danger ? AppColors.danger : AppColors.ok;
    final toneBg = widget.danger ? AppColors.dangerBg : AppColors.okBg;
    final hasAction = widget.actionLabel != null;
    final dir = kMobile ? 16.0 : -8.0;
    // Material ancestor: without it, overlay text gets the debug style.
    return Material(
      type: MaterialType.transparency,
      child: FadeTransition(
        opacity: curve,
        child: AnimatedBuilder(
          animation: curve,
          builder: (_, child) => Transform.translate(
              offset: Offset(0, (1 - curve.value) * dir + _drag), child: child),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: hasAction ? null : _dismiss,
            onVerticalDragUpdate: (d) => setState(
                () => _drag = (_drag + d.delta.dy).clamp(0.0, double.infinity)),
            onVerticalDragEnd: (d) {
              if (_drag > 24 || (d.primaryVelocity ?? 0) > 300) {
                _dismiss();
              } else {
                setState(() => _drag = 0);
              }
            },
            child: Container(
              constraints: BoxConstraints(
                  maxWidth: kMobile ? 360 : 420, minHeight: kMobile ? 44 : 36),
              padding: EdgeInsets.only(
                  left: S.s12,
                  right: hasAction ? S.s4 : S.s12,
                  top: S.s4,
                  bottom: S.s4),
              decoration: BoxDecoration(
                color: AppColors.surface3,
                border: Border.all(color: AppColors.border2),
                borderRadius: BorderRadius.circular(14),
                boxShadow: overlayShadow,
              ),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                Container(
                  width: 20,
                  height: 20,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                      color: toneBg, borderRadius: BorderRadius.circular(6)),
                  child: widget.danger
                      ? Text('!',
                          style: sans(12, weight: FontWeight.w700, color: tone)
                              .copyWith(decoration: TextDecoration.none))
                      : AppIcon('check', size: 12, color: tone),
                ),
                SizedBox(width: S.s12),
                Flexible(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: S.s8),
                    child: Text(widget.message,
                        maxLines: 4,
                        overflow: TextOverflow.ellipsis,
                        style: sans(kMobile ? 14 : 13,
                                weight: W.label,
                                height: 1.35,
                                color: AppColors.fg1)
                            .copyWith(decoration: TextDecoration.none)),
                  ),
                ),
                if (hasAction)
                  GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: () {
                      widget.onAction?.call();
                      _dismiss();
                    },
                    child: Container(
                      constraints: BoxConstraints(
                          minWidth: kMobile ? 44 : 32,
                          minHeight: kMobile ? 44 : 32),
                      alignment: Alignment.center,
                      padding: EdgeInsets.symmetric(horizontal: S.s12),
                      child: Text(widget.actionLabel!,
                          style: sans(kMobile ? 14 : 13,
                                  weight: W.label,
                                  color: widget.danger
                                      ? AppColors.danger
                                      : AppColors.accent)
                              .copyWith(decoration: TextDecoration.none)),
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
