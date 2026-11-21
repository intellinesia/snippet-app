/// Mission Control session predicates and the typed envelopes agents and the
/// daemon write into transcripts.
library;

import '../../envelope.dart';
import '../../models.dart';

bool isDedicatedMcSession(String? id) {
  if (id == null || id.isEmpty) return false;
  final normalized = id.replaceAll(r'\', '/').trim();
  return normalized == 'mission-control' ||
      normalized == 'mission-control/session.json';
}

/// True for the dedicated MC home — by session id or the exact tab title
/// leftover from when MC was listed as a regular chat.
bool isMissionControlTab({String? sessionId, String? title}) {
  if (isDedicatedMcSession(sessionId)) return true;
  return title?.trim() == 'Mission Control';
}

bool isMissionControlListRow(SessionInfo session) {
  return isMissionControlTab(sessionId: session.id, title: session.title);
}

/// Whether a session id names an agent inbox rather than a project session.
bool isInboxSession(String? id) {
  if (id == null || id.isEmpty) return false;
  final normalized = id.replaceAll(r'\', '/').trim();
  if (normalized.startsWith('inbox-') || normalized.startsWith('inbox/')) {
    return true;
  }
  final lastSlash = normalized.lastIndexOf('/');
  if (lastSlash >= 0 && lastSlash + 1 < normalized.length) {
    final name = normalized.substring(lastSlash + 1);
    if (name.startsWith('inbox-')) return true;
  }
  return false;
}

/// Whether a session row represents an agent inbox.
bool isInboxSessionRow(SessionInfo session) {
  return isInboxSession(session.id) ||
      session.folder.trim().toLowerCase() == 'inbox';
}

class MissionEnvelope {
  const MissionEnvelope({
    required this.isReport,
    required this.taskId,
    required this.title,
    required this.status,
    required this.summary,
    this.isRecurring = false,
    this.isPlan = false,
    this.review = '',
    this.round = '',
  });
  final bool isReport;
  final bool isRecurring;
  final bool isPlan;

  /// `findings` or `request` for a review envelope, otherwise empty.
  final String review;
  final String round;
  final String taskId;
  final String title;
  final String status;
  final String summary;

  String get eventKind {
    if (!isReport) return 'queued';
    return switch (status) {
      'done' || 'completed' => 'done',
      'failed' => 'failed',
      'cancelled' => 'cancelled',
      'blocked' => 'blocked',
      'stalled' => 'stalled',
      'in_progress' || 'working' => 'working',
      'message' => 'message',
      _ => 'update',
    };
  }
}

const _envelopeNames = {
  'direct_message': 'Message',
  'agent_reply': 'Reply',
  'group_message': 'Group message',
  'coordination_board_message': 'Task room post',
  'task_offer': 'Task offer',
  'mission_control_task': 'Task',
  'mission_task_report': 'Task report',
  'review_request': 'Review request',
  'review_findings': 'Review findings',
  'owed_reply': 'Reply owed',
  'lane_report': 'Lane report',
  'watch': 'Watch',
  'wake': 'Wake',
};

/// A one-line label for a queued harness envelope, or null for plain text.
String? queuedEnvelopeLabel(String text) {
  final tag = envelopeKind(text);
  if (tag == null) return null;
  final kind = _envelopeNames[tag] ?? tag.replaceAll('_', ' ');
  var from = envelopeField(text, 'from');
  if (from.isEmpty) from = envelopeField(text, 'from_id');
  from = from.contains(':') ? from.split(':').last : from;
  final detail = [
    envelopeField(text, 'body'),
    envelopeField(text, 'task_title'),
    envelopeField(text, 'title'),
    envelopeField(text, 'wake_note'),
    envelopeField(text, 'note'),
  ].firstWhere((s) => s.isNotEmpty, orElse: () => '');
  final head = from.isEmpty ? kind : '$kind from $from';
  return detail.isEmpty ? head : '$head: ${detail.split('\n').first}';
}

MissionEnvelope? parseMissionEnvelope(String text) {
  final t = text.trim();
  final tag = envelopeKind(t);
  final isRecurring = tag == 'recurring_run_report';
  final isPlan = tag == 'task_plan';
  final isReport = isRecurring || isPlan || tag == 'mission_task_report';
  final isTask = tag == 'mission_control_task';
  final review = tag == 'review_findings'
      ? 'findings'
      : tag == 'review_request'
      ? 'request'
      : '';
  if (!isReport && !isTask && review.isEmpty) return null;
  String field(String name) => envelopeField(t, name);

  if (review.isNotEmpty) {
    final findings = (envelopeChild(t, 'findings') ?? '')
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.startsWith('- '))
        .join('\n');
    return MissionEnvelope(
      isReport: true,
      review: review,
      round: field('round'),
      taskId: field('task_id'),
      title: field('title'),
      status: 'message',
      summary: findings,
    );
  }

  if (isPlan) {
    final plan = envelopeChild(t, 'plan') ?? '';
    return MissionEnvelope(
      isReport: true,
      isPlan: true,
      taskId: field('task_id'),
      title: field('title'),
      status: 'message',
      summary: plan
          .trim()
          .split('\n')
          .where((l) => l.trim().isNotEmpty)
          .map((l) {
            final m = RegExp(r'^\[(\w+)\]\s*(.*)$').firstMatch(l.trim());
            if (m == null) return '- ${l.trim()}';
            final step = m.group(2) ?? '';
            return switch (m.group(1)) {
              'done' => '- ~~$step~~',
              'in_progress' => '- **$step** · now',
              _ => '- $step',
            };
          })
          .join('\n'),
    );
  }
  return MissionEnvelope(
    isReport: isReport,
    isRecurring: isRecurring,
    taskId: field('task_id'),
    title: isRecurring ? field('job') : field('title'),
    status: isReport ? field('status') : 'pending',
    summary: isReport
        ? _readableStall(field('summary'))
        : (envelopeChild(t, 'scope') ?? field('scope')).trim(),
  );
}

/// Stall reports are written for Mission Control; keep what the user can use.
String _readableStall(String summary) {
  final head = RegExp(
    r'^stalled (\d+) min: no progress since \S+; ',
  ).matchAsPrefix(summary);
  if (head == null) return summary;
  final rest = summary
      .substring(head.end)
      .replaceFirst(RegExp(r'\n?If that asks for something,[^\n]*$'), '')
      .replaceFirst(RegExp(r'[;,]?\s*check it with inspect_session[^\n]*$'), '')
      .replaceAll('waiting_for_input', 'waiting for input');
  final last = RegExp(r';?\s*its last message was:\s*').firstMatch(rest);
  final state = (last == null ? rest : rest.substring(0, last.start)).trim();
  final lead = state.isEmpty
      ? ''
      : ' ${state[0].toUpperCase()}${state.substring(1)}.';
  final said = last == null ? '' : rest.substring(last.end).trim();
  return 'No progress for ${head.group(1)} min.$lead'
      '${said.isEmpty ? '' : '\n\nIts last message:\n\n$said'}';
}

/// Stall reports overtaken by a later report on the same task.
Set<int> supersededStalls(List<Map<String, dynamic>> events) {
  final seen = <String>{};
  final out = <int>{};
  for (var i = events.length - 1; i >= 0; i--) {
    final kind = events[i]['kind'];
    if (kind != 'user_input' && kind != 'steer') continue;
    final envelope = parseMissionEnvelope(events[i]['text'] as String? ?? '');
    if (envelope == null || !envelope.isReport || envelope.isPlan) continue;
    if (envelope.taskId.isEmpty) continue;
    if (!seen.add(envelope.taskId) && envelope.status == 'stalled') out.add(i);
  }
  return out;
}

class QuietWake {
  const QuietWake({required this.time, required this.reply});
  final String time;
  final String reply;
}

class QuietWakeRun {
  const QuietWakeRun({required this.end, required this.wakes});

  /// Index of the run's last event.
  final int end;
  final List<QuietWake> wakes;
}

final _quietOpening = RegExp(
  r'^(nothing|still quiet|quiet|same quiet|no changes?|no action|'
  r'staying quiet|still waiting)\b',
  caseSensitive: false,
);
final _needsAttention = RegExp(
  r'\b(except|but|however|stuck|failed|failing|blocked|wedged|error|limit|'
  r'approval|your (call|input|answer|review)|needs? you|'
  r'waiting (item|on))\b',
  caseSensitive: false,
);

bool _isQuietReply(String reply) {
  final text = reply.trim();
  return text.isNotEmpty &&
      text.length <= 320 &&
      _quietOpening.hasMatch(text) &&
      !_needsAttention.hasMatch(
        text.replaceAll(RegExp(r'nothing needs you', caseSensitive: false), ''),
      );
}

/// An `assistant_text` the daemon flagged as "no reply needed". Older daemons
/// send no flag, so callers fall back to [_isQuietReply].
bool quietAssistantEvent(Map<String, dynamic> e) =>
    (e['kind'] == 'assistant_text' || e['kind'] == 'assistant') &&
    e['quiet'] == true;

/// Runs of automated wakes that produced nothing for the user, keyed by the
/// index of their first event. A wake counts only if its reply says so and it
/// did nothing beyond scheduling the next look, so real news is never folded.
Map<int, QuietWakeRun> quietWakeRuns(List<Map<String, dynamic>> events) {
  bool isInput(Map<String, dynamic> e) =>
      e['kind'] == 'user_input' || e['kind'] == 'steer';
  final out = <int, QuietWakeRun>{};
  int? start;
  var wakes = <QuietWake>[];
  var i = 0;
  void close(int end) {
    if (start != null) out[start!] = QuietWakeRun(end: end, wakes: wakes);
    start = null;
    wakes = <QuietWake>[];
  }

  while (i < events.length) {
    final e = events[i];
    final round = isInput(e)
        ? parseAutonomousRound(e['text'] as String? ?? '')
        : null;
    if (round == null || round.due.isNotEmpty) {
      close(i - 1);
      i++;
      continue;
    }
    var j = i + 1;
    var quiet = true;
    final reply = StringBuffer();
    var flagged = false;
    while (j < events.length && !isInput(events[j])) {
      final next = events[j];
      switch (next['kind']) {
        case 'assistant_text':
          reply.writeln(next['text'] as String? ?? '');
          if (quietAssistantEvent(next)) flagged = true;
        case 'tool_call' || 'tool_result':
          if (next['tool_name'] != 'schedule_wake') quiet = false;
        case 'turn_changes' || 'system_decision':
          break;
        default:
          quiet = false;
      }
      j++;
    }
    if (quiet &&
        reply.toString().trim().isNotEmpty &&
        (flagged || _isQuietReply(reply.toString()))) {
      start ??= i;
      wakes.add(QuietWake(time: round.time, reply: reply.toString().trim()));
    } else {
      close(i - 1);
    }
    i = j;
  }
  close(events.length - 1);
  return out;
}

/// The periodic round the daemon hands Mission Control in autonomous mode.
/// Parsed so the transcript shows a compact summary instead of the envelope.
class AutonomousRound {
  const AutonomousRound({
    required this.time,
    required this.firstRound,
    required this.quiet,
    required this.changed,
    required this.open,
    required this.due,
    required this.scheduled,
  });
  final String time;
  final bool firstRound;
  final bool quiet;
  final List<String> changed;
  final List<String> open;
  final List<String> due;
  final List<String> scheduled;

  String get headline {
    final parts = <String>[
      if (firstRound) 'Automated wakes switched on',
      '${open.length} open',
      if (changed.isNotEmpty) '${changed.length} changed',
      if (due.isNotEmpty)
        '${due.length} wake-up${due.length == 1 ? '' : 's'} due',
    ];
    return parts.join(' · ');
  }

  String get markdown {
    final out = StringBuffer();
    void section(String title, List<String> items) {
      if (items.isEmpty) return;
      out.writeln('**$title**');
      for (final item in items) {
        out.writeln('- $item');
      }
      out.writeln();
    }

    section('Wake-ups due', due);
    section('Changed since last wake', changed);
    section('Open work', open);
    section('Scheduled', scheduled);
    if (quiet) {
      out.writeln('_Quiet hours: non-urgent pings wait until morning._');
    }
    final text = out.toString().trim();
    return text.isEmpty ? 'Nothing changed, nothing open.' : text;
  }
}

String _taskLine(String raw) {
  final parts = raw.split(' · ').map((p) => p.trim()).toList();
  if (parts.length < 3) return raw;
  final status = parts[0].replaceAll('_', ' ');
  final title = parts[1];
  final note = parts.length > 3 ? parts.sublist(3).join(' · ') : '';
  return note.isEmpty ? '**$title** · $status' : '**$title** · $status · $note';
}

String _roundTime(String raw) {
  final head = raw.split(' (').first.trim();
  final parts = head.split(RegExp(r'\s+'));
  if (parts.length >= 4 && parts.last.contains(':')) {
    return '${parts.first} ${parts.last}';
  }
  return head;
}

AutonomousRound? parseAutonomousRound(String text) {
  final t = text.trim();
  final tag = envelopeKind(t);
  if (tag != 'automated_wake' && tag != 'autonomous_round') return null;
  final lines = (envelopeChild(t, 'body') ?? t).split('\n');
  String field(String name) => envelopeField(t, name.replaceAll(' ', '_'));

  List<String> section(String heading) {
    final start = lines.indexWhere((l) => l.trim() == '## $heading');
    if (start < 0) return const [];
    final items = <String>[];
    for (final l in lines.skip(start + 1)) {
      final line = l.trim();
      if (line.startsWith('## ') || line.startsWith('</')) break;
      if (line.startsWith('- ')) items.add(line.substring(2));
    }
    return items;
  }

  return AutonomousRound(
    time: _roundTime(field('time')),
    firstRound:
        (field('last wake').isEmpty ? field('last round') : field('last wake'))
            .startsWith('never'),
    quiet: field('quiet hours').startsWith('yes'),
    changed: [
      ...section('Changed since last wake'),
      ...section('Changed since last round'),
    ].map(_taskLine).toList(),
    open: section('Open work').map(_taskLine).toList(),
    due: [...section('Wake-ups due now'), ...section('Follow-ups due now')],
    scheduled: [
      ...section('Wake-ups scheduled'),
      ...section('Follow-ups scheduled'),
    ],
  );
}

/// A worker paused on a question, forwarded to Mission Control.
class WorkerQuestion {
  const WorkerQuestion({
    required this.taskId,
    required this.task,
    required this.question,
  });
  final String taskId;
  final String task;
  final String question;
}

WorkerQuestion? parseWorkerQuestion(String text) {
  final t = text.trim();
  if (envelopeKind(t) != 'worker_question') return null;
  return WorkerQuestion(
    taskId: envelopeField(t, 'task_id'),
    task: envelopeField(t, 'task'),
    question: envelopeField(t, 'question'),
  );
}

/// A human/agent message routed from the coordination board into a session's
/// transcript. Rendered as a compact card so the raw envelope never appears.
class BoardMessage {
  const BoardMessage({
    required this.threadId,
    required this.fromId,
    required this.fromKind,
    required this.body,
  });
  final String threadId;
  final String fromId;
  final String fromKind;
  final String body;
}

BoardMessage? parseBoardMessage(String text) {
  final t = text.trim();
  if (envelopeKind(t) != 'coordination_board_message') return null;
  return BoardMessage(
    threadId: envelopeField(t, 'thread_id'),
    fromId: envelopeField(t, 'from_id'),
    fromKind: envelopeField(t, 'from_kind'),
    body: (envelopeChild(t, 'body') ?? '').trim(),
  );
}

/// A DIRECT message delivered into an agent's inbox session.
///
/// Same shape of problem as [BoardMessage]: the envelope is an internal
/// transport, and rendering it raw puts `rules:`, history rows, and the closing
/// tag in the user's transcript. Parsed so only who-and-what is shown.
class DirectMessage {
  const DirectMessage({
    required this.threadId,
    required this.fromId,
    required this.fromKind,
    required this.body,
    this.isReply = false,
    this.messageKind = '',
    this.urgent = false,
  });
  final String threadId;
  final String fromId;
  final String fromKind;
  final String body;
  final String messageKind;
  final bool urgent;

  /// True when this is an ANSWER to a question this session asked, rather than
  /// a message addressed to this session's agent. The two read differently.
  final bool isReply;

  /// How to name the sender in a one-line label.
  String get fromLabel {
    final id = fromId.trim();
    if (id.isEmpty) return 'someone';
    if (fromKind == 'human' || id == 'local') return 'you';
    return id;
  }
}

DirectMessage? parseDirectMessage(String text) {
  final t = text.trim();
  if (envelopeKind(t) != 'direct_message') return null;
  return DirectMessage(
    threadId: envelopeField(t, 'thread_id'),
    fromId: envelopeField(t, 'from'),
    fromKind: envelopeField(t, 'from_kind'),
    body: (envelopeChild(t, 'body') ?? '').trim(),
    messageKind: envelopeField(t, 'kind'),
    urgent: envelopeField(t, 'urgency').startsWith('urgent'),
  );
}

/// A group chat post, or the notice that this agent joined a group, delivered
/// into an agent's desk.
class GroupMessage {
  const GroupMessage({
    required this.threadId,
    required this.title,
    required this.fromId,
    required this.fromKind,
    required this.body,
    this.added = false,
    this.members = const [],
    this.lead = '',
    this.mentions = const [],
    this.replyExpected = false,
  });
  final String threadId;
  final String title;
  final String fromId;
  final String fromKind;
  final String body;
  final bool added;
  final List<String> members;
  final String lead;
  final List<String> mentions;
  final bool replyExpected;

  String get fromLabel {
    if (fromKind == 'human' || fromId == 'human' || fromId == 'local') {
      return 'You';
    }
    return fromId.isEmpty ? 'someone' : fromId;
  }
}

GroupMessage? parseGroupMessage(String text) {
  final t = text.trim();
  final tag = envelopeKind(t);
  if (tag != 'group_added' && tag != 'group_message') return null;
  List<String> list(String raw) => [
    for (final s in raw.split(RegExp(r'[,;]')))
      if (s.trim().isNotEmpty) s.replaceFirst(RegExp(r'\s*\(.*\)$'), '').trim(),
  ];
  final from = envelopeField(t, 'from');
  final split = from.indexOf(':');
  final lead =
      envelopeAttr(t, 'lead') ?? envelopeChildAttrs(t, 'lead')['agent'] ?? '';
  return GroupMessage(
    threadId: envelopeField(t, 'thread_id'),
    title: envelopeField(t, 'title'),
    fromKind: split > 0 ? from.substring(0, split) : '',
    fromId: split > 0 ? from.substring(split + 1) : from,
    body: (envelopeChild(t, 'body') ?? '').trim(),
    added: tag == 'group_added',
    members: list(envelopeField(t, 'members')),
    lead: lead == 'none' ? '' : lead,
    mentions: list(envelopeField(t, 'mentions')),
    replyExpected: envelopeField(t, 'reply_expected') == 'true',
  );
}

/// The REPLY an agent sent back into a session that asked it something.
///
/// Delivered as a user-turn so the session's own agent sees the answer and the
/// transcript keeps a record of the exchange — which is the whole point of
/// asking from inside a session rather than in the agent's inbox.
DirectMessage? parseCoordinationReply(String text) {
  final t = text.trim();
  final tag = envelopeKind(t);
  if (tag != 'agent_reply' && tag != 'coordination_reply') return null;
  final raw = envelopeField(t, 'from');
  final split = raw.indexOf(':');
  return DirectMessage(
    threadId: envelopeField(t, 'thread_id'),
    fromId: split > 0 ? raw.substring(split + 1) : raw,
    fromKind: split > 0 ? raw.substring(0, split) : 'agent',
    body: (envelopeChild(t, 'body') ?? '').trim(),
    isReply: true,
  );
}

/// A `<watch>` envelope: an agent's own background script reported new lines.
class WatchEnvelope {
  final String name;
  final String mode;
  final String event;
  final int held;
  final List<String> lines;
  const WatchEnvelope({
    required this.name,
    required this.mode,
    required this.event,
    required this.held,
    required this.lines,
  });
}

WatchEnvelope? parseWatchEnvelope(String text) {
  final t = text.trim();
  if (envelopeKind(t) != 'watch') return null;
  final body = envelopeChild(t, 'body');
  if (body == null) return null;
  return WatchEnvelope(
    name: envelopeAttr(t, 'name') ?? 'watch',
    mode: envelopeField(t, 'mode'),
    event: envelopeAttr(t, 'event') ?? 'change',
    held: int.tryParse(envelopeField(t, 'held')) ?? 0,
    lines: body.split('\n').where((l) => l.trim().isNotEmpty).toList(),
  );
}

/// A `<wake>` envelope: the note an agent left itself with `schedule_wake`.
String? parseWakeNote(String text) {
  final t = text.trim();
  if (envelopeKind(t) != 'wake') return null;
  return (envelopeChild(t, 'wake_note') ?? envelopeChild(t, 'note') ?? '')
      .trim();
}

/// A message from the agent that delegated a lane, delivered into the lane.
String? parseParentMessage(String text) {
  final t = text.trim();
  if (envelopeKind(t) != 'parent_message') return null;
  return envelopeBody(t);
}

/// Work Mission Control offers an agent, carried as the body of a direct
/// message. Nothing starts until the agent claims it.
class TaskOffer {
  const TaskOffer({
    required this.taskId,
    required this.title,
    required this.briefing,
  });
  final String taskId;
  final String title;
  final String briefing;
}

TaskOffer? parseTaskOffer(String text) {
  final flat = text.contains('<task_offer') ? text : unescapeXml(text);
  final start = flat.indexOf('<task_offer');
  if (start < 0) return null;
  final t = flat.substring(start);
  return TaskOffer(
    taskId: envelopeField(t, 'task_id'),
    title: envelopeField(t, 'title'),
    briefing: (envelopeChild(t, 'briefing') ?? envelopeBody(t)).trim(),
  );
}

/// The assignment envelope handed to a session that is being given work.
///
/// A third internal transport with the same problem: the raw form is a field
/// list plus a paragraph of rules, none of which belongs in a transcript.
class AssignmentEnvelope {
  const AssignmentEnvelope({
    required this.assignmentId,
    required this.goalId,
    required this.agentId,
    required this.scope,
    required this.definitionOfDone,
  });
  final String assignmentId;
  final String goalId;
  final String agentId;
  final String scope;
  final String definitionOfDone;
}

AssignmentEnvelope? parseAssignmentEnvelope(String text) {
  final t = text.trim();
  if (envelopeKind(t) != 'coordination_assignment') return null;
  return AssignmentEnvelope(
    assignmentId: envelopeField(t, 'assignment_id'),
    goalId: envelopeField(t, 'goal_id'),
    agentId: envelopeField(t, 'agent_id'),
    scope: envelopeField(t, 'scope'),
    definitionOfDone: envelopeField(t, 'definition_of_done'),
  );
}

class AmbientTurn {
  const AmbientTurn({
    required this.device,
    required this.at,
    required this.text,
    this.mode = '',
    this.wake = false,
    this.continuation = false,
    this.interruptedReply = '',
    this.context = const [],
    this.judged = '',
    this.addressed,
    this.userVoice,
    this.expects = '',
    this.ids = const [],
    this.continuationOf = const [],
  });
  final List<String> ids;
  final List<String> continuationOf;
  final String device;
  final DateTime? at;
  final String text;
  final String mode;
  final bool wake;
  final bool continuation;
  final String interruptedReply;
  final List<String> context;
  final String judged;
  final double? addressed;
  final double? userVoice;
  final String expects;
}

String? voiceClassifierNote(String agentId, String body) {
  if (agentId != 'voice classifier' && agentId != 'ambient mode') return null;
  final text = body.trim();
  final mode = RegExp(
    r'^Ambient mode is now (\w+) \((.*)\)\.?$',
  ).firstMatch(text);
  if (mode != null) {
    final reason = (mode.group(2) ?? '').replaceFirst(
      RegExp(r'^mission_control:\s*'),
      '',
    );
    final label = mode.group(1) == 'active'
        ? 'Voice conversation started'
        : 'Back to passive listening';
    return reason.isEmpty ? label : '$label · $reason';
  }
  return 'Noted for later: $text';
}

AmbientTurn? parseAmbientTurn(String text) {
  final match = RegExp(
    r'^\s*<ambient_turn([^>]*)>([\s\S]*?)</ambient_turn>\s*$',
  ).firstMatch(text);
  if (match == null) return null;
  final attrs = <String, String>{
    for (final m in RegExp(r'(\w+)="([^"]*)"').allMatches(match.group(1) ?? ''))
      m.group(1)!: unescapeXml(m.group(2) ?? ''),
  };
  final raw = match.group(2) ?? '';
  final contextBlock =
      RegExp(r'<context>([\s\S]*?)</context>').firstMatch(raw)?.group(1) ?? '';
  final context = [
    for (final line in unescapeXml(contextBlock).split('\n'))
      if (line.trim().isNotEmpty)
        line.replaceFirst(RegExp(r'^\[earlier, not sent\]\s*'), '').trim(),
  ];
  final body = unescapeXml(
    raw.replaceAll(RegExp(r'<(recent_speech|context)>[\s\S]*?</\1>'), ''),
  );
  return AmbientTurn(
    device: attrs['device'] ?? '',
    at: DateTime.tryParse(attrs['at'] ?? '')?.toLocal(),
    text: body.trim(),
    mode: attrs['mode'] ?? '',
    wake: attrs['wake'] == 'true',
    continuation: (attrs['continuation_of'] ?? '').isNotEmpty,
    interruptedReply: attrs['interrupted_reply'] ?? '',
    context: context,
    judged: attrs['judged'] ?? '',
    addressed: double.tryParse(attrs['addressed'] ?? ''),
    userVoice: double.tryParse(attrs['user_voice'] ?? ''),
    expects: attrs['expects'] ?? '',
    ids: _idList(attrs['ids']),
    continuationOf: _idList(attrs['continuation_of']),
  );
}

List<String> _idList(String? raw) => [
  for (final s in (raw ?? '').split(','))
    if (s.trim().isNotEmpty) s.trim(),
];

String _spokenKey(String s) => s
    .toLowerCase()
    .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
    .replaceAll(RegExp(r' +'), ' ')
    .trim();

/// Ambient turn ids whose words a later continuation repeats in full, so the
/// earlier bubble can be dropped.
Set<String> supersededAmbientTurns(Iterable<String> texts) {
  final byId = <String, String>{};
  final out = <String>{};
  for (final text in texts) {
    final turn = parseAmbientTurn(text);
    if (turn == null) continue;
    final key = _spokenKey(turn.text);
    for (final parent in turn.continuationOf) {
      final prev = byId[parent];
      if (prev != null && prev.isNotEmpty && key.startsWith(prev))
        out.add(parent);
    }
    for (final id in turn.ids) {
      byId[id] = key;
    }
  }
  return out;
}

bool isAmbientResume(String text) =>
    text.trimLeft().startsWith('<ambient_resume');

/// Daemon-written routing instructions (`<routing>`) sent to the model when a
/// profile hits its usage limit or resets. Returns a clean one-line status for
/// the transcript when no `profile_switched` event already rendered it.
String? parseRoutingNote(String text) {
  final t = text.trim();
  if (envelopeKind(t) != 'routing') return null;
  final body = envelopeBody(t)
      .replaceFirst(
        RegExp(r'\s*Pick up where the last turn stopped and finish it\.?$'),
        '',
      )
      .trim();
  final switched = RegExp(
    r'^(.+?) hit its usage limit, so this session now runs on (.+?)\.?$',
  ).firstMatch(body);
  if (switched != null) {
    return '${switched.group(1)} hit its usage limit. Continuing on ${switched.group(2)}.';
  }
  return body.isEmpty ? 'Resumed after usage limit' : body;
}

/// What a notification says when an agent asks the user: the question itself,
/// with a count when it asks several, never a generic "needs input".
String userQuestionLead(Map<String, dynamic> e) {
  final raw = e['questions'];
  final list = raw is Map ? raw['questions'] : raw;
  final text = missionControlQuestionText({
    ...e,
    'questions': list is List ? list : const [],
  });
  if (text.isEmpty) return 'Needs your input';
  final more = list is List && list.length > 1
      ? ' (+${list.length - 1} more)'
      : '';
  return '$text$more';
}

String missionControlQuestionText(Map<String, dynamic> e) {
  final questions = e['questions'];
  if (questions is List && questions.isNotEmpty) {
    final first = questions.first;
    if (first is Map) {
      return (first['prompt'] ?? first['question'] ?? first['text'] ?? '')
          .toString()
          .trim();
    }
    return first.toString().trim();
  }
  return (e['text'] ?? e['question'] ?? '').toString().trim();
}
