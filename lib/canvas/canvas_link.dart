// Parser and formatter for `canvas:` markdown links:
// `[title](canvas:<canvas_id>/<frame_id>[/<el_id>][@<rev>])`.

final _revDigitsRe = RegExp(r'^\d+$');
final _whitespaceRe = RegExp(r'\s');
final _markdownCanvasLinkRe =
    RegExp(r'(?<!!)\[((?:\\.|[^\]\n])+)\]\(((?:canvas|artifact):[^)\s]+)\)');
final _bareCanvasLinkRe = RegExp(
    r'(?<![\w\](/:<])(?:canvas|artifact):[^\s)>\]…]*[^\s)>\].,;:!?…]');
final _standaloneBareCanvasLinkRe =
    RegExp(r'^<?((?:canvas|artifact):[^\s<>…]+)>?…?$');
final _standaloneCanvasLinkRe =
    RegExp(r'^\[((?:\\.|[^\]\n])+)\]\(((?:canvas|artifact):[^)\s]+)\)$');

String _unescapeLinkTitle(String raw) =>
    raw.trim().replaceAll(r'\[', '[').replaceAll(r'\]', ']');

/// A parsed `canvas:<canvas_id>[/<frame_id>[/<el_id>]][@<rev>]` reference.
class CanvasRef {
  const CanvasRef({
    required this.canvasId,
    this.frameId,
    this.elId,
    this.rev,
  });

  final String canvasId;
  final String? frameId;
  final String? elId;
  final int? rev;

  /// True when the link does not pin a specific revision (`@<rev>` omitted).
  bool get isLive => rev == null;

  /// Canonical `canvas:...` string representation.
  String format() => formatCanvasRef(
        canvasId: canvasId,
        frameId: frameId,
        elId: elId,
        rev: rev,
      );

  /// Formats this reference as a markdown link `[title](canvas:...)`.
  String formatMarkdown(String title) => '[$title](${format()})';

  @override
  bool operator ==(Object other) =>
      other is CanvasRef &&
      other.canvasId == canvasId &&
      other.frameId == frameId &&
      other.elId == elId &&
      other.rev == rev;

  @override
  int get hashCode => Object.hash(canvasId, frameId, elId, rev);

  @override
  String toString() => format();
}

/// Formats components into a canonical `canvas:` reference string.
String formatCanvasRef({
  required String canvasId,
  String? frameId,
  String? elId,
  int? rev,
}) {
  final buf = StringBuffer('canvas:')..write(Uri.encodeComponent(canvasId));
  if (frameId != null && frameId.isNotEmpty) {
    buf
      ..write('/')
      ..write(Uri.encodeComponent(frameId));
    if (elId != null && elId.isNotEmpty) {
      buf
        ..write('/')
        ..write(Uri.encodeComponent(elId));
    }
  }
  if (rev != null) {
    buf
      ..write('@')
      ..write(rev);
  }
  return buf.toString();
}

/// Parses a `canvas:<canvas_id>[/<frame_id>[/<el_id>]][@<rev>]` href.
/// Returns null if the href is not a valid `canvas:` reference.
CanvasRef? parseCanvasRef(String? href) {
  if (href == null) return null;
  final trimmed = href.trim();
  if (!trimmed.startsWith('canvas:')) return null;
  final body = trimmed.substring(7);
  if (body.isEmpty || _whitespaceRe.hasMatch(body)) return null;

  String pathPart = body;
  int? rev;
  final at = body.lastIndexOf('@');
  if (at >= 0) {
    final revStr = body.substring(at + 1);
    if (!_revDigitsRe.hasMatch(revStr)) return null;
    rev = int.tryParse(revStr);
    if (rev == null || rev < 0) return null;
    pathPart = body.substring(0, at);
  }

  final rawParts = pathPart.split('/');
  if (rawParts.isEmpty || rawParts.length > 3) return null;

  final parts = <String>[];
  for (final raw in rawParts) {
    if (raw.isEmpty) return null;
    String decoded;
    try {
      decoded = Uri.decodeComponent(raw);
    } catch (_) {
      return null;
    }
    if (decoded.isEmpty || _whitespaceRe.hasMatch(decoded)) return null;
    parts.add(decoded);
  }

  return CanvasRef(
    canvasId: parts[0],
    frameId: parts.length >= 2 ? parts[1] : null,
    elId: parts.length == 3 ? parts[2] : null,
    rev: rev,
  );
}

/// A parsed `artifact:<id>[@<rev>]` reference: a canvas id, or
/// `<session>/<artifact id>` for a document, image, PDF or file.
class ArtifactRef {
  const ArtifactRef(this.id, [this.rev]);
  final String id;
  final int? rev;

  String format() => rev == null ? 'artifact:$id' : 'artifact:$id@$rev';

  @override
  bool operator ==(Object other) =>
      other is ArtifactRef && other.id == id && other.rev == rev;

  @override
  int get hashCode => Object.hash(id, rev);
}

/// Parses an `artifact:<id>[@<rev>]` href; null when malformed.
ArtifactRef? parseArtifactRef(String? href) {
  if (href == null) return null;
  final t = href.trim();
  if (!t.startsWith('artifact:')) return null;
  var body = t.substring(9);
  int? rev;
  final at = body.lastIndexOf('@');
  if (at >= 0) {
    final r = body.substring(at + 1);
    if (!_revDigitsRe.hasMatch(r)) return null;
    rev = int.tryParse(r);
    body = body.substring(0, at);
  }
  if (body.isEmpty || _whitespaceRe.hasMatch(body)) return null;
  for (final part in body.split('/')) {
    if (part.isEmpty || part == '.' || part == '..') return null;
  }
  return ArtifactRef(body, rev);
}

/// A segment of chat markdown split around valid `canvas:` links.
sealed class CanvasMarkdownSegment {
  const CanvasMarkdownSegment();
}

class CanvasTextSegment extends CanvasMarkdownSegment {
  const CanvasTextSegment(this.text);
  final String text;
}

class CanvasCardSegment extends CanvasMarkdownSegment {
  const CanvasCardSegment({
    required this.title,
    required this.rawHref,
    required this.ref,
    required this.inline,
  });

  final String title;
  final String rawHref;
  final CanvasRef ref;

  /// True when the link appeared inside a sentence/line that was kept as
  /// markdown above the card; false when the link occupied the whole line.
  final bool inline;
}

/// A card for an `artifact:` link (canvas, document, image, PDF or file).
class ArtifactCardSegment extends CanvasMarkdownSegment {
  const ArtifactCardSegment({
    required this.title,
    required this.rawHref,
    required this.ref,
    required this.inline,
  });

  final String title;
  final String rawHref;
  final ArtifactRef ref;
  final bool inline;
}

CanvasMarkdownSegment? _cardFor(String href, String? title, bool inline) {
  if (href.startsWith('artifact:')) {
    final ref = parseArtifactRef(href);
    if (ref == null) return null;
    return ArtifactCardSegment(
      title: title ?? '',
      rawHref: href,
      ref: ref,
      inline: inline,
    );
  }
  final ref = parseCanvasRef(href);
  if (ref == null) return null;
  return CanvasCardSegment(
    title: title ?? ref.frameId ?? ref.canvasId,
    rawHref: href,
    ref: ref,
    inline: inline,
  );
}

/// Splits [markdown] into text and `canvas:` card segments while skipping
/// fenced code blocks and leaving malformed `canvas:` links in plain text.
List<CanvasMarkdownSegment> splitCanvasMarkdown(String markdown) {
  if (!markdown.contains('canvas:') && !markdown.contains('artifact:')) {
    return markdown.isEmpty ? const [] : [CanvasTextSegment(markdown)];
  }
  final out = <CanvasMarkdownSegment>[];
  final mdLines = <String>[];
  var inFence = false;
  var fenceChar = '';
  var fenceLen = 0;

  void flushMd() {
    if (mdLines.isEmpty) return;
    final chunk = mdLines.join('\n').trim();
    mdLines.clear();
    if (chunk.isNotEmpty) out.add(CanvasTextSegment(chunk));
  }

  for (final line in markdown.split('\n')) {
    final trimmed = line.trim();
    final fenceMatch = RegExp(r'^(`{3,}|~{3,})').firstMatch(trimmed);
    if (fenceMatch != null) {
      final run = fenceMatch.group(1)!;
      if (!inFence) {
        inFence = true;
        fenceChar = run[0];
        fenceLen = run.length;
      } else if (run[0] == fenceChar &&
          run.length >= fenceLen &&
          trimmed.substring(run.length).trim().isEmpty) {
        inFence = false;
      }
      mdLines.add(line);
      continue;
    }

    if (!inFence &&
        (trimmed.contains('canvas:') || trimmed.contains('artifact:'))) {
      final standalone = _standaloneCanvasLinkRe.firstMatch(trimmed);
      if (standalone != null) {
        final card = _cardFor(standalone.group(2)!,
            _unescapeLinkTitle(standalone.group(1)!), false);
        if (card != null) {
          flushMd();
          out.add(card);
          continue;
        }
      }

      final bare = _standaloneBareCanvasLinkRe.firstMatch(trimmed);
      if (bare != null) {
        final card = _cardFor(bare.group(1)!, null, false);
        if (card != null) {
          flushMd();
          out.add(card);
          continue;
        }
      }

      // Inline canvas links keep the surrounding markdown sentence and attach
      // preview cards directly below it.
      final inlineCards = <CanvasMarkdownSegment>[];
      for (final m in _markdownCanvasLinkRe.allMatches(line)) {
        if (_insideInlineCode(line, m.start)) continue;
        final card =
            _cardFor(m.group(2)!, _unescapeLinkTitle(m.group(1)!), true);
        if (card != null) inlineCards.add(card);
      }
      // Bare `canvas:` references inside a sentence, outside markdown links.
      final stripped = line.replaceAll(_markdownCanvasLinkRe, '');
      for (final m in _bareCanvasLinkRe.allMatches(stripped)) {
        if (_insideInlineCode(stripped, m.start)) continue;
        final card = _cardFor(m.group(0)!, null, true);
        if (card != null) inlineCards.add(card);
      }
      if (inlineCards.isNotEmpty) {
        mdLines.add(line);
        flushMd();
        out.addAll(inlineCards);
        continue;
      }
    }

    mdLines.add(line);
  }
  flushMd();
  return out;
}

bool _insideInlineCode(String line, int index) {
  var inCode = false;
  var ticks = 0;
  var i = 0;
  while (i < index) {
    if (line.codeUnitAt(i) == 0x60) {
      var run = 0;
      while (i + run < line.length && line.codeUnitAt(i + run) == 0x60) {
        run++;
      }
      if (!inCode) {
        inCode = true;
        ticks = run;
      } else if (run == ticks) {
        inCode = false;
        ticks = 0;
      }
      i += run;
    } else {
      i++;
    }
  }
  return inCode;
}
