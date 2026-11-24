// Parser and formatter for `canvas:` markdown links:
// `[title](canvas:<canvas_id>/<frame_id>[/<el_id>][@<rev>])`.

final _revDigitsRe = RegExp(r'^\d+$');
final _whitespaceRe = RegExp(r'\s');
final _markdownCanvasLinkRe =
    RegExp(r'(?<!!)\[((?:\\.|[^\]\n])+)\]\((canvas:[^)\s]+)\)');
final _bareCanvasLinkRe = RegExp(r'(?<![\w\](/:<])canvas:[^\s)>\]]*[^\s)>\].,;:!?]');
final _standaloneBareCanvasLinkRe = RegExp(r'^<?(canvas:[^\s<>]+)>?$');
final _standaloneCanvasLinkRe =
    RegExp(r'^\[((?:\\.|[^\]\n])+)\]\((canvas:[^)\s]+)\)$');

String _unescapeLinkTitle(String raw) =>
    raw.trim().replaceAll(r'\[', '[').replaceAll(r'\]', ']');

/// A parsed `canvas:<canvas_id>/<frame_id>[/<el_id>][@<rev>]` reference.
class CanvasRef {
  const CanvasRef({
    required this.canvasId,
    required this.frameId,
    this.elId,
    this.rev,
  });

  final String canvasId;
  final String frameId;
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
  required String frameId,
  String? elId,
  int? rev,
}) {
  final buf = StringBuffer('canvas:')
    ..write(Uri.encodeComponent(canvasId))
    ..write('/')
    ..write(Uri.encodeComponent(frameId));
  if (elId != null && elId.isNotEmpty) {
    buf
      ..write('/')
      ..write(Uri.encodeComponent(elId));
  }
  if (rev != null) {
    buf
      ..write('@')
      ..write(rev);
  }
  return buf.toString();
}

/// Parses a `canvas:<canvas_id>/<frame_id>[/<el_id>][@<rev>]` href.
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
  if (rawParts.length < 2 || rawParts.length > 3) return null;

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
    frameId: parts[1],
    elId: parts.length == 3 ? parts[2] : null,
    rev: rev,
  );
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

/// Splits [markdown] into text and `canvas:` card segments while skipping
/// fenced code blocks and leaving malformed `canvas:` links in plain text.
List<CanvasMarkdownSegment> splitCanvasMarkdown(String markdown) {
  if (!markdown.contains('canvas:')) {
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

    if (!inFence && trimmed.contains('canvas:')) {
      final standalone = _standaloneCanvasLinkRe.firstMatch(trimmed);
      if (standalone != null) {
        final title = _unescapeLinkTitle(standalone.group(1)!);
        final href = standalone.group(2)!;
        final ref = parseCanvasRef(href);
        if (ref != null) {
          flushMd();
          out.add(CanvasCardSegment(
            title: title,
            rawHref: href,
            ref: ref,
            inline: false,
          ));
          continue;
        }
      }

      final bare = _standaloneBareCanvasLinkRe.firstMatch(trimmed);
      if (bare != null) {
        final href = bare.group(1)!;
        final ref = parseCanvasRef(href);
        if (ref != null) {
          flushMd();
          out.add(CanvasCardSegment(
            title: ref.frameId,
            rawHref: href,
            ref: ref,
            inline: false,
          ));
          continue;
        }
      }

      // Inline canvas links keep the surrounding markdown sentence and attach
      // preview cards directly below it.
      final inlineCards = <CanvasCardSegment>[];
      for (final m in _markdownCanvasLinkRe.allMatches(line)) {
        if (_insideInlineCode(line, m.start)) continue;
        final ref = parseCanvasRef(m.group(2));
        if (ref == null) continue;
        inlineCards.add(CanvasCardSegment(
          title: _unescapeLinkTitle(m.group(1)!),
          rawHref: m.group(2)!,
          ref: ref,
          inline: true,
        ));
      }
      // Bare `canvas:` references inside a sentence, outside markdown links.
      final stripped = line.replaceAll(_markdownCanvasLinkRe, '');
      for (final m in _bareCanvasLinkRe.allMatches(stripped)) {
        final ref = parseCanvasRef(m.group(0));
        if (ref == null || _insideInlineCode(stripped, m.start)) continue;
        inlineCards.add(CanvasCardSegment(
          title: ref.frameId,
          rawHref: m.group(0)!,
          ref: ref,
          inline: true,
        ));
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
