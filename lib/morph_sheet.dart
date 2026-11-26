import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/gestures.dart' show Drag;
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';

import 'dialog_widgets.dart';
import 'gesture_physics.dart';
import 'platform.dart';
import 'theme.dart';
import 'widgets.dart';

/// Named sheet sizes (spec DL-03): small fits content up to 40 percent, medium
/// is 60 percent, large reaches safe-area top plus 16; auto fits up to 85.
enum SheetSize { auto, small, medium, large }

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
    origin: null, // spec G: no shared-element morph
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
      instant ? Duration.zero : const Duration(milliseconds: 200);

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
      Animation<double> secondaryAnimation) {
    final t = CurvedAnimation(
        parent: animation, curve: Curves.easeOut, reverseCurve: Curves.easeOut);
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
        color: AppColors.surface1,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
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
  RenderObject createRenderObject(BuildContext context) =>
      _RenderMorph(t, origin, bottomInset, topInset, color);

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
  _RenderMorph(
      this._t, this._origin, this._bottomInset, this._topInset, this._color)
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
    pd.offset = Offset(
        (size.width - w) / 2, size.height - _bottomInset - c.size.height);
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

/// Pushes an [AppSheetRoute] on the nearest navigator, carrying the caller's
/// themes the way showModalBottomSheet does.
Future<T?> showSpringSheet<T>(
  BuildContext context, {
  required Widget Function(BuildContext context, ScrollController scroll)
      builder,
  SheetSize size = SheetSize.auto,
  double? medium,
  double largeGap = 16,
  SheetDetents? detents,
}) {
  final nav = Navigator.of(context);
  return nav.push<T>(AppSheetRoute<T>(
    size: size,
    medium: medium,
    largeGap: largeGap,
    detents: detents,
    builder: builder,
    capturedThemes: InheritedTheme.capture(from: context, to: nav.context),
    instant: reduceMotion(context),
  ));
}

/// Phone bottom sheet on springs. Opens at a half detent (52% of the screen)
/// when the content is taller than that, else at its own height; drags from
/// anywhere, scrolls only at full, rubber-bands past the top, and scales the
/// page behind back to 0.94 with rounded corners.
class AppSheetRoute<T> extends PopupRoute<T> {
  AppSheetRoute({
    this.size = SheetSize.auto,
    this.medium,
    this.largeGap = 16,
    this.detents,
    required this.builder,
    required this.capturedThemes,
    this.instant = false,
    super.settings,
  });

  /// Hand the [ScrollController] to the sheet's main scroller so a drag
  /// passes between the sheet and its content.
  final Widget Function(BuildContext context, ScrollController scroll) builder;
  final CapturedThemes capturedThemes;
  final bool instant;
  final SheetSize size;

  /// With [SheetSize.large]: also rest at this fraction of the screen
  /// height, opening there (two detents: medium and large).
  final double? medium;

  /// Gap between the top safe area and a large sheet's top edge.
  final double largeGap;
  final SheetDetents? detents;

  static const SpringDescription presentSpring =
      SpringDescription(mass: 1, stiffness: 300, damping: 32);
  static const SpringDescription dismissSpring =
      SpringDescription(mass: 1, stiffness: 340, damping: 38);
  static const double halfDetent = 0.52;
  static const double fullCap = 0.85;
  static const double behindScale = 0.94;
  static const double behindRadius = 18;
  static const double behindDrop = 10;
  static const double scrim = 0.58;
  static const double rubberDim = 120;
  static const double projectSeconds = 0.18;
  static const double closeFling = 1100;

  final ValueNotifier<double> _extra = ValueNotifier<double>(0);
  _SheetBodyState? _body;

  AnimationController? get _sheetController => controller;

  @override
  Color? get barrierColor => AppColors.scrim;
  @override
  bool get barrierDismissible => true;
  @override
  String? get barrierLabel => 'Close';
  @override
  Duration get transitionDuration =>
      instant ? Duration.zero : const Duration(milliseconds: 200);
  @override
  Duration get reverseTransitionDuration =>
      instant ? Duration.zero : const Duration(milliseconds: 200);

  @override
  bool didPop(T? result) {
    _body?._settleExtra(0, 0);
    return super.didPop(result);
  }

  @override
  void dispose() {
    _extra.dispose();
    super.dispose();
  }

  @override
  DelegatedTransitionBuilder? get delegatedTransition => _behind;

  static Widget? _behind(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    bool allowSnapshotting,
    Widget? child,
  ) =>
      child; // spec G: the page behind stays still

  @override
  Widget buildPage(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation) =>
      capturedThemes.wrap(MediaQuery.removePadding(
        context: context,
        removeTop: true,
        child: _SheetBody<T>(
            route: this, topPad: MediaQuery.paddingOf(context).top),
      ));

  @override
  Widget buildTransitions(BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation, Widget child) =>
      child;
}

/// Drives a two-detent [AppSheetRoute]: reports whether it rests at large
/// and moves it between medium and large.
class SheetDetents extends ChangeNotifier {
  _SheetBodyState? _body;
  bool _large = false;
  bool _disposed = false;

  bool get large => _large;

  @override
  void dispose() {
    _disposed = true;
    _body = null;
    super.dispose();
  }

  void _set(bool v) {
    // The route's exit animation can outlive the owner's dispose.
    if (_disposed || v == _large) return;
    _large = v;
    notifyListeners();
  }

  void expand() => _body?._settleExtra(_body!._maxExtra, 0);
  void collapse() => _body?._settleExtra(0, 0);
}

class _SheetBody<T> extends StatefulWidget {
  const _SheetBody({required this.route, required this.topPad});
  final AppSheetRoute<T> route;
  final double topPad;

  @override
  State<_SheetBody<T>> createState() => _SheetBodyState<T>();
}

class _SheetBodyState<T> extends State<_SheetBody<T>>
    with SingleTickerProviderStateMixin {
  late final AnimationController _extraC;
  late final _SheetScrollController _scroll;
  late final Animation<double> _curved = CurvedAnimation(
      parent: _route.animation!,
      curve: Curves.easeOut,
      reverseCurve: Curves.easeOut);

  // Laid-out heights: the lowest detent and the full height.
  double _base = 0;
  double _full = 0;
  double _over = 0;
  int _startDetent = 1;
  bool _sheetMoved = false;

  AppSheetRoute<T> get _route => widget.route;
  AnimationController get _c => _route._sheetController!;
  double get _maxExtra => math.max(0, _full - _base);
  bool get _hasHalf => _maxExtra > 0;

  @override
  void initState() {
    super.initState();
    // Eager: dispose must not be the first touch of a lazy ticker.
    _extraC = AnimationController.unbounded(vsync: this)
      ..addListener(_syncExtra);
    _scroll = _SheetScrollController(this);
    _route._body = this;
    _route.detents?._body = this;
  }

  @override
  void dispose() {
    if (_route._body == this) _route._body = null;
    if (_route.detents?._body == this) _route.detents?._body = null;
    _extraC.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _syncExtra() {
    _route._extra.value = _extraC.value;
    _route.detents?._set(_hasHalf && _extraC.value >= _maxExtra - 0.5);
  }

  void _metrics(double base, double full) {
    _base = base;
    _full = full;
  }

  double get _visible => _c.value * _base + _extraC.value;

  int _detentOf(double visible) {
    if (!_hasHalf) return 1;
    return (visible - _base).abs() <= (visible - _full).abs() ? 1 : 2;
  }

  bool get _closing =>
      !_route.isCurrent || _c.status == AnimationStatus.reverse;

  void dragStart() {
    if (_closing) return;
    _c.stop();
    _extraC.stop();
    _over = 0;
    _sheetMoved = false;
    _startDetent = _detentOf(_visible);
  }

  /// [delta] is finger travel, positive downward. Returns what the content
  /// scroller should take.
  double consume(double delta, ScrollPosition? p) {
    if (_closing || _base <= 0) return 0;
    final canScroll = p != null && p.maxScrollExtent > p.minScrollExtent;
    if (delta < 0) {
      var up = -delta;
      if (_c.value < 1) {
        final dc = math.min(up / _base, 1 - _c.value);
        _c.value += dc;
        up -= dc * _base;
        _sheetMoved = true;
      }
      final room = _maxExtra - _extraC.value;
      if (up > 0 && room > 0 && _over == 0) {
        final de = math.min(up, room);
        _extraC.value += de;
        up -= de;
        _sheetMoved = true;
      }
      if (up <= 0) return 0;
      if (canScroll && _over == 0) return -up;
      _over += up;
      _extraC.value = _maxExtra + rubberBand(_over, AppSheetRoute.rubberDim);
      _sheetMoved = true;
      return 0;
    }
    var down = delta;
    var content = 0.0;
    if (_over > 0) {
      final take = math.min(down, _over);
      _over -= take;
      down -= take;
      _extraC.value = _maxExtra + rubberBand(_over, AppSheetRoute.rubberDim);
    }
    if (down > 0 && p != null && p.pixels > p.minScrollExtent) {
      content = math.min(down, p.pixels - p.minScrollExtent);
      down -= content;
    }
    if (down > 0 && _extraC.value > 0) {
      final de = math.min(down, _extraC.value);
      _extraC.value -= de;
      down -= de;
      _sheetMoved = true;
    }
    if (down > 0) {
      _c.value = math.max(0, _c.value - down / _base);
      _sheetMoved = true;
    }
    return content;
  }

  /// [velocity] is finger speed in px/s, positive downward. Returns false when
  /// the content should fling instead.
  bool dragEnd(double velocity) {
    if (_closing || _base <= 0) return true;
    if (!_sheetMoved) return false;
    _over = 0;
    final projected = _visible - velocity * AppSheetRoute.projectSeconds;
    final stops = <double>[0, _base, if (_hasHalf) _full];
    var to = stops.reduce(
        (a, b) => (b - projected).abs() < (a - projected).abs() ? b : a);
    if (velocity > AppSheetRoute.closeFling) to = 0;
    if (to == 0) {
      Navigator.of(context).pop();
      return true;
    }
    final detent = to == _base ? 1 : 2;
    if (_hasHalf && detent != _startDetent) HapticFeedback.selectionClick();
    if (_c.value < 1) _spring(_c, 1, -velocity / _base);
    _settleExtra(to - _base, -velocity);
    return true;
  }

  void _settleExtra(double to, double velocity) {
    if (!mounted) return;
    _spring(_extraC, to, velocity);
  }

  void _spring(AnimationController c, double to, double v) {
    if (_route.instant || reduceMotion(context)) {
      c.value = to;
    } else {
      c.animateTo(to,
          duration: const Duration(milliseconds: 200), curve: Curves.easeOut);
    }
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final keyboard = media.viewInsets.bottom;
    return Padding(
      padding: EdgeInsets.only(bottom: keyboard),
      child: _SpringSheetFrame(
        progress: _curved,
        size: _route.size,
        topInset: widget.topPad,
        medium: _route.medium,
        largeGap: _route.largeGap,
        extra: _route._extra,
        screenHeight: media.size.height - keyboard,
        onMetrics: _metrics,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onVerticalDragStart: (_) => dragStart(),
          onVerticalDragUpdate: (d) => consume(d.primaryDelta ?? 0, null),
          onVerticalDragEnd: (d) => dragEnd(d.primaryVelocity ?? 0),
          onVerticalDragCancel: () => dragEnd(0),
          child: _route.builder(context, _scroll),
        ),
      ),
    );
  }
}

/// Lays the sheet out at its natural height (capped at 92% of the screen),
/// derives the detents from it, and places it by the route progress plus the
/// lift above the lowest detent.
class _SpringSheetFrame extends SingleChildRenderObjectWidget {
  const _SpringSheetFrame({
    required this.progress,
    required this.extra,
    required this.screenHeight,
    required this.onMetrics,
    required this.size,
    required this.topInset,
    this.medium,
    this.largeGap = 16,
    required super.child,
  });

  final SheetSize size;
  final double topInset;
  final double? medium;
  final double largeGap;

  final Animation<double> progress;
  final ValueListenable<double> extra;
  final double screenHeight;
  final void Function(double base, double full) onMetrics;

  @override
  _RenderSpringSheetFrame createRenderObject(BuildContext context) =>
      _RenderSpringSheetFrame(progress, extra, screenHeight, onMetrics, size,
          topInset, medium, largeGap);

  @override
  void updateRenderObject(BuildContext context, _RenderSpringSheetFrame r) {
    r
      ..progress = progress
      ..extra = extra
      ..screenHeight = screenHeight
      ..sheetSize = size
      ..topInset = topInset
      ..medium = medium
      ..largeGap = largeGap
      ..onMetrics = onMetrics;
  }
}

class _RenderSpringSheetFrame extends RenderShiftedBox {
  _RenderSpringSheetFrame(this._progress, this._extra, this._screenHeight,
      this.onMetrics, this.sheetSize, this.topInset, this.medium,
      this.largeGap)
      : super(null);

  SheetSize sheetSize;
  double topInset;
  double? medium;
  double largeGap;

  Animation<double> _progress;
  ValueListenable<double> _extra;
  double _screenHeight;
  void Function(double base, double full) onMetrics;

  set progress(Animation<double> v) {
    if (v == _progress) return;
    if (attached) _progress.removeListener(markNeedsLayout);
    _progress = v;
    if (attached) _progress.addListener(markNeedsLayout);
    markNeedsLayout();
  }

  set extra(ValueListenable<double> v) {
    if (v == _extra) return;
    if (attached) _extra.removeListener(markNeedsLayout);
    _extra = v;
    if (attached) _extra.addListener(markNeedsLayout);
    markNeedsLayout();
  }

  set screenHeight(double v) {
    if (v == _screenHeight) return;
    _screenHeight = v;
    markNeedsLayout();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _progress.addListener(markNeedsLayout);
    _extra.addListener(markNeedsLayout);
  }

  @override
  void detach() {
    _progress.removeListener(markNeedsLayout);
    _extra.removeListener(markNeedsLayout);
    super.detach();
  }

  @override
  void performLayout() {
    size = constraints.biggest;
    final c = child;
    if (c == null) return;
    final screen = math.min(size.height, _screenHeight);
    final cap = switch (sheetSize) {
      SheetSize.small => screen * 0.40,
      SheetSize.medium => screen * 0.60,
      SheetSize.large => screen - (topInset + largeGap),
      SheetSize.auto => screen * AppSheetRoute.fullCap,
    };
    final fixed = sheetSize == SheetSize.medium || sheetSize == SheetSize.large;
    c.layout(
        BoxConstraints(
            minWidth: size.width,
            maxWidth: size.width,
            minHeight: fixed ? cap : 0,
            maxHeight: cap),
        parentUsesSize: true);
    final full = c.size.height;
    // One detent (the named size) unless a medium rest is asked for.
    final m = medium;
    final base = m != null && sheetSize == SheetSize.large
        ? math.min(full, (screen * m).roundToDouble())
        : full;
    onMetrics(base, full);
    final visible = _progress.value * base + _extra.value;
    (c.parentData! as BoxParentData).offset =
        Offset((size.width - c.size.width) / 2, size.height - visible);
  }
}

class _SheetScrollController extends ScrollController {
  _SheetScrollController(this.sheet);
  final _SheetBodyState sheet;

  @override
  ScrollPosition createScrollPosition(ScrollPhysics physics,
          ScrollContext context, ScrollPosition? oldPosition) =>
      _SheetScrollPosition(
        sheet: sheet,
        physics: const AlwaysScrollableScrollPhysics(
            parent: ClampingScrollPhysics()),
        context: context,
        oldPosition: oldPosition,
      );
}

class _SheetScrollPosition extends ScrollPositionWithSingleContext {
  _SheetScrollPosition({
    required this.sheet,
    required super.physics,
    required super.context,
    super.oldPosition,
  });

  final _SheetBodyState sheet;
  bool _dragging = false;

  @override
  Drag drag(DragStartDetails details, VoidCallback dragCancelCallback) {
    _dragging = true;
    sheet.dragStart();
    return super.drag(details, dragCancelCallback);
  }

  @override
  void applyUserOffset(double delta) {
    final rest = sheet.consume(delta, this);
    if (rest != 0) super.applyUserOffset(rest);
  }

  @override
  void goBallistic(double velocity) {
    if (_dragging) {
      _dragging = false;
      // Scroll velocity is positive when the finger moves up.
      if (sheet.dragEnd(-velocity)) {
        super.goBallistic(0);
        return;
      }
    }
    super.goBallistic(velocity);
  }
}
