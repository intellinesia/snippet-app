import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:snippet/api.dart';
import 'package:snippet/canvas/artifact_cards.dart';
import 'package:snippet/canvas/artifact_link_card.dart';
import 'package:snippet/canvas/canvas_card_client.dart';
import 'package:snippet/canvas/canvas_models.dart'
    show CanvasRevEvent, CanvasSnapshot, canvasCount;
import 'package:snippet/canvas/canvas_screen.dart' show canvasLoadMessage;
import 'package:snippet/canvas/canvas_link.dart';
import 'package:snippet/canvas/canvas_link_card.dart';
import 'package:snippet/chat/group_post.dart';
import 'package:snippet/chat/message_body.dart';
import 'package:snippet/screens/group_messaging.dart'
    show groupMarkdownWithMentions;
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
      const CanvasCardActivity(author: 'You', editedAt: null, comments: 2);

  @override
  Future<CanvasLinkMeta> resolveLink(CanvasRef ref) async {
    resolveCalls++;
    if (unreachable) throw const CanvasUnreachableException();
    if (unavailable) throw const CanvasUnavailableException();
    final preset = metaByRef[ref.format()];
    if (preset != null) {
      final key = ref.frameId ?? preset.frameId;
      final liveRev = ref.rev ?? _latestRevs[key] ?? preset.rev;
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
    final resolvedFrame = ref.frameId ?? 'first-frame';
    final rev = ref.rev ?? _latestRevs[resolvedFrame] ?? 1;
    return CanvasLinkMeta(
      canvasId: ref.canvasId,
      frameId: resolvedFrame,
      elId: ref.elId,
      rev: rev,
      title: ref.frameId ?? ref.canvasId,
      thumbUrl: '/canvas/frames/$resolvedFrame/thumb.png?rev=$rev',
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
  canvasLiteTests();
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

    test('parses and formats canvas-only refs with and without rev', () {
      final live = parseCanvasRef('canvas:x');
      expect(live, isNotNull);
      expect(live!.canvasId, 'x');
      expect(live.frameId, isNull);
      expect(live.elId, isNull);
      expect(live.rev, isNull);
      expect(live.isLive, isTrue);
      expect(live.format(), 'canvas:x');

      final pinned = parseCanvasRef('canvas:x@3');
      expect(pinned, isNotNull);
      expect(pinned!.canvasId, 'x');
      expect(pinned.frameId, isNull);
      expect(pinned.elId, isNull);
      expect(pinned.rev, 3);
      expect(pinned.isLive, isFalse);
      expect(pinned.format(), 'canvas:x@3');
      expect(formatCanvasRef(canvasId: 'x', rev: 3), 'canvas:x@3');
    });

    test('rejects malformed canvas refs', () {
      expect(parseCanvasRef(null), isNull);
      expect(parseCanvasRef(''), isNull);
      expect(parseCanvasRef('artifact:a/b'), isNull);
      expect(parseCanvasRef('canvas:'), isNull);
      expect(parseCanvasRef('canvas:@3'), isNull);
      expect(parseCanvasRef('canvas:x/'), isNull);
      expect(parseCanvasRef('canvas:/f'), isNull);
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
      final inline =
          splitCanvasMarkdown('See canvas:app/home/cta, then reply.');
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

  testWidgets('group thread renders canvas: links in all forms, also capped',
      (tester) async {
    final fake = _TestCanvasCardClient(
      metaByRef: {
        for (final ref in [
          'canvas:app/home',
          'canvas:app/pricing/cta',
          'canvas:app/phone@2'
        ])
          ref: CanvasLinkMeta(
            canvasId: 'app',
            frameId: ref.split('/')[1].split('@').first,
            rev: 2,
            title: 'Frame ${ref.split('/')[1]}',
            thumbUrl: '/canvas/frames/x/thumb.png',
            width: 390,
            height: 240,
          ),
      },
    );
    addTearDown(fake.dispose);
    final daemon = DaemonClient('https://daemon.invalid', 'test');
    const members = {'sashy', 'buddy'};
    Widget host(String body) => MaterialApp(
          theme: buildAppTheme(),
          home: Scaffold(
            body: SingleChildScrollView(
              child: CanvasCardClientScope(
                client: fake,
                child: CappedProse(
                  key: ValueKey(body),
                  body: body,
                  builder: (text) => ChatMessageBody(
                    client: daemon,
                    body: text,
                    mine: false,
                    markdown: (t) => groupMarkdownWithMentions(t, members),
                  ),
                ),
              ),
            ),
          ),
        );

    // Bare on its own line, inline in a sentence, and markdown, with a mention.
    await tester.pumpWidget(host(
        '@sashy look:\ncanvas:app/home\nAlso canvas:app/pricing/cta, thanks.\n[Phone](canvas:app/phone@2)'));
    await tester.pump();
    await tester.pump();
    // The cap keeps three lines; the fourth appears with Show more.
    expect(find.byType(CanvasLinkCard), findsNWidgets(2));
    await tester.tap(find.text('Show more'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(CanvasLinkCard), findsNWidgets(3));

    // A long agent post is cut with an ellipsis; a link at the cut must stay
    // a card for the right frame, not swallow the ellipsis.
    final long = '${'x ' * 70}canvas:app/home ${'b' * 30}';
    final preview = groupPostPreview(long)!;
    expect(preview.endsWith('…'), isTrue);
    await tester.pumpWidget(host('${'word ' * 40}\ncanvas:app/home'));
    await tester.pump();
    await tester.pump();
    expect(find.text('Show more'), findsOneWidget);
    await tester.tap(find.text('Show more'));
    await tester.pump();
    await tester.pump();
    expect(find.byType(CanvasLinkCard), findsOneWidget);
    expect(
        splitCanvasMarkdown('see canvas:app/home…')
            .whereType<CanvasCardSegment>()
            .single
            .ref
            .frameId,
        'home');
  });

  group('artifact: links', () {
    test('parses ids with slashes and revisions, rejects malformed', () {
      expect(parseArtifactRef('artifact:q4-board-1a2b3c'),
          const ArtifactRef('q4-board-1a2b3c'));
      expect(parseArtifactRef('artifact:s1/conversations/c9/report@3'),
          const ArtifactRef('s1/conversations/c9/report', 3));
      expect(parseArtifactRef('artifact:'), isNull);
      expect(parseArtifactRef('artifact:../x'), isNull);
      expect(parseArtifactRef('artifact:a b'), isNull);
      expect(parseArtifactRef('artifact:a@x'), isNull);
    });

    test('markdown, bare line and inline forms split into cards', () {
      final segs = splitCanvasMarkdown(
          'See [Report](artifact:s1/report)\nartifact:q4-board-1a\nand artifact:s2/x@2, ok\n`artifact:s/no`');
      final cards = segs.whereType<ArtifactCardSegment>().toList();
      expect(cards.map((c) => c.ref.id), ['s1/report', 'q4-board-1a', 's2/x']);
      expect(cards.first.title, 'Report');
      expect(cards[1].inline, isFalse);
      expect(cards.last.ref.rev, 2);
    });
  });

  testWidgets('artifact card resolves any kind and group chat renders it',
      (tester) async {
    final daemon = DaemonClient('https://daemon.invalid', 'test');
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Column(children: [
          ArtifactLinkCard(
            title: 'x',
            artifactRef: const ArtifactRef('s1/report'),
            daemonClient: daemon,
            resolver: (id) async => ArtifactCard(
              id: id,
              kind: 'pdf',
              title: 'Q4 report',
              rev: 2,
              author: 'user',
              updatedAt: DateTime.now(),
            ),
          ),
          ChatMessageBody(
            client: daemon,
            body: '@sashy see [Report](artifact:s1/report)',
            mine: false,
            markdown: (t) => groupMarkdownWithMentions(t, const {'sashy'}),
          ),
        ]),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(find.text('Q4 report'), findsOneWidget);
    expect(find.text('PDF · rev 2'), findsOneWidget);
    expect(find.text('By You, just now'), findsOneWidget);
    expect(find.text('Open'), findsOneWidget);
    expect(find.byType(ArtifactLinkCard), findsNWidgets(2));
  });

  test('canvasCount pluralises', () {
    expect(canvasCount(1, 'frame'), '1 frame');
    expect(canvasCount(0, 'frame'), '0 frames');
    expect(canvasCount(24, 'frame'), '24 frames');
  });

  testWidgets('narrow card drops the thumbnail and keeps a readable title',
      (tester) async {
    final daemon = DaemonClient('https://daemon.invalid', 'test');
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: Align(
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: 250,
            child: ArtifactLinkCard(
              title: 'x',
              artifactRef: const ArtifactRef('s1/report'),
              daemonClient: daemon,
              resolver: (id) async =>
                  ArtifactCard(id: id, kind: 'pdf', title: 'Q4 report', rev: 2),
            ),
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();
    expect(tester.getTopLeft(find.text('Q4 report')).dx, lessThan(40));
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
    pinnedClient
        .emitRev(const CanvasRevEvent(rev: 9, frameIds: ['home-screen']));
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

  testWidgets('canvas-only links split and render preview cards',
      (tester) async {
    final bare = splitCanvasMarkdown('See canvas:x@3 now');
    final bareCard = bare.whereType<CanvasCardSegment>().single;
    expect(bareCard.ref.canvasId, 'x');
    expect(bareCard.ref.frameId, isNull);
    expect(bareCard.ref.rev, 3);

    final standalone = splitCanvasMarkdown('canvas:x');
    final standaloneCard = standalone.whereType<CanvasCardSegment>().single;
    expect(standaloneCard.ref.canvasId, 'x');
    expect(standaloneCard.ref.frameId, isNull);
    expect(standaloneCard.title, 'x');

    final client = _TestCanvasCardClient(
      metaByRef: {
        'canvas:x': const CanvasLinkMeta(
          canvasId: 'x',
          frameId: 'first-frame',
          rev: 4,
          title: 'Pricing board',
          thumbUrl: '/canvas/frames/first-frame/thumb.png',
          width: 390,
          height: 240,
        ),
      },
    );
    addTearDown(client.dispose);

    final daemon = DaemonClient('https://daemon.invalid', 'test');
    await tester.pumpWidget(MaterialApp(
      theme: buildAppTheme(),
      home: Scaffold(
        body: CanvasCardClientScope(
          client: client,
          child: ChatMessageBody(
            client: daemon,
            body: '[Pricing board](canvas:x)',
            mine: false,
          ),
        ),
      ),
    ));
    await tester.pump();
    await tester.pump();

    expect(find.byType(CanvasLinkCard), findsOneWidget);
    expect(find.text('Pricing board'), findsOneWidget);
    expect(find.text('Canvas · rev 4'), findsOneWidget);
  });
}

void canvasLiteTests() {
  test('lite snapshot without html parses', () {
    final s = CanvasSnapshot.fromJson({
      'canvas_id': 'c',
      'rev': 4,
      'frames': [
        {'id': 'a', 'title': 'Home', 'x': 0, 'y': 0, 'w': 390, 'h': 800, 'rev': 1}
      ],
    });
    expect(s.frames.single.id, 'a');
    expect(s.rev, 4);
  });

  test('362-frame snapshot decodes, large bodies off the UI thread', () async {
    final frames = [
      for (var i = 0; i < 362; i++)
        {
          'id': 'f$i',
          'title': 'Frame $i',
          'x': i * 400.0,
          'y': 0,
          'w': 390,
          'h': 800,
          'rev': 1,
          'html': 'x' * 18000,
        }
    ];
    final body = jsonEncode({'canvas_id': 'big', 'rev': 9, 'frames': frames});
    expect(body.length, greaterThan(512 * 1024));
    final json = await decodeCanvasBody(body);
    final s = CanvasSnapshot.fromJson(json);
    expect(s.frames.length, 362);
    expect(s.frames.last.id, 'f361');
  });

  test('load failures read as real messages', () {
    expect(canvasLoadMessage(TimeoutException('x')), contains('too long'));
    expect(canvasLoadMessage('boom'), 'boom');
  });
}
