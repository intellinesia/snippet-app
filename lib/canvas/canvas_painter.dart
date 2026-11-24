import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';

import '../theme.dart';
import 'canvas_models.dart';
import 'canvas_viewport.dart';
import 'spatial_index.dart';
import 'thumb_cache.dart';

/// Below this zoom frames draw as labelled blocks with no thumbnail text.
const double kCanvasBlockZoom = 0.15;

/// Pins and frame labels shrink with zoom: full size from 0.5x, 45% at 0.22x.
double canvasChromeScale(double zoom) => (zoom / 0.5).clamp(0.45, 1.0);

/// Callback notified with the visible frames and active thumbnail scale bucket on paint.
typedef CanvasVisibleCallback = void Function(
  List<CanvasFrame> visibleFrames,
  double scaleBucket,
);

/// Single CustomPainter that renders the infinite canvas, culled frames,
/// cached thumbnails, selection overlays, and anchored pins.
class InfiniteCanvasPainter extends CustomPainter {
  InfiniteCanvasPainter({
    required this.viewport,
    required this.index,
    required this.cache,
    required this.devicePixelRatio,
    required this.isInteracting,
    this.isPhone = false,
    this.paintVersion = 0,
    this.selectedFrameId,
    this.selectedElement,
    this.pins = const <CanvasPin>[],
    this.selectedPinId,
    this.layouts = const <String, List<CanvasElementRect>>{},
    this.onVisibleFrames,
    this.onTapPin,
  }) : super(repaint: viewport);

  final CanvasViewportController viewport;
  final CanvasSpatialIndex index;
  final ThumbLruCache<ui.Image> cache;
  final double devicePixelRatio;
  final bool isInteracting;
  final bool isPhone;
  final int paintVersion;
  final String? selectedFrameId;
  final CanvasElementRect? selectedElement;
  final List<CanvasPin> pins;
  final String? selectedPinId;
  final Map<String, List<CanvasElementRect>> layouts;
  final CanvasVisibleCallback? onVisibleFrames;
  final ValueChanged<CanvasPin>? onTapPin;

  @override
  void paint(Canvas canvas, Size size) {
    final bgPaint = Paint()..color = AppColors.bg;
    canvas.drawRect(Offset.zero & size, bgPaint);

    final zoom = viewport.scale;
    final worldRect = viewport.worldViewport(size);
    _paintDotGrid(canvas, size, worldRect, zoom);

    final visible = index.query(worldRect);
    final scaleBucket =
        pickThumbScaleBucket(zoom, devicePixelRatio: devicePixelRatio);
    final blockMode = zoom < kCanvasBlockZoom;
    onVisibleFrames?.call(blockMode ? const <CanvasFrame>[] : visible, scaleBucket);

    final frameFillPaint = Paint()..color = AppColors.surface1;
    final frameBorderPaint = Paint()
      ..color = AppColors.border
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.0;
    final selectedBorderPaint = Paint()
      ..color = AppColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.0;
    final imgPaint = Paint()
      ..filterQuality =
          isInteracting ? FilterQuality.low : FilterQuality.medium;

    final visibleIds = <String>{};
    final labels = <_FrameLabel>[];
    final chrome = canvasChromeScale(zoom);

    for (final frame in visible) {
      visibleIds.add(frame.id);
      final tl = viewport.worldToScreen(Offset(frame.x, frame.y));
      final screenW = frame.w * zoom;
      final screenH = frame.h * zoom;
      final screenRect = Rect.fromLTWH(tl.dx, tl.dy, screenW, screenH);
      final isSelected = frame.id == selectedFrameId;

      final image = blockMode
          ? null
          : cache.bestAvailable(
              frame.id,
              rev: frame.rev,
              preferredScale: scaleBucket,
            );

      if (blockMode) {
        canvas.drawRect(screenRect, Paint()..color = AppColors.surface2);
        if (screenW >= 56 && screenH >= 18) {
          _paintBlockTitle(canvas, frame.title, screenRect);
        }
      } else if (image != null) {
        final src = Rect.fromLTWH(
            0, 0, image.width.toDouble(), image.height.toDouble());
        canvas.drawImageRect(image, src, screenRect, imgPaint);
      } else {
        canvas.drawRect(screenRect, frameFillPaint);
        if (screenW > 56 && screenH > 40) {
          _paintPlaceholder(canvas, screenRect);
        }
      }

      canvas.drawRect(
        screenRect,
        isSelected ? selectedBorderPaint : frameBorderPaint,
      );

      // Frame title label sits cleanly above the frame when legible.
      if (screenW >= 42 && !blockMode) {
        labels.add(_FrameLabel(frame.title, screenRect, isSelected));
      }

      // Selected element highlight when zoomed into the frame.
      if (isSelected && selectedElement != null && screenW > 120) {
        _paintSelectedElement(canvas, frame, selectedElement!, zoom);
      }
    }

    // Labels paint last so a neighbouring frame never covers them.
    for (final l in labels) {
      _paintFrameTitle(canvas, l.title, l.rect, l.selected, chrome);
    }

    if (pins.isNotEmpty) {
      _paintPins(canvas, visible, visibleIds, zoom);
    }
  }

  void _paintDotGrid(Canvas canvas, Size size, Rect worldRect, double zoom) {
    // Choose a grid spacing whose on-screen pitch stays comfortable (18..48 px).
    var step = 32.0;
    while (step * zoom < 18.0 && step < 4096.0) {
      step *= 2.0;
    }
    while (step * zoom > 56.0 && step > 4.0) {
      step /= 2.0;
    }
    final pitch = step * zoom;
    if (pitch < 14.0) return;

    final alpha = ((pitch - 14.0) / 28.0).clamp(0.0, 1.0) * 0.22;
    final paint = Paint()
      ..color = AppColors.fg4.withValues(alpha: alpha)
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;

    final startX = (worldRect.left / step).floor() * step;
    final startY = (worldRect.top / step).floor() * step;
    final points = <Offset>[];
    for (var wx = startX; wx <= worldRect.right; wx += step) {
      final sx = wx * zoom + viewport.tx;
      if (sx < -2 || sx > size.width + 2) continue;
      for (var wy = startY; wy <= worldRect.bottom; wy += step) {
        final sy = wy * zoom + viewport.ty;
        if (sy < -2 || sy > size.height + 2) continue;
        points.add(Offset(sx, sy));
      }
    }
    if (points.isNotEmpty) {
      canvas.drawPoints(ui.PointMode.points, points, paint);
    }
  }

  void _paintPlaceholder(Canvas canvas, Rect rect) {
    final inner = rect.deflate(math.min(12, rect.width * 0.1));
    final barPaint = Paint()..color = AppColors.surface2;
    final topBar = Rect.fromLTWH(
      inner.left,
      inner.top,
      inner.width * 0.55,
      math.min(10, inner.height * 0.08),
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(topBar, const Radius.circular(3)),
      barPaint,
    );
  }

  void _paintBlockTitle(Canvas canvas, String title, Rect rect) {
    if (title.isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(text: title, style: sans(10, color: AppColors.fg2)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    )..layout(maxWidth: math.max(1, rect.width - 8));
    tp.paint(
      canvas,
      Offset(rect.center.dx - tp.width / 2, rect.center.dy - tp.height / 2),
    );
  }

  void _paintFrameTitle(
    Canvas canvas,
    String title,
    Rect screenRect,
    bool isSelected,
    double chrome,
  ) {
    if (title.isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(
        text: title,
        style: sans(
          11 * chrome,
          weight: isSelected ? W.label : W.body,
          color: isSelected ? AppColors.fg1 : AppColors.fg3,
        ),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
      ellipsis: '...',
    )..layout(maxWidth: math.max(40, screenRect.width));
    final at = Offset(
      screenRect.left,
      screenRect.top - tp.height - 6 * chrome,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(at.dx - 2, at.dy - 1, tp.width + 4, tp.height + 2),
        const Radius.circular(3),
      ),
      Paint()..color = AppColors.bg.withValues(alpha: 0.85),
    );
    tp.paint(canvas, at);
  }

  void _paintSelectedElement(
    Canvas canvas,
    CanvasFrame frame,
    CanvasElementRect el,
    double zoom,
  ) {
    final tl = viewport.worldToScreen(Offset(frame.x + el.x, frame.y + el.y));
    final elRect = Rect.fromLTWH(tl.dx, tl.dy, el.w * zoom, el.h * zoom);

    canvas.drawRect(
      elRect,
      Paint()..color = AppColors.accent.withValues(alpha: 0.12),
    );
    canvas.drawRect(
      elRect,
      Paint()
        ..color = AppColors.accent
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.5,
    );

    final label = el.id.isNotEmpty ? el.id : el.tag;
    if (label.isEmpty) return;
    final tp = TextPainter(
      text: TextSpan(
        text: label,
        style: mono(10, weight: W.label, color: AppColors.accentFg),
      ),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout(maxWidth: 220);

    final badgeRect = Rect.fromLTWH(
      elRect.left,
      math.max(4.0, elRect.top - tp.height - 8),
      tp.width + 10,
      tp.height + 4,
    );
    canvas.drawRRect(
      RRect.fromRectAndRadius(badgeRect, const Radius.circular(4)),
      Paint()..color = AppColors.accent,
    );
    tp.paint(canvas, Offset(badgeRect.left + 5, badgeRect.top + 2));
  }

  void _paintPins(
    Canvas canvas,
    List<CanvasFrame> visibleFrames,
    Set<String> visibleIds,
    double zoom,
  ) {
    final frameById = <String, CanvasFrame>{
      for (final f in visibleFrames) f.id: f,
    };

    for (var i = 0; i < pins.length; i++) {
      final pin = pins[i];
      if (!visibleIds.contains(pin.frameId)) continue;
      final frame = frameById[pin.frameId]!;
      final worldPos = pinWorldAnchor(pin, frame, layouts);
      final screenPos = viewport.worldToScreen(worldPos);
      final isSelected = pin.id == selectedPinId;
      final chrome = canvasChromeScale(zoom);
      final radius = (isSelected ? 11.5 : 9.5) * chrome;
      final fillColor = pin.isResolved ? AppColors.fg3 : AppColors.fg1;

      if (isSelected) {
        canvas.drawCircle(
          screenPos,
          radius + 3 * chrome,
          Paint()..color = fillColor.withValues(alpha: 0.28),
        );
      }
      canvas.drawCircle(screenPos, radius, Paint()..color = fillColor);
      canvas.drawCircle(
        screenPos,
        radius,
        Paint()
          ..color = AppColors.bg
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1.5,
      );

      final tp = TextPainter(
        text: TextSpan(
          text: '${i + 1}',
          style: mono(10 * chrome, weight: W.strong, color: AppColors.bg),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(
        canvas,
        Offset(screenPos.dx - tp.width / 2, screenPos.dy - tp.height / 2),
      );
    }
  }

  @override
  SemanticsBuilderCallback get semanticsBuilder => _buildSemantics;

  List<CustomPainterSemantics> _buildSemantics(Size size) {
    if (pins.isEmpty || size.isEmpty) return const <CustomPainterSemantics>[];
    final worldRect = viewport.worldViewport(size);
    final visible = index.query(worldRect);
    final frameById = <String, CanvasFrame>{
      for (final f in visible) f.id: f,
    };
    final hitRadius = math.max(
        12.0, (isPhone ? 22.0 : 18.0) * canvasChromeScale(viewport.scale));
    final canvasBounds = Offset.zero & size;
    final nodes = <CustomPainterSemantics>[];

    for (var i = 0; i < pins.length; i++) {
      final pin = pins[i];
      final frame = frameById[pin.frameId];
      if (frame == null) continue;
      final screenPos =
          viewport.worldToScreen(pinWorldAnchor(pin, frame, layouts));
      final rect = Rect.fromCircle(center: screenPos, radius: hitRadius);
      if (!rect.overlaps(canvasBounds)) continue;
      final status = pin.isResolved ? 'resolved' : 'open';
      final note = pin.text.trim();
      final label = note.isNotEmpty
          ? 'Pin ${i + 1}, $status: $note'
          : 'Pin ${i + 1}, $status';
      nodes.add(CustomPainterSemantics(
        rect: rect,
        properties: SemanticsProperties(
          button: true,
          selected: pin.id == selectedPinId,
          label: label,
          onTap: onTapPin == null ? null : () => onTapPin!(pin),
        ),
      ));
    }
    return nodes;
  }

  @override
  bool shouldRepaint(covariant InfiniteCanvasPainter oldDelegate) =>
      oldDelegate.paintVersion != paintVersion ||
      oldDelegate.viewport != viewport ||
      oldDelegate.index != index ||
      oldDelegate.devicePixelRatio != devicePixelRatio ||
      oldDelegate.isInteracting != isInteracting ||
      oldDelegate.isPhone != isPhone ||
      oldDelegate.selectedFrameId != selectedFrameId ||
      oldDelegate.selectedElement != selectedElement ||
      oldDelegate.selectedPinId != selectedPinId ||
      oldDelegate.pins != pins;
}

class _FrameLabel {
  const _FrameLabel(this.title, this.rect, this.selected);
  final String title;
  final Rect rect;
  final bool selected;
}
