import 'package:flutter/material.dart';

import '../desktop_look.dart';
import '../api.dart';
import '../chat/chat_style.dart' show ChatColors;
import '../approval_code.dart';
import '../chat/chat_card.dart';
import '../chat/chat_style.dart';
import '../media_views.dart';
import '../models.dart';
import '../notification_text.dart';
import '../platform.dart';
import '../session_quick_send.dart';
import '../theme.dart';
import '../tool_activity.dart';
import '../transcript.dart';
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

String? _eventTaskId(CoordinationEvent e) {
  final about = '${e.payload['about_task'] ?? ''}'.trim();
  if (about.isNotEmpty) return about;
  final tid = '${e.payload['task_id'] ?? ''}'.trim();
  if (tid.isNotEmpty) return tid;
  return null;
}

bool _isLatestForTask(
  CoordinationEvent e,
  String taskId,
  List<CoordinationEvent> events,
) {
  if (events.isEmpty) return true;
  CoordinationEvent? latest;
  for (final ev in events) {
    if (ev.actorKind == 'human') continue;
    if (_eventTaskId(ev) == taskId) latest = ev;
  }
  if (latest == null) return true;
  if (e.eventId.isNotEmpty && latest.eventId.isNotEmpty) {
    return e.eventId == latest.eventId;
  }
  return identical(e, latest) || e.sequence == latest.sequence;
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
        chatStyle: true,
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
    if (items.isNotEmpty) {
      return _ToolActivityCard(
        items: items,
        agentId: e.actorId.isNotEmpty ? e.actorId : agentId,
      );
    }
  }
  final taskId = _eventTaskId(e);
  if (taskId != null && _isLatestForTask(e, taskId, events)) {
    return _TaskThreadCard(
      key: ValueKey('task-card-$taskId-${e.eventId}'),
      event: e,
      taskId: taskId,
      client: client,
    );
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

Widget _chatCardShell({
  required String icon,
  required String label,
  String? title,
  String? body,
  Widget? child,
  Widget? footer,
}) {
  final cleanTitle = title?.trim() ?? '';
  final cleanBody = body?.trim() ?? '';
  return Container(
    padding: const EdgeInsets.all(14),
    decoration: BoxDecoration(
      color: ChatColors.card,
      borderRadius: BorderRadius.circular(ChatColors.radius),
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Row(
          children: [
            AppIcon(icon, size: 13, color: ChatColors.meta),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TS.caption(ChatColors.meta),
              ),
            ),
          ],
        ),
        if (cleanTitle.isNotEmpty) ...[
          const SizedBox(height: 6),
          Text(
            cleanTitle,
            style: sans(
              kMobile ? 15 : 13,
              weight: W.title,
              color: ChatColors.receivedText,
            ),
          ),
        ],
        if (cleanBody.isNotEmpty) ...[
          SizedBox(height: cleanTitle.isEmpty ? 6 : 4),
          Text(
            cleanBody,
            style: chatText(mine: false).copyWith(color: ChatColors.meta),
          ),
        ],
        if (child != null) ...[
          const SizedBox(height: 10),
          child,
        ],
        if (footer != null) ...[
          const SizedBox(height: 12),
          footer,
        ],
      ],
    ),
  );
}

Widget _chatPill({
  required String label,
  required bool primary,
  VoidCallback? onTap,
  bool disabled = false,
  String? badge,
}) {
  final bg = primary ? ChatColors.action : ChatColors.cardButton;
  final fg = primary ? ChatColors.onAction : ChatColors.receivedText;
  final pill = Opacity(
    opacity: disabled ? 0.5 : 1,
    child: Container(
      height: kMobile ? 36 : 30,
      padding: EdgeInsets.symmetric(horizontal: kMobile ? 16 : 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label,
            style: sans(kMobile ? 15 : 13, weight: W.label, color: fg),
          ),
          if (badge != null && badge.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(
              badge,
              style: TS.caption(fg.withValues(alpha: 0.8)),
            ),
          ],
        ],
      ),
    ),
  );
  if (onTap == null || disabled) return pill;
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap,
    child: pill,
  );
}

Widget _questionCard(
  CoordinationEvent e,
  Map<dynamic, dynamic> question, {
  Object? answer,
}) {
  final rawText = (question['text'] ?? '').toString().trim();
  final text = rawText.isNotEmpty ? rawText : e.body.trim();
  final kind = (question['kind'] ?? '').toString().trim();
  final choices = _parseChoices(question, kind);
  final effectiveAnswer = answer ?? question['answer'];
  final tokens =
      _answerTokens(effectiveAnswer, multi: kind == 'multi_choice');
  final hasAnswer = tokens.isNotEmpty;
  var anyMatched = false;
  for (final c in choices) {
    if (_choiceMatches(c, tokens)) anyMatched = true;
  }
  var primaryAssigned = false;
  bool claimPrimary(bool want) {
    if (!want || primaryAssigned) return false;
    primaryAssigned = true;
    return true;
  }

  return _chatCardShell(
    icon: 'help-circle',
    label: hasAnswer ? 'Question \u00b7 Answered' : 'Question',
    title: text.isNotEmpty ? text : null,
    child: (choices.isEmpty && !(hasAnswer && !anyMatched))
        ? null
        : Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (choices.isNotEmpty)
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    for (var i = 0; i < choices.length; i++)
                      () {
                        final c = choices[i];
                        final selected = _choiceMatches(c, tokens);
                        final wantPrimary = selected ||
                            (!hasAnswer &&
                                (c.recommended ||
                                    ((kind == 'yes_no' || kind == 'confirm') &&
                                        i == 0)));
                        final badge = selected
                            ? 'Chosen'
                            : (!hasAnswer && c.recommended
                                ? 'Recommended'
                                : null);
                        final pill = _chatPill(
                          label: c.label,
                          primary: claimPrimary(wantPrimary),
                          badge: badge,
                        );
                        if (c.description.isEmpty) return pill;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            pill,
                            const SizedBox(height: 2),
                            Padding(
                              padding: const EdgeInsets.only(left: 4),
                              child: Text(
                                c.description,
                                style: chatText(mine: false)
                                    .copyWith(color: ChatColors.meta),
                              ),
                            ),
                          ],
                        );
                      }(),
                  ],
                ),
              if (hasAnswer && !anyMatched) ...[
                if (choices.isNotEmpty) const SizedBox(height: 8),
                Text(
                  tokens.join(', '),
                  style: chatText(mine: false).copyWith(color: ChatColors.meta),
                ),
              ],
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
  final (statusLabel, icon) = switch (statusRaw.toLowerCase()) {
    'approved' || 'allowed' || 'allow' || 'approve' || 'approve_all' => (
        'Approved',
        'check-circle',
      ),
    'denied' || 'rejected' || 'deny' || 'reject' => (
        'Rejected',
        'x-circle',
      ),
    'pending' || 'waiting' || '' => (
        'Pending',
        parsed.secrets.isNotEmpty ? 'lock-key' : 'shield',
      ),
    _ => (
        '${statusRaw[0].toUpperCase()}${statusRaw.substring(1)}',
        'shield',
      ),
  };
  final code = parsed.shownCommand;
  final showSummaryTitle =
      summary.isNotEmpty && command.isNotEmpty && summary != command;
  return _chatCardShell(
    icon: icon,
    label: statusLabel.isEmpty ? 'Approval' : 'Approval \u00b7 $statusLabel',
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

class _TaskCardCache {
  static final Map<int, Map<String, Future<TaskItem?>>> _byScreen = {};

  static Map<String, Future<TaskItem?>> _mapFor(BuildContext context) {
    final screen = context.findAncestorStateOfType<State<StatefulWidget>>();
    final key = screen == null ? 0 : identityHashCode(screen);
    if (_byScreen.length > 32) _byScreen.clear();
    return _byScreen.putIfAbsent(key, () => {});
  }

  static Future<TaskItem?> fetch(
    BuildContext context,
    DaemonClient client,
    String taskId, {
    bool force = false,
  }) {
    final map = _mapFor(context);
    if (!force && map.containsKey(taskId)) return map[taskId]!;
    final fut = client.getTask(taskId).then<TaskItem?>((t) => t).catchError((_) => null);
    map[taskId] = fut;
    return fut;
  }

  static void put(BuildContext context, String taskId, TaskItem task) {
    _mapFor(context)[taskId] = Future<TaskItem?>.value(task);
  }
}

class _TaskThreadCard extends StatefulWidget {
  const _TaskThreadCard({
    super.key,
    required this.event,
    required this.taskId,
    required this.client,
  });

  final CoordinationEvent event;
  final String taskId;
  final DaemonClient client;

  @override
  State<_TaskThreadCard> createState() => _TaskThreadCardState();
}

class _TaskThreadCardState extends State<_TaskThreadCard> {
  Future<TaskItem?>? _future;
  TaskItem? _task;
  bool _loaded = false;
  bool _busy = false;
  String? _error;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _future ??= _load();
  }

  @override
  void didUpdateWidget(covariant _TaskThreadCard oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.taskId != widget.taskId ||
        oldWidget.client != widget.client) {
      _future = _load();
    }
  }

  Future<TaskItem?> _load({bool force = false}) async {
    final t = await _TaskCardCache.fetch(
      context,
      widget.client,
      widget.taskId,
      force: force,
    );
    if (mounted) {
      setState(() {
        _task = t;
        _loaded = true;
      });
    }
    return t;
  }

  static String _headerLabel(TaskItem task) {
    final base = switch (task.status) {
      TaskStatus.inReview => 'Task in review',
      _ => 'Task \u00b7 ${task.status.label}',
    };
    final age = _ageLabel(task.updatedAt.isNotEmpty ? task.updatedAt : task.createdAt);
    return age.isEmpty ? base : '$base \u00b7 $age';
  }

  static String _ageLabel(String raw) {
    final dt = DateTime.tryParse(raw.trim());
    if (dt == null) return '';
    final d = DateTime.now().toUtc().difference(dt.toUtc());
    if (d.isNegative || d.inMinutes < 1) return '';
    if (d.inHours < 1) return '${d.inMinutes} min';
    if (d.inHours < 48) return '${d.inHours} h';
    return '${d.inDays} d';
  }

  Future<void> _submitVerdict(
    String verdict, [
    List<String> findings = const [],
  ]) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final nextStatus = await widget.client.submitTaskVerdict(
        widget.taskId,
        verdict,
        findings,
      );
      if (!mounted) return;
      final current = _task;
      if (current != null) {
        final optimistic = current.movedTo(nextStatus);
        _TaskCardCache.put(context, widget.taskId, optimistic);
        setState(() => _task = optimistic);
      }
      final refreshed = await _load(force: true);
      if (!mounted) return;
      setState(() {
        if (refreshed != null) _task = refreshed;
        _busy = false;
      });
    } on TaskVerdictConflict catch (e) {
      if (!mounted) return;
      final refreshed = await _load(force: true);
      if (!mounted) return;
      setState(() {
        if (refreshed != null) _task = refreshed;
        _busy = false;
        _error = e.message.isNotEmpty
            ? e.message
            : 'Task is no longer in review.';
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _error = '$e';
      });
    }
  }

  Future<void> _promptSendBack() async {
    if (_busy) return;
    final finding = await showAppSheet<String>(
      context,
      title: 'Send back',
      child: const _SendBackSheet(),
    );
    if (!mounted || finding == null || finding.trim().isEmpty) return;
    await _submitVerdict('changes', [finding.trim()]);
  }

  Widget _fallbackBubble(BuildContext context) {
    final body = widget.event.body.trim();
    return ChatBubble(
      mine: false,
      tail: true,
      child: body.isEmpty
          ? const SizedBox.shrink()
          : MarkdownBody(
              data: unwrapCodedLinks(body),
              selectable: false,
              styleSheet: chatMarkdownStyle(context, mine: false),
              builders: {'pre': PreBlockBuilder()},
              onTapLink: (txt, href, _) =>
                  openMarkdownLink(href, context, txt),
            ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final task = _task;
    if (!_loaded || task == null || task.title.trim().isEmpty) {
      return _fallbackBubble(context);
    }
    final bodyText = widget.event.body.trim().isNotEmpty
        ? widget.event.body.trim()
        : ((task.currentStep ?? '').trim().isNotEmpty
            ? task.currentStep!.trim()
            : task.description.trim());
    final inReview = task.status == TaskStatus.inReview;
    final showFooter = inReview || _error != null;
    return _chatCardShell(
      icon: 'check-square',
      label: _headerLabel(task),
      title: task.title,
      body: bodyText.isNotEmpty ? bodyText : null,
      footer: !showFooter
          ? null
          : Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (inReview)
                  Wrap(
                    spacing: 8,
                    runSpacing: 8,
                    children: [
                      _chatPill(
                        label: 'Approve',
                        primary: true,
                        disabled: _busy,
                        onTap: () => _submitVerdict('approve'),
                      ),
                      _chatPill(
                        label: 'Send back',
                        primary: false,
                        disabled: _busy,
                        onTap: _promptSendBack,
                      ),
                    ],
                  ),
                if (_error != null) ...[
                  if (inReview) const SizedBox(height: 6),
                  Text(
                    _error!,
                    style: TS.caption(AppColors.danger),
                  ),
                ],
              ],
            ),
    );
  }
}

class _SendBackSheet extends StatefulWidget {
  const _SendBackSheet();

  @override
  State<_SendBackSheet> createState() => _SendBackSheetState();
}

class _SendBackSheetState extends State<_SendBackSheet> {
  final _controller = TextEditingController();

  @override
  void initState() {
    super.initState();
    _controller.addListener(() {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _submit() {
    final text = _controller.text.trim();
    if (text.isEmpty) return;
    Navigator.of(context).pop(text);
  }

  @override
  Widget build(BuildContext context) {
    final canSubmit = _controller.text.trim().isNotEmpty;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AppField(
          controller: _controller,
          hint: 'What needs changing?',
          autofocus: true,
          minLines: 2,
          maxLines: 5,
          onSubmitted: (_) => _submit(),
        ),
        SizedBox(height: kMobile ? S.s16 : 14),
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            _chatPill(
              label: 'Cancel',
              primary: false,
              onTap: () => Navigator.of(context).pop(),
            ),
            const SizedBox(width: 8),
            _chatPill(
              label: 'Send back',
              primary: true,
              disabled: !canSubmit,
              onTap: _submit,
            ),
          ],
        ),
      ],
    );
  }
}

class _ToolActivityCard extends StatefulWidget {
  final List<Map<dynamic, dynamic>> items;
  final String agentId;
  const _ToolActivityCard({
    required this.items,
    this.agentId = '',
  });

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

  static String _displayActor(String raw) {
    final trimmed = raw.trim();
    if (trimmed.isEmpty) return 'Agent';
    return trimmed
        .split(RegExp(r'[-_\s]+'))
        .where((p) => p.isNotEmpty)
        .map((p) => '${p[0].toUpperCase()}${p.substring(1)}')
        .join(' ');
  }

  static String _summaryLine(
    List<Map<dynamic, dynamic>> items,
    String agentId, {
    required int failures,
  }) {
    var edited = 0;
    var ran = 0;
    var read = 0;
    var searched = 0;
    var other = 0;
    for (final item in items) {
      final name = toolBaseName('${item['name'] ?? 'tool'}'.trim());
      switch (name) {
        case 'change_files':
          edited++;
        case 'bash':
        case 'manage_process':
          ran++;
        case 'read_file':
        case 'view_file':
        case 'view_image':
        case 'web_read':
          read++;
        case 'web_search':
        case 'search_skills':
        case 'search_content':
          searched++;
        default:
          other++;
      }
    }
    final parts = <String>[
      if (edited > 0) 'edited $edited ${edited == 1 ? 'file' : 'files'}',
      if (ran > 0) 'ran $ran ${ran == 1 ? 'command' : 'commands'}',
      if (read > 0) 'read $read ${read == 1 ? 'file' : 'files'}',
      if (searched > 0) 'searched $searched ${searched == 1 ? 'time' : 'times'}',
      if (other > 0)
        'ran $other ${ (edited + ran + read + searched) > 0 ? 'other ' : ''}${other == 1 ? 'tool' : 'tools'}',
    ];
    final actor = _displayActor(agentId);
    final count = items.length;
    final base = parts.isEmpty
        ? '$actor ran $count tool ${count == 1 ? 'call' : 'calls'}'
        : '$actor ${parts.join(', ')}';
    return failures > 0 ? '$base \u00b7 $failures failed' : base;
  }

  @override
  Widget build(BuildContext context) {
    final items = widget.items;
    var failures = 0;
    final rows = <Widget>[];
    for (var i = 0; i < items.length; i++) {
      final item = items[i];
      final name = (item['name'] ?? 'tool').toString().trim();
      final summary = (item['summary'] ?? '').toString().trim();
      final status = (item['status'] ?? '').toString().trim();
      final res = _resultFor(status);
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
    final summaryText = _summaryLine(items, widget.agentId, failures: failures);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ChatSystemLine(
          summaryText,
          action: (
            _open ? 'Hide' : 'Show',
            () => setState(() => _open = !_open),
          ),
        ),
        if (_open)
          Padding(
            padding: const EdgeInsets.only(top: S.s4),
            child: Stack(
              children: [
                Positioned(
                  left: 7.5,
                  top: 6,
                  bottom: 6,
                  width: 1,
                  child: ColoredBox(color: AppColors.border2),
                ),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: rows,
                ),
              ],
            ),
          ),
      ],
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
