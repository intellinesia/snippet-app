import 'dart:ui' show Offset, Rect;

import 'canvas_link.dart' show formatCanvasRef;

/// Snapshot of a canvas returned by `GET /canvas`.
class CanvasSnapshot {
  const CanvasSnapshot({
    required this.canvasId,
    required this.rev,
    required this.frames,
  });

  final String canvasId;
  final int rev;
  final List<CanvasFrame> frames;

  factory CanvasSnapshot.fromJson(Map<String, dynamic> json) {
    final rawFrames = (json['frames'] as List?) ?? const [];
    return CanvasSnapshot(
      canvasId: json['canvas_id']?.toString() ?? 'default',
      rev: (json['rev'] as num?)?.toInt() ?? 0,
      frames: [
        for (final item in rawFrames)
          if (item is Map)
            CanvasFrame.fromJson(item.cast<String, dynamic>()),
      ],
    );
  }
}

/// One positioned frame on the infinite canvas.
class CanvasFrame {
  const CanvasFrame({
    required this.id,
    required this.title,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    required this.rev,
  });

  final String id;
  final String title;
  final double x;
  final double y;
  final double w;
  final double h;
  final int rev;

  Rect get bounds => Rect.fromLTWH(x, y, w, h);

  bool overlapsRect(Rect r) =>
      x < r.right && x + w > r.left && y < r.bottom && y + h > r.top;

  CanvasFrame copyWith({
    String? title,
    double? x,
    double? y,
    double? w,
    double? h,
    int? rev,
  }) =>
      CanvasFrame(
        id: id,
        title: title ?? this.title,
        x: x ?? this.x,
        y: y ?? this.y,
        w: w ?? this.w,
        h: h ?? this.h,
        rev: rev ?? this.rev,
      );

  factory CanvasFrame.fromJson(Map<String, dynamic> json) => CanvasFrame(
        id: json['id']?.toString() ?? '',
        title: json['title']?.toString() ?? '',
        x: (json['x'] as num?)?.toDouble() ?? 0,
        y: (json['y'] as num?)?.toDouble() ?? 0,
        w: (json['w'] as num?)?.toDouble() ?? 360,
        h: (json['h'] as num?)?.toDouble() ?? 640,
        rev: (json['rev'] as num?)?.toInt() ?? 0,
      );
}

/// Element bounding box from `GET /canvas/frames/{id}/layout.json` in logical px.
class CanvasElementRect {
  const CanvasElementRect({
    required this.id,
    required this.x,
    required this.y,
    required this.w,
    required this.h,
    this.tag = '',
    this.text = '',
  });

  final String id;
  final double x;
  final double y;
  final double w;
  final double h;
  final String tag;
  final String text;

  Rect get bounds => Rect.fromLTWH(x, y, w, h);
  double get area => w * h;

  factory CanvasElementRect.fromJson(
    Map<String, dynamic> json, {
    String? fallbackId,
  }) =>
      CanvasElementRect(
        id: (json['data-cv-id'] ?? json['cv_id'] ?? json['id'] ?? fallbackId ?? '')
            .toString(),
        x: (json['x'] as num?)?.toDouble() ?? 0,
        y: (json['y'] as num?)?.toDouble() ?? 0,
        w: ((json['w'] ?? json['width']) as num?)?.toDouble() ?? 0,
        h: ((json['h'] ?? json['height']) as num?)?.toDouble() ?? 0,
        tag: json['tag']?.toString() ?? '',
        text: json['text']?.toString() ?? '',
      );
}

/// Readable author name from a string or an `{id, kind, name}` map.
String parseCanvasAuthor(Object? raw, {String fallback = 'Agent'}) {
  if (raw is Map) {
    final name = raw['name']?.toString().trim() ?? '';
    final kind = raw['kind']?.toString() ?? '';
    final id = raw['id']?.toString().trim() ?? '';
    if (kind == 'user' || id == 'user') return 'You';
    if (name.isNotEmpty) return name;
    return id.isNotEmpty ? id : fallback;
  }
  final text = raw?.toString().trim() ?? '';
  if (text.isEmpty) return fallback;
  return text == 'user' ? 'You' : text;
}

/// A comment pin anchored to an element (or frame) via fractional offsets.
class CanvasPin {
  const CanvasPin({
    required this.id,
    required this.frameId,
    this.elId,
    required this.dx,
    required this.dy,
    required this.text,
    this.status = 'open',
    this.reply,
    this.author = '',
    this.createdAt,
  });

  final String id;
  final String frameId;
  final String? elId;
  final double dx;
  final double dy;
  final String text;
  final String status;
  final String? reply;
  final String author;
  final DateTime? createdAt;

  bool get isResolved => status == 'resolved';

  CanvasPin copyWith({
    String? text,
    String? status,
    String? reply,
  }) =>
      CanvasPin(
        id: id,
        frameId: frameId,
        elId: elId,
        dx: dx,
        dy: dy,
        text: text ?? this.text,
        status: status ?? this.status,
        reply: reply ?? this.reply,
        author: author,
        createdAt: createdAt,
      );

  factory CanvasPin.fromJson(Map<String, dynamic> json) {
    final rawTs = json['created_at'] ?? json['ts'];
    final rawEl = json['el_id']?.toString();
    return CanvasPin(
      id: json['id']?.toString() ?? '',
      frameId: json['frame_id']?.toString() ?? '',
      elId: (rawEl != null && rawEl.isNotEmpty) ? rawEl : null,
      dx: (json['dx'] as num?)?.toDouble() ?? 0.5,
      dy: (json['dy'] as num?)?.toDouble() ?? 0.5,
      text: json['text']?.toString() ?? '',
      status: json['status']?.toString() ?? 'open',
      reply: json['reply']?.toString(),
      author: parseCanvasAuthor(json['author'], fallback: ''),
      createdAt: _parseTimestamp(rawTs),
    );
  }
}

/// One history batch from `GET /canvas/ops?since=rev`.
class CanvasOpBatch {
  const CanvasOpBatch({
    required this.rev,
    required this.batchId,
    required this.author,
    required this.label,
    required this.ts,
  });

  final int rev;
  final String batchId;
  final String author;
  final String label;
  final DateTime ts;

  factory CanvasOpBatch.fromJson(Map<String, dynamic> json) => CanvasOpBatch(
        rev: (json['rev'] as num?)?.toInt() ?? 0,
        batchId: json['batch_id']?.toString() ?? '',
        author: parseCanvasAuthor(json['author']),
        label: json['label']?.toString() ?? '',
        ts: _parseTimestamp(json['ts']) ?? DateTime.now(),
      );
}

/// Live canvas revision update from WebSocket `/events`.
class CanvasRevEvent {
  const CanvasRevEvent({
    required this.rev,
    required this.frameIds,
    this.batchId = '',
    this.label = '',
    this.canvasId,
  });

  final int rev;
  final List<String> frameIds;
  final String batchId;
  final String label;
  final String? canvasId;

  bool affectsFrame(String frameId, {String? canvasId}) {
    final mine = this.canvasId;
    if (mine != null && mine.isNotEmpty && canvasId != null && canvasId.isNotEmpty && mine != canvasId) {
      return false;
    }
    return frameIds.contains(frameId);
  }

  static CanvasRevEvent? tryFromFrame(Map<String, dynamic> frame) {
    final tag = frame['type'] ?? frame['kind'];
    if (tag != 'canvas_rev') return null;
    final rawRev = frame['rev'];
    final rev = rawRev is num ? rawRev.toInt() : int.tryParse('${rawRev ?? ''}');
    if (rev == null) return null;
    final ids = <String>[];
    final rawIds = frame['frame_ids'];
    if (rawIds is List) {
      for (final id in rawIds) {
        final s = id?.toString() ?? '';
        if (s.isNotEmpty) ids.add(s);
      }
    } else if (frame['frame_id'] != null) {
      final s = frame['frame_id'].toString();
      if (s.isNotEmpty) ids.add(s);
    }
    return CanvasRevEvent(
      rev: rev,
      frameIds: ids,
      batchId: frame['batch_id']?.toString() ?? '',
      label: frame['label']?.toString() ?? '',
      canvasId: frame['canvas_id']?.toString(),
    );
  }

  factory CanvasRevEvent.fromJson(Map<String, dynamic> json) {
    final rawIds = (json['frame_ids'] as List?) ?? const [];
    return CanvasRevEvent(
      rev: (json['rev'] as num?)?.toInt() ?? 0,
      frameIds: [for (final id in rawIds) id.toString()],
      batchId: json['batch_id']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      canvasId: json['canvas_id']?.toString(),
    );
  }
}

DateTime? _parseTimestamp(Object? raw) {
  if (raw == null) return null;
  if (raw is num) {
    final v = raw.toInt();
    // Seconds vs milliseconds heuristic.
    final ms = v > 100000000000 ? v : v * 1000;
    return DateTime.fromMillisecondsSinceEpoch(ms, isUtc: true).toLocal();
  }
  if (raw is String && raw.isNotEmpty) {
    return DateTime.tryParse(raw)?.toLocal();
  }
  return null;
}

/// Deepest element rect containing [localPoint] (smallest area, latest order on tie).
CanvasElementRect? hitTestCanvasElements(
  List<CanvasElementRect> rects,
  Offset localPoint,
) {
  CanvasElementRect? best;
  for (final rect in rects) {
    if (rect.w <= 0 || rect.h <= 0) continue;
    if (!rect.bounds.contains(localPoint)) continue;
    if (best == null || rect.area <= best.area) {
      best = rect;
    }
  }
  return best;
}

/// Resolves a pin's world-space position against its anchored element or frame.
Offset pinWorldAnchor(
  CanvasPin pin,
  CanvasFrame frame,
  Map<String, List<CanvasElementRect>> layouts,
) {
  if (pin.elId != null && pin.elId!.isNotEmpty) {
    final rects = layouts[frame.id];
    if (rects != null) {
      for (final r in rects) {
        if (r.id == pin.elId) {
          return Offset(
            frame.x + r.x + pin.dx * r.w,
            frame.y + r.y + pin.dy * r.h,
          );
        }
      }
    }
  }
  return Offset(
    frame.x + pin.dx * frame.w,
    frame.y + pin.dy * frame.h,
  );
}

/// Builds the raw `canvas:<canvas_id>/<frame_id>[/<el_id>]@<rev>` URI.
String formatCanvasUri({
  required String canvasId,
  required String frameId,
  String? elId,
  required int rev,
}) =>
    formatCanvasRef(
      canvasId: canvasId,
      frameId: frameId,
      elId: elId,
      rev: rev,
    );

/// Builds a markdown link `[Title](canvas:<canvas_id>/<frame_id>[/<el_id>]@<rev>)`.
String formatCanvasMarkdownLink({
  required String title,
  required String canvasId,
  required String frameId,
  String? elId,
  required int rev,
}) {
  final cleaned = title
      .trim()
      .replaceAll('[', r'\[')
      .replaceAll(']', r'\]');
  final label = cleaned.isEmpty ? frameId : cleaned;
  final uri = formatCanvasUri(
    canvasId: canvasId,
    frameId: frameId,
    elId: elId,
    rev: rev,
  );
  return '[$label]($uri)';
}

/// Short relative time: just now, 5m ago, 3h ago, 2d ago.
String formatCanvasRelativeTime(DateTime ts) {
  final diff = DateTime.now().difference(ts);
  if (diff.inSeconds < 60) return 'just now';
  if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
  if (diff.inHours < 24) return '${diff.inHours}h ago';
  return '${diff.inDays}d ago';
}
