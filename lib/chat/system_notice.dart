import 'package:flutter/material.dart';

import '../envelope.dart';
import '../mochi.dart';
import '../phosphor_icons.dart';
import '../platform.dart';
import '../tap_detector.dart';
import '../theme.dart';
import '../widgets.dart';
import 'signal_row.dart' show showSignalDetails;

/// A daemon envelope shown as one muted line: icon, summary, full note.
class SystemNotice {
  const SystemNotice(this.icon, this.summary, this.detail,
      {this.kind = '', this.rows = const [], this.memberId, this.progress});
  final String icon;
  final String summary;
  final String detail;

  /// The envelope tag, such as `session_stopped`; picks the desktop icon.
  final String kind;

  /// Labelled detail rows for the desktop block, such as ("Last said", ...).
  final List<(String, String)> rows;

  /// A member named by the notice, for MSG-14's 18px avatar.
  final String? memberId;

  /// MSG-18 compaction progress in the 4px track, when this is one.
  final double? progress;
}

String _plain(String text) =>
    unescapeXml(text.replaceAll(RegExp(r'<[^>]+>'), ' '))
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

String _joinParts(List<String> parts) => [
      for (final p in parts)
        if (p.trim().isNotEmpty) p.trim()
    ].join('\n\n');

/// Goals and plans were removed from the service: their notices are void.
bool _isGoalKind(String kind) => kind == 'goal' || kind.startsWith('goal_');

SystemNotice? _parseSingleNotice(String text) {
  final kind = envelopeKind(text)!;
  if (_isGoalKind(kind)) return null;
  final n = _parseNoticeBody(text, kind);
  if (n == null) return null;
  String f(String name) => envelopeField(text, name).trim();
  final rows = <(String, String)>[
    if (kind == 'session_stopped') ...[
      if (f('last_said').isNotEmpty) ('Last said', f('last_said')),
      if (f('approval').isNotEmpty) ('Approval', f('approval')),
      if (f('question').isNotEmpty) ('Question', f('question')),
      if (envelopeBody(text).trim().isNotEmpty)
        ('Note', envelopeBody(text).trim()),
    ],
  ];
  return SystemNotice(n.icon, n.summary, n.detail,
      kind: kind, rows: rows, memberId: n.memberId, progress: n.progress);
}

SystemNotice? _parseNoticeBody(String text, String kind) {
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
              : 'Compacting context…',
          note,
          progress: 0.45);
    case 'compacted':
      final before = f('before').isNotEmpty ? f('before') : f('tokens_before');
      final after = f('after').isNotEmpty ? f('after') : f('tokens_after');
      final count = before.isNotEmpty && after.isNotEmpty
          ? ' $before → $after tokens'
          : '';
      return SystemNotice('archive', 'Context compacted$count',
          before.isNotEmpty || after.isNotEmpty ? note : _plain(text),
          progress: 1);
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
    case 'group_removed':
    case 'member_added':
    case 'member_removed':
      final title = f('title');
      final member = f('member').isNotEmpty ? f('member') : f('agent');
      final removed = kind.contains('removed');
      final action = removed ? 'left' : 'joined';
      return SystemNotice(
          'users',
          member.isNotEmpty && title.isNotEmpty
              ? '$member $action $title'
              : title.isEmpty
                  ? (removed ? 'Member removed' : 'Added to a group')
                  : 'Added to $title',
          note,
          memberId: member.isEmpty ? null : member);
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
      final body = (note.isNotEmpty ? note : _plain(text))
          .replaceAll(RegExp(r'\s+'), ' ')
          .trim();
      return SystemNotice(
          'transfer',
          body.isEmpty ? 'Model route switched' : 'Model route switched: $body',
          '');
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
      return SystemNotice(
          'info', 'Lane offer declined', _joinParts([f('reason'), note]));
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
    kind: notices.first.kind,
    rows: [for (final n in notices) ...n.rows],
    memberId: notices.first.memberId,
    progress: notices.first.progress,
  );
}

/// Desktop icon per notice kind (MSG-12..18): stop, arrow right, member,
/// clock or eye, rewind, compress; the phone keeps [SystemNotice.icon].
IconData _deskIcon(SystemNotice n) => switch (n.kind) {
      'session_stopped' => PhIcons.stop,
      'routing' => PhIcons.arrowRight,
      'group_added' || 'member_added' => PhIcons.userPlus,
      'group_removed' || 'member_removed' => PhIcons.user,
      'wake' || 'automated_wake' => PhIcons.clock,
      'watch' || 'file_watch' => PhIcons.eye,
      'rewind' => PhIcons.clockCounterClockwise,
      'compaction' || 'compacted' || 'lean_continuation' => PhIcons.arrowsIn,
      'reflection' || 'reflect' => PhIcons.sparkle,
      'task_cancelled' => PhIcons.xCircle,
      'session_question' => PhIcons.question,
      'owed_reply' || 'lane_message' || 'reaction' => PhIcons.chatText,
      'managed_by' || 'handoff' || 'lane_offer' => PhIcons.arrowsLeftRight,
      'session_artifact' => PhIcons.file,
      'review_due' || 'review_request' || 'review_findings' => PhIcons.eye,
      _ => PhIcons.info,
    };

/// The notice in a transcript; tap opens the full note when there is one.
/// Desktop (MSG-11): min 28 high, icon 14 fg3 at x+7, text 12/400 fg2 lh17
/// at x+22; a notice with detail adds a chevron and expands in place.
class SystemNoticeLine extends StatefulWidget {
  const SystemNoticeLine({super.key, required this.notice});
  final SystemNotice notice;

  @override
  State<SystemNoticeLine> createState() => _SystemNoticeLineState();
}

class _SystemNoticeLineState extends State<SystemNoticeLine> {
  bool _open = false;

  SystemNotice get notice => widget.notice;

  Widget _phone() {
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

  List<(String?, String)> get _rows => notice.rows.isNotEmpty
      ? [for (final (k, v) in notice.rows) (k, v)]
      : [
          for (final p in notice.detail.split(RegExp(r'\n\s*\n')))
            if (p.trim().isNotEmpty) (null, p.trim()),
        ];

  Widget _detail() {
    final text = sans(kMobile ? 14 : 12, height: kMobile ? 19 / 14 : 17 / 12, color: AppColors.fg2);
    return Padding(
      padding: const EdgeInsets.only(left: 22, bottom: 6),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (k, v) in _rows)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 2.5),
                child: Text.rich(
                  TextSpan(children: [
                    if (k != null)
                      TextSpan(
                          text: '$k: ',
                          style: text.copyWith(color: AppColors.fg3)),
                    TextSpan(text: v),
                  ]),
                  maxLines: 8,
                  overflow: TextOverflow.ellipsis,
                  style: text,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _desk() {
    final interactive = notice.detail.isNotEmpty || notice.rows.isNotEmpty;
    // Capy's finished compaction checkpoint is only a dim centred label.
    if (notice.kind == 'compacted') {
      return Padding(
        padding: EdgeInsets.symmetric(vertical: S.s12),
        child: Center(
          child: Text('Context compacted',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(11.5, color: AppColors.fg4)),
        ),
      );
    }
    final line = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 28),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 5.5),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const SizedBox(width: 7),
          Padding(
            padding: const EdgeInsets.only(top: 1.5),
            child: Icon(_deskIcon(notice), size: 14, color: AppColors.fg3),
          ),
          const SizedBox(width: 1),
          if (notice.memberId != null) ...[
            Padding(
              padding: const EdgeInsets.only(right: 6),
              child: AgentMochi(notice.memberId!, size: 18),
            ),
          ],
          Expanded(
            child: Text(notice.summary,
                style: sans(kMobile ? 14 : 12, height: kMobile ? 19 / 14 : 17 / 12, color: AppColors.fg2)),
          ),
          if (notice.progress != null) ...[
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 7, right: 7),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(2),
                child: SizedBox(
                  width: 92,
                  height: 4,
                  child: Stack(children: [
                    Positioned.fill(
                        child: ColoredBox(color: AppColors.surface2)),
                    FractionallySizedBox(
                      widthFactor: notice.progress!.clamp(0.0, 1.0),
                      child: ColoredBox(color: AppColors.fg3),
                    ),
                  ]),
                ),
              ),
            ),
          ],
          if (interactive) ...[
            const SizedBox(width: 8),
            Padding(
              padding: const EdgeInsets.only(top: 1.5, right: 7),
              child: Icon(_open ? PhIcons.caretDown : PhIcons.caretRight,
                  size: 14, color: AppColors.fg3),
            ),
          ],
        ]),
      ),
    );
    if (!interactive) return Semantics(container: true, child: line);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Semantics(
          button: true,
          expanded: _open,
          child: HoverSurface(
            radius: 6,
            hoverColor: AppColors.surface1,
            onTap: () => setState(() => _open = !_open),
            child: line,
          ),
        ),
        if (_open) _detail(),
      ],
    );
  }

  @override
  Widget build(BuildContext context) => kMobile ? _phone() : _desk();
}
