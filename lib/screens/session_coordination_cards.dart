import 'dart:async';

import 'package:flutter/material.dart';

import '../platform.dart';
import '../transcript_card.dart';
import '../theme.dart';
import '../widgets.dart';
import '../chat/chat_card.dart';
import '../chat/signal_row.dart';
import '../mochi.dart';
import 'mission_control/mission_control_state.dart'
    show
        QuietWakeRun,
        GroupMessage,
        AmbientTurn,
        AssignmentEnvelope,
        AutonomousRound,
        BoardMessage,
        DirectMessage,
        MissionEnvelope,
        WorkerQuestion,
        WatchEnvelope,
        parseTaskOffer;

class CardMarkdownBody extends StatefulWidget {
  final String body;
  final String? preview;
  final bool collapsible;
  final bool selectable;
  const CardMarkdownBody(
      {super.key,
      required this.body,
      this.preview,
      this.collapsible = true,
      this.selectable = true});

  @override
  State<CardMarkdownBody> createState() => _CardMarkdownBodyState();
}

class _CardMarkdownBodyState extends State<CardMarkdownBody> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final body = widget.body.trim();
    final long = widget.collapsible &&
        (body.length > 160 || '\n'.allMatches(body).length > 1);
    final text = TranscriptCard.bodyStyle;
    final sheet = markdownStyle(context).copyWith(
      p: text,
      listBullet: text,
      strong:
          text.copyWith(color: AppColors.fg1, fontWeight: weightFor(W.strong)),
      em: text.copyWith(fontStyle: FontStyle.italic),
      del: text.copyWith(
          decoration: TextDecoration.lineThrough, color: AppColors.fg3),
      a: text.copyWith(color: AppColors.accent),
      h1: text.copyWith(color: AppColors.fg1, fontWeight: weightFor(W.strong)),
      h2: text.copyWith(color: AppColors.fg1, fontWeight: weightFor(W.strong)),
      h3: text.copyWith(color: AppColors.fg1, fontWeight: weightFor(W.strong)),
      h4: text.copyWith(color: AppColors.fg1, fontWeight: weightFor(W.strong)),
      h1Padding: EdgeInsets.zero,
      h2Padding: EdgeInsets.zero,
      h3Padding: EdgeInsets.zero,
      pPadding: EdgeInsets.zero,
      blockSpacing: 4,
      listIndent: 16,
      listBulletPadding: EdgeInsets.only(right: S.s4),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AnimatedSize(
          duration: Motion.fast,
          curve: Motion.enter,
          alignment: Alignment.topLeft,
          child: SizedBox(
            width: double.infinity,
            child: !_open && long && widget.preview != null
                ? Text(widget.preview!,
                    maxLines: 2, overflow: TextOverflow.ellipsis, style: text)
                : ConstrainedBox(
                    constraints: BoxConstraints(
                        maxHeight: _open || !long
                            ? double.infinity
                            : text.fontSize! * 1.4 * 2 + 2),
                    child: ShaderMask(
                      blendMode: BlendMode.dstIn,
                      shaderCallback: (r) => LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: _open || !long
                            ? const [Colors.white, Colors.white]
                            : const [
                                Colors.white,
                                Colors.white,
                                Colors.transparent
                              ],
                        stops: _open || !long ? null : const [0, 0.55, 1],
                      ).createShader(r),
                      child: ClipRect(
                        child: SingleChildScrollView(
                          physics: const NeverScrollableScrollPhysics(),
                          child: MarkdownBody(
                            data: unwrapCodedLinks(body),
                            selectable: widget.selectable && (_open || !long),
                            styleSheet: sheet,
                            builders: {'pre': PreBlockBuilder()},
                            onTapLink: (_, href, __) =>
                                openMarkdownLink(href, context),
                          ),
                        ),
                      ),
                    ),
                  ),
          ),
        ),
        if (long)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: EdgeInsets.only(top: S.s2),
              child: Text(_open ? 'Show less' : 'Show more',
                  style: sans(TranscriptCard.metaSize,
                      weight: W.label, color: AppColors.fg3)),
            ),
          ),
      ],
    );
  }
}

class _ThreadCard extends StatelessWidget {
  final String icon;
  final Tone tone;
  final String kind;
  final String? title;
  final String? status;
  final String body;
  final String? reference;
  final String? footer;
  const _ThreadCard({
    required this.icon,
    required this.tone,
    required this.kind,
    this.title,
    this.status,
    required this.body,
    this.reference,
    this.footer,
  });

  @override
  Widget build(BuildContext context) {
    final ref = reference?.trim() ?? '';
    final foot = footer?.trim() ?? '';
    return TranscriptCard(
      icon: icon,
      tone: tone,
      kind: ref.isEmpty ? kind : '$kind · $ref',
      status: status,
      title: title,
      footer: foot.isEmpty
          ? null
          : Text(foot,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(TranscriptCard.metaSize,
                  height: 1.35, color: AppColors.fg4)),
      child: body.trim().isEmpty ? null : CardMarkdownBody(body: body),
    );
  }
}

String _short(String id) => id.length > 8 ? id.substring(0, 8) : id;

/// A board thread id as a short reference: `task:<uuid>` reads `task eaa98084`.
String _threadRef(String id) {
  final i = id.indexOf(':');
  if (i <= 0) return _short(id);
  return '${id.substring(0, i)} ${_short(id.substring(i + 1))}';
}

class MissionEnvelopeCard extends StatelessWidget {
  const MissionEnvelopeCard({super.key, required this.envelope});
  final MissionEnvelope envelope;

  @override
  Widget build(BuildContext context) {
    final (tone, icon, tag) = envelope.isPlan
        ? (Tone.accent, 'list', 'Plan')
        : switch (envelope.eventKind) {
            'working' => (Tone.run, 'activity', 'Working'),
            'done' => (Tone.ok, 'check', 'Done'),
            'blocked' => (Tone.danger, 'alert-triangle', 'Blocked'),
            'failed' => (Tone.danger, 'x-circle', 'Failed'),
            'stalled' => (Tone.run, 'alert-triangle', 'Stalled'),
            'cancelled' => (Tone.neutral, 'x-circle', 'Cancelled'),
            'message' => (Tone.neutral, 'message', 'Message'),
            'update' => (Tone.neutral, 'info', 'Update'),
            _ => (Tone.accent, 'inbox', 'New task'),
          };
    if (envelope.review.isNotEmpty) {
      final findings = envelope.review == 'findings';
      final round = envelope.round.isEmpty ? '' : ' · round ${envelope.round}';
      return _ThreadCard(
        icon: findings ? 'alert-triangle' : 'eye',
        tone: findings ? Tone.run : Tone.accent,
        kind: findings ? 'Review findings$round' : 'Review request$round',
        reference: envelope.taskId.isEmpty ? null : _short(envelope.taskId),
        title: envelope.title.isEmpty ? 'Task' : envelope.title,
        status: findings ? 'Changes asked' : 'To review',
        body: envelope.summary,
      );
    }
    if (envelope.isPlan) {
      final steps = parsePlanSteps(envelope.summary);
      final done = steps.where((s) => s.$2 == PlanStep.done).length;
      return TranscriptCard(
        icon: 'list',
        tone: Tone.accent,
        kind: envelope.taskId.isEmpty
            ? 'Worker plan'
            : 'Worker plan · ${_short(envelope.taskId)}',
        title: envelope.title.isEmpty ? 'Task' : envelope.title,
        status: steps.isEmpty ? 'Plan' : '$done/${steps.length}',
        child: steps.isEmpty ? null : PlanChecklist(steps: steps),
      );
    }
    return _ThreadCard(
      icon: icon,
      tone: tone,
      kind: envelope.isRecurring
          ? 'Scheduled run'
          : envelope.isPlan
              ? 'Worker plan'
              : envelope.isReport
                  ? 'Task report'
                  : 'Task from Mission Control',
      reference: envelope.taskId.isEmpty ? null : _short(envelope.taskId),
      title: envelope.title.isEmpty
          ? (envelope.isRecurring ? 'Scheduled run' : 'Task')
          : envelope.title,
      status: tag,
      body: envelope.summary,
    );
  }
}

enum PlanStep { done, now, todo }

List<(String, PlanStep)> parsePlanSteps(String summary) => [
      for (final raw in summary.split('\n'))
        if (raw.trim().startsWith('- '))
          switch (raw.trim().substring(2).trim()) {
            final t
                when t.startsWith('~~') && t.endsWith('~~') && t.length > 4 =>
              (t.substring(2, t.length - 2), PlanStep.done),
            final t when t.startsWith('**') && t.endsWith('** · now') => (
                t.substring(2, t.length - '** · now'.length),
                PlanStep.now
              ),
            final t => (t, PlanStep.todo),
          },
    ];

class PlanChecklist extends StatefulWidget {
  const PlanChecklist({super.key, required this.steps});
  final List<(String, PlanStep)> steps;

  @override
  State<PlanChecklist> createState() => _PlanChecklistState();
}

class _PlanChecklistState extends State<PlanChecklist> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final steps = widget.steps;
    const cap = 4;
    var shown = steps;
    if (!_open && steps.length > cap) {
      final now = steps.indexWhere((s) => s.$2 != PlanStep.done);
      final from =
          (now < 0 ? steps.length - cap : now - 1).clamp(0, steps.length - cap);
      shown = steps.sublist(from, from + cap);
    }
    final style = TranscriptCard.bodyStyle;
    final lineH = style.fontSize! * style.height!;
    Widget mark(PlanStep s) => SizedBox(
          width: 14,
          height: lineH,
          child: Center(
            child: switch (s) {
              PlanStep.done => AppIcon('check', size: 11, color: AppColors.fg4),
              PlanStep.now => Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                      color: AppColors.accent, shape: BoxShape.circle)),
              PlanStep.todo => Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: AppColors.fg4, width: 1))),
            },
          ),
        );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final (text, state) in shown)
          Padding(
            padding: EdgeInsets.only(bottom: S.of(3)),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                mark(state),
                SizedBox(width: S.s6),
                Expanded(
                  child: Text(text,
                      maxLines: _open ? null : 1,
                      overflow: _open ? null : TextOverflow.ellipsis,
                      style: style.copyWith(
                          color: switch (state) {
                        PlanStep.done => AppColors.fg4,
                        PlanStep.now => AppColors.fg1,
                        PlanStep.todo => AppColors.fg2,
                      })),
                ),
              ],
            ),
          ),
        if (steps.length > cap)
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => setState(() => _open = !_open),
            child: Padding(
              padding: EdgeInsets.only(top: S.s4, left: S.s20),
              child: Text(
                  _open ? 'Show less' : 'Show all ${steps.length} steps',
                  style: sans(TranscriptCard.metaSize,
                      weight: W.label, color: AppColors.fg3)),
            ),
          ),
      ],
    );
  }
}

class BoardMessageCard extends StatelessWidget {
  const BoardMessageCard({super.key, required this.message});
  final BoardMessage message;

  @override
  Widget build(BuildContext context) {
    final from = message.fromId.trim().isEmpty ? 'Someone' : message.fromId;
    return _ThreadCard(
      icon: 'coordination',
      tone: Tone.neutral,
      kind: 'Board · $from',
      reference: message.threadId.isEmpty ? null : _threadRef(message.threadId),
      status: 'Posted',
      body: message.body,
    );
  }
}

class DirectMessageCard extends StatelessWidget {
  const DirectMessageCard({super.key, required this.message});
  final DirectMessage message;

  @override
  Widget build(BuildContext context) {
    final from = message.fromLabel;
    final who = from == 'you' ? 'You' : from;
    final offer = message.isReply ? null : parseTaskOffer(message.body);
    if (offer != null) {
      return _ThreadCard(
        icon: 'agent',
        tone: Tone.run,
        kind: 'Task offer from $who',
        title: offer.title.isEmpty ? null : offer.title,
        reference: offer.taskId.isEmpty ? null : _short(offer.taskId),
        status: 'Offered',
        body: offer.briefing,
        footer: 'Starts once claimed; the agent can also ask or decline',
      );
    }
    final typed = message.messageKind.replaceAll('_', ' ');
    final label =
        typed.isEmpty ? '' : '${typed[0].toUpperCase()}${typed.substring(1)}';
    return _ThreadCard(
      icon: message.isReply ? 'corner-down-right' : 'message',
      tone: message.urgent ? Tone.danger : Tone.accent,
      kind: message.isReply ? 'Reply from $who' : 'Message from $who',
      status: message.urgent
          ? (label.isEmpty ? 'Urgent' : '$label, urgent')
          : (label.isNotEmpty
              ? label
              : (message.isReply ? 'Reply' : 'Message')),
      body: message.body,
    );
  }
}

class GroupMessageCard extends StatelessWidget {
  const GroupMessageCard({super.key, required this.message});
  final GroupMessage message;

  @override
  Widget build(BuildContext context) {
    final m = message;
    final group = m.title.isEmpty ? 'a group' : m.title;
    if (m.added) {
      return _ThreadCard(
        icon: 'users',
        tone: Tone.accent,
        kind: 'Added to $group',
        status: 'Group',
        body: [
          if (m.members.isNotEmpty) m.members.join(', '),
          if (m.lead.isNotEmpty) 'lead ${m.lead}',
        ].join(' · '),
      );
    }
    return _ThreadCard(
      icon: 'users',
      tone: m.replyExpected ? Tone.run : Tone.accent,
      kind: '${m.fromLabel} in $group',
      status: m.replyExpected
          ? 'Reply expected'
          : (m.mentions.isNotEmpty
              ? 'Mentioned ${m.mentions.join(', ')}'
              : 'Group'),
      body: m.body,
    );
  }
}

class AutonomousRoundCard extends StatefulWidget {
  const AutonomousRoundCard({super.key, required this.round});
  final AutonomousRound round;

  @override
  State<AutonomousRoundCard> createState() => _AutonomousRoundCardState();
}

class _AutonomousRoundCardState extends State<AutonomousRoundCard> {
  bool _open = false;

  @override
  Widget build(BuildContext context) {
    final r = widget.round;
    final sections = [
      ('Due', r.due),
      ('Changed', r.changed),
      ('Open', r.open),
      ('Scheduled', r.scheduled),
    ].where((s) => s.$2.isNotEmpty).toList();
    final items = [for (final s in sections) ...s.$2.map(_plain)];
    final summary = r.firstRound
        ? 'Automated wakes switched on'
        : r.due.isNotEmpty
            ? '${r.due.length} due'
            : r.changed.isNotEmpty
                ? '${r.changed.length} changed'
                : 'nothing new';
    final body = TranscriptCard.bodyStyle;
    final shown = r.due.isNotEmpty
        ? r.due.first
        : r.changed.isNotEmpty
            ? r.changed.first
            : '';
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SignalRow(
          icon: 'clock',
          tone: r.due.isNotEmpty ? SignalTone.run : SignalTone.neutral,
          text: 'Woke on schedule \u00b7 $summary',
          sub: shown.isEmpty ? null : _plain(shown),
          time: _roundTime(r.time),
          onTap: items.isEmpty ? null : () => setState(() => _open = !_open),
        ),
        if (_open)
          for (final (label, list) in sections) ...[
            Padding(
              padding: EdgeInsets.only(left: S.of(28), top: S.s4),
              child: Text(label,
                  style: sans(TranscriptCard.metaSize,
                      weight: W.label, color: AppColors.fg4)),
            ),
            for (final item in list)
              Padding(
                padding: EdgeInsets.only(left: S.of(28), top: S.s2),
                child: SelectableText(_plain(item), style: body),
              ),
          ],
      ],
    );
  }
}

/// One quiet row for a run of automated wakes that needed nothing from the user.
class QuietWakesRow extends StatefulWidget {
  const QuietWakesRow({super.key, required this.run});
  final QuietWakeRun run;

  @override
  State<QuietWakesRow> createState() => _QuietWakesRowState();
}

class _QuietWakesRowState extends State<QuietWakesRow> {
  bool _open = false;

  String get _span {
    final wakes = widget.run.wakes;
    final first = _roundTime(wakes.first.time);
    if (wakes.length == 1) return first;
    final last = _roundTime(wakes.last.time);
    final firstDay = first.split(' ').first;
    return last.startsWith('$firstDay ')
        ? '$first to ${last.substring(firstDay.length + 1)}'
        : '$first to $last';
  }

  @override
  Widget build(BuildContext context) {
    final wakes = widget.run.wakes;
    final meta = TranscriptCard.metaSize;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SignalRow(
          icon: 'clock',
          text: wakes.length == 1
              ? 'Woke on schedule \u00b7 nothing new'
              : 'Woke ${wakes.length} times \u00b7 nothing new',
          time: _span,
          onTap: () => setState(() => _open = !_open),
        ),
        if (_open)
          for (final wake in wakes)
            Padding(
              padding: EdgeInsets.only(left: S.of(28), top: S.s4, bottom: S.s4),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(_roundTime(wake.time),
                      style: sans(meta, color: AppColors.fg4)),
                  SizedBox(height: S.s2),
                  SelectableText(_plain(wake.reply),
                      style: TranscriptCard.bodyStyle),
                ],
              ),
            ),
      ],
    );
  }
}

String _roundTime(String time) {
  final parts = time.trim().split(RegExp(r'\s+'));
  if (parts.length < 2) return time.isEmpty ? 'Wake' : time;
  return '${parts.first} ${parts.last}';
}

String _plain(String line) => line.replaceAll('**', '');

class WorkerQuestionCard extends StatelessWidget {
  const WorkerQuestionCard({super.key, required this.question});
  final WorkerQuestion question;

  @override
  Widget build(BuildContext context) => ChatCard(children: [
        ChatCardHeader(
          title: question.question.trim(),
          subtitle: question.task.trim(),
          trailing: const ChatCardPill('1 of 1'),
        ),
        ChatCardBody(
          child: Text(
            'Mission Control answers from your brief, or pings you',
            style: sans(TranscriptCard.metaSize, color: AppColors.fg3),
          ),
        ),
      ]);
}

class AgentMessageCard extends StatelessWidget {
  const AgentMessageCard({
    super.key,
    required this.agentId,
    required this.body,
    required this.outbound,
    this.laneTitle,
    this.meId,
    this.meName,
    this.time,
    this.at,
  });

  final String agentId;
  final String body;
  final bool outbound;
  final String? laneTitle;

  /// This session's own agent, for the "Me to Them" label.
  final String? meId;
  final String? meName;
  final String? time;

  /// Raw event time, for lane cards.
  final dynamic at;

  @override
  Widget build(BuildContext context) {
    final lane = agentId.startsWith('lane ');
    if (lane) {
      final given = laneTitle?.trim() ?? '';
      final laneName = given.isNotEmpty ? given : agentId.substring(5).trim();
      return LaneMessageCard(
        laneTitle: laneName,
        notes: outbound ? const [] : [LaneNote(body: body, at: at)],
        reply: outbound ? body : null,
        replyAt: outbound ? at : null,
        meId: meId,
        meName: meName,
      );
    }
    return AgentNamesBuilder(builder: (context, names) {
      final them = agentDisplayName(agentId, names);
      final meKey = meId?.trim() ?? '';
      final me = (meName?.trim().isNotEmpty ?? false)
          ? meName!.trim()
          : (meKey.isEmpty ? '' : agentDisplayName(meKey, names));
      final env = parseCoordinationEnvelope(body);
      if (env != null) {
        final sender = outbound ? (me.isEmpty ? 'You' : me) : them;
        final sig = envelopeSignal(env, sender);
        return SignalRow(
          icon: sig.icon,
          tone: sig.tone,
          leading: outbound && meKey.isEmpty
              ? null
              : AgentMochi(outbound ? meKey : agentId, size: 20),
          text: sig.text,
          sub: sig.sub,
          time: time,
        );
      }
      return _AgentBubble(
        id: outbound ? meKey : agentId,
        label: outbound ? (me.isEmpty ? 'To $them' : '$me to $them') : them,
        body: body,
        outbound: outbound,
      );
    });
  }
}

/// One message in a lane card: its body and when it arrived.
class LaneNote {
  const LaneNote({required this.body, this.at});
  final String body;
  final dynamic at;
}

/// The glyph a lane wears in chat, read from its title.
String laneGlyph(String title) {
  final t = title.toLowerCase();
  if (RegExp(r'setting|config|prefer').hasMatch(t)) return 'settings';
  if (RegExp(r'tool|terminal|shell|cli').hasMatch(t)) return 'terminal';
  if (RegExp(r'agent|bot').hasMatch(t)) return 'bot';
  if (RegExp(r'test|check|verif').hasMatch(t)) return 'check-check';
  if (RegExp(r'search|research|audit').hasMatch(t)) return 'search';
  if (RegExp(r'git|branch|pr\b|merge').hasMatch(t)) return 'git-branch';
  return 'layers';
}

DateTime? _eventDate(dynamic raw) {
  if (raw is num && raw > 0) {
    final ms = raw > 100000000000 ? raw.toInt() : (raw * 1000).toInt();
    return DateTime.fromMillisecondsSinceEpoch(ms);
  }
  if (raw is String && raw.isNotEmpty) return DateTime.tryParse(raw)?.toLocal();
  return null;
}

String _elapsed(Duration d) {
  if (d.inMinutes < 1) return '';
  if (d.inMinutes < 60) return ' ${d.inMinutes} min';
  return ' ${d.inHours} h';
}

/// The status word in a lane card's header.
String laneStatusWord({required List<LaneNote> notes, bool answered = false}) {
  if (notes.isEmpty) return '';
  if (notes.last.body.contains('?')) return answered ? 'asked' : 'asks';
  return notes.length > 1 ? '${notes.length} notes' : 'note';
}

/// A lane's notes to its parent, grouped, with the parent's reply inside.
/// [notes] runs oldest first; empty means the parent told the lane first.
class LaneMessageCard extends StatefulWidget {
  const LaneMessageCard({
    super.key,
    required this.laneTitle,
    required this.notes,
    this.reply,
    this.replyAt,
    this.meId,
    this.meName,
    this.waiting = false,
    this.onOpenLane,
  });

  final String laneTitle;
  final List<LaneNote> notes;
  final String? reply;
  final dynamic replyAt;
  final String? meId;
  final String? meName;

  /// The newest note asks, nobody answered, and the lane still runs.
  final bool waiting;
  final VoidCallback? onOpenLane;

  @override
  State<LaneMessageCard> createState() => _LaneMessageCardState();
}

class _LaneMessageCardState extends State<LaneMessageCard> {
  bool _open = false;
  bool _earlier = false;
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _syncTick();
  }

  @override
  void didUpdateWidget(covariant LaneMessageCard old) {
    super.didUpdateWidget(old);
    _syncTick();
  }

  // The waiting clock reads in minutes; refresh it once a minute.
  void _syncTick() {
    if (widget.waiting && _tick == null) {
      _tick = Timer.periodic(
          const Duration(minutes: 1), (_) => mounted ? setState(() {}) : null);
    } else if (!widget.waiting) {
      _tick?.cancel();
      _tick = null;
    }
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  static String _plain(String body) => body
      .replaceAll(RegExp(r'[#*`>_]+'), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();

  @override
  Widget build(BuildContext context) {
    final notes = widget.notes;
    final told = notes.isEmpty;
    final reply = widget.reply?.trim() ?? '';
    final newest = told ? null : notes.last;
    final earlier =
        told ? const <LaneNote>[] : notes.sublist(0, notes.length - 1);
    final indent = S.of(34);
    final faint = AppColors.fg4;

    var status =
        told ? '' : laneStatusWord(notes: notes, answered: reply.isNotEmpty);
    if (widget.waiting && status == 'asks') {
      final at = _eventDate(newest!.at);
      status =
          'asks · waiting${at == null ? '' : _elapsed(DateTime.now().difference(at))}';
    }
    final time = formatEventTime(told ? widget.replyAt : newest!.at);

    final header = Row(children: [
      Container(
        width: 26,
        height: 26,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surface3,
          borderRadius: BorderRadius.circular(R.of(8)),
        ),
        child: AppIcon(laneGlyph(widget.laneTitle),
            size: 14, color: AppColors.accent),
      ),
      const SizedBox(width: 8),
      Expanded(
        child: Row(children: [
          if (told) ...[
            Text('Told',
                style: sans(14, height: 18 / 14, color: AppColors.fg3)),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: Text(widget.laneTitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(14,
                    weight: FontWeight.w500,
                    height: 18 / 14,
                    color: AppColors.fg1)),
          ),
          if (status.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(status,
                style: sans(12,
                    height: 18 / 12.5,
                    color: widget.waiting ? AppColors.run : AppColors.fg3)),
          ],
        ]),
      ),
      if (time != null && !widget.waiting) ...[
        const SizedBox(width: 8),
        Text(time, style: sans(12, color: faint)),
      ],
    ]);

    final text = sans(14, height: 20 / 14, color: AppColors.fg2);
    Widget noteBody(LaneNote n, {required bool open}) => open
        ? CardMarkdownBody(body: n.body.trim(), collapsible: false)
        : Text(_plain(n.body),
            maxLines: 3, overflow: TextOverflow.ellipsis, style: text);

    final children = <Widget>[header];
    if (earlier.isNotEmpty) {
      children.add(Padding(
        padding: EdgeInsets.only(left: indent),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () => setState(() => _earlier = !_earlier),
          child: Row(children: [
            Container(
                width: 4,
                height: 4,
                decoration:
                    BoxDecoration(color: faint, shape: BoxShape.circle)),
            const SizedBox(width: 6),
            Text(
                _earlier
                    ? 'Hide ${earlier.length} earlier'
                    : '${earlier.length} earlier',
                style: sans(12, height: 18 / 12, color: AppColors.fg3)),
          ]),
        ),
      ));
      if (_earlier) {
        for (final n in earlier) {
          final t = formatEventTime(n.at);
          children.add(Padding(
            padding: EdgeInsets.only(left: indent),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Expanded(child: noteBody(n, open: _open)),
              if (t != null) ...[
                const SizedBox(width: 8),
                Text(t, style: sans(12, height: 20 / 12, color: faint)),
              ],
            ]),
          ));
        }
      }
    }
    if (newest != null) {
      children.add(Padding(
        padding: EdgeInsets.only(left: indent),
        child: noteBody(newest, open: _open),
      ));
    }
    if (reply.isNotEmpty) {
      final me = widget.meId?.trim() ?? '';
      children.add(AgentNamesBuilder(builder: (context, names) {
        final given = widget.meName?.trim() ?? '';
        final name = given.isNotEmpty
            ? given
            : (me.isEmpty ? 'You' : agentDisplayName(me, names));
        final small = sans(13, height: 19 / 13, color: AppColors.fg2);
        final body = told
            ? (_open
                ? CardMarkdownBody(body: reply, collapsible: false)
                : Text(_plain(reply),
                    maxLines: 3, overflow: TextOverflow.ellipsis, style: text))
            : (_open
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                        Text(name,
                            style: small.copyWith(
                                fontWeight: FontWeight.w500,
                                color: AppColors.fg1)),
                        CardMarkdownBody(body: reply, collapsible: false),
                      ])
                : Text.rich(
                    TextSpan(style: small, children: [
                      TextSpan(
                          text: '$name ',
                          style: TextStyle(
                              fontWeight: FontWeight.w500,
                              color: AppColors.fg1)),
                      TextSpan(text: _plain(reply)),
                    ]),
                    maxLines: 4,
                    overflow: TextOverflow.ellipsis));
        if (told) {
          return Padding(padding: EdgeInsets.only(left: indent), child: body);
        }
        return Container(
          margin: EdgeInsets.only(left: indent, top: 4),
          padding: const EdgeInsets.only(top: 8),
          decoration: BoxDecoration(
              border: Border(top: BorderSide(color: AppColors.border))),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: me.isEmpty
                  ? const SizedBox(width: 18, height: 18)
                  : AgentMochi(me, size: 18),
            ),
            const SizedBox(width: 8),
            Expanded(child: body),
          ]),
        );
      }));
    }
    if (widget.waiting && widget.onOpenLane != null) {
      children.add(Padding(
        padding: EdgeInsets.only(left: indent, top: 6),
        child: Row(children: [
          _LaneCardButton(label: 'Open lane', onTap: widget.onOpenLane!),
        ]),
      ));
    }

    final radius = BorderRadius.circular(R.of(14));
    return Padding(
      padding: EdgeInsets.symmetric(vertical: S.s4),
      child: Material(
        color: AppColors.surface1,
        shape: RoundedRectangleBorder(
            borderRadius: radius, side: BorderSide(color: AppColors.border)),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          borderRadius: radius,
          onTap: () => setState(() => _open = !_open),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                for (var i = 0; i < children.length; i++) ...[
                  if (i > 0) const SizedBox(height: 4),
                  children[i],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _LaneCardButton extends StatelessWidget {
  const _LaneCardButton({required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(R.of(10));
    return Material(
      color: AppColors.surface3,
      borderRadius: radius,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: Container(
          constraints: const BoxConstraints(minHeight: 32),
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(label, style: sans(13, color: AppColors.fg1)),
        ),
      ),
    );
  }
}

class _AgentBubble extends StatelessWidget {
  const _AgentBubble(
      {required this.id,
      required this.label,
      required this.body,
      required this.outbound});

  final String id;
  final String label;
  final String body;
  final bool outbound;

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.only(
      topLeft: Radius.circular(R.of(18)),
      topRight: Radius.circular(R.of(18)),
      bottomLeft: Radius.circular(outbound ? R.of(18) : R.sm),
      bottomRight: Radius.circular(outbound ? R.sm : R.of(18)),
    );
    final bubble = Container(
      padding: EdgeInsets.symmetric(horizontal: S.s12, vertical: S.s8),
      decoration: BoxDecoration(
        color: outbound ? AppColors.accentBg : AppColors.surface2,
        borderRadius: radius,
      ),
      child: CardMarkdownBody(body: body, collapsible: true),
    );
    final col = Column(
      crossAxisAlignment:
          outbound ? CrossAxisAlignment.end : CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: EdgeInsets.fromLTRB(S.s4, 0, S.s4, S.s2),
          child: Text(label, style: sans(12, color: AppColors.fg3)),
        ),
        bubble,
      ],
    );
    return Padding(
      padding: EdgeInsets.symmetric(vertical: S.s4),
      child: LayoutBuilder(builder: (context, box) {
        final cap = (box.maxWidth.isFinite ? box.maxWidth * 0.8 : 560.0)
            .clamp(0.0, 600.0);
        final avatar =
            id.isEmpty ? const SizedBox.shrink() : AgentMochi(id, size: 28);
        return Row(
          mainAxisAlignment:
              outbound ? MainAxisAlignment.end : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            if (!outbound) ...[avatar, SizedBox(width: S.s8)],
            Flexible(
                child: ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: cap), child: col)),
            if (outbound && id.isNotEmpty) ...[SizedBox(width: S.s8), avatar],
          ],
        );
      }),
    );
  }
}

class ParentMessageCard extends StatelessWidget {
  const ParentMessageCard({super.key, required this.body});
  final String body;

  @override
  Widget build(BuildContext context) => _ThreadCard(
        icon: 'corner-down-right',
        tone: Tone.accent,
        kind: 'From the agent that handed this over',
        status: 'Message',
        body: body,
      );
}

class AssignmentCard extends StatelessWidget {
  const AssignmentCard({super.key, required this.assignment});
  final AssignmentEnvelope assignment;

  @override
  Widget build(BuildContext context) {
    final agent = assignment.agentId.trim();
    final done = assignment.definitionOfDone.trim();
    return _ThreadCard(
      icon: 'agent',
      tone: Tone.run,
      kind: 'Assignment',
      title: agent.isEmpty ? 'Work assigned here' : 'Assigned to $agent',
      status: 'Assigned',
      body: assignment.scope,
      footer: done.isEmpty ? null : 'Done when: $done',
    );
  }
}

class AmbientTurnCard extends StatefulWidget {
  const AmbientTurnCard({super.key, required this.turn});
  final AmbientTurn turn;

  @override
  State<AmbientTurnCard> createState() => _AmbientTurnCardState();
}

class _AmbientTurnCardState extends State<AmbientTurnCard> {
  bool _open = false;

  AmbientTurn get turn => widget.turn;

  String get _where {
    final os = turn.device.split('-').first;
    return switch (os) {
      'android' => 'Android',
      'ios' => 'iPhone',
      'macos' => 'Mac',
      'linux' => 'Linux',
      'windows' => 'Windows',
      _ => turn.device,
    };
  }

  bool get _hasDetail =>
      turn.context.isNotEmpty ||
      turn.interruptedReply.isNotEmpty ||
      turn.judged.isNotEmpty ||
      turn.addressed != null ||
      turn.userVoice != null;

  @override
  Widget build(BuildContext context) {
    final at = turn.at;
    final time = at == null
        ? ''
        : '${at.hour.toString().padLeft(2, '0')}:${at.minute.toString().padLeft(2, '0')}';
    final meta = [
      _where,
      if (time.isNotEmpty) time,
      if (turn.mode == 'passive') 'passive',
      if (turn.wake) 'wake word',
      if (turn.userVoice != null) 'voice ${(turn.userVoice! * 100).round()}%',
      if (turn.continuation) 'continuation',
      if (turn.interruptedReply.isNotEmpty) 'interrupted a reply',
      if (turn.context.isNotEmpty)
        '${turn.context.length} earlier ${turn.context.length == 1 ? 'line' : 'lines'}',
    ].join(' · ');
    final detail = sans(kMobile ? 13 : 13, height: 1.4, color: AppColors.fg3);
    return LayoutBuilder(builder: (context, box) {
      final inset = kMobile
          ? 48.0
          : (box.maxWidth.isFinite ? box.maxWidth * 0.18 : 140.0)
              .clamp(24.0, 140.0);
      return Padding(
        padding: EdgeInsets.only(left: inset),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _hasDetail ? () => setState(() => _open = !_open) : null,
              child: Container(
                padding: kMobile
                    ? EdgeInsets.fromLTRB(
                        S.of(15), S.of(10), S.of(15), S.of(11))
                    : EdgeInsets.fromLTRB(
                        S.of(14), S.of(9), S.of(14), S.of(10)),
                decoration: BoxDecoration(
                  color: AppColors.surface2,
                  borderRadius: kMobile
                      ? BorderRadius.only(
                          topLeft: Radius.circular(R.of(20)),
                          topRight: Radius.circular(R.of(20)),
                          bottomLeft: Radius.circular(R.of(20)),
                          bottomRight: Radius.circular(R.sm),
                        )
                      : BorderRadius.circular(R.of(20)),
                ),
                child: SelectionArea(
                  child: Text(
                    turn.text,
                    textWidthBasis: TextWidthBasis.longestLine,
                    style: sans(
                      kMobile ? 16 : 14,
                      height: kMobile ? 24 / 16 : 22 / 14,
                      color: AppColors.fg1,
                    ),
                  ),
                ),
              ),
            ),
            Padding(
              padding: EdgeInsets.only(top: S.s4, right: S.s2),
              child: Text(meta,
                  textAlign: TextAlign.end,
                  style: sans(kMobile ? 13 : 12, color: AppColors.fg4)),
            ),
            if (_open) ...[
              SizedBox(height: S.s6),
              if (turn.judged.isNotEmpty ||
                  turn.addressed != null ||
                  turn.userVoice != null)
                Text(
                    [
                      if (turn.judged.isNotEmpty) 'Judged ${turn.judged}',
                      if (turn.userVoice != null)
                        'voice match ${(turn.userVoice! * 100).round()}%',
                      if (turn.addressed != null)
                        'reply expected ${(turn.addressed! * 100).round()}%',
                      if (turn.expects.isNotEmpty)
                        'answering a ${turn.expects} question',
                    ].join(' · '),
                    textAlign: TextAlign.end,
                    style: detail),
              if (turn.interruptedReply.isNotEmpty) ...[
                SizedBox(height: S.s4),
                Text('Heard of its last reply: ${turn.interruptedReply}',
                    textAlign: TextAlign.end, style: detail),
              ],
              for (final line in turn.context) ...[
                SizedBox(height: S.s4),
                Text('Earlier, not sent: $line',
                    textAlign: TextAlign.end, style: detail),
              ],
            ],
          ],
        ),
      );
    });
  }
}

class SpeakCard extends StatelessWidget {
  const SpeakCard({super.key, required this.text, this.expecting = ''});
  final String text;
  final String expecting;

  @override
  Widget build(BuildContext context) {
    final asking =
        expecting.isNotEmpty && expecting != 'none' && text.contains('?');
    return TranscriptCard(
      icon: 'volume',
      tone: asking ? Tone.accent : Tone.neutral,
      kind: 'Said aloud',
      status: asking ? 'Waiting for you' : null,
      body: text,
    );
  }
}

class WatchEnvelopeCard extends StatelessWidget {
  const WatchEnvelopeCard({super.key, required this.watch});
  final WatchEnvelope watch;

  @override
  Widget build(BuildContext context) {
    final error = watch.event == 'error';
    final n = watch.lines.length;
    final first = watch.lines.isEmpty ? '' : watch.lines.first.trim();
    return SignalRow(
      icon: error ? 'alert-triangle' : 'eye',
      tone: error ? SignalTone.danger : SignalTone.accent,
      text: error
          ? '**${watch.name}** is failing'
          : '**${watch.name}** updated \u00b7 $n new ${n == 1 ? 'line' : 'lines'}',
      sub: first.length > 100 ? '${first.substring(0, 99)}\u2026' : first,
    );
  }
}

class WakeNoteCard extends StatelessWidget {
  const WakeNoteCard({super.key, required this.note});
  final String note;

  @override
  Widget build(BuildContext context) => SignalRow(
        icon: 'clock',
        text: 'Woke on a note it left itself',
        sub: note,
      );
}
