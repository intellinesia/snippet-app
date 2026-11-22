import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'theme.dart';
import 'widgets.dart';

/// A menu entry that also carries the text the popover search matches.
class AppMenuItem<T> extends PopupMenuItem<T> {
  const AppMenuItem({
    super.key,
    super.value,
    super.enabled,
    super.height,
    super.padding,
    required super.child,
    required this.searchText,
  });

  final String searchText;
}

/// Section label inside a desktop popover.
class AppMenuHeading extends StatelessWidget {
  const AppMenuHeading(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) => Text(label,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: sans(12.5, weight: FontWeight.w500, color: AppColors.fg3));
}

/// The one desktop popover surface: flat solid fill, hairline, 4pt padding.
class AppPopoverSurface extends StatelessWidget {
  const AppPopoverSurface({super.key, required this.child, this.padding});
  final Widget child;
  final EdgeInsetsGeometry? padding;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(R.lg);
    return DecoratedBox(
      decoration: BoxDecoration(borderRadius: radius, boxShadow: overlayShadow),
      child: Material(
        color: AppColors.surface2,
        shape: RoundedRectangleBorder(
            borderRadius: radius,
            side: BorderSide(color: AppColors.panelOutline)),
        clipBehavior: Clip.antiAlias,
        child: Padding(padding: padding ?? EdgeInsets.all(S.s4), child: child),
      ),
    );
  }
}

/// Row body used by the desktop builders: icon, title, optional detail,
/// trailing meta and a check when selected.
class AppPopoverRowBody extends StatelessWidget {
  const AppPopoverRowBody({
    super.key,
    required this.label,
    this.icon,
    this.leading,
    this.detail,
    this.trailing,
    this.trailingWidget,
    this.danger = false,
    this.selected = false,
    this.disabled = false,
  });

  final String label;
  final String? icon;
  final Widget? leading;
  final String? detail;
  final String? trailing;
  final Widget? trailingWidget;
  final bool danger, selected, disabled;

  @override
  Widget build(BuildContext context) {
    final color = disabled
        ? AppColors.fg4
        : danger
            ? AppColors.danger
            : AppColors.fg1;
    final lead = leading ??
        (icon == null
            ? null
            : AppIcon(icon!,
                size: 16, color: danger ? AppColors.danger : AppColors.fg3));
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: S.s8),
      child: Row(children: [
        if (lead != null) ...[
          SizedBox(width: 16, child: Center(child: lead)),
          SizedBox(width: S.of(10)),
        ],
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13,
                      weight: selected ? FontWeight.w500 : FontWeight.w400,
                      color: color)),
              if (detail != null)
                Text(detail!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(11.5,
                        weight: FontWeight.w400, color: AppColors.fg4)),
            ],
          ),
        ),
        if (trailingWidget != null) ...[
          SizedBox(width: S.s8),
          trailingWidget!,
        ],
        if (trailing != null) ...[
          SizedBox(width: S.s8),
          Text(trailing!,
              maxLines: 1,
              style: sans(12, weight: FontWeight.w400, color: AppColors.fg4)),
        ],
        if (selected) ...[
          SizedBox(width: S.s8),
          AppIcon('check', size: 14, color: AppColors.fg1),
        ],
      ]),
    );
  }
}

/// Where a popover sits relative to what opened it.
class AppPopoverAnchor {
  const AppPopoverAnchor({
    required this.control,
    required this.vertical,
    this.below = false,
    this.alignEnd = false,
  });

  /// Horizontal reference, in overlay coordinates.
  final Rect control;

  /// Vertical reference (the control, or the composer card above it).
  final Rect vertical;
  final bool below;
  final bool alignEnd;
}

/// Where a popover of [child] size goes in a [size] overlay: under (or above)
/// the anchor, flipping when the preferred side lacks room, clamped on screen.
Offset popoverPosition(AppPopoverAnchor anchor, Size size, Size child) {
  const gap = 6.0, edge = 8.0;
  final spaceBelow = size.height - anchor.vertical.bottom - gap - edge;
  final spaceAbove = anchor.vertical.top - gap - edge;
  final below = anchor.below
      ? (spaceBelow >= child.height || spaceBelow >= spaceAbove)
      : !(spaceAbove >= child.height || spaceAbove >= spaceBelow);
  final y = below
      ? anchor.vertical.bottom + gap
      : anchor.vertical.top - gap - child.height;
  final x = anchor.alignEnd
      ? anchor.control.right - child.width
      : anchor.control.left;
  return Offset(x.clamp(edge, size.width - child.width - edge),
      y.clamp(edge, size.height - child.height - edge));
}

class _PopoverLayout extends SingleChildLayoutDelegate {
  const _PopoverLayout(this.anchor, this.minWidth, this.maxWidth);
  final AppPopoverAnchor anchor;
  final double minWidth, maxWidth;

  static const _gap = 6.0;
  static const _edge = 8.0;

  double _spaceBelow(Size s) =>
      s.height - anchor.vertical.bottom - _gap - _edge;
  double _spaceAbove(Size s) => anchor.vertical.top - _gap - _edge;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints c) {
    final room = _spaceBelow(c.biggest) > _spaceAbove(c.biggest)
        ? _spaceBelow(c.biggest)
        : _spaceAbove(c.biggest);
    final preferred =
        anchor.below ? _spaceBelow(c.biggest) : _spaceAbove(c.biggest);
    final h = (preferred >= 160 ? preferred : room).clamp(80.0, 440.0);
    return BoxConstraints(
        minWidth: minWidth.clamp(0, c.maxWidth - 2 * _edge),
        maxWidth: maxWidth.clamp(0, c.maxWidth - 2 * _edge),
        maxHeight: h);
  }

  @override
  Offset getPositionForChild(Size size, Size child) =>
      popoverPosition(anchor, size, child);

  @override
  bool shouldRelayout(_PopoverLayout old) =>
      anchor != old.anchor || minWidth != old.minWidth;
}

Future<T?> showAppPopoverMenu<T>(
  BuildContext context, {
  required List<PopupMenuEntry<T>> items,
  required AppPopoverAnchor anchor,
  double minWidth = 280,
  double maxWidth = 360,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Dismiss',
    barrierColor: Colors.transparent,
    transitionDuration: Motion.quick,
    pageBuilder: (ctx, _, __) => CustomSingleChildLayout(
      delegate: _PopoverLayout(anchor, minWidth, maxWidth),
      child: IntrinsicWidth(child: _PopoverMenu<T>(items: items)),
    ),
    transitionBuilder: (_, animation, __, child) {
      final curve = CurvedAnimation(parent: animation, curve: Motion.enter);
      return FadeTransition(
        opacity: curve,
        child: ScaleTransition(
          scale: Tween(begin: 0.97, end: 1.0).animate(curve),
          alignment: anchor.below
              ? (anchor.alignEnd ? Alignment.topRight : Alignment.topLeft)
              : (anchor.alignEnd
                  ? Alignment.bottomRight
                  : Alignment.bottomLeft),
          child: child,
        ),
      );
    },
  );
}

/// Rows the search and keyboard navigation operate on.
bool _selectable(PopupMenuEntry e) => e is PopupMenuItem && e.enabled;

String _searchText(PopupMenuItem e) =>
    e is AppMenuItem ? e.searchText.toLowerCase() : '';

class _PopoverMenu<T> extends StatefulWidget {
  const _PopoverMenu({required this.items});
  final List<PopupMenuEntry<T>> items;

  @override
  State<_PopoverMenu<T>> createState() => _PopoverMenuState<T>();
}

class _PopoverMenuState<T> extends State<_PopoverMenu<T>> {
  static const _searchFrom = 8;

  late final FocusNode _focus = FocusNode(onKeyEvent: _onKey);
  final _search = TextEditingController();
  final _keys = <int, GlobalKey>{};
  int _active = -1;

  bool get _hasSearch => widget.items.where(_selectable).length >= _searchFrom;

  List<PopupMenuEntry<T>> get _shown {
    final q = _search.text.trim().toLowerCase();
    if (q.isEmpty) return widget.items;
    return [
      for (final e in widget.items)
        if (e is PopupMenuItem<T> && e.enabled && _searchText(e).contains(q)) e
    ];
  }

  List<int> get _rows {
    final shown = _shown;
    return [
      for (var i = 0; i < shown.length; i++)
        if (_selectable(shown[i])) i
    ];
  }

  @override
  void initState() {
    super.initState();
    _search.addListener(
        () => setState(() => _active = _rows.isEmpty ? -1 : _rows.first));
  }

  @override
  void dispose() {
    _focus.dispose();
    _search.dispose();
    super.dispose();
  }

  void _move(int delta) {
    final rows = _rows;
    if (rows.isEmpty) return;
    final at = rows.indexOf(_active);
    final next =
        at < 0 ? (delta > 0 ? 0 : rows.length - 1) : (at + delta) % rows.length;
    _setActive(rows[next < 0 ? next + rows.length : next]);
  }

  void _setActive(int i) {
    setState(() => _active = i);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final ctx = _keys[i]?.currentContext;
      if (ctx != null) Scrollable.ensureVisible(ctx, alignment: 0.5);
    });
  }

  void _pick(int i) {
    final e = _shown[i] as PopupMenuItem<T>;
    e.onTap?.call();
    Navigator.pop(context, e.value);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final k = event.logicalKey;
    if (k == LogicalKeyboardKey.arrowDown) {
      _move(1);
    } else if (k == LogicalKeyboardKey.arrowUp) {
      _move(-1);
    } else if (k == LogicalKeyboardKey.home) {
      final r = _rows;
      if (r.isNotEmpty) _setActive(r.first);
    } else if (k == LogicalKeyboardKey.end) {
      final r = _rows;
      if (r.isNotEmpty) _setActive(r.last);
    } else if (k == LogicalKeyboardKey.enter ||
        k == LogicalKeyboardKey.numpadEnter) {
      if (_active >= 0 && _active < _shown.length) _pick(_active);
    } else if (k == LogicalKeyboardKey.escape) {
      if (_search.text.isNotEmpty) {
        _search.clear();
      } else {
        Navigator.pop(context);
      }
    } else {
      return KeyEventResult.ignored;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final shown = _shown;
    if (widget.items
        .any((e) => e is! PopupMenuItem<T> && e is! PopupMenuDivider)) {
      // Custom entries (reaction strip) draw their own surface.
      return Material(
          type: MaterialType.transparency,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            for (final e in widget.items) e,
          ]));
    }
    final children = <Widget>[];
    var firstGroup = true;
    for (var i = 0; i < shown.length; i++) {
      final e = shown[i];
      if (e is PopupMenuDivider) {
        children.add(Container(
            height: 1,
            margin: EdgeInsets.symmetric(vertical: S.s4),
            color: AppColors.line));
        continue;
      }
      if (e is! PopupMenuItem<T>) continue;
      if (!e.enabled && e.child is AppMenuHeading) {
        children.add(Padding(
          padding: EdgeInsets.fromLTRB(
              S.s8, firstGroup ? S.s4 : S.s8 + S.s2, S.s8, S.s4),
          child: e.child,
        ));
        firstGroup = false;
        continue;
      }
      firstGroup = false;
      final height = e.height < 30 ? 30.0 : e.height;
      if (!e.enabled) {
        children.add(ConstrainedBox(
            constraints: BoxConstraints(minHeight: height), child: e.child));
        continue;
      }
      final active = i == _active;
      children.add(KeyedSubtree(
        key: _keys.putIfAbsent(i, GlobalKey.new),
        child: MouseRegion(
          onEnter: (_) => setState(() => _active = i),
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => _pick(i),
            child: Container(
              constraints: BoxConstraints(minHeight: height),
              alignment: Alignment.centerLeft,
              decoration: BoxDecoration(
                color: active
                    ? AppColors.fg1.withValues(alpha: 0.07)
                    : Colors.transparent,
                borderRadius: BorderRadius.circular(R.md),
              ),
              child: e.child,
            ),
          ),
        ),
      ));
    }
    return AppPopoverSurface(
      child: Focus(
        focusNode: _hasSearch ? null : _focus,
        autofocus: !_hasSearch,
        onKeyEvent: _hasSearch ? _onKey : null,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (_hasSearch)
              Padding(
                padding: EdgeInsets.all(S.s4),
                child: SizedBox(
                  height: 28,
                  child: TextField(
                    controller: _search,
                    autofocus: true,
                    style:
                        sans(13, weight: FontWeight.w400, color: AppColors.fg1),
                    cursorColor: AppColors.fg1,
                    textAlignVertical: TextAlignVertical.center,
                    decoration: InputDecoration(
                      isDense: true,
                      filled: true,
                      fillColor: AppColors.surface1,
                      hintText: 'Search',
                      hintStyle: sans(13,
                          weight: FontWeight.w400, color: AppColors.fg4),
                      prefixIcon: Padding(
                        padding: EdgeInsets.symmetric(horizontal: S.s8),
                        child:
                            AppIcon('search', size: 14, color: AppColors.fg4),
                      ),
                      prefixIconConstraints:
                          const BoxConstraints(minWidth: 0, minHeight: 0),
                      contentPadding: EdgeInsets.zero,
                      enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(R.sm),
                          borderSide: BorderSide(color: AppColors.line)),
                      focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(R.sm),
                          borderSide: BorderSide(color: AppColors.border2)),
                    ),
                  ),
                ),
              ),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: children),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
