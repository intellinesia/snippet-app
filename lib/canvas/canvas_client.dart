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
  DaemonCanvasClient(this.daemon);

  final DaemonClient daemon;

  static final Expando<DaemonCanvasClient> _cache =
      Expando<DaemonCanvasClient>('DaemonCanvasClient');

  /// Stable shared instance per [DaemonClient], used by link cards.
  factory DaemonCanvasClient.forDaemon(DaemonClient daemon) =>
      _cache[daemon] ??= DaemonCanvasClient(daemon);

  @override
  Future<CanvasLinkMeta> resolveLink(CanvasRef ref) async {
    try {
      final json = await daemon.canvasLink(ref.format());
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
    final json = await daemon.getCanvas();
    return CanvasSnapshot.fromJson(json);
  }

  @override
  Future<Uint8List> fetchThumbPng(String frameId, double scale,
          {int? rev}) =>
      daemon.getCanvasThumbPng(frameId, scale, rev: rev);

  @override
  Future<List<CanvasElementRect>> fetchLayout(String frameId,
      {int? rev}) async {
    final raw = await daemon.getCanvasLayout(frameId, rev: rev);
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
    final json = await daemon.postCanvasHit(frameId, x, y);
    final id = json['el_id']?.toString();
    return (id == null || id.isEmpty) ? null : id;
  }

  @override
  Future<List<CanvasPin>> fetchPins() async {
    final raw = await daemon.getCanvasPins();
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
    });
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
    });
    final payload = json['pin'] is Map
        ? (json['pin'] as Map).cast<String, dynamic>()
        : json;
    return CanvasPin.fromJson(payload);
  }

  @override
  Future<List<CanvasOpBatch>> fetchOps({int since = 0}) async {
    final raw = await daemon.getCanvasOps(since: since);
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
      final results = await Future.wait([
        fetchOps(since: rev > 0 ? rev - 1 : 0),
        fetchPins(),
      ]);
      final ops = results[0] as List<CanvasOpBatch>;
      final pins = results[1] as List<CanvasPin>;
      CanvasOpBatch? last;
      for (final b in ops) {
        if (last == null || b.rev > last.rev) last = b;
      }
      final comments = pins
          .where((p) =>
              p.frameId == ref.frameId &&
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
    final json = await daemon.postCanvasRevert(batchId);
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
