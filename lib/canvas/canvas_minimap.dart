import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme.dart';
import 'canvas_models.dart';
import 'canvas_viewport.dart';

/// Maps between world space and a minimap box that always shows the content
/// and the current viewport.
class MinimapGeometry {
  MinimapGeometry._(this.world, this.scale, this.offset);

  final Rect world;
  final double scale;
  final Offset offset;

  factory MinimapGeometry.fit(
    Rect content,
    Rect viewportWorld,
    Size mapSize, {
    double padding = 8,
  }) {
    final world = content.expandToInclude(viewportWorld);
    final w = math.max(1.0, world.width);
    final h = math.max(1.0, world.height);
    final availW = math.max(1.0, mapSize.width - padding * 2);
    final availH = math.max(1.0, mapSize.height - padding * 2);
    final s = math.min(availW / w, availH / h);
    final off = Offset(
      (mapSize.width - w * s) / 2 - world.left * s,
      (mapSize.height - h * s) / 2 - world.top * s,
    );
    return MinimapGeometry._(world, s, off);
  }

  Offset worldToMap(Offset p) =>
      Offset(p.dx * scale + offset.dx, p.dy * scale + offset.dy);
  Offset mapToWorld(Offset p) =>
      Offset((p.dx - offset.dx) / scale, (p.dy - offset.dy) / scale);

  Rect mapRect(Rect r) =>
      Rect.fromPoints(worldToMap(r.topLeft), worldToMap(r.bottomRight));
}

/// Transform that centres [worldPoint] in a viewport of [viewportSize] at [scale].
({double tx, double ty}) centerOn(
        Offset worldPoint, Size viewportSize, double scale) =>
    (
      tx: viewportSize.width / 2 - worldPoint.dx * scale,
      ty: viewportSize.height / 2 - worldPoint.dy * scale,
    );

/// Overview of every frame with the viewport rectangle; tap or drag to jump.
class CanvasMinimap extends StatelessWidget {
  const CanvasMinimap({
    super.key,
    required this.frames,
    required this.contentBounds,
    required this.viewport,
    required this.viewportSize,
    required this.selectedFrameId,
  });

  static const Size size = Size(160, 108);

  final List<CanvasFrame> frames;
  final Rect? contentBounds;
  final CanvasViewportController viewport;
  final Size viewportSize;
  final String? selectedFrameId;

  MinimapGeometry? _geometry() {
    final content = contentBounds;
    if (content == null || viewportSize.isEmpty) return null;
    return MinimapGeometry.fit(
        content, viewport.worldViewport(viewportSize), size);
  }

  void _jump(Offset local) {
    final g = _geometry();
    if (g == null) return;
    final c = centerOn(g.mapToWorld(local), viewportSize, viewport.scale);
    viewport.setPanZoom(tx: c.tx, ty: c.ty, scale: viewport.scale);
  }

  @override
  Widget build(BuildContext context) {
    if (contentBounds == null) return const SizedBox.shrink();
    return Semantics(
      label: 'Minimap. Tap or drag to move the view',
      child: Container(
        width: size.width,
        height: size.height,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surface1,
          borderRadius: BorderRadius.circular(R.of(10)),
          border: Border.all(color: AppColors.paneLine, width: AppColors.hairline),
        ),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapDown: (d) => _jump(d.localPosition),
          onPanUpdate: (d) => _jump(d.localPosition),
          child: RepaintBoundary(
            child: CustomPaint(
              size: size,
              painter: _MinimapPainter(
                frames: frames,
                geometry: _geometry,
                viewportSize: viewportSize,
                viewport: viewport,
                selectedFrameId: selectedFrameId,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MinimapPainter extends CustomPainter {
  _MinimapPainter({
    required this.frames,
    required this.geometry,
    required this.viewportSize,
    required this.viewport,
    required this.selectedFrameId,
  }) : super(repaint: viewport);

  final List<CanvasFrame> frames;
  final MinimapGeometry? Function() geometry;
  final Size viewportSize;
  final CanvasViewportController viewport;
  final String? selectedFrameId;

  @override
  void paint(Canvas canvas, Size size) {
    final g = geometry();
    if (g == null) return;
    final block = Paint()..color = AppColors.surface2;
    final selected = Paint()..color = AppColors.surface3;
    for (final f in frames) {
      final r = g.mapRect(f.bounds);
      canvas.drawRect(r.width < 1.5 || r.height < 1.5 ? r.inflate(0.75) : r,
          f.id == selectedFrameId ? selected : block);
    }
    final vp = g.mapRect(viewport.worldViewport(viewportSize));
    canvas.drawRect(
      vp,
      Paint()
        ..color = PaneRow.labelOff
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  @override
  bool shouldRepaint(_MinimapPainter old) =>
      old.frames != frames ||
      old.selectedFrameId != selectedFrameId ||
      old.viewportSize != viewportSize;
}
