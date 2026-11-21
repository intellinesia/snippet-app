/// Reader for the daemon's XML envelopes; mirrors src/envelope.rs.
library;

String unescapeXml(String s) => s
    .replaceAll('&lt;', '<')
    .replaceAll('&gt;', '>')
    .replaceAll('&quot;', '"')
    .replaceAll('&amp;', '&');

final _kindPattern = RegExp(r'^<([a-z][a-z0-9_]*)(?=[\s>/])');

String? envelopeKind(String text) =>
    _kindPattern.firstMatch(text.trimLeft())?.group(1);

String? _openTag(String text) {
  if (envelopeKind(text) == null) return null;
  final start = text.trimLeft();
  final end = start.indexOf('>');
  return end < 0 ? null : start.substring(0, end);
}

Map<String, String> _parseAttrs(String tag) => {
  for (final m in RegExp(r'([A-Za-z_][\w-]*)="([^"]*)"').allMatches(tag))
    m.group(1)!: unescapeXml(m.group(2)!),
};

Map<String, String> envelopeAttrs(String text) {
  final tag = _openTag(text);
  return tag == null ? const {} : _parseAttrs(tag);
}

String? envelopeAttr(String text, String name) => envelopeAttrs(text)[name];

String _inner(String text) {
  final tag = _openTag(text);
  if (tag == null) return text;
  final start = text.trimLeft();
  return start.substring(tag.length + 1);
}

Match? _childOpen(String inner, String name) =>
    RegExp('<$name(?=[\\s>])[^>]*>').firstMatch(inner);

String? envelopeChild(String text, String name) {
  final inner = _inner(text);
  final open = _childOpen(inner, name);
  if (open == null) return null;
  final end = inner.indexOf('</$name>', open.end);
  if (end < 0) return null;
  return unescapeXml(
    inner.substring(open.end, end).replaceAll(RegExp(r'^\n+|\n+$'), ''),
  );
}

Map<String, String> envelopeChildAttrs(String text, String name) {
  final open = _childOpen(_inner(text), name);
  return open == null ? const {} : _parseAttrs(open.group(0)!);
}

/// An attribute of the opening tag, else the text of a child of that name.
String envelopeField(String text, String name) =>
    (envelopeAttr(text, name) ?? envelopeChild(text, name) ?? '').trim();

/// The free text of an envelope: its body, note or text child.
String envelopeBody(String text) {
  for (final name in const ['body', 'note', 'text']) {
    final c = envelopeChild(text, name);
    if (c != null) return c.trim();
  }
  return '';
}
