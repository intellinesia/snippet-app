import 'package:flutter/painting.dart';

import 'theme.dart';

final _fence = RegExp(r'```[^\n]*\n?');
final _link = RegExp(r'!?\[([^\]]*)\]\([^)]*\)');
final _heading = RegExp(r'^\s{0,3}#{1,6}\s+', multiLine: true);
final _bullet = RegExp(r'^\s*(?:[-*+]|\d+\.)\s+', multiLine: true);
final _inlineBullet = RegExp(r'([:;.!?])\s+(?:[-*+]|\d+\.)\s+(?=\S)');
final _quote = RegExp(r'^\s*>\s?', multiLine: true);
final _emph = RegExp(r'(\*\*|__|~~|`)');
final _ws = RegExp(r'\s+');

/// One line of text from markdown: block syntax goes, inline marks stay.
String flattenMarkdown(String raw) => raw
    .replaceAll(_fence, '')
    .replaceAllMapped(_link, (m) => m[1] ?? '')
    .replaceAll(_heading, '')
    .replaceAll(_bullet, '')
    .replaceAll(_quote, '')
    .split('\n')
    .map((l) => l.replaceAll(_ws, ' ').trim())
    .where((l) => l.isNotEmpty)
    .join(' · ')
    .replaceAll(': · ', ': ')
    // A body already collapsed to one line still carries `: - item`.
    .replaceAllMapped(_inlineBullet, (m) => '${m[1]} ');

String plainPreview(String raw) => flattenMarkdown(raw).replaceAll(_emph, '');

final _inline = RegExp(
  r'`([^`]+)`'
  r'|\*\*(.+?)\*\*'
  r'|__(.+?)__'
  r'|~~(.+?)~~'
  r'|(?<![\w*])\*(?![\s*])(.+?)(?<![\s*])\*(?![\w*])'
  r'|(?<![\w_])_(?![\s_])(.+?)(?<![\s_])_(?![\w_])',
);

/// Inline markdown in a one-line preview as styled spans; block syntax is
/// flattened first.
TextSpan markdownPreviewSpan(String raw, TextStyle base) =>
    TextSpan(style: base, children: _spans(flattenMarkdown(raw), base));

List<InlineSpan> _spans(String text, TextStyle style) {
  final out = <InlineSpan>[];
  var at = 0;
  for (final m in _inline.allMatches(text)) {
    if (m.start > at) out.add(TextSpan(text: text.substring(at, m.start)));
    if (m[1] != null) {
      out.add(TextSpan(
          text: m[1],
          style: TextStyle(
            fontFamily: monoFamily,
            fontFamilyFallback: const ['GeistMono', 'monospace'],
            fontSize: (style.fontSize ?? 13) * 0.92,
            letterSpacing: 0,
          )));
    } else {
      final inner = m[2] ?? m[3] ?? m[4] ?? m[5] ?? m[6] ?? '';
      final TextStyle s = m[2] != null || m[3] != null
          ? TextStyle(fontWeight: weightFor(W.strong))
          : m[4] != null
              ? const TextStyle(decoration: TextDecoration.lineThrough)
              : const TextStyle(fontStyle: FontStyle.italic);
      out.add(TextSpan(style: s, children: _spans(inner, style.merge(s))));
    }
    at = m.end;
  }
  if (at < text.length) out.add(TextSpan(text: text.substring(at)));
  return out;
}
