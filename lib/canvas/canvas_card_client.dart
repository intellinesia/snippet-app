import 'dart:async';

import 'package:flutter/widgets.dart';

import 'canvas_link.dart';
import 'canvas_models.dart' show CanvasRevEvent;

/// Raised when the canvas backend cannot be reached (network/transport error).
/// Cards fall back to normal markdown link text.
class CanvasUnreachableException implements Exception {
  const CanvasUnreachableException([this.message = 'Canvas backend unreachable']);
  final String message;

  @override
  String toString() => message;
}

/// Raised when the backend responded but the referenced frame is unavailable.
/// Cards render their error state ("Frame unavailable").
class CanvasUnavailableException implements Exception {
  const CanvasUnavailableException([this.message = 'Frame unavailable']);
  final String message;

  @override
  String toString() => message;
}

/// Metadata resolved by `GET /canvas/link?ref=<canvas:...>`.
class CanvasLinkMeta {
  const CanvasLinkMeta({
    required this.canvasId,
    required this.frameId,
    this.elId,
    required this.rev,
    required this.title,
    required this.thumbUrl,
    this.width,
    this.height,
  });

  final String canvasId;
  final String frameId;
  final String? elId;
  final int rev;
  final String title;
  final String thumbUrl;
  final double? width;
  final double? height;

  double? get aspectRatio {
    final w = width;
    final h = height;
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return w / h;
  }

  factory CanvasLinkMeta.fromJson(Map<String, dynamic> j) {
    final rawRev = j['rev'];
    final rev = rawRev is num
        ? rawRev.toInt()
        : int.tryParse('${rawRev ?? 0}') ?? 0;
    double? numField(List<String> keys) {
      for (final k in keys) {
        final v = j[k];
        if (v is num && v > 0) return v.toDouble();
      }
      return null;
    }

    return CanvasLinkMeta(
      canvasId: (j['canvas_id'] ?? '').toString(),
      frameId: (j['frame_id'] ?? '').toString(),
      elId: (j['el_id'] as String?)?.isNotEmpty == true
          ? j['el_id'] as String
          : null,
      rev: rev,
      title: (j['title'] ?? '').toString(),
      thumbUrl: (j['thumb_url'] ?? '').toString(),
      width: numField(const ['width', 'frame_width', 'w']),
      height: numField(const ['height', 'frame_height', 'h']),
    );
  }
}

/// Logical pixel rectangle for an element in `layout.json`.
class CanvasElementBox {
  const CanvasElementBox({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  final double x;
  final double y;
  final double w;
  final double h;

  static CanvasElementBox? tryFromJson(Object? raw) {
    if (raw is! Map) return null;
    final x = raw['x'];
    final y = raw['y'];
    final w = raw['w'] ?? raw['width'];
    final h = raw['h'] ?? raw['height'];
    if (x is! num || y is! num || w is! num || h is! num) return null;
    if (w <= 0 || h <= 0) return null;
    return CanvasElementBox(
      x: x.toDouble(),
      y: y.toDouble(),
      w: w.toDouble(),
      h: h.toDouble(),
    );
  }
}

/// Parsed `GET /canvas/frames/{id}/layout.json` mapping `data-cv-id` -> box.
class CanvasLayout {
  const CanvasLayout({
    required this.elements,
    this.frameWidth,
    this.frameHeight,
  });

  final Map<String, CanvasElementBox> elements;
  final double? frameWidth;
  final double? frameHeight;

  CanvasElementBox? operator [](String elId) => elements[elId];

  factory CanvasLayout.fromJson(Map<String, dynamic> j) {
    double? frameW;
    double? frameH;

    void readSize(Object? src) {
      if (src is! Map) return;
      final w = src['w'] ?? src['width'];
      final h = src['h'] ?? src['height'];
      if (w is num && w > 0 && h is num && h > 0) {
        frameW ??= w.toDouble();
        frameH ??= h.toDouble();
      }
    }

    readSize(j['frame']);
    readSize(j['viewport']);
    readSize(j['_frame']);
    readSize(j);

    final out = <String, CanvasElementBox>{};

    void addMap(Object? raw) {
      if (raw is! Map) return;
      for (final entry in raw.entries) {
        final key = entry.key.toString();
        if (key == 'frame' || key == 'viewport' || key == '_frame') continue;
        final box = CanvasElementBox.tryFromJson(entry.value);
        if (box != null) out[key] = box;
      }
    }

    void addList(Object? raw) {
      if (raw is! List) return;
      for (final item in raw) {
        if (item is! Map) continue;
        final id =
            (item['data-cv-id'] ?? item['cv_id'] ?? item['id'] ?? '').toString();
        if (id.isEmpty) continue;
        final box = CanvasElementBox.tryFromJson(item);
        if (box != null) out[id] = box;
      }
    }

    addMap(j['elements']);
    addMap(j['boxes']);
    addList(j['nodes']);
    addList(j['elements']);
    if (out.isEmpty) addMap(j);

    return CanvasLayout(
      elements: out,
      frameWidth: frameW,
      frameHeight: frameH,
    );
  }
}

/// Event pushed over `/events`:
/// `{type: "canvas_rev", rev, frame_ids, batch_id, label}`.
/// Abstract client backing [CanvasLinkCard], implemented by [DaemonCanvasClient]
/// in production and test doubles in unit/widget tests.
abstract class CanvasCardClient {
  Future<CanvasLinkMeta> resolveLink(CanvasRef ref);

  Future<CanvasLayout?> fetchCardLayout(
    String frameId, {
    String? canvasId,
    int? rev,
  });

  ImageProvider imageProvider(String thumbUrl, {int? rev});

  Stream<CanvasRevEvent> get revEvents;

  Stream<void> get onReconnected => const Stream.empty();
}

/// Provides an optional [CanvasCardClient] override (for tests).
class CanvasCardClientScope extends InheritedWidget {
  const CanvasCardClientScope({
    super.key,
    required this.client,
    required super.child,
  });

  final CanvasCardClient client;

  static CanvasCardClient? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<CanvasCardClientScope>()?.client;

  @override
  bool updateShouldNotify(CanvasCardClientScope oldWidget) =>
      oldWidget.client != client;
}
