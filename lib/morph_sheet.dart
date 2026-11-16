import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import 'dialog_widgets.dart';
import 'platform.dart';
import 'theme.dart';
import 'widgets.dart';

/// Global rect of the widget behind [context], for [showMorphSheet]'s origin.
Rect? globalRectOf(BuildContext context) {
  final box = context.findRenderObject();
  if (box is! RenderBox || !box.attached || !box.hasSize) return null;
  return box.localToGlobal(Offset.zero) & box.size;
}

/// Rect of the chip tapped last in the composer, so a fork flow that starts
/// from the chip can pass it as `origin` without extra plumbing.
Rect? lastChipOrigin;

/// A bottom sheet that grows out of [origin] (the tapped chip's global rect)
/// and folds back into it on close. Without an origin it slides up. Desktop
/// uses the regular dialog sheet.
Future<T?> showMorphSheet<T>(
  BuildContext context, {
  required String title,
  String? subtitle,
  required WidgetBuilder builder,
  Rect? origin,
}) {
  if (!kMobile) {
    return showAppSheet<T>(context,
        title: title,
        subtitle: subtitle,
        maxWidth: 400,
        maxHeight: 560,
        child: Builder(builder: builder));
  }
  return Navigator.of(context, rootNavigator: true).push<T>(_MorphRoute<T>(
    title: title,
    subtitle: subtitle,
    builder: builder,
    origin: origin,
    instant: reduceMotion(context),
  ));
}

class _MorphRoute<T> extends PopupRoute<T> {
  _MorphRoute({
    required this.title,
    required this.subtitle,
    required this.builder,
    required this.origin,
    required this.instant,
  });

  final String title;
  final String? subtitle;
  final WidgetBuilder builder;
  final Rect? origin;
  final bool instant;

  @override
  Color? get barrierColor => AppColors.glassScrim;
  @override
  bool get barrierDismissible => true;
  @override
  String? get barrierLabel => 'Close';
  @override
  Duration get transitionDuration =>
      instant ? Duration.zero : const Duration(milliseconds: 250);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    final t = CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic);
    final mq = MediaQuery.of(context);
    final bottom = math.max(mq.viewInsets.bottom, mq.padding.bottom) + S.s8;
    return AnimatedBuilder(
      animation: t,
      builder: (_, child) => _MorphBox(
        t: t.value,
        origin: origin,
        bottomInset: bottom,
        topInset: mq.padding.top + S.s24,
        color: AppColors.surface2,
        child: child!,
      ),
      child: _SheetFrame(
          title: title,
          subtitle: subtitle,
          child: Builder(builder: builder),
          onClose: () => Navigator.of(context).maybePop()),
    );
  }
}

class _SheetFrame extends StatefulWidget {
  const _SheetFrame(
      {required this.title,
      required this.subtitle,
      required this.child,
      required this.onClose});
  final String title;
  final String? subtitle;
  final Widget child;
  final VoidCallback onClose;
  @override
  State<_SheetFrame> createState() => _SheetFrameState();
}

class _SheetFrameState extends State<_SheetFrame> {
  double _dy = 0;

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    return Transform.translate(
      offset: Offset(0, _dy),
      child: Material(
        color: AppColors.surface2,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: AppColors.border),
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onVerticalDragUpdate: (d) =>
                  setState(() => _dy = math.max(0, _dy + d.delta.dy)),
              onVerticalDragEnd: (d) {
                if (_dy > 90 || (d.primaryVelocity ?? 0) > 700) {
                  widget.onClose();
                } else {
                  setState(() => _dy = 0);
                }
              },
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Center(
                    child: Container(
                      margin: EdgeInsets.only(top: S.s8, bottom: S.s12),
                      width: 36,
                      height: 4,
                      decoration: BoxDecoration(
                          color: AppColors.border2,
                          borderRadius: BorderRadius.circular(2)),
                    ),
                  ),
                  Padding(
                    padding: EdgeInsets.symmetric(horizontal: S.s16),
                    child: Text(widget.title,
                        style: sans(17, weight: W.title, color: AppColors.fg1)),
                  ),
                  if (widget.subtitle != null)
                    Padding(
                      padding: EdgeInsets.fromLTRB(S.s16, S.s4, S.s16, 0),
                      child: Text(widget.subtitle!,
                          style: sans(13, height: 1.45, color: AppColors.fg3)),
                    ),
                  SizedBox(height: S.s12),
                ],
              ),
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: EdgeInsets.fromLTRB(S.s16, 0, S.s16, S.s16),
                child: widget.child,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MorphBox extends SingleChildRenderObjectWidget {
  const _MorphBox({
    required this.t,
    required this.origin,
    required this.bottomInset,
    required this.topInset,
    required this.color,
    required super.child,
  });
  final double t;
  final Rect? origin;
  final double bottomInset;
  final double topInset;
  final Color color;

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderMorph(t, origin, bottomInset, topInset, color);

  @override
  void updateRenderObject(BuildContext context, _RenderMorph r) {
    r
      ..t = t
      ..origin = origin
      ..bottomInset = bottomInset
      ..topInset = topInset
      ..color = color;
  }
}

class _RenderMorph extends RenderShiftedBox {
  _RenderMorph(this._t, this._origin, this._bottomInset, this._topInset,
      this._color)
      : super(null);

  double _t;
  Rect? _origin;
  double _bottomInset;
  double _topInset;
  Color _color;

  set t(double v) {
    if (v == _t) return;
    _t = v;
    markNeedsPaint();
  }

  set origin(Rect? v) {
    if (v == _origin) return;
    _origin = v;
    markNeedsPaint();
  }

  set bottomInset(double v) {
    if (v == _bottomInset) return;
    _bottomInset = v;
    markNeedsLayout();
  }

  set topInset(double v) {
    if (v == _topInset) return;
    _topInset = v;
    markNeedsLayout();
  }

  set color(Color v) {
    if (v == _color) return;
    _color = v;
    markNeedsPaint();
  }

  static const _margin = 8.0;

  @override
  void performLayout() {
    size = constraints.biggest;
    final c = child;
    if (c == null) return;
    final w = math.min(size.width - _margin * 2, 460.0);
    c.layout(
        BoxConstraints(
            minWidth: w,
            maxWidth: w,
            maxHeight: math.max(120, size.height - _bottomInset - _topInset)),
        parentUsesSize: true);
    final pd = c.parentData as BoxParentData;
    pd.offset = Offset((size.width - w) / 2, size.height - _bottomInset - c.size.height);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final c = child;
    if (c == null) return;
    final pd = c.parentData as BoxParentData;
    final dest = pd.offset & c.size;
    final o = _origin;
    if (o == null) {
      final slide = (1 - _t) * (c.size.height + _bottomInset);
      context.paintChild(c, offset + pd.offset + Offset(0, slide));
      return;
    }
    final rect = Rect.lerp(o, dest, _t)!.shift(offset);
    final rrect = RRect.fromRectAndRadius(
        rect, Radius.circular(lerpDouble(o.height / 2, 20, _t)!));
    final opacity = ((_t - .2) / .8).clamp(0.0, 1.0);
    context.canvas.drawRRect(rrect, Paint()..color = _color);
    context.pushClipRRect(needsCompositing, Offset.zero, rect.inflate(2), rrect,
        (ctx, off) {
      ctx.pushOpacity(off, (opacity * 255).round(),
          (ctx2, off2) => ctx2.paintChild(c, off2 + offset + pd.offset));
    });
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) {
    final c = child;
    if (c == null) return false;
    final pd = c.parentData as BoxParentData;
    return result.addWithPaintOffset(
      offset: pd.offset,
      position: position,
      hitTest: (r, p) => c.hitTest(r, position: p),
    );
  }
}
