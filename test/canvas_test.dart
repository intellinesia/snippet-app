import 'dart:ui' show Offset, Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/canvas/canvas_client.dart';
import 'package:snippet/canvas/canvas_link.dart';
import 'package:snippet/canvas/canvas_models.dart';
import 'package:snippet/canvas/spatial_index.dart';
import 'package:snippet/canvas/thumb_cache.dart';

void main() {
  group('parseCanvasAuthor', () {
    test('maps user and agent shapes to readable names', () {
      expect(parseCanvasAuthor({'id': 'user', 'kind': 'user'}), 'You');
      expect(parseCanvasAuthor({'id': 'a1', 'kind': 'agent', 'name': 'Lead'}),
          'Lead');
      expect(parseCanvasAuthor({'id': 'a1', 'kind': 'agent'}), 'a1');
      expect(parseCanvasAuthor(null), 'Agent');
      expect(parseCanvasAuthor('user'), 'You');
    });
  });
  group('CanvasSpatialIndex', () {
    test('culls 2000 synthetic frames to only viewport-intersecting frames', () {
      const cols = 50;
      const rows = 40;
      const frameW = 360.0;
      const frameH = 640.0;
      const gapX = 80.0;
      const gapY = 100.0;

      final frames = List<CanvasFrame>.generate(cols * rows, (i) {
        final col = i % cols;
        final row = i ~/ cols;
        return CanvasFrame(
          id: 'syn-$i',
          title: 'Frame $i',
          x: col * (frameW + gapX),
          y: row * (frameH + gapY),
          w: frameW,
          h: frameH,
          rev: 1,
        );
      });

      final index = CanvasSpatialIndex(cellSize: 1024.0)..rebuild(frames);
      expect(index.length, 2000);
      expect(index.contentBounds, isNotNull);

      // A 1280x800 desktop viewport positioned over frames (10,10)..(12,11).
      final viewport = Rect.fromLTWH(
        10 * (frameW + gapX) - 20,
        10 * (frameH + gapY) - 20,
        1280,
        800,
      );
      final visible = index.query(viewport);

      // Must return exact matches with zero duplicates and tiny draw count.
      final expected = frames
          .where((f) => f.bounds.overlaps(viewport))
          .map((f) => f.id)
          .toSet();
      final actual = visible.map((f) => f.id).toSet();

      expect(actual, expected);
      expect(visible.length, expected.length);
      expect(visible.length, lessThanOrEqualTo(12));
    });

    test('handles frames spanning multiple 1024-cell boundaries without duplicates',
        () {
      const wideFrame = CanvasFrame(
        id: 'wide',
        title: 'Wide',
        x: 900,
        y: 900,
        w: 2400,
        h: 1500,
        rev: 2,
      );
      const farFrame = CanvasFrame(
        id: 'far',
        title: 'Far',
        x: 12000,
        y: 12000,
        w: 300,
        h: 300,
        rev: 2,
      );

      final index = CanvasSpatialIndex(cellSize: 1024.0)
        ..rebuild([wideFrame, farFrame]);

      final hits = index.query(const Rect.fromLTWH(800, 800, 2600, 1700));
      expect(hits.map((f) => f.id).toList(), ['wide']);
      expect(index.hitTestFrame(1500, 1500)?.id, 'wide');
      expect(index.hitTestFrame(5000, 5000), isNull);
    });

    test('handles negative coordinates cleanly', () {
      const negFrame = CanvasFrame(
        id: 'neg',
        title: 'Neg',
        x: -2500,
        y: -1800,
        w: 400,
        h: 600,
        rev: 1,
      );
      final index = CanvasSpatialIndex(cellSize: 1024.0)..rebuild([negFrame]);
      final hits = index.query(const Rect.fromLTWH(-2600, -1900, 600, 800));
      expect(hits.length, 1);
      expect(hits.first.id, 'neg');
      expect(index.hitTestFrame(-2300, -1500)?.id, 'neg');
    });

    test('preserves frame z-order across cell boundaries and skips non-finite bounds',
        () {
      const f1 = CanvasFrame(
        id: 'bottom',
        title: 'Bottom',
        x: 900,
        y: 0,
        w: 400,
        h: 400,
        rev: 1,
      );
      const f2 = CanvasFrame(
        id: 'top',
        title: 'Top',
        x: 0,
        y: 0,
        w: 1200,
        h: 400,
        rev: 1,
      );
      const bad = CanvasFrame(
        id: 'bad',
        title: 'Bad',
        x: double.nan,
        y: 0,
        w: 100,
        h: 100,
        rev: 1,
      );

      final index = CanvasSpatialIndex(cellSize: 1024.0)
        ..rebuild([f1, f2, bad]);
      expect(index.length, 2);
      final hits = index.query(const Rect.fromLTWH(0, 0, 1400, 500));
      expect(hits.map((f) => f.id).toList(), ['bottom', 'top']);
    });
  });

  group('ThumbLruCache', () {
    test('evicts least-recently-used entries when byte budget is exceeded', () {
      final evicted = <ThumbCacheKey>[];
      final cache = ThumbLruCache<String>(
        maxBytes: 1000,
        onEvict: (key, _) => evicted.add(key),
      );

      const k1 = ThumbCacheKey(frameId: 'f1', rev: 1, scale: 1.0);
      const k2 = ThumbCacheKey(frameId: 'f2', rev: 1, scale: 1.0);
      const k3 = ThumbCacheKey(frameId: 'f3', rev: 1, scale: 1.0);

      cache.put(k1, 'img1', 400);
      cache.put(k2, 'img2', 400);
      expect(cache.currentBytes, 800);

      // Promote k1 to MRU so k2 becomes the LRU candidate.
      expect(cache.get(k1), 'img1');

      cache.put(k3, 'img3', 400);
      expect(cache.currentBytes, 800);
      expect(cache.containsKey(k1), isTrue);
      expect(cache.containsKey(k2), isFalse);
      expect(cache.containsKey(k3), isTrue);
      expect(evicted, [k2]);
      expect(cache.evictionCount, 1);
    });

    test('drops oversized single entry without evicting existing cached entries',
        () {
      final evicted = <ThumbCacheKey>[];
      final cache = ThumbLruCache<String>(
        maxBytes: 500,
        onEvict: (key, _) => evicted.add(key),
      );
      const keep = ThumbCacheKey(frameId: 'small', rev: 1, scale: 1.0);
      const big = ThumbCacheKey(frameId: 'huge', rev: 1, scale: 2.0);
      cache.put(keep, 'small-img', 200);
      cache.put(big, 'huge-img', 1200);
      expect(cache.length, 1);
      expect(cache.currentBytes, 200);
      expect(cache.containsKey(keep), isTrue);
      expect(evicted, [big]);
    });

    test('pickThumbScaleBucket maps zoom * dpr onto 0.25/0.5/1/2 buckets', () {
      expect(pickThumbScaleBucket(0.2, devicePixelRatio: 1.0), 0.25);
      expect(pickThumbScaleBucket(0.5, devicePixelRatio: 1.0), 0.5);
      expect(pickThumbScaleBucket(1.0, devicePixelRatio: 1.0), 1.0);
      expect(pickThumbScaleBucket(1.0, devicePixelRatio: 2.0), 2.0);
    });
  });

  group('Canvas link formatting and element hit-testing', () {
    test('formats frame-only and element markdown links with rev', () {
      expect(
        formatCanvasUri(canvasId: 'c1', frameId: 'home', rev: 7),
        'canvas:c1/home@7',
      );
      expect(
        formatCanvasUri(
            canvasId: 'c1', frameId: 'home', elId: 'hero-cta', rev: 7),
        'canvas:c1/home/hero-cta@7',
      );
      expect(
        formatCanvasMarkdownLink(
          title: 'Home Desktop',
          canvasId: 'c1',
          frameId: 'home',
          rev: 7,
        ),
        '[Home Desktop](canvas:c1/home@7)',
      );
      expect(
        formatCanvasMarkdownLink(
          title: 'Home [v11]',
          canvasId: 'c1',
          frameId: 'home',
          elId: 'hero-cta',
          rev: 12,
        ),
        r'[Home \[v11\]](canvas:c1/home/hero-cta@12)',
      );
    });

    test('hitTestCanvasElements selects deepest (smallest area) containing rect',
        () {
      const rects = <CanvasElementRect>[
        CanvasElementRect(id: 'root', x: 0, y: 0, w: 960, h: 640),
        CanvasElementRect(id: 'card-0', x: 20, y: 80, w: 400, h: 120),
        CanvasElementRect(id: 'card-0-btn', x: 300, y: 120, w: 96, h: 36),
      ];

      expect(
        hitTestCanvasElements(rects, const Offset(340, 140))?.id,
        'card-0-btn',
      );
      expect(
        hitTestCanvasElements(rects, const Offset(50, 100))?.id,
        'card-0',
      );
      expect(
        hitTestCanvasElements(rects, const Offset(800, 500))?.id,
        'root',
      );
      expect(
        hitTestCanvasElements(rects, const Offset(1200, 500)),
        isNull,
      );
    });

    test('share link with brackets round-trips through splitCanvasMarkdown', () {
      final md = formatCanvasMarkdownLink(
        title: 'Home [v11]',
        canvasId: 'c1',
        frameId: 'home',
        elId: 'hero-cta',
        rev: 12,
      );
      final segs = splitCanvasMarkdown(md);
      expect(segs.length, 1);
      final card = segs.single as CanvasCardSegment;
      expect(card.title, 'Home [v11]');
      expect(card.ref.canvasId, 'c1');
      expect(card.ref.frameId, 'home');
      expect(card.ref.elId, 'hero-cta');
      expect(card.ref.rev, 12);
    });

    test('pinWorldAnchor resolves element and frame fractional anchors', () {
      const frame = CanvasFrame(
        id: 'f1',
        title: 'F1',
        x: 100,
        y: 200,
        w: 400,
        h: 800,
        rev: 1,
      );
      const layouts = {
        'f1': [
          CanvasElementRect(id: 'cta', x: 50, y: 100, w: 200, h: 40),
        ],
      };
      const elPin = CanvasPin(
        id: 'p1',
        frameId: 'f1',
        elId: 'cta',
        dx: 0.5,
        dy: 0.25,
        text: 'note',
      );
      expect(pinWorldAnchor(elPin, frame, layouts), const Offset(250, 310));

      const framePin = CanvasPin(
        id: 'p2',
        frameId: 'f1',
        dx: 0.25,
        dy: 0.5,
        text: 'note',
      );
      expect(pinWorldAnchor(framePin, frame, layouts), const Offset(200, 600));
    });

    test('DaemonClient.canvasAssetUri enforces same-origin auth', () {
      final client = DaemonClient('https://daemon.example:8443', 'secret-tok');
      final authed = client.canvasAssetUri('/canvas/frames/f1/thumb.png', rev: 3);
      expect(authed.origin, 'https://daemon.example:8443');
      expect(authed.queryParameters['token'], 'secret-tok');
      expect(authed.queryParameters['rev'], '3');

      final signed = client.canvasAssetUri('/canvas/frames/f1/thumb.png?sig=abc');
      expect(signed.queryParameters['sig'], 'abc');
      expect(signed.queryParameters.containsKey('token'), isFalse);

      expect(
        () => client.canvasAssetUri('https://evil.example/leak.png'),
        throwsFormatException,
      );
    });

    test('DaemonCanvasClient.parseLayoutRects handles map and list layouts', () {
      final fromMap = DaemonCanvasClient.parseLayoutRects({
        'frame': {'width': 390, 'height': 844},
        'elements': {
          'cta': {'x': 10, 'y': 20, 'width': 120, 'height': 44},
        },
      });
      expect(fromMap.length, 1);
      expect(fromMap.first.id, 'cta');
      expect(fromMap.first.w, 120);

      final fromNodes = DaemonCanvasClient.parseLayoutRects({
        'nodes': [
          {'data-cv-id': 'hero', 'x': 0, 'y': 0, 'w': 300, 'h': 80},
        ],
      });
      expect(fromNodes.length, 1);
      expect(fromNodes.first.id, 'hero');
    });
  });
}
