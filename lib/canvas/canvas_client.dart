import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/painting.dart';
import 'package:http/http.dart' as http;

import '../api.dart';
import '../swr.dart' show DeviceEventHub;
import 'canvas_card_client.dart';
import 'canvas_link.dart';
import 'canvas_models.dart';

/// Client contract for the infinite canvas screen.
abstract class CanvasClient {
  Future<CanvasSnapshot> fetchCanvas();
  Future<Uint8List> fetchThumbPng(String frameId, double scale, {int? rev});
  Future<List<CanvasElementRect>> fetchLayout(String frameId, {int? rev});
  Future<String?> hitTestRemote(String frameId, double x, double y);
  Future<List<CanvasPin>> fetchPins();
  Future<CanvasPin> createPin({
    required String frameId,
    String? elId,
    required double dx,
    required double dy,
    required String text,
  });
  Future<CanvasPin> patchPin(String pinId, {String? status, String? reply});
  Future<List<CanvasOpBatch>> fetchOps({int since = 0});
  Future<int> revertBatch(String batchId);
  Stream<CanvasRevEvent> get revEvents;
  Stream<void> get onReconnected => const Stream.empty();
  void dispose();
}

/// Real canvas client backed by [DaemonClient] HTTP endpoints and `/events` WS.
class DaemonCanvasClient implements CanvasClient, CanvasCardClient {
  DaemonCanvasClient(this.daemon, {this.canvasId});

  final DaemonClient daemon;

  /// Canvas this client reads and writes; null means the workspace canvas.
  final String? canvasId;

  static final Expando<DaemonCanvasClient> _cache =
      Expando<DaemonCanvasClient>('DaemonCanvasClient');

  /// Stable shared instance per [DaemonClient], used by link cards.
  factory DaemonCanvasClient.forDaemon(DaemonClient daemon) =>
      _cache[daemon] ??= DaemonCanvasClient(daemon);

  @override
  Future<CanvasLinkMeta> resolveLink(CanvasRef ref) async {
    try {
      var target = ref;
      if (target.frameId == null) {
        final snap = CanvasSnapshot.fromJson(
          await daemon.getCanvas(canvasId: ref.canvasId),
        );
        if (snap.frames.isEmpty) {
          throw const CanvasUnavailableException('Canvas has no frames');
        }
        target = CanvasRef(
          canvasId: ref.canvasId,
          frameId: snap.frames.first.id,
          elId: ref.elId,
          rev: ref.rev,
        );
      }
      final json = await daemon.canvasLink(target.format());
      final meta = CanvasLinkMeta.fromJson(json);
      if (meta.thumbUrl.isEmpty) {
        throw const CanvasUnavailableException('Missing thumbnail URL');
      }
      // Validate same-origin auth before handing the URL to image loading.
      daemon.canvasAssetUri(meta.thumbUrl, rev: meta.rev);
      return meta;
    } on CanvasUnavailableException {
      rethrow;
    } on CanvasHttpException catch (e) {
      if (e.statusCode >= 500 || e.statusCode == 0) {
        throw CanvasUnreachableException(e.message);
      }
      throw CanvasUnavailableException(e.message);
    } on SocketException catch (e) {
      throw CanvasUnreachableException(e.message);
    } on TimeoutException {
      throw const CanvasUnreachableException('Request timed out');
    } on http.ClientException catch (e) {
      throw CanvasUnreachableException(e.message);
    } on TlsException catch (e) {
      throw CanvasUnreachableException(e.message);
    } on FormatException {
      throw const CanvasUnavailableException('Invalid canvas metadata');
    }
  }

  @override
  Future<CanvasLayout?> fetchCardLayout(
    String frameId, {
    String? canvasId,
    int? rev,
  }) async {
    try {
      final json = await daemon.canvasFrameLayout(
        frameId,
        canvasId: canvasId,
        rev: rev,
      );
      if (json == null) return null;
      return CanvasLayout.fromJson(json);
    } catch (_) {
      return null;
    }
  }

  @override
  ImageProvider imageProvider(String thumbUrl, {int? rev}) =>
      daemon.canvasImage(thumbUrl, rev: rev);

  // Lazy broadcast mapping: subscribes to DeviceEventHub only while listeners exist.
  @override
  Stream<CanvasRevEvent> get revEvents => daemon.deviceEvents.stream
      .map(CanvasRevEvent.tryFromFrame)
      .where((e) => e != null)
      .cast<CanvasRevEvent>();

  @override
  Stream<void> get onReconnected => daemon.deviceEvents.stream
      .where((f) => f['kind'] == DeviceEventHub.reconnected)
      .map((_) {});

  @override
  Future<CanvasSnapshot> fetchCanvas() async {
    final json = await daemon.getCanvas(canvasId: canvasId);
    return CanvasSnapshot.fromJson(json);
  }

  @override
  Future<Uint8List> fetchThumbPng(String frameId, double scale,
          {int? rev}) =>
      daemon.getCanvasThumbPng(frameId, scale, rev: rev, canvasId: canvasId);

  @override
  Future<List<CanvasElementRect>> fetchLayout(String frameId,
      {int? rev}) async {
    final raw = await daemon.getCanvasLayout(frameId, rev: rev, canvasId: canvasId);
    return parseLayoutRects(raw);
  }

  /// Parses list- or map-shaped `layout.json` payloads into element rects.
  static List<CanvasElementRect> parseLayoutRects(Object? raw) {
    final out = <CanvasElementRect>[];

    void addList(Object? src) {
      if (src is! List) return;
      for (final item in src) {
        if (item is! Map) continue;
        final rect = CanvasElementRect.fromJson(item.cast<String, dynamic>());
        if (rect.w > 0 && rect.h > 0) out.add(rect);
      }
    }

    void addMap(Object? src) {
      if (src is! Map) return;
      for (final entry in src.entries) {
        final key = entry.key.toString();
        if (key == 'frame' || key == 'viewport' || key == '_frame') continue;
        final val = entry.value;
        if (val is! Map) continue;
        final rect = CanvasElementRect.fromJson(
          val.cast<String, dynamic>(),
          fallbackId: key,
        );
        if (rect.w > 0 && rect.h > 0) out.add(rect);
      }
    }

    if (raw is List) {
      addList(raw);
      return out;
    }
    if (raw is Map) {
      for (final key in const ['rects', 'elements', 'nodes', 'layout']) {
        addList(raw[key]);
      }
      if (out.isEmpty) {
        addMap(raw['elements']);
        addMap(raw['boxes']);
      }
      if (out.isEmpty) {
        addMap(raw);
      }
    }
    return out;
  }

  @override
  Future<String?> hitTestRemote(String frameId, double x, double y) async {
    final json = await daemon.postCanvasHit(frameId, x, y, canvasId: canvasId);
    final id = json['el_id']?.toString();
    return (id == null || id.isEmpty) ? null : id;
  }

  @override
  Future<List<CanvasPin>> fetchPins() async {
    final raw = await daemon.getCanvasPins(canvasId: canvasId);
    final list = _extractList(raw, const ['pins']);
    return [
      for (final item in list)
        if (item is Map) CanvasPin.fromJson(item.cast<String, dynamic>()),
    ];
  }

  @override
  Future<CanvasPin> createPin({
    required String frameId,
    String? elId,
    required double dx,
    required double dy,
    required String text,
  }) async {
    final json = await daemon.postCanvasPin({
      'frame_id': frameId,
      if (elId != null && elId.isNotEmpty) 'el_id': elId,
      'dx': dx,
      'dy': dy,
      'text': text,
    }, canvasId: canvasId);
    final payload = json['pin'] is Map
        ? (json['pin'] as Map).cast<String, dynamic>()
        : json;
    return CanvasPin.fromJson(payload);
  }

  @override
  Future<CanvasPin> patchPin(String pinId,
      {String? status, String? reply}) async {
    final json = await daemon.patchCanvasPin(pinId, {
      if (status != null) 'status': status,
      if (reply != null) 'reply': reply,
    }, canvasId: canvasId);
    final payload = json['pin'] is Map
        ? (json['pin'] as Map).cast<String, dynamic>()
        : json;
    return CanvasPin.fromJson(payload);
  }

  @override
  Future<List<CanvasOpBatch>> fetchOps({int since = 0}) async {
    final raw = await daemon.getCanvasOps(since: since, canvasId: canvasId);
    final list = _extractList(raw, const ['batches', 'ops']);
    return [
      for (final item in list)
        if (item is Map)
          CanvasOpBatch.fromJson(item.cast<String, dynamic>()),
    ];
  }

  @override
  Future<CanvasCardActivity?> fetchCardActivity(CanvasRef ref, int rev) async {
    try {
      final scoped = DaemonCanvasClient(daemon, canvasId: ref.canvasId);
      final results = await Future.wait([
        scoped.fetchOps(since: rev > 0 ? rev - 1 : 0),
        scoped.fetchPins(),
      ]);
      final ops = results[0] as List<CanvasOpBatch>;
      final pins = results[1] as List<CanvasPin>;
      CanvasOpBatch? last;
      for (final b in ops) {
        if (last == null || b.rev > last.rev) last = b;
      }
      final comments = pins
          .where((p) =>
              (ref.frameId == null || p.frameId == ref.frameId) &&
              (ref.elId == null || p.elId == ref.elId))
          .length;
      return CanvasCardActivity(
        author: last?.author,
        editedAt: last?.ts,
        comments: comments,
      );
    } catch (_) {
      return null;
    }
  }

  @override
  Future<int> revertBatch(String batchId) async {
    final json = await daemon.postCanvasRevert(batchId, canvasId: canvasId);
    return (json['rev'] as num?)?.toInt() ?? 0;
  }

  @override
  void dispose() {}

  static List<dynamic> _extractList(Object? raw, List<String> keys) {
    if (raw is List) return raw;
    if (raw is Map) {
      for (final k in keys) {
        final v = raw[k];
        if (v is List) return v;
      }
    }
    return const <dynamic>[];
  }
}
