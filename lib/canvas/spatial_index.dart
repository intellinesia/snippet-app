import 'dart:math' as math;
import 'dart:ui' show Rect;

import 'canvas_models.dart';

/// Uniform grid spatial index (default cell 1024) for O(visible) viewport culling.
class CanvasSpatialIndex {
  CanvasSpatialIndex({this.cellSize = 1024.0}) : assert(cellSize > 0);

  final double cellSize;
  final Map<int, List<CanvasFrame>> _cells = <int, List<CanvasFrame>>{};
  final Map<String, int> _orderById = <String, int>{};
  List<CanvasFrame> _all = const <CanvasFrame>[];
  Rect? _contentBounds;

  List<CanvasFrame> get frames => _all;
  int get length => _all.length;
  Rect? get contentBounds => _contentBounds;

  void rebuild(Iterable<CanvasFrame> frames) {
    _cells.clear();
    _orderById.clear();
    final list = <CanvasFrame>[
      for (final frame in frames)
        if (frame.x.isFinite &&
            frame.y.isFinite &&
            frame.w.isFinite &&
            frame.h.isFinite &&
            frame.w > 0 &&
            frame.h > 0)
          frame,
    ];
    _all = List<CanvasFrame>.unmodifiable(list);
    if (list.isEmpty) {
      _contentBounds = null;
      return;
    }

    var minX = double.infinity;
    var minY = double.infinity;
    var maxX = double.negativeInfinity;
    var maxY = double.negativeInfinity;

    for (var i = 0; i < list.length; i++) {
      final frame = list[i];
      _orderById[frame.id] = i;
      final b = frame.bounds;
      if (b.left < minX) minX = b.left;
      if (b.top < minY) minY = b.top;
      if (b.right > maxX) maxX = b.right;
      if (b.bottom > maxY) maxY = b.bottom;

      final x0 = _cellCoord(b.left);
      final x1 = _cellCoord(b.right);
      final y0 = _cellCoord(b.top);
      final y1 = _cellCoord(b.bottom);

      for (var cx = x0; cx <= x1; cx++) {
        for (var cy = y0; cy <= y1; cy++) {
          final bucket = _cells.putIfAbsent(_packKey(cx, cy), () => <CanvasFrame>[]);
          bucket.add(frame);
        }
      }
    }

    _contentBounds = Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  /// Returns all frames whose world bounds intersect [viewport], in z-order.
  List<CanvasFrame> query(Rect viewport) {
    if (_all.isEmpty ||
        viewport.isEmpty ||
        !viewport.left.isFinite ||
        !viewport.top.isFinite ||
        !viewport.right.isFinite ||
        !viewport.bottom.isFinite) {
      return const <CanvasFrame>[];
    }
    final x0 = _cellCoord(viewport.left);
    final x1 = _cellCoord(viewport.right);
    final y0 = _cellCoord(viewport.top);
    final y1 = _cellCoord(viewport.bottom);

    final cellCount = (x1 - x0 + 1) * (y1 - y0 + 1);
    // When zoomed so far out that the viewport spans more cells than frames exist,
    // a linear scan avoids hashing thousands of empty cells.
    if (cellCount > _cells.length && cellCount > 256) {
      return [
        for (final frame in _all)
          if (frame.bounds.overlaps(viewport)) frame,
      ];
    }

    final seen = <String>{};
    final out = <CanvasFrame>[];
    for (var cx = x0; cx <= x1; cx++) {
      for (var cy = y0; cy <= y1; cy++) {
        final bucket = _cells[_packKey(cx, cy)];
        if (bucket == null) continue;
        for (final frame in bucket) {
          if (seen.add(frame.id) && frame.bounds.overlaps(viewport)) {
            out.add(frame);
          }
        }
      }
    }
    if (out.length > 1) {
      out.sort((a, b) => (_orderById[a.id] ?? 0).compareTo(_orderById[b.id] ?? 0));
    }
    return out;
  }

  /// Returns the topmost frame containing [worldPoint], if any.
  CanvasFrame? hitTestFrame(double worldX, double worldY) {
    if (!worldX.isFinite || !worldY.isFinite) return null;
    final bucket = _cells[_packKey(_cellCoord(worldX), _cellCoord(worldY))];
    if (bucket == null) return null;
    for (var i = bucket.length - 1; i >= 0; i--) {
      final f = bucket[i];
      if (worldX >= f.x &&
          worldX <= f.x + f.w &&
          worldY >= f.y &&
          worldY <= f.y + f.h) {
        return f;
      }
    }
    return null;
  }

  int _cellCoord(double value) => (value / cellSize).floor();

  // Pack two signed 26-bit cell coordinates into one SMI-safe integer key.
  static int _packKey(int cx, int cy) {
    const bias = 1 << 25;
    final ux = math.max(0, math.min((1 << 26) - 1, cx + bias));
    final uy = math.max(0, math.min((1 << 26) - 1, cy + bias));
    return (ux << 26) | uy;
  }
}
