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

final _attach =
    RegExp(r'\[attached (image|file)(?: —[^\]]*?)?:\s*([^\]\s]+)\]');
final _attachCut = RegExp(r'\[attached (image|file)\b[^\]]*$');
final _transcript = RegExp(r'\[Audio transcript for [^\]\r\n]+\]\r?\n?');
final _noTranscript = RegExp(r'\[Audio transcription unavailable:[^\]]*\]');
final _audioExt = RegExp(r'\.(m4a|mp3|wav|ogg|oga|opus|aac|flac|amr|3gp)$',
    caseSensitive: false);

String _count(int n, String one, String many) => n == 1 ? one : '$n $many';

/// Daemon attachment and transcript markers as short labels
/// ("Voice note · …", "Photo", "File report.pdf"). With [labels] false the
/// markers are dropped and the labels only stand in for an empty text.
String describeAttachments(String raw, {bool labels = true}) {
  if (!raw.contains('[attached ') && !raw.contains('[Audio transcri')) {
    return raw;
  }
  var images = 0, voice = 0;
  final files = <String>[];
  for (final m in _attach.allMatches(raw)) {
    final path = m[2] ?? '';
    if (m[1] == 'image') {
      images++;
    } else if (_audioExt.hasMatch(path)) {
      voice++;
    } else {
      files.add(path.split('/').last);
    }
  }
  final cut = _attachCut.firstMatch(raw);
  if (cut != null) {
    if (cut[1] == 'image') {
      images++;
    } else {
      files.add('');
    }
  }
  final hasTranscript = _transcript.hasMatch(raw);
  if (voice == 0 && (hasTranscript || _noTranscript.hasMatch(raw))) voice = 1;
  final text = raw
      .replaceAll(_attach, '')
      .replaceAll(_attachCut, '')
      .replaceAll(_transcript, '')
      .replaceAll(_noTranscript, '')
      .trim();
  final parts = [
    if (voice > 0) _count(voice, 'Voice note', 'voice notes'),
    if (images > 0) _count(images, 'Photo', 'photos'),
    if (files.length == 1) 'File ${files.first}'.trim(),
    if (files.length > 1) '${files.length} files',
  ];
  final label = parts.join(', ');
  if (text.isEmpty) return label;
  if (!labels || label.isEmpty) return text;
  return '$label · $text';
}

/// One line of text from markdown: block syntax goes, inline marks stay.
String flattenMarkdown(String raw) => describeAttachments(raw)
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
