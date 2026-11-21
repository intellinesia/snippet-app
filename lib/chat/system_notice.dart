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

/// Reads a whole envelope; null for anything else, so typed text that merely
/// starts with a tag still renders as the user's message.
SystemNotice? parseSystemNotice(String raw) {
  final text = raw.trim();
  final kind = envelopeKind(text);
  if (kind == null || !text.endsWith('</$kind>') && !text.endsWith('/>')) {
    return null;
  }
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
      return SystemNotice(
          'info',
          [title.isEmpty ? 'A session' : title, status.isEmpty ? 'stopped' : status]
              .join(' '),
          f('last_said'));
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
    case 'handoff':
      final from = f('by').isNotEmpty ? f('by') : f('from');
      return SystemNotice('transfer',
          from.isEmpty ? 'Handed over' : 'Handed over by $from', f('handoff_note'));
    case 'group_added':
      final title = f('title');
      return SystemNotice('users',
          title.isEmpty ? 'Added to a group' : 'Added to $title', note);
    case 'reaction':
      final from = f('from');
      return SystemNotice('message',
          '${from.isEmpty ? 'Someone' : from} reacted ${f('emoji')}'.trim(), '');
    case 'automated_wake':
      return SystemNotice('bell', 'Automated wake', _plain(text));
    case 'goal':
      final title = f('title').isNotEmpty ? f('title') : f('goal_text');
      return SystemNotice(
          'sparkles', title.isEmpty ? 'Goal update' : 'Goal: $title', note);
  }
  final body = note.isNotEmpty ? note : _plain(text);
  return SystemNotice('info', _label(kind), body);
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
