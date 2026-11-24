import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';

/// Manages the infinite canvas world-to-screen transform (pan + uniform zoom).
class CanvasViewportController extends ChangeNotifier {
  CanvasViewportController({
    this.minScale = 0.04,
    this.maxScale = 8.0,
  });

  final double minScale;
  final double maxScale;

  Matrix4 _transform = Matrix4.identity();

  Matrix4 get transform => _transform;
  double get scale => _transform.storage[0];
  double get tx => _transform.storage[12];
  double get ty => _transform.storage[13];

  void markNeedsPaint() => notifyListeners();

  void setTransform(Matrix4 next) {
    _transform = next.clone();
    notifyListeners();
  }

  void setPanZoom({required double tx, required double ty, required double scale}) {
    final s = scale.clamp(minScale, maxScale);
    _transform = Matrix4.identity()
      ..storage[0] = s
      ..storage[5] = s
      ..storage[12] = tx
      ..storage[13] = ty;
    notifyListeners();
  }

  Offset screenToWorld(Offset screen) {
    final s = scale;
    return Offset((screen.dx - tx) / s, (screen.dy - ty) / s);
  }

  Offset worldToScreen(Offset world) {
    final s = scale;
    return Offset(world.dx * s + tx, world.dy * s + ty);
  }

  Rect worldViewport(Size screenSize) {
    final tl = screenToWorld(Offset.zero);
    final br = screenToWorld(Offset(screenSize.width, screenSize.height));
    return Rect.fromLTRB(tl.dx, tl.dy, br.dx, br.dy);
  }

  void panBy(Offset screenDelta) {
    setPanZoom(tx: tx + screenDelta.dx, ty: ty + screenDelta.dy, scale: scale);
  }

  /// Zooms by [factor] keeping [screenFocal] fixed on the same world point.
  void zoomAt(double factor, Offset screenFocal) {
    if (!factor.isFinite || factor <= 0) return;
    final oldScale = scale;
    final nextScale = (oldScale * factor).clamp(minScale, maxScale);
    if ((nextScale - oldScale).abs() < 1e-6) return;
    final ratio = nextScale / oldScale;
    final nextTx = screenFocal.dx - (screenFocal.dx - tx) * ratio;
    final nextTy = screenFocal.dy - (screenFocal.dy - ty) * ratio;
    setPanZoom(tx: nextTx, ty: nextTy, scale: nextScale);
  }

  /// Computes a target transform that centres [worldRect] inside [viewportSize].
  Matrix4 computeFitTransform(
    Rect worldRect,
    Size viewportSize, {
    EdgeInsets padding = const EdgeInsets.all(64),
    double? maxFitScale,
  }) {
    final availW = math.max(1.0, viewportSize.width - padding.horizontal);
    final availH = math.max(1.0, viewportSize.height - padding.vertical);
    final rectW = math.max(1.0, worldRect.width);
    final rectH = math.max(1.0, worldRect.height);
    final rawScale = math.min(availW / rectW, availH / rectH);
    final upper = maxFitScale ?? maxScale;
    final s = rawScale.clamp(minScale, upper);
    final cx = padding.left + availW / 2;
    final cy = padding.top + availH / 2;
    final nextTx = cx - worldRect.center.dx * s;
    final nextTy = cy - worldRect.center.dy * s;
    return Matrix4.identity()
      ..storage[0] = s
      ..storage[5] = s
      ..storage[12] = nextTx
      ..storage[13] = nextTy;
  }

  void fitRect(
    Rect worldRect,
    Size viewportSize, {
    EdgeInsets padding = const EdgeInsets.all(64),
    double? maxFitScale,
  }) {
    setTransform(computeFitTransform(
      worldRect,
      viewportSize,
      padding: padding,
      maxFitScale: maxFitScale,
    ));
  }
}
