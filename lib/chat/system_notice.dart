import 'package:flutter/material.dart';

import '../envelope.dart';
import '../tap_detector.dart';
import '../widgets.dart';
import 'signal_row.dart' show showSignalDetails;

/// A daemon envelope shown as one muted line: icon, summary, full note.
class SystemNotice {
  const SystemNotice(this.icon, this.summary, this.detail);
  final String icon;
  final String summary;
  final String detail;
}

String _plain(String text) => unescapeXml(text.replaceAll(RegExp(r'<[^>]+>'), ' '))
    .replaceAll(RegExp(r'[ \t]+'), ' ')
    .replaceAll(RegExp(r'\s*\n\s*'), '\n')
    .trim();

String _label(String kind) {
  final words = kind.replaceAll('_', ' ');
  return words[0].toUpperCase() + words.substring(1);
}

final _openTagRe = RegExp(
    r'<([a-z][a-z0-9_]*)(?=\s|>|/>)((?:[^>"\x27/]|/(?!>)|"[^"]*"|\x27[^\x27]*\x27)*)(/?)>');
final _joinSepRe = RegExp(r'[\s·•|]+');

const _childFragmentTags = {
  'last_said',
  'note',
  'body',
  'text',
  'approval',
  'question',
  'held_for_user',
  'summary',
  'reason',
  'handoff_note',
};

/// Splits one or more top-level XML envelopes joined by whitespace or `·`.
/// Returns null if any non-envelope prose appears before, between, or after.
List<String>? _splitEnvelopes(String raw) {
  final text = raw.trim();
  if (!text.startsWith('<')) return null;

  final parts = <({String tag, String attrs, String raw, bool headerOnly})>[];
  var pos = 0;

  while (pos < text.length) {
    if (parts.isNotEmpty) {
      final sep = _joinSepRe.matchAsPrefix(text, pos);
      if (sep != null) {
        pos = sep.end;
        if (pos >= text.length) break;
      }
    }
    final open = _openTagRe.matchAsPrefix(text, pos);
    if (open == null) return null;
    final tag = open.group(1)!;
    final attrs = open.group(2) ?? '';
    final selfClosing = open.group(3) == '/';

    if (selfClosing) {
      parts.add((
        tag: tag,
        attrs: attrs,
        raw: text.substring(pos, open.end),
        headerOnly: false,
      ));
      pos = open.end;
      continue;
    }

    final closeEnd = _findClosingTagEnd(text, tag, open.end);
    if (closeEnd != null) {
      parts.add((
        tag: tag,
        attrs: attrs,
        raw: text.substring(pos, closeEnd),
        headerOnly: false,
      ));
      pos = closeEnd;
      continue;
    }

    // Flattened notice fragments like `<session_stopped ...> · <last_said>...</last_said> · <note>...</note>`.
    final sep = _joinSepRe.matchAsPrefix(text, open.end);
    if (sep != null &&
        sep.end < text.length &&
        text.codeUnitAt(sep.end) == 0x3C /* '<' */) {
      parts.add((
        tag: tag,
        attrs: attrs,
        raw: text.substring(pos, open.end),
        headerOnly: true,
      ));
      pos = open.end;
      continue;
    }
    return null;
  }

  if (parts.isEmpty) return null;

  // Merge trailing child-field tags (like <last_said> and <note>) back into the
  // envelope they describe, so flattened notices parse as one rich notice.
  final merged = <String>[];
  var i = 0;
  while (i < parts.length) {
    final p = parts[i];
    final children = <String>[];
    var j = i + 1;
    while (j < parts.length &&
        _childFragmentTags.contains(parts[j].tag) &&
        !parts[j].headerOnly) {
      children.add(parts[j].raw);
      j++;
    }
    if (p.headerOnly) {
      if (children.isEmpty) return null;
      merged.add('<${p.tag}${p.attrs}>${children.join('\n')}</${p.tag}>');
    } else if (children.isNotEmpty) {
      final close = '</${p.tag}>';
      if (p.raw.endsWith('/>')) {
        merged.add('<${p.tag}${p.attrs}>${children.join('\n')}$close');
      } else if (p.raw.endsWith(close)) {
        final head = p.raw.substring(0, p.raw.length - close.length);
        merged.add('$head\n${children.join('\n')}$close');
      } else {
        merged.add(p.raw);
        merged.addAll(children);
      }
    } else {
      merged.add(p.raw);
    }
    i = j;
  }
  return merged;
}

int? _findClosingTagEnd(String text, String tag, int start) {
  final openRe = RegExp(
      '<$tag(?=[\\s>/])(?:[^>"\x27/]|/(?!>)|"[^"]*"|\x27[^\x27]*\x27)*(/?)>');
  final closeTag = '</$tag>';
  var depth = 1;
  var pos = start;
  while (pos < text.length) {
    final nextClose = text.indexOf(closeTag, pos);
    if (nextClose < 0) return null;
    final nextOpen = openRe.firstMatch(text.substring(pos, nextClose));
    if (nextOpen != null) {
      if (nextOpen.group(1) != '/') depth++;
      pos += nextOpen.end;
    } else {
      depth--;
      pos = nextClose + closeTag.length;
      if (depth == 0) return pos;
    }
  }
  return null;
}

String _joinParts(List<String> parts) =>
    [for (final p in parts) if (p.trim().isNotEmpty) p.trim()].join('\n\n');

SystemNotice? _parseSingleNotice(String text) {
  final kind = envelopeKind(text)!;
  if (kind == 'goal') return null;
  String f(String name) => envelopeField(text, name);
  final note = envelopeBody(text);
  final attr = f('kind');
  switch (kind) {
    case 'managed_by':
      if (attr == 'handed') {
        final agent = f('agent');
        return SystemNotice('transfer',
            agent.isEmpty ? 'Handed to an agent' : 'Handed to $agent', note);
      }
      if (attr == 'returned') {
        return SystemNotice('transfer', 'You took this session back', note);
      }
      if (attr == 'summary') {
        return SystemNotice('history', 'Handover summary', f('summary'));
      }
    case 'session_stopped':
      final title = f('title');
      final status = f('status');
      final detail = _joinParts([
        f('last_said'),
        f('approval'),
        f('question'),
        note,
      ]);
      return SystemNotice(
        'info',
        [
          title.isEmpty ? 'A session' : title,
          status.isEmpty ? 'stopped' : status,
        ].join(' '),
        detail,
      );
    case 'session_no_reply':
      final title = f('title');
      return SystemNotice(
        'info',
        title.isEmpty
            ? 'Session ended without replying'
            : '$title ended without replying',
        note.isNotEmpty ? note : _plain(text),
      );
    case 'session_question':
      final title = f('title');
      return SystemNotice(
        'help-circle',
        title.isEmpty ? 'Session asked a question' : '$title asked a question',
        _joinParts([f('question'), note]),
      );
    case 'owed_reply':
      return SystemNotice(
        'message',
        'Reply still owed',
        note.isNotEmpty ? note : _plain(text),
      );
    case 'task_cancelled':
      final title = f('title');
      return SystemNotice(
        'x-circle',
        title.isEmpty ? 'Task cancelled' : 'Task cancelled: $title',
        _joinParts([f('reason'), note]),
      );
    case 'rewind':
      final at = f('message');
      return SystemNotice(
          'undo', at.isEmpty ? 'Rewound' : 'Rewound to before "$at"', note);
    case 'compaction':
      return SystemNotice(
          'archive',
          attr == 'save'
              ? 'Saving notes before compacting'
              : 'Summarising before compacting',
          note);
    case 'compacted':
      return SystemNotice('archive', 'Conversation compacted', _plain(text));
    case 'lean_continuation':
      return SystemNotice('history', 'Continued in lean mode',
          note.isNotEmpty ? note : _plain(text));
    case 'handoff':
      final from = f('by').isNotEmpty ? f('by') : f('from');
      return SystemNotice(
          'transfer',
          from.isEmpty ? 'Handed over' : 'Handed over by $from',
          _joinParts([f('handoff_note'), note]));
    case 'group_added':
      final title = f('title');
      return SystemNotice('users',
          title.isEmpty ? 'Added to a group' : 'Added to $title', note);
    case 'reaction':
      final from = f('from');
      return SystemNotice(
          'message',
          '${from.isEmpty ? 'Someone' : from} reacted ${f('emoji')}'.trim(),
          '');
    case 'automated_wake':
      return SystemNotice('bell', 'Automated wake', _plain(text));
    case 'wake':
      return SystemNotice(
          'bell', 'Scheduled wake', note.isNotEmpty ? note : _plain(text));
    case 'watch':
    case 'file_watch':
      final name = f('name');
      return SystemNotice(
          'eye',
          name.isEmpty ? 'Watch triggered' : 'Watch: $name',
          note.isNotEmpty ? note : _plain(text));
    case 'routing':
      return SystemNotice('transfer', 'Model route switched',
          note.isNotEmpty ? note : _plain(text));
    case 'review_due':
      return SystemNotice(
          'eye', 'Review due', note.isNotEmpty ? note : _plain(text));
    case 'review_request':
      return SystemNotice(
          'eye', 'Review requested', note.isNotEmpty ? note : _plain(text));
    case 'review_findings':
      return SystemNotice(
          'eye', 'Review findings', note.isNotEmpty ? note : _plain(text));
    case 'lane_offer':
      final title = f('title');
      return SystemNotice('transfer',
          title.isEmpty ? 'Lane offered' : 'Lane offered: $title', note);
    case 'lane_offer_declined':
      return SystemNotice('info', 'Lane offer declined',
          _joinParts([f('reason'), note]));
    case 'lane_report':
      final subject = f('subject');
      return SystemNotice(
          'info',
          subject.isEmpty ? 'Lane report' : 'Lane report: $subject',
          _joinParts([f('summary'), note]));
    case 'lane_message':
      return SystemNotice(
          'message', 'Lane message', note.isNotEmpty ? note : _plain(text));
    case 'session_artifact':
      final title = f('title');
      return SystemNotice('file',
          title.isEmpty ? 'Shared artifact' : 'Shared artifact: $title', note);
    case 'reflection':
    case 'reflect':
      return SystemNotice('sparkles', 'Memory reflection',
          note.isNotEmpty ? note : _plain(text));
  }
  final body = note.isNotEmpty ? note : _plain(text);
  return SystemNotice('info', _label(kind), body);
}

/// Reads one or more whole daemon envelopes (including envelopes joined by
/// whitespace or `·`); returns null for anything else, so typed text that
/// merely starts with a tag still renders as the user's message.
SystemNotice? parseSystemNotice(String raw) {
  final envelopes = _splitEnvelopes(raw);
  if (envelopes == null || envelopes.isEmpty) return null;
  final notices = [
    for (final e in envelopes)
      if (_parseSingleNotice(e) case final notice?) notice,
  ];
  if (notices.isEmpty) return null;
  if (notices.length == 1) return notices.first;
  return SystemNotice(
    notices.first.icon,
    [for (final n in notices) n.summary].join(' · '),
    _joinParts([for (final n in notices) n.detail]),
  );
}

/// The notice in a transcript; tap opens the full note when there is one.
class SystemNoticeLine extends StatelessWidget {
  const SystemNoticeLine({super.key, required this.notice});
  final SystemNotice notice;

  @override
  Widget build(BuildContext context) {
    final line = NoteLine(notice.summary, icon: notice.icon);
    if (notice.detail.isEmpty) return line;
    return Align(
      alignment: Alignment.centerLeft,
      child: TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => showSignalDetails(context,
            title: notice.summary, body: notice.detail),
        child: line,
      ),
    );
  }
}
