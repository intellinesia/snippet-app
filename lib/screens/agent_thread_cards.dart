import 'package:flutter/material.dart';

import '../desktop_look.dart';
import '../api.dart';
import '../chat/chat_style.dart' show ChatColors;
import '../approval_code.dart';
import '../chat/chat_card.dart';
import '../media_views.dart';
import '../models.dart';
import '../notification_text.dart';
import '../platform.dart';
import '../session_quick_send.dart';
import '../theme.dart';
import '../tool_activity.dart';
import '../transcript.dart';
import '../transcript_card.dart';
import '../widgets.dart';
import 'agent_questions_card.dart';
import 'artifact_viewer.dart';
import 'presented_file_card.dart';

String daemonRelativeUrl(DaemonClient client, String url) {
  final raw = url.trim();
  if (raw.isEmpty) return '';
  final parsed = Uri.parse(raw);
  if (parsed.hasScheme) return raw;
  final base = Uri.parse(client.baseUrl);
  return base.replace(
    path: parsed.path,
    queryParameters: {
      ...parsed.queryParameters,
      if (client.token.isNotEmpty &&
          !parsed.queryParameters.containsKey('token'))
        'token': client.token,
    },
  ).toString();
}

Widget? agentThreadEventCard(
  CoordinationEvent e, {
  required DaemonClient client,
  required String agentId,
  List<CoordinationEvent> events = const [],
}) {
  final payload = e.payload;
  final attachment = payload['attachment'];
  if (attachment is Map && attachment['kind'] == 'audio') {
    return _audioCard(e, attachment, client: client);
  }
  final artifact = payload['artifact'];
  if (artifact is Map) {
    return _artifactCard(e, artifact, client: client, agentId: agentId);
  }
  final question = payload['question'];
  if (question is Map) {
    if (question['questions'] is List) {
      return AgentQuestionsCard(
        event: e,
        question: question,
        client: client,
        events: events,
      );
    }
    return _questionCard(e, question, answer: payload['answer']);
  }
  final approval = payload['approval'];
  if (approval is Map) {
    if ('${approval['session'] ?? ''}'.isNotEmpty &&
        '${approval['approval_id'] ?? ''}'.isNotEmpty) {
      return DeskApprovalCard(
          event: e, approval: approval, client: client);
    }
    return _approvalCard(e, approval);
  }
  final tools = payload['tool_activity'];
  if (tools is List && tools.isNotEmpty) {
    final items = tools.whereType<Map>().toList();
    if (items.isNotEmpty) return _ToolActivityCard(items: items);
  }
  return null;
}

Widget _audioCard(
  CoordinationEvent e,
  Map<dynamic, dynamic> attachment, {
  required DaemonClient client,
}) {
  final relUrl = (attachment['url'] ?? '').toString().trim();
  final fallbackPath = (attachment['path'] ?? '').toString().trim();
  final resolvedUrl =
      relUrl.isNotEmpty ? daemonRelativeUrl(client, relUrl) : null;
  final durationMs = (attachment['duration_ms'] as num?)?.toInt();
  final duration = durationMs != null && durationMs > 0
      ? Duration(milliseconds: durationMs)
      : null;
  final fromAttachment = (attachment['transcript'] ?? '').toString().trim();
  final transcriptText =
      fromAttachment.isNotEmpty ? fromAttachment : e.body.trim();
  return Container(
    constraints: BoxConstraints(maxWidth: kMobile ? 272 : 340),
    padding: const EdgeInsets.fromLTRB(8, 8, 12, 10),
    decoration: BoxDecoration(
      color: ChatColors.received,
      borderRadius: BorderRadius.circular(ChatColors.radius),
    ),
    child: VoiceNote(
      client: client,
      ink: ChatColors.receivedText,
      path: fallbackPath,
      url: resolvedUrl,
      duration: duration,
      transcript: AudioTranscriptCard(
        items: [
          if (transcriptText.isNotEmpty) AudioTranscriptItem(transcriptText),
        ],
      ),
    ),
  );
}

Widget _artifactCard(
  CoordinationEvent e,
  Map<dynamic, dynamic> artifact, {
  required DaemonClient client,
  required String agentId,
}) {
  final id = (artifact['id'] ?? '').toString().trim();
  final rawSession = (artifact['session'] ?? '').toString().trim();
  final originSession = (e.payload['origin_session'] ?? '').toString().trim();
  final session = rawSession.isNotEmpty
      ? rawSession
      : (originSession.isNotEmpty ? originSession : 'inbox-$agentId');
  final rawTitle = (artifact['title'] ?? '').toString().trim();
  final title =
      rawTitle.isNotEmpty ? rawTitle : (id.isNotEmpty ? id : 'Artifact');
  final version = (artifact['version'] as num?)?.toInt() ?? 1;
  final kind = (artifact['kind'] ?? 'file').toString().trim();
  final caption = (artifact['caption'] ?? '').toString().trim();
  if (id.isEmpty) {
    final path = (artifact['path'] ?? artifact['url'] ?? '').toString().trim();
    if (path.isNotEmpty) {
      return PresentedFileCard(
        client: client,
        path: path,
        caption: title,
      );
    }
  }
  return ArtifactRow(
    client: client,
    session: session,
    id: id,
    version: version,
    title: title,
    kind: kind.isEmpty ? 'file' : kind,
    caption: caption,
  );
}

class _ChoiceItem {
  final String value;
  final String label;
  final String description;
  final bool recommended;
  const _ChoiceItem({
    required this.value,
    required this.label,
    required this.description,
    required this.recommended,
  });
}

List<_ChoiceItem> _parseChoices(Map<dynamic, dynamic> q, String kind) {
  final raw = q['choices'];
  if (raw is List && raw.isNotEmpty) {
    return [
      for (final c in raw.whereType<Map>())
        () {
          final label = (c['label'] ?? c['value'] ?? '').toString().trim();
          final value = (c['value'] ?? label).toString().trim();
          return _ChoiceItem(
            value: value,
            label: label.isEmpty ? value : label,
            description: (c['description'] ?? '').toString().trim(),
            recommended: c['recommended'] == true,
          );
        }(),
    ];
  }
  if (kind == 'yes_no') {
    return const [
      _ChoiceItem(
          value: 'yes', label: 'Yes', description: '', recommended: false),
      _ChoiceItem(
          value: 'no', label: 'No', description: '', recommended: false),
    ];
  }
  if (kind == 'confirm') {
    return const [
      _ChoiceItem(
          value: 'confirm',
          label: 'Confirm',
          description: '',
          recommended: false),
      _ChoiceItem(
          value: 'cancel',
          label: 'Cancel',
          description: '',
          recommended: false),
    ];
  }
  return const [];
}

Set<String> _answerTokens(Object? raw, {required bool multi}) {
  if (raw == null) return const {};
  if (raw is List) {
    return {
      for (final item in raw)
        if (item != null && '$item'.trim().isNotEmpty) '$item'.trim(),
    };
  }
  if (raw is Map) {
    final v =
        (raw['value'] ?? raw['label'] ?? raw['text'] ?? '').toString().trim();
    return v.isEmpty ? const {} : {v};
  }
  final s = '$raw'.trim();
  if (s.isEmpty) return const {};
  if (multi && s.contains(',')) {
    return {
      for (final part in s.split(','))
        if (part.trim().isNotEmpty) part.trim(),
    };
  }
  return {s};
}

bool _choiceMatches(_ChoiceItem c, Set<String> tokens) {
  if (tokens.isEmpty) return false;
  final combined = '${c.label} (${c.value})';
  return tokens.contains(c.value) ||
      tokens.contains(c.label) ||
      tokens.contains(combined);
}

Widget _questionCard(
  CoordinationEvent e,
  Map<dynamic, dynamic> question, {
  Object? answer,
}) {
  final rawText = (question['text'] ?? '').toString().trim();
  final text = rawText.isNotEmpty ? rawText : e.body.trim();
  final kind = (question['kind'] ?? '').toString().trim();
  final multi = kind == 'multi_choice';
  final choices = _parseChoices(question, kind);
  final effectiveAnswer = answer ?? question['answer'];
  final tokens = _answerTokens(effectiveAnswer, multi: multi);
  final hasAnswer = tokens.isNotEmpty;
  var anyMatched = false;
  for (final c in choices) {
    if (_choiceMatches(c, tokens)) anyMatched = true;
  }
  return TranscriptCard(
    kind: 'Question',
    icon: 'help-circle',
    tone: hasAnswer ? Tone.ok : Tone.accent,
    status: hasAnswer ? 'Answered' : null,
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (text.isNotEmpty)
          Text(
            text,
            style: sans(TranscriptCard.titleSize,
                weight: W.label, height: 1.4, color: AppColors.fg1),
          ),
        if (choices.isNotEmpty) ...[
          if (text.isNotEmpty) const SizedBox(height: S.s8),
          for (var i = 0; i < choices.length; i++) ...[
            if (i > 0) const SizedBox(height: S.s6),
            _readOnlyChoiceRow(
              choices[i],
              selected: _choiceMatches(choices[i], tokens),
              multi: multi,
            ),
          ],
        ],
        if (hasAnswer && !anyMatched) ...[
          const SizedBox(height: S.s8),
          Container(
            padding: const EdgeInsets.only(left: S.s8),
            decoration: BoxDecoration(
              border:
                  Border(left: BorderSide(color: AppColors.accent, width: 2)),
            ),
            child: Text(
              tokens.join(', '),
              style: sans(TranscriptCard.bodySize,
                  height: 1.4, color: AppColors.fg1),
            ),
          ),
        ],
      ],
    ),
  );
}

Widget _readOnlyChoiceRow(
  _ChoiceItem choice, {
  required bool selected,
  required bool multi,
}) {
  final mark = multi
      ? Container(
          width: 16,
          height: 16,
          decoration: BoxDecoration(
            color: selected ? AppColors.accentFill : Colors.transparent,
            borderRadius: BorderRadius.circular(4),
            border: Border.all(
                color: selected ? AppColors.accentFill : AppColors.lineStrong,
                width: 1.5),
          ),
          child: selected
              ? AppIcon('check', size: 11, color: AppColors.accentFg)
              : null,
        )
      : SelectCheck(selected, size: 16);
  return Container(
    padding: kMobile
        ? const EdgeInsets.fromLTRB(12, 10, 12, 10)
        : const EdgeInsets.fromLTRB(10, 8, 10, 8),
    decoration: BoxDecoration(
      color: selected ? AppColors.accentBg : AppColors.surface2,
      borderRadius: BorderRadius.circular(kMobile ? 12 : R.md),
      border: Border.all(
        color: selected ? AppColors.accent : AppColors.border2,
        width: selected ? 1.2 : 1,
      ),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(padding: const EdgeInsets.only(top: 2), child: mark),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Wrap(
                crossAxisAlignment: WrapCrossAlignment.center,
                spacing: 8,
                runSpacing: 4,
                children: [
                  Text(
                    choice.label,
                    style: sans(kMobile ? 14 : 13,
                        weight: W.label,
                        color: selected ? AppColors.fg1 : AppColors.fg2),
                  ),
                  if (selected) const Tag('Chosen', tone: Tone.accent),
                  if (!selected && choice.recommended)
                    const Tag('Recommended', tone: Tone.accent),
                ],
              ),
              if (choice.description.isNotEmpty) ...[
                const SizedBox(height: 2),
                Text(
                  choice.description,
                  style: sans(kMobile ? 13 : 12,
                      height: 1.4, color: AppColors.fg3),
                ),
              ],
            ],
          ),
        ),
      ],
    ),
  );
}

Widget _approvalCard(CoordinationEvent e, Map<dynamic, dynamic> approval) {
  final command = (approval['command'] ?? '').toString().trim();
  final summary = (approval['summary'] ?? '').toString().trim();
  final raw = summary.isNotEmpty
      ? summary
      : (command.isNotEmpty ? command : e.body.trim());
  final parsed = ApprovalSummary.parse(
    raw,
    fullCommand: command.isNotEmpty ? command : null,
  );
  final statusRaw = (approval['status'] ?? '').toString().trim();
  final (tone, statusLabel, icon) = switch (statusRaw.toLowerCase()) {
    'approved' || 'allowed' || 'allow' || 'approve' || 'approve_all' => (
        Tone.ok,
        'Approved',
        'check-circle',
      ),
    'denied' || 'rejected' || 'deny' || 'reject' => (
        Tone.danger,
        'Rejected',
        'x-circle',
      ),
    'pending' || 'waiting' || '' => (
        Tone.run,
        'Pending',
        parsed.secrets.isNotEmpty ? 'lock-key' : 'shield',
      ),
    _ => (
        Tone.neutral,
        '${statusRaw[0].toUpperCase()}${statusRaw.substring(1)}',
        'shield',
      ),
  };
  final code = parsed.shownCommand;
  final showSummaryTitle =
      summary.isNotEmpty && command.isNotEmpty && summary != command;
  return TranscriptCard(
    kind: 'Approval',
    icon: icon,
    tone: tone,
    status: statusLabel,
    title: showSummaryTitle ? summary : null,
    child: (code.isEmpty && parsed.secrets.isEmpty)
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (code.isNotEmpty)
                ApprovalCode(
                  code: code,
                  shell: command.isNotEmpty,
                  collapsedLines: 4,
                ),
              if (parsed.secrets.isNotEmpty) ...[
                if (code.isNotEmpty) const SizedBox(height: S.s6),
                Wrap(
                  spacing: S.s6,
                  runSpacing: S.s4,
                  children: [
                    for (final name in parsed.secrets)
                      Tag(name, tone: Tone.run, icon: 'key', mono: true),
                  ],
                ),
              ],
            ],
          ),
  );
}

class _ToolActivityCard extends StatefulWidget {
  final List<Map<dynamic, dynamic>> items;
  const _ToolActivityCard({required this.items});

  @override
  State<_ToolActivityCard> createState() => _ToolActivityCardState();
}

class _ToolActivityCardState extends State<_ToolActivityCard> {
  bool _open = false;

  static Map<String, dynamic> _argsFor(String name, String summary) {
    if (summary.isEmpty) return const {};
    return switch (toolBaseName(name)) {
      'change_files' => {
          'changes': [
            {'path': summary, 'action': 'replace'}
          ],
        },
      'read_file' || 'present_file' || 'view_image' || 'monitor' => {
          'path': summary,
        },
      'view_file' => {'AbsolutePath': summary},
      'web_search' || 'search_skills' || 'search_content' => {'query': summary},
      'web_read' => {'url': summary},
      'skill' => {'name': summary},
      'schedule_wake' || 'schedule_followup' => {'note': summary},
      'bash' => {'command': summary},
      _ => {'title': summary},
    };
  }

  static Map<String, dynamic>? _resultFor(String status) =>
      switch (status.toLowerCase()) {
        'running' || 'pending' || 'in_progress' => null,
        'error' || 'failed' => const {'status': 'error'},
        _ => const {'status': 'ok'},
      };

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    final count = items.length;
    final label = '$count tool ${count == 1 ? 'call' : 'calls'}';
    var failures = 0;
    var running = false;
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final name = (item['name'] ?? 'tool').toString().trim();
      final summary = (item['summary'] ?? '').toString().trim();
      final status = (item['status'] ?? '').toString().trim();
      final res = _resultFor(status);
      if (res == null) running = true;
      if (res != null && res['status'] == 'error') failures++;
      rows.add(DenseToolRow(
        key: ValueKey('agent-tool-$i-$name'),
        tool: name.isEmpty ? 'tool' : name,
        args: _argsFor(name, summary),
        result: res,
        open: false,
        onOpenChanged: (_) {},
      ));
    }
    final dotColor = running
        ? AppColors.accent
        : (failures > 0 ? AppColors.danger : AppColors.fg4);
    final fontSize = kMobile ? 13.5 : 12.5;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: S.s4),
      child: Stack(
        children: [
          if (_open)
            Positioned(
              left: 7.5,
              top: 14,
              bottom: 14,
              width: 1,
              child: ColoredBox(color: AppColors.border2),
            ),
          Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: () => setState(() => _open = !_open),
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: kMobile ? 32 : 26),
                  child: Row(
                    children: [
                      SizedBox(
                        width: 16,
                        child: Center(
                          child: Container(
                            width: 6,
                            height: 6,
                            decoration: BoxDecoration(
                              color: dotColor,
                              shape: BoxShape.circle,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: S.s8),
                      Flexible(
                        child: Text(
                          label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              sans(fontSize, height: 1.4, color: AppColors.fg2),
                        ),
                      ),
                      if (failures > 0) ...[
                        const SizedBox(width: S.s8),
                        Text(
                          '$failures failed',
                          style: sans(fontSize, color: AppColors.danger),
                        ),
                      ],
                      const SizedBox(width: S.s6),
                      AnimatedRotation(
                        turns: _open ? 0.25 : 0,
                        duration: Motion.fast,
                        child: AppIcon('chevron-right',
                            size: 12, color: AppColors.fg4),
                      ),
                    ],
                  ),
                ),
              ),
              if (_open) ...rows,
            ],
          ),
        ],
      ),
    );
  }
}

/// A work session's approval, forwarded by its agent's desk. Only the human
/// decides, so the buttons go straight to the session.
class DeskApprovalCard extends StatefulWidget {
  const DeskApprovalCard({
    super.key,
    required this.event,
    required this.approval,
    required this.client,
  });

  final CoordinationEvent event;
  final Map<dynamic, dynamic> approval;
  final DaemonClient client;

  @override
  State<DeskApprovalCard> createState() => _DeskApprovalCardState();
}

class _DeskApprovalCardState extends State<DeskApprovalCard> {
  static final _decided = <String, bool>{};
  bool _busy = false;

  String _s(String k) => '${widget.approval[k] ?? ''}'.trim();
  String get _key => '${_s('session')}:${_s('approval_id')}';

  Future<void> _decide(bool approve) async {
    setState(() => _busy = true);
    final ok = await quickSend(
      client: widget.client,
      session: _s('session'),
      action: approve ? const QuickApprove() : const QuickDeny(),
    );
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) _decided[_key] = approve;
    });
    if (!ok) toast(context, 'Could not reach the session', danger: true);
  }

  @override
  Widget build(BuildContext context) {
    final summary = _s('summary').isNotEmpty
        ? _s('summary')
        : widget.event.body.trim();
    final parsed = ApprovalSummary.parse(summary);
    final tool = _s('tool');
    final from = [
      if (_s('task_title').isNotEmpty) _s('task_title'),
      if (_s('session_title').isNotEmpty) _s('session_title'),
    ].join(' · ');
    final index = (widget.approval['index'] as num?)?.toInt();
    final total = (widget.approval['total'] as num?)?.toInt();
    final context_ = '${widget.event.payload['context'] ?? ''}'.trim();
    final decided = _decided[_key];
    final title = parsed.headline(tool);
    if (decided != null) {
      return ChatCardResolved(
        title: title,
        subtitle: decided ? 'Approved' : 'Denied',
        approved: decided,
      );
    }
    return ChatCard(children: [
      ChatCardHeader(
        title: title,
        subtitle: from.isNotEmpty ? from : null,
        trailing: total != null && total > 1 && index != null
            ? ChatCardPill('$index of $total')
            : null,
      ),
      if (parsed.shownCommand.isNotEmpty)
        ChatCardBody(
          child: Tactile(
            radius: BorderRadius.circular(10),
            kind: TactileKind.inset,
            child: Container(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
              decoration: BoxDecoration(
                color: AppColors.bg,
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: AppColors.line),
              ),
              child:
                  ApprovalCode(code: parsed.shownCommand, collapsedLines: 4),
            ),
          ),
        ),
      if (parsed.secrets.isNotEmpty)
        ChatCardBody(
          child: Wrap(spacing: S.s6, runSpacing: S.s4, children: [
            for (final name in parsed.secrets)
              Tag(name, tone: Tone.run, icon: 'key', mono: true),
          ]),
        ),
      if (context_.isNotEmpty)
        ChatCardBody(
          child: Text(context_,
              style: sans(kMobile ? 14 : 13, color: AppColors.fg2)),
        ),
      ChatCardActions(stack: true, buttons: [
        ChatCardButton('Deny',
            kind: ChatCardButtonKind.secondary,
            onTap: _busy ? null : () => _decide(false)),
        ChatCardButton('Approve', onTap: _busy ? null : () => _decide(true)),
      ]),
    ]);
  }
}
