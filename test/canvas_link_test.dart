import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/canvas/canvas_card_client.dart';
import 'package:snippet/canvas/canvas_models.dart' show CanvasRevEvent;
import 'package:snippet/canvas/canvas_link.dart';
import 'package:snippet/canvas/canvas_link_card.dart';
import 'package:snippet/chat/message_body.dart';
import 'package:snippet/theme.dart';

final Uint8List _testPngBytes = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg==',
);

class _TestCanvasCardClient implements CanvasCardClient {
  _TestCanvasCardClient({
    this.metaByRef = const {},
    this.layouts = const {},
    this.unreachable = false,
    this.unavailable = false,
  });

  final Map<String, CanvasLinkMeta> metaByRef;
  final Map<String, CanvasLayout> layouts;
  final bool unreachable;
  final bool unavailable;

  final _revController = StreamController<CanvasRevEvent>.broadcast();
  final Map<String, int> _latestRevs = {};
  int resolveCalls = 0;

  void emitRev(CanvasRevEvent event) {
    for (final id in event.frameIds) {
      _latestRevs[id] = event.rev;
    }
    _revController.add(event);
  }

  void dispose() => _revController.close();

  @override
  Stream<CanvasRevEvent> get revEvents => _revController.stream;

  @override
  Stream<void> get onReconnected => const Stream.empty();

  @override
  Future<CanvasCardActivity?> fetchCardActivity(CanvasRef ref, int rev) async =>
      const CanvasCardActivity(
          author: 'You', editedAt: null, comments: 2);

  @override
  Future<CanvasLinkMeta> resolveLink(CanvasRef ref) async {
    resolveCalls++;
    if (unreachable) throw const CanvasUnreachableException();
    if (unavailable) throw const CanvasUnavailableException();
    final preset = metaByRef[ref.format()];
    if (preset != null) {
      final liveRev = ref.rev ?? _latestRevs[ref.frameId] ?? preset.rev;
      return CanvasLinkMeta(
        canvasId: preset.canvasId,
        frameId: preset.frameId,
        elId: preset.elId,
        rev: liveRev,
        title: preset.title,
        thumbUrl: preset.thumbUrl,
        width: preset.width ?? 390,
        height: preset.height ?? 240,
      );
    }
    final rev = ref.rev ?? _latestRevs[ref.frameId] ?? 1;
    return CanvasLinkMeta(
      canvasId: ref.canvasId,
      frameId: ref.frameId,
      elId: ref.elId,
      rev: rev,
      title: ref.frameId,
      thumbUrl: '/canvas/frames/${ref.frameId}/thumb.png?rev=$rev',
      width: 390,
      height: 240,
    );
  }

  @override
  Future<CanvasLayout?> fetchCardLayout(
    String frameId, {
    String? canvasId,
    int? rev,
  }) async =>
      layouts[frameId];

  @override
  ImageProvider imageProvider(String thumbUrl, {int? rev}) =>
      MemoryImage(_testPngBytes);
}

void main() {
  group('canvas: link parser and formatter', () {
    test('parses and formats canvas/frame without el or rev', () {
      final ref = parseCanvasRef('canvas:design-1/hero-frame');
      expect(ref, isNotNull);
      expect(ref!.canvasId, 'design-1');
      expect(ref.frameId, 'hero-frame');
      expect(ref.elId, isNull);
      expect(ref.rev, isNull);
      expect(ref.isLive, isTrue);
      expect(ref.format(), 'canvas:design-1/hero-frame');
    });

    test('parses and formats canvas/frame with rev and no el', () {
      final ref = parseCanvasRef('canvas:design-1/hero-frame@7');
      expect(ref, isNotNull);
      expect(ref!.canvasId, 'design-1');
      expect(ref.frameId, 'hero-frame');
      expect(ref.elId, isNull);
      expect(ref.rev, 7);
      expect(ref.isLive, isFalse);
      expect(ref.format(), 'canvas:design-1/hero-frame@7');
    });

    test('parses and formats canvas/frame/el without rev', () {
      final ref = parseCanvasRef('canvas:design-1/hero-frame/cta-btn');
      expect(ref, isNotNull);
      expect(ref!.canvasId, 'design-1');
      expect(ref.frameId, 'hero-frame');
      expect(ref.elId, 'cta-btn');
      expect(ref.rev, isNull);
      expect(ref.isLive, isTrue);
      expect(ref.format(), 'canvas:design-1/hero-frame/cta-btn');
    });

    test('parses and formats canvas/frame/el with rev', () {
      final ref = parseCanvasRef('canvas:design-1/hero-frame/cta-btn@12');
      expect(ref, isNotNull);
      expect(ref!.canvasId, 'design-1');
      expect(ref.frameId, 'hero-frame');
      expect(ref.elId, 'cta-btn');
      expect(ref.rev, 12);
      expect(ref.isLive, isFalse);
      expect(ref.format(), 'canvas:design-1/hero-frame/cta-btn@12');
      expect(
        formatCanvasRef(
          canvasId: 'design-1',
          frameId: 'hero-frame',
          elId: 'cta-btn',
          rev: 12,
        ),
        'canvas:design-1/hero-frame/cta-btn@12',
      );
    });

    test('rejects malformed canvas refs', () {
      expect(parseCanvasRef(null), isNull);
      expect(parseCanvasRef(''), isNull);
      expect(parseCanvasRef('artifact:a/b'), isNull);
      expect(parseCanvasRef('canvas:'), isNull);
      expect(parseCanvasRef('canvas:only-canvas'), isNull);
      expect(parseCanvasRef('canvas:c/f/'), isNull);
      expect(parseCanvasRef('canvas:c/f/el/extra'), isNull);
      expect(parseCanvasRef('canvas:c/f@'), isNull);
      expect(parseCanvasRef('canvas:c/f@abc'), isNull);
      expect(parseCanvasRef('canvas:c/f@-1'), isNull);
      expect(parseCanvasRef('canvas:c/f with space'), isNull);
    });
  });

  group('bare canvas: links', () {
    test('standalone line and inline sentence become cards', () {
      final lone = splitCanvasMarkdown('Look:\ncanvas:app/home@3\nthanks');
      expect(lone.whereType<CanvasCardSegment>().single.ref.rev, 3);
      final inline = splitCanvasMarkdown('See canvas:app/home/cta, then reply.');
      final card = inline.whereType<CanvasCardSegment>().single;
      expect(card.ref.elId, 'cta');
      expect(card.inline, isTrue);
    });

    test('markdown link is not duplicated and code is skipped', () {
      expect(
        splitCanvasMarkdown('[a](canvas:app/home) here')
            .whereType<CanvasCardSegment>()
            .length,
        1,
      );
      expect(
        splitCanvasMarkdown('use `canvas:app/home` literally')
            .whereType<CanvasCardSegment>(),
        isEmpty,
      );
    });
  });

  testWidgets('canvas: link in chat transcript renders CanvasLinkCard',
      (tester) async {
    final fake = _TestCanvasCardClient(
      metaByRef: {
        'canvas:app/home-screen/cta': const CanvasLinkMeta(
          canvasId: 'app',
          frameId: 'home-screen',
          elId: 'cta',
          rev: 4,
          title: 'Home screen',
          thumbUrl: '/canvas/frames/home-screen/thumb.png',
          width: 390,
          height: 240,
        ),
      },
      layouts: {
        'home-screen': const CanvasLayout(
          frameWidth: 390,
          frameHeight: 240,
          elements: {
            'cta': CanvasElementBox(x: 24, y: 120, w: 140, h: 44),
          },
        ),
      },
    );
    addTearDown(fake.dispose);

    final daemon = DaemonClient('https://daemon.invalid', 'test');
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: CanvasCardClientScope(
          client: fake,
          child: ChatMessageBody(
            client: daemon,
            body: '[Home screen](canvas:app/home-screen/cta)',
            mine: false,
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.byType(CanvasLinkCard), findsOneWidget);
    expect(find.text('Home screen'), findsOneWidget);
    expect(find.text('Canvas · rev 4'), findsOneWidget);
    expect(find.text('live'), findsOneWidget);

    // Live card refreshes its revision when a canvas_rev event arrives.
    fake.emitRev(const CanvasRevEvent(rev: 5, frameIds: ['home-screen']));
    await tester.pump();
    await tester.pump();
    expect(find.text('Canvas · rev 5'), findsOneWidget);
  });

  testWidgets('pinned @rev card ignores live events and unreachable falls back',
      (tester) async {
    final pinnedClient = _TestCanvasCardClient(
      metaByRef: {
        'canvas:app/home-screen@3': const CanvasLinkMeta(
          canvasId: 'app',
          frameId: 'home-screen',
          rev: 3,
          title: 'Pinned screen',
          thumbUrl: '/canvas/frames/home-screen/thumb.png',
          width: 390,
          height: 240,
        ),
      },
    );
    addTearDown(pinnedClient.dispose);

    final daemon = DaemonClient('https://daemon.invalid', 'test');
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: CanvasCardClientScope(
          client: pinnedClient,
          child: ChatMessageBody(
            client: daemon,
            body: '[Pinned screen](canvas:app/home-screen@3)',
            mine: false,
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('Canvas · rev 3'), findsOneWidget);
    expect(find.text('live'), findsNothing);

    final callsBefore = pinnedClient.resolveCalls;
    pinnedClient.emitRev(const CanvasRevEvent(rev: 9, frameIds: ['home-screen']));
    await tester.pump();
    expect(pinnedClient.resolveCalls, callsBefore);

    final offlineClient = _TestCanvasCardClient(unreachable: true);
    addTearDown(offlineClient.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: CanvasCardClientScope(
          client: offlineClient,
          child: ChatMessageBody(
            client: daemon,
            body: '[Fallback frame](canvas:app/home-screen)',
            mine: false,
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('Fallback frame'), findsOneWidget);
    expect(find.text('Canvas · rev 1'), findsNothing);

    final missingClient = _TestCanvasCardClient(unavailable: true);
    addTearDown(missingClient.dispose);
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: CanvasCardClientScope(
          client: missingClient,
          child: ChatMessageBody(
            client: daemon,
            body: '[Deleted frame](canvas:app/missing)',
            mine: false,
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('Frame unavailable'), findsOneWidget);
  });
}
