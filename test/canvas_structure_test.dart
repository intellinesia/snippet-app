import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/canvas/canvas_minimap.dart';
import 'package:snippet/canvas/canvas_models.dart';
import 'package:snippet/canvas/canvas_outline.dart';

CanvasElementRect _el(String id, double x, double y, double w, double h,
        {String tag = '', String text = ''}) =>
    CanvasElementRect(id: id, x: x, y: y, w: w, h: h, tag: tag, text: text);

void main() {
  group('outline', () {
    final rects = [
      _el('hd-01', 0, 0, 400, 80, tag: 'header'),
      _el('ti-02', 16, 16, 200, 30, tag: 'h1', text: 'Home'),
      _el('bt-03', 16, 200, 100, 40, tag: 'button', text: 'Create'),
      _el('', 0, 0, 1, 1),
    ];

    test('nests by containment and skips id-less rects', () {
      final rows = buildOutline(rects);
      expect(rows.map((r) => r.element.id), ['hd-01', 'ti-02', 'bt-03']);
      expect(rows.map((r) => r.depth), [0, 1, 0]);
      expect(rows[1].label, 'Home');
    });

    test('filters by id, tag and text, and frames by title', () {
      final rows = buildOutline(rects);
      expect(filterOutline(rows, 'BUTTON').single.element.id, 'bt-03');
      expect(filterOutline(rows, 'ti-0').single.element.id, 'ti-02');
      expect(filterOutline(rows, ' '), hasLength(3));
      const frames = [
        CanvasFrame(id: 'home', title: 'Home', x: 0, y: 0, w: 1, h: 1, rev: 1),
        CanvasFrame(id: 'new', title: 'Create sheet', x: 0, y: 0, w: 1, h: 1, rev: 1),
      ];
      expect(filterFrames(frames, 'sheet').single.id, 'new');
    });
  });

  group('minimap', () {
    test('round trips and always contains the viewport', () {
      const content = Rect.fromLTWH(0, 0, 4000, 2000);
      const view = Rect.fromLTWH(3500, 1800, 1200, 800);
      final g = MinimapGeometry.fit(content, view, const Size(160, 108));
      final mapped = g.mapRect(view);
      expect(mapped.left, greaterThanOrEqualTo(0));
      expect(mapped.right, lessThanOrEqualTo(160.01));
      expect(mapped.bottom, lessThanOrEqualTo(108.01));
      final p = g.mapToWorld(g.worldToMap(const Offset(1234, 567)));
      expect((p - const Offset(1234, 567)).distance, lessThan(1e-6));
    });

    test('centerOn puts the world point at the viewport centre', () {
      final c = centerOn(const Offset(1000, 500), const Size(800, 600), 0.5);
      expect(1000 * 0.5 + c.tx, 400);
      expect(500 * 0.5 + c.ty, 300);
    });
  });
}
