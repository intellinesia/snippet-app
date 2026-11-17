part of 'session.dart';

bool _looksLikeQuestionAnswer(String text) {
  final t = text.trim();
  if (t.isEmpty) return false;
  if (t == 'user skipped the question') return true;
  return t.contains('\n→ ') || t.startsWith('→ ');
}

class _QuestionRecord extends StatelessWidget {
  final Map<String, dynamic> event;
  final String? answer;
  const _QuestionRecord(this.event, {this.answer});

  static String _displayAnswer(String s) =>
      s == 'user skipped the question' ? 'Skipped' : s;

  List<Map<String, dynamic>> get _questions {
    final qd = event['questions'];
    final raw = qd is Map ? qd['questions'] : event['questions'];
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((e) => Map<String, dynamic>.from(e))
        .toList();
  }

  Map<String, String> get _answers {
    final out = <String, String>{};
    final src = (answer ?? event['answer'] ?? event['value'] ?? '').toString();
    if (src.trim().isEmpty) return out;
    final qs = _questions;
    if (qs.length <= 1) {
      final text = qs.isEmpty ? '' : (qs.first['text']?.toString() ?? '');
      var body = src.trim();
      if (text.isNotEmpty && body.startsWith(text)) {
        body = body.substring(text.length).trim();
        if (body.startsWith('→')) body = body.substring(1).trim();
      } else if (body.contains('\n→ ')) {
        body = body.split('\n→ ').skip(1).join('\n→ ').trim();
      }
      out[qs.isEmpty ? '0' : qs.first['id']?.toString() ?? '0'] = body;
      return out;
    }
    final parts = src.split(RegExp(r'\n\n+'));
    for (final part in parts) {
      final idx = part.indexOf('\n→ ');
      if (idx < 0) continue;
      final qText = part.substring(0, idx).trim();
      final a = part.substring(idx + 3).trim();
      for (final q in qs) {
        if ((q['text']?.toString() ?? '').trim() == qText) {
          out[q['id']?.toString() ?? qText] = a;
          break;
        }
      }
    }
    return out;
  }

  @override
  Widget build(BuildContext context) {
    final qs = _questions;
    final answers = _answers;
    final rows = <(String, String?)>[
      for (final q in qs)
        (
          q['text']?.toString() ?? '',
          answers[q['id']?.toString() ?? ''] ?? answers['0'],
        ),
      if (qs.isEmpty && event['text'] != null)
        (event['text'].toString(), answers['0']),
    ];
    String shown(String? a) =>
        a == null || a.isEmpty ? 'Not answered' : _displayAnswer(a);
    if (rows.length <= 1) {
      final (q, a) = rows.isEmpty ? ('Question', null) : rows.first;
      return Padding(
        padding: EdgeInsets.symmetric(vertical: S.s4),
        child: ChatCardResolved(
            title: q.isEmpty ? 'Question' : q,
            subtitle: shown(a),
            approved: answers.isNotEmpty),
      );
    }
    final p = ChatCard.pad;
    return Padding(
      padding: EdgeInsets.symmetric(vertical: S.s4),
      child: ChatCard(dimmed: true, children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const ChatCardDivider(),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: p, vertical: S.of(10)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rows[i].$1,
                    style: sans(kMobile ? 15 : 13,
                        weight: W.strong, color: AppColors.fg2)),
                SizedBox(height: S.s2),
                Text(shown(rows[i].$2),
                    style: sans(13,
                        height: 1.4,
                        color: rows[i].$2 == null || rows[i].$2!.isEmpty
                            ? AppColors.fg4
                            : AppColors.fg3)),
              ],
            ),
          ),
        ],
      ]),
    );
  }
}

class ApprovalBar extends StatefulWidget {
  final List<Map<String, dynamic>> events;
  final void Function(Map<String, dynamic>) onSend;
  final bool showApproveAll;

  /// The asking agent, for the phone's "{Agent} asks" row; the row is left out
  /// when the session's agent is not known yet.
  final String? agentId;
  final String? agentName;
  final String? stepLabel;
  const ApprovalBar(
      {super.key,
      required this.events,
      required this.onSend,
      this.showApproveAll = false,
      this.agentId,
      this.agentName,
      this.stepLabel});
  @override
  State<ApprovalBar> createState() => ApprovalBarState();
}

class ApprovalBarState extends State<ApprovalBar> {
  bool _sent = false;

  void _decide(Map<String, dynamic> m) {
    if (_sent) return;
    setState(() => _sent = true);
    widget.onSend(m);
  }

  Map<String, dynamic>? get _request {
    for (var i = widget.events.length - 1; i >= 0; i--) {
      final e = widget.events[i];
      if (e['kind'] == 'approval_request') return e;
    }
    return null;
  }

  Widget _askRow(Map<String, dynamic>? req) {
    final raw = req?['at'] ?? req?['created_at'];
    final at = raw is num ? raw.toInt() : 0;
    final mins = at <= 0
        ? 0
        : DateTime.now()
            .difference(DateTime.fromMillisecondsSinceEpoch(
                (at > 100000000000 ? at : at * 1000)))
            .inMinutes;
    final name = (widget.agentName ?? '').trim().isEmpty
        ? widget.agentId!
        : widget.agentName!;
    final step = widget.stepLabel;
    return Row(children: [
      AgentMochi(widget.agentId!, size: 18),
      SizedBox(width: S.s8),
      Expanded(
        child: Text(step == null ? '$name asks' : '$name asks · $step',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: sans(12, color: AppColors.fg3)),
      ),
      if (mins >= 1) ...[
        SizedBox(width: S.s8),
        Text('waiting $mins min', style: sans(12, color: AppColors.fg3)),
      ],
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final req = _request;
    final tool = req?['tool_name']?.toString() ?? '';
    var detail = (req?['summary']?.toString() ?? '').trim();
    if (detail.isEmpty) detail = toolArgSummary(tool, req?['arguments']);
    final parsed = ApprovalSummary.parse(detail,
        fullCommand: req == null
            ? null
            : fullApprovalCommand(widget.events, req, detail));
    final call = req == null ? -1 : widget.events.indexOf(req) - 1;
    final callArgs = call >= 0 ? widget.events[call]['arguments'] : null;
    final callLabel = parsed.lane == null &&
            parsed.customTool == null &&
            call >= 0 &&
            widget.events[call]['tool_name'] == tool &&
            callArgs is Map
        ? '${callArgs['label'] ?? ''}'.trim()
        : '';
    detail = parsed.shownCommand;
    final laneName = parsed.lane;
    final secrets = parsed.secrets;
    final customTool = parsed.customTool;
    final isVault = secrets.isNotEmpty;
    final index = (req?['index'] as num?)?.toInt() ?? 1;
    final total = (req?['total'] as num?)?.toInt() ?? 1;
    final action = customTool != null
        ? (parsed.newCustomTool
            ? 'Run new custom tool $customTool?'
            : 'Run custom tool $customTool?')
        : switch (tool) {
            'bash' => 'Run this command?',
            'change_files' => 'Make these file changes?',
            '' => 'Allow this action?',
            _ => 'Allow ${toolTitle(tool).toLowerCase()}?',
          };
    final title = approvalTitle(req?['title']);
    final headline = title ?? (callLabel.isNotEmpty ? callLabel : action);
    final reason = '${req?['reason'] ?? ''}'.trim();
    final ruleLabel = approvalRuleLabel(req?['rule']);
    final isShell = tool == 'bash' || customTool != null;

    // The daemon only offers a rule when one is safe, so it needs no gating.
    final canAlways = ruleLabel == null &&
        widget.showApproveAll &&
        !isVault &&
        laneName == null &&
        !parsed.newCustomTool;
    final isKnownTool = tool == 'bash' || tool == 'change_files';
    final subtitle = laneName != null
        ? 'Lane «$laneName»'
        : customTool != null
            ? 'Custom tool'
            : tool.isEmpty ||
                    ((callLabel.isEmpty || title != null) && isKnownTool)
                ? null
                : toolTitle(tool);

    return Padding(
      padding: EdgeInsets.fromLTRB(0, S.s4, 0, S.s6),
      child: ChatCard(children: [
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ChatCardHeader(
                  title: headline,
                  subtitle: reason.isEmpty ? subtitle : null,
                  subtitleView: reason.isEmpty
                      ? null
                      : ApprovalReason(reason, meta: subtitle),
                  eyebrow: kMobile && widget.agentId != null
                      ? _askRow(req)
                      : null,
                  trailing: total > 1 ? ChatCardPill('$index of $total') : null,
                ),
                if (detail.isNotEmpty)
                  ChatCardBody(
                    child: Tactile(
                      radius: BorderRadius.circular(R.card),
                      kind: TactileKind.inset,
                      child: Container(
                        padding: EdgeInsets.fromLTRB(S.s12, S.of(10), S.s12, S.s6),
                        decoration: BoxDecoration(
                          color: AppColors.bg,
                          borderRadius: BorderRadius.circular(R.card),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: ApprovalCode(code: detail, shell: isShell),
                      ),
                    ),
                  ),
                if (isVault)
                  ChatCardBody(
                    child: Wrap(spacing: S.s6, runSpacing: S.s4, children: [
                      for (final name in secrets)
                        Tag(name, tone: Tone.run, icon: 'key', mono: true),
                    ]),
                  ),
              ],
            ),
          ),
        ),
        ChatCardActions(
          buttons: [
            ChatCardButton('Deny',
                kind: ChatCardButtonKind.secondary,
                onTap: _sent ? null : () => _decide({'kind': 'deny'})),
            ChatCardButton('Approve',
                icon: Icons.check,
                busy: _sent,
                onTap: () => _decide({'kind': 'approve'})),
          ],
          link: ruleLabel != null
              ? 'Always allow $ruleLabel in this session'
              : (canAlways ? 'Always allow' : null),
          onLink: _sent
              ? null
              : () => _decide(
                  {'kind': ruleLabel != null ? 'approve_rule' : 'approve_all'}),
        ),
      ]),
    );
  }
}

/// The agent's plan as a compact checklist: done steps recede, the step in
/// progress is highlighted, and the optional explanation says why it changed.
class QuestionBar extends StatefulWidget {
  final Map<String, dynamic> question;
  final void Function(Map<String, dynamic>) onSend;
  const QuestionBar({super.key, required this.question, required this.onSend});
  @override
  State<QuestionBar> createState() => QuestionBarState();
}

/// One selectable answer to a question.
class _QOption {
  final String value;
  final String label;
  final String description;
  final bool recommended;
  const _QOption(this.value, this.label,
      {this.description = '', this.recommended = false});

  /// How the choice reads in the answer: the label, with the value alongside
  /// when it says something the label doesn't ("android" for "Android" adds
  /// nothing).
  String get answer {
    String norm(String x) =>
        x.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return norm(value) == norm(label) ? label : '$label ($value)';
  }
}

class QuestionBarState extends State<QuestionBar> {
  final Map<String, TextEditingController> _text = {};
  final Map<String, String> _choice = {};
  final Map<String, Set<String>> _multi = {};
  final Set<String> _skipped = {};
  final Set<String> _freeText = {};
  final FocusNode _keys = FocusNode(debugLabel: 'question keys');
  bool _sent = false;
  bool _review = false;
  int _step = 0;

  @override
  void initState() {
    super.initState();
    // The recommended option starts selected (ticked, for multi-choice).
    for (final q in _questions) {
      final id = q['id'].toString();
      final rec = _options(q).where((o) => o.recommended).map((o) => o.value);
      if (_kind(q) == 'multi_choice') {
        _multi[id] = rec.toSet();
      } else if (_kind(q) == 'single_choice' && rec.isNotEmpty) {
        _choice[id] = rec.first;
      }
    }
    if (!kMobile) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _keys.requestFocus();
      });
    }
  }

  TextEditingController _controllerFor(String id) {
    return _text.putIfAbsent(id, () {
      final c = TextEditingController();
      c.addListener(_onAnswerChanged);
      return c;
    });
  }

  void _onAnswerChanged() {
    if (mounted) setState(() {});
  }

  Map<String, dynamic>? get _currentQuestion => _questions.isEmpty
      ? null
      : _questions[_step.clamp(0, _questions.length - 1)];

  List<Map<String, dynamic>> get _questions =>
      ((widget.question['questions'] as List?) ?? const [])
          .cast<Map<String, dynamic>>();

  String _kind(Map<String, dynamic> q) =>
      (q['answer_kind'] is Map ? q['answer_kind']['kind'] : null)?.toString() ??
      'free_text';

  String _header(Map<String, dynamic> q, int i) {
    final h = '${q['header'] ?? ''}'.trim();
    return h.isEmpty ? 'Q${i + 1}' : h;
  }

  /// Options for a choice question, the recommended one first.
  List<_QOption> _options(Map<String, dynamic> q) {
    final ak = q['answer_kind'] is Map ? q['answer_kind'] as Map : const {};
    String labelOr(String k, String fallback) {
      final v = '${ak[k] ?? ''}'.trim();
      return v.isEmpty ? fallback : v;
    }

    switch (_kind(q)) {
      case 'yes_no':
        return const [_QOption('yes', 'Yes'), _QOption('no', 'No')];
      case 'confirm':
        return [
          _QOption('confirm', labelOr('confirm_label', 'Confirm')),
          _QOption('cancel', labelOr('cancel_label', 'Cancel')),
        ];
      case 'single_choice':
      case 'multi_choice':
        final opts = [
          for (final e
              in ((ak['choices'] as List?) ?? const []).whereType<Map>())
            _QOption('${e['value']}'.trim(), '${e['label']}'.trim(),
                description: '${e['description'] ?? ''}'.trim(),
                recommended: e['recommended'] == true),
        ];
        // Stable: recommended first, the rest in the agent's order.
        return [
          ...opts.where((o) => o.recommended),
          ...opts.where((o) => !o.recommended),
        ];
    }
    return const [];
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    _keys.dispose();
    super.dispose();
  }

  bool _answered(Map<String, dynamic> q) {
    final id = q['id'].toString();
    if (_skipped.contains(id)) return true;
    final k = _kind(q);
    if (k == 'free_text' || _freeText.contains(id)) {
      return _text[id]?.text.trim().isNotEmpty ?? false;
    }
    if (k == 'multi_choice') return _multi[id]?.isNotEmpty ?? false;
    return _choice[id]?.isNotEmpty ?? false;
  }

  bool get _ready {
    if (_review) return true;
    final q = _currentQuestion;
    return q != null && _answered(q);
  }

  String _answerFor(Map<String, dynamic> q) {
    final id = q['id'].toString();
    if (_skipped.contains(id)) return 'user skipped the question';
    final k = _kind(q);
    if (k == 'free_text' || _freeText.contains(id)) {
      return _text[id]?.text.trim() ?? '';
    }
    final opts = _options(q);
    if (k == 'multi_choice') {
      final picked = _multi[id] ?? const {};
      return opts
          .where((o) => picked.contains(o.value))
          .map((o) => o.answer)
          .join(', ');
    }
    return opts.where((o) => o.value == _choice[id]).firstOrNull?.answer ?? '';
  }

  /// Next question, the review once all are answered, then send.
  void _submit() {
    if (_questions.isEmpty || !_ready || _sent) return;
    if (!_review && _step < _questions.length - 1) {
      setState(() => _step++);
      return;
    }
    if (!_review && _questions.length > 1) {
      setState(() => _review = true);
      return;
    }
    setState(() => _sent = true);
    final parts =
        _questions.map((q) => '${q['text']}\n→ ${_answerFor(q)}').toList();
    widget.onSend({'kind': 'answer', 'value': parts.join('\n\n')});
  }

  void _back() {
    if (_sent) return;
    setState(() {
      if (_review) {
        _review = false;
      } else if (_step > 0) {
        _step--;
      }
    });
  }

  /// Jump to a question from its tab or the review.
  void _goTo(int i) {
    if (_sent) return;
    setState(() {
      _review = false;
      _step = i.clamp(0, _questions.length - 1);
    });
  }

  void _skip() {
    final q = _currentQuestion;
    if (q == null || _sent) return;
    final id = q['id'].toString();
    _skipped.add(id);
    _freeText.remove(id);
    _choice.remove(id);
    _multi.remove(id);
    _submit();
  }

  void _pick(Map<String, dynamic> q, _QOption o) {
    final id = q['id'].toString();
    setState(() {
      _skipped.remove(id);
      _freeText.remove(id);
      if (_kind(q) == 'multi_choice') {
        final set = _multi.putIfAbsent(id, () => <String>{});
        set.contains(o.value) ? set.remove(o.value) : set.add(o.value);
      } else {
        _choice[id] = o.value;
      }
    });
  }

  void _toggleFreeText() {
    final q = _currentQuestion;
    if (q == null || _sent) return;
    final id = q['id'].toString();
    setState(() {
      _skipped.remove(id);
      _freeText.contains(id) ? _freeText.remove(id) : _freeText.add(id);
    });
  }

  /// Desktop keys: 1-9 pick (toggle for multi-choice), Enter moves on.
  KeyEventResult _onKey(FocusNode _, KeyEvent e) {
    if (e is! KeyDownEvent || _sent) return KeyEventResult.ignored;
    if (e.logicalKey == LogicalKeyboardKey.enter ||
        e.logicalKey == LogicalKeyboardKey.numpadEnter) {
      _submit();
      return KeyEventResult.handled;
    }
    final q = _currentQuestion;
    final ch = e.character;
    if (q == null || _review || ch == null) return KeyEventResult.ignored;
    final n = int.tryParse(ch);
    final opts = _options(q);
    if (n != null && n >= 1 && n <= opts.length && n <= 9) {
      _pick(q, opts[n - 1]);
      return KeyEventResult.handled;
    }
    return KeyEventResult.ignored;
  }

  Widget _numberHint(int index) => Text('${index + 1}',
      style: mono(10, color: AppColors.fg4));

  List<Widget> _inputFor(Map<String, dynamic> q) {
    final id = q['id'].toString();
    final k = _kind(q);
    final opts = _options(q);
    final controller = _controllerFor(id);
    final multi = k == 'multi_choice';
    final writing = k == 'free_text' || _freeText.contains(id);
    return [
      if (k != 'free_text') ...[
        const ChatCardDivider(),
        for (var i = 0; i < opts.length; i++) ...[
          ChatCardOption(
            label: opts[i].label,
            detail: opts[i].description,
            multi: multi,
            recommended: opts[i].recommended,
            selected: multi
                ? (_multi[id]?.contains(opts[i].value) ?? false) &&
                    !_freeText.contains(id)
                : _choice[id] == opts[i].value && !_freeText.contains(id),
            trailing: !kMobile && i < 9 ? _numberHint(i) : null,
            onTap: _sent ? null : () => _pick(q, opts[i]),
          ),
          const ChatCardDivider(),
        ],
        ChatCardOption(
          label: _freeText.contains(id)
              ? 'Writing a response'
              : 'Write your own answer',
          muted: !_freeText.contains(id),
          multi: multi,
          selected: _freeText.contains(id),
          onTap: _sent ? null : _toggleFreeText,
        ),
      ],
      if (writing)
        Padding(
          padding: EdgeInsets.fromLTRB(
              ChatCard.pad, k == 'free_text' ? 0 : S.of(10), ChatCard.pad, S.s4),
          child: AppField(
              controller: controller,
              hint: 'Write your answer',
              minLines: 2,
              maxLines: 4,
              onSubmitted: (_) => _submit()),
        ),
    ];
  }

  List<Widget> _reviewRows() => [
        const ChatCardDivider(),
        for (var i = 0; i < _questions.length; i++) ...[
          if (i > 0) const ChatCardDivider(),
          InkWell(
            onTap: _sent ? null : () => _goTo(i),
            child: Padding(
              padding:
                  EdgeInsets.symmetric(horizontal: ChatCard.pad, vertical: S.of(10)),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_header(_questions[i], i), style: TS.meta()),
                      SizedBox(height: S.s2),
                      Text(_answerFor(_questions[i]),
                          style: sans(kMobile ? 15 : 13,
                              height: 1.4, color: AppColors.fg1)),
                    ],
                  ),
                ),
                SizedBox(width: S.s8),
                Text('Edit', style: sans(13, color: AppColors.fg3)),
              ]),
            ),
          ),
        ],
      ];

  @override
  Widget build(BuildContext context) {
    final ctx = widget.question['context']?.toString();
    final total = _questions.length;
    final last = _review || total <= 1;
    final nextLabel = _review || total <= 1
        ? 'Send'
        : _step < total - 1
            ? 'Next'
            : 'Review';
    final q = _currentQuestion;
    final hasCtx = ctx != null && ctx.isNotEmpty && ctx != 'null' && _step == 0;
    final eyebrow = total > 1
        ? (_review
            ? Text('Review', style: sans(13, color: AppColors.fg3))
            : ChatCardSteps(index: _step, total: total))
        : null;
    return Focus(
      focusNode: _keys,
      onKeyEvent: _onKey,
      child: Padding(
        padding: EdgeInsets.fromLTRB(0, S.s4, 0, S.s6),
        child: ChatCard(children: [
          Flexible(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_review) ...[
                    ChatCardHeader(
                        title: 'Check your answers', eyebrow: eyebrow),
                    ..._reviewRows(),
                  ] else if (q != null) ...[
                    ChatCardHeader(
                      title: q['text']?.toString() ?? '',
                      subtitle: hasCtx ? ctx : null,
                      eyebrow: eyebrow,
                    ),
                    ..._inputFor(q),
                  ],
                ],
              ),
            ),
          ),
          if (!kMobile && !_sent)
            Padding(
              padding: EdgeInsets.fromLTRB(ChatCard.pad, S.s8, ChatCard.pad, 0),
              child: Text(last ? 'Enter to submit' : 'Enter for next',
                  style: TS.caption(AppColors.fg4)),
            ),
          SizedBox(height: S.of(10)),
          ChatCardActions(
            stack: !(_step > 0 || _review),
            buttons: [
              if (_step > 0 || _review)
                ChatCardButton('Back',
                    kind: ChatCardButtonKind.secondary,
                    onTap: _sent ? null : _back),
              ChatCardButton(_sent ? 'Sending…' : nextLabel,
                  busy: _sent,
                  onTap: (_ready && !_sent) ? _submit : null),
            ],
            link: _review ? null : 'Skip',
            onLink: _sent ? null : _skip,
          ),
        ]),
      ),
    );
  }
}

class _Attachment {
  final String name;
  final bool isImage;
  final bool isAudio;
  final String? localPath;
  String? remotePath;
  bool uploading = true;

  /// Text pasted into the composer, kept as a card and sent inline.
  String? pastedText;
  _Attachment(
      {required this.name,
      required this.isImage,
      required this.isAudio,
      this.localPath});

  _Attachment.pasted(String text)
      : name = 'Pasted text',
        isImage = false,
        isAudio = false,
        localPath = null,
        pastedText = text,
        uploading = false;

  /// Brought back from a saved draft: already uploaded (or pasted), so ready.
  _Attachment.fromDraft(DraftAttachment d)
      : name = d.name,
        isImage = d.isImage,
        isAudio = d.isAudio,
        localPath = d.localPath,
        remotePath = d.remotePath,
        pastedText = d.pastedText,
        uploading = false;

  DraftAttachment toDraft() => DraftAttachment(
        name: name,
        isImage: isImage,
        isAudio: isAudio,
        localPath: localPath,
        remotePath: remotePath,
        pastedText: pastedText,
      );

  bool get ready => remotePath != null || pastedText != null;

  /// How this attachment is referenced in the outgoing message.
  String get marker {
    final pasted = pastedText;
    if (pasted != null) return pastedTextBlock(pasted);
    return isImage
        ? '[attached image — call view_image on this exact path to see it: $remotePath]'
        : '[attached file — read it at this exact path: $remotePath]';
  }
}

class _SessionActionsPanel extends StatefulWidget {
  final HarnessState? session;
  final void Function(String text) onSetGoal;
  final VoidCallback onCancelGoal;
  final VoidCallback onResumeGoal;
  final VoidCallback onLanes;
  final VoidCallback? onGiveWork;
  final VoidCallback? onAutonomy;
  final VoidCallback? onWakes;
  final bool hideShell;
  final VoidCallback onTerm;
  final VoidCallback onGit;
  final VoidCallback onFiles;
  final VoidCallback onDeliverables;
  final VoidCallback? onPullRequests;
  final VoidCallback onProcesses;
  final VoidCallback onRecurring;
  final VoidCallback? onTasks;
  final VoidCallback onCompact;
  final VoidCallback onCheckpoints;
  final VoidCallback onMemory;
  final VoidCallback? onFileChanges;
  final int fileChangeCount;
  final bool hideWorkspace;
  final bool hideGoal;
  final bool hideCheckpoints;
  final bool? autoSettle;
  final ValueChanged<bool>? onAutoSettle;

  /// The session's persisted cold-resume mode ('ask'/'lean'/'full'), when the
  /// session is allowed to change it.
  final String? resumeMode;
  final ValueChanged<String>? onResumeMode;

  /// Pass the session to another agent; null hides the row.
  final VoidCallback? onHandOff;
  final VoidCallback? onFork;
  final Widget? header;

  /// The Actions page layout: hero, grouped rows and drill-in pages.
  final bool page;

  /// Deletes the session; null hides the danger group.
  final VoidCallback? onDelete;
  final String? ownAgent;
  final String? ownProfile;

  /// Profile name to provider, for the lane provider icons.
  final Map<String, String> providers;
  const _SessionActionsPanel({
    required this.session,
    this.onFork,
    this.header,
    this.page = false,
    this.onDelete,
    this.ownAgent,
    this.ownProfile,
    this.providers = const {},
    required this.onSetGoal,
    required this.onCancelGoal,
    required this.onResumeGoal,
    required this.onLanes,
    this.onGiveWork,
    this.onAutonomy,
    this.onWakes,
    this.hideShell = false,
    required this.onTerm,
    required this.onGit,
    required this.onFiles,
    required this.onDeliverables,
    this.onPullRequests,
    required this.onProcesses,
    required this.onRecurring,
    this.onTasks,
    required this.onCompact,
    required this.onCheckpoints,
    required this.onMemory,
    this.onFileChanges,
    this.fileChangeCount = 0,
    this.hideWorkspace = false,
    this.hideGoal = false,
    this.hideCheckpoints = false,
    this.autoSettle,
    this.onAutoSettle,
    this.resumeMode,
    this.onResumeMode,
    this.onHandOff,
  });

  @override
  State<_SessionActionsPanel> createState() => _SessionActionsPanelState();
}

class _SessionActionsPanelState extends State<_SessionActionsPanel> {
  String? _open;
  ({String title, Widget Function(BuildContext, VoidCallback) body})? _sub;
  late bool? _auto = widget.autoSettle;
  late String? _resume = widget.resumeMode;
  late final TextEditingController _goalCtl = TextEditingController();

  @override
  void dispose() {
    _goalCtl.dispose();
    super.dispose();
  }

  void _toggle(String id) => setState(() => _open = _open == id ? null : id);

  Widget _group(String label, List<Widget> rows) =>
      ActionGroup(label: label, rows: rows, card: true);

  Widget _row({
    required String icon,
    required String label,
    String? detail,
    String? value,
    String? id,
    VoidCallback? onTap,
    Widget? child,
    Widget? trailing,
  }) =>
      ActionRow(
        icon: icon,
        label: label,
        detail: detail,
        value: value,
        dense: true,
        expandable: id != null,
        open: id != null && _open == id,
        onTap: onTap ?? (id != null ? () => _toggle(id) : null),
        trailing: trailing,
        child: child,
      );



  Widget _mobileGoalRow(HarnessState? s, bool goalOn) {
    final goal = s?.goal;
    if (goalOn && goal != null) {
      return _row(
        icon: 'goal',
        label: 'Goal',
        detail: goal.text,
        value: goal.paused ? 'Paused' : 'Working',
        id: 'goal',
        child: Align(
          alignment: Alignment.centerLeft,
          child: Btn(goal.paused ? 'Resume goal' : 'Cancel goal',
              small: true,
              variant: BtnVariant.secondary,
              onTap: goal.paused ? widget.onResumeGoal : widget.onCancelGoal),
        ),
      );
    }
    return _row(
      icon: 'goal',
      label: 'Set a goal',
      detail: 'Something to work toward on its own',
      id: 'goal',
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          AppField(
              controller: _goalCtl,
              hint: 'What should the agent work toward?',
              minLines: 2,
              maxLines: 4),
          SizedBox(height: S.of(10)),
          Btn('Set goal', full: true, onTap: () {
            final t = _goalCtl.text.trim();
            if (t.isEmpty) return;
            widget.onSetGoal(t);
            _goalCtl.clear();
          }),
        ],
      ),
    );
  }

  Widget? _autoSettleRow() {
    final on = _auto;
    if (on == null || widget.onAutoSettle == null) return null;
    void flip() {
      setState(() => _auto = !on);
      widget.onAutoSettle!(!on);
    }

    return _row(
      icon: 'archive',
      label: 'Auto-settle',
      detail: 'Save memory and park this chat after 12 hours idle',
      onTap: flip,
      trailing: SettingsSwitch(value: on, onChanged: (_) => flip()),
    );
  }

  Widget? _resumeModeRow() {
    final mode = _resume;
    if (mode == null || widget.onResumeMode == null) return null;
    void pick(String m) {
      setState(() => _resume = m);
      widget.onResumeMode!(m);
    }

    return _row(
      icon: 'clock',
      label: 'Cold resume',
      detail: 'How a cold session picks up its history',
      value: _modeLabel(mode),
      id: 'resume',
      child: Row(children: [
        for (final m in const ['ask', 'lean', 'full'])
          Padding(
            padding: EdgeInsets.only(right: S.s6),
            child: Btn(
              _modeLabel(m),
              small: true,
              variant:
                  m == mode ? BtnVariant.primary : BtnVariant.secondary,
              onTap: () => pick(m),
            ),
          ),
      ]),
    );
  }

  static String _modeLabel(String mode) => switch (mode) {
        'lean' => 'Lean',
        'full' => 'Full',
        _ => 'Ask',
      };

  Widget _goalCard(HarnessState? s) {
    final goal = s!.goal!;
    return Container(
      padding: EdgeInsets.all(S.of(14)),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(R.of(20)),
        border: Border.all(color: AppColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(children: [
            AppIcon('goal', size: 15, color: AppColors.accent),
            SizedBox(width: S.s8),
            Text('Goal', style: sans(13, color: AppColors.fg3)),
            const Spacer(),
            Container(
              padding:
                  EdgeInsets.symmetric(horizontal: S.s8, vertical: S.s2),
              decoration: BoxDecoration(
                color: (goal.paused ? AppColors.run : AppColors.ok)
                    .withValues(alpha: 0.13),
                borderRadius: BorderRadius.circular(R.of(8)),
              ),
              child: Text(goal.paused ? 'Paused' : 'Working',
                  style: sans(12,
                      weight: W.label,
                      color: goal.paused ? AppColors.run : AppColors.ok)),
            ),
          ]),
          SizedBox(height: S.s8),
          Text(goal.text, style: sans(15, color: AppColors.fg1)),
          SizedBox(height: S.s12),
          Btn(goal.paused ? 'Resume goal' : 'Cancel goal',
              small: true,
              variant: BtnVariant.secondary,
              onTap: goal.paused ? widget.onResumeGoal : widget.onCancelGoal),
        ],
      ),
    );
  }


  /// A drill-in: a pushed page on phones (so back steps out one level), the
  /// panel's own content on desktop where a popover has no route stack.
  void _drill(BuildContext context, String title,
      Widget Function(BuildContext, VoidCallback) body) {
    if (kMobile) {
      pushActionsSubPage(context, title: title, body: body);
    } else {
      setState(() => _sub = (title: title, body: body));
    }
  }

  /// Leaves a drill-in page, then runs an action that closes the whole panel.
  void _leave(VoidCallback back, VoidCallback action) {
    if (kMobile) back();
    action();
  }

  SettingsRow _prow(String icon, String label, String? sub, VoidCallback? onTap,
          {String? value, bool accent = false, bool danger = false}) =>
      SettingsRow(
        icon: icon,
        label: label,
        sub: sub,
        value: value,
        accent: accent,
        danger: danger,
        chevron: !danger,
        onTap: onTap,
      );

  Widget _pageBuild(BuildContext context) {
    final s = widget.session;
    final goal = s?.goal;
    final goalOn = (goal?.ongoing ?? false) && goal != null;
    final lanes = s?.lanes ?? const <LaneInfo>[];
    final running = lanes.where((l) => l.running).length;
    final counts = s?.counts ?? const SessionCounts();
    final sub = _sub;
    if (sub != null && !kMobile) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(
                Grouped.padX, Grouped.padX, Grouped.padX, 8),
            child: Row(children: [
              GroupedCircleButton(
                  icon: 'chevron-left',
                  tooltip: 'Back',
                  onTap: () => setState(() => _sub = null)),
              const SizedBox(width: 12),
              Expanded(
                  child: Text(sub.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Grouped.pageTitleStyle())),
            ]),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: Grouped.padX),
            child: sub.body(context, () => setState(() => _sub = null)),
          ),
        ],
      );
    }

    final now = <Widget>[
      if (!widget.hideGoal && lanes.isNotEmpty)
        SettingsRow(
            icon: 'layers',
            label: 'Lanes',
            subWidget: LaneSub(
                text: laneSummary(lanes, ownAgent: widget.ownAgent),
                providers:
                    laneProviders(lanes, widget.providers, widget.ownProfile)),
            value: running > 0 ? '$running running' : 'All finished',
            chevron: true,
            onTap: widget.onLanes),
      if (!widget.hideGoal)
        goalOn
            ? _prow('goal', 'Goal', goal.text,
                () => _drill(context, 'Goal', (_, back) => SessionGoalPage(
                    goal: goal,
                    onSet: widget.onSetGoal,
                    onCancel: widget.onCancelGoal,
                    onResume: widget.onResumeGoal,
                    onDone: back)),
                value: goal.paused ? 'Paused' : 'Working')
            : _prow(
                'goal',
                'Set a goal',
                'Something to work toward on its own',
                () => _drill(context, 'Set a goal', (_, back) => SessionGoalPage(
                    goal: null,
                    onSet: widget.onSetGoal,
                    onCancel: widget.onCancelGoal,
                    onResume: widget.onResumeGoal,
                    onDone: back)),
                accent: true),
      if (widget.onAutonomy != null)
        _prow('activity', 'Automated wakes',
            'Keeps the work moving while you are away', widget.onAutonomy),
      if (widget.onTasks != null)
        _prow('task', 'Tasks', 'Work on the board and its reviews',
            widget.onTasks),
    ];
    final session = <Widget>[
      if (widget.onHandOff != null)
        _prow('transfer', 'Hand off', 'Pass this session to another agent',
            widget.onHandOff),
      if (widget.onFork != null)
        _prow('git-fork', 'Fork from here', 'A new session; this one stays',
            widget.onFork),
      if (widget.onWakes != null)
        _prow('calendar-clock', 'Wakes and schedule',
            'Wake times, keep warm, recurring jobs', widget.onWakes),
      _prow('scheduled', 'Scheduled', 'Recurring jobs on this machine',
          widget.onRecurring),
    ];
    final auto = _auto;
    final resume = _resume;
    final behaviour = [
      if (auto != null && widget.onAutoSettle != null)
        'Auto-settle ${auto ? 'on' : 'off'}',
      if (resume != null && widget.onResumeMode != null)
        'cold resume ${_modeLabel(resume).toLowerCase()}s',
    ];
    final more = <Widget>[
      if (!widget.hideWorkspace)
        _prow(
            'folder',
            'Workspace',
            [
              if (widget.onFileChanges != null) 'Changes',
              'Git',
              'files',
              if (!widget.hideShell) 'shell',
              'processes',
            ].join(', '), () {
          _drill(context, 'Workspace', (_, back) => _workspace(counts, back));
        }),
      _prow('history', 'History', [
          if (!widget.hideCheckpoints) 'Checkpoints',
          'memory',
          'compact',
        ].join(', '), () {
          _drill(context, 'History', (_, back) => _history(back));
        }),
      if (behaviour.isNotEmpty)
        _prow('sliders', 'Behaviour', behaviour.join(' \u00b7 '), () {
          _drill(
              context,
              'Behaviour',
              (_, __) => SessionBehaviourPage(
                    auto: _auto,
                    resume: _resume,
                    onAuto: widget.onAutoSettle == null
                        ? null
                        : (v) {
                            setState(() => _auto = v);
                            widget.onAutoSettle!(v);
                          },
                    onResume: widget.onResumeMode == null
                        ? null
                        : (m) {
                            setState(() => _resume = m);
                            widget.onResumeMode!(m);
                          },
                  ));
        }),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.header != null)
          Padding(
              padding: EdgeInsets.only(bottom: Grouped.sectionGap - 8),
              child: widget.header!),
        SettingsGroup(header: now.isEmpty ? null : 'Now', children: now),
        SettingsGroup(header: 'Session', children: session),
        SettingsGroup(header: 'More', children: more),
        if (widget.onDelete != null)
          SettingsGroup(children: [
            _prow('trash', 'Delete session',
                'Removes the chat; the workspace stays', widget.onDelete,
                danger: true),
          ]),
      ],
    );
  }

  Widget _workspace(SessionCounts counts, VoidCallback back) => SettingsGroup(
        children: [
          if (widget.onFileChanges != null)
            _prow(
                'file-code',
                'Changes',
                widget.fileChangeCount == 0
                    ? 'Nothing edited yet'
                    : '${widget.fileChangeCount} file${widget.fileChangeCount == 1 ? '' : 's'} changed in this session',
                widget.onFileChanges),
          _prow('git-branch', 'Git', 'Branch, commits and diffs',
              widget.onGit,
              value: counts.changedFiles > 0 ? '${counts.changedFiles}' : null),
          _prow('folder', 'Files', 'Browse the workspace', widget.onFiles),
          _prow('layers', 'Shared', 'Files the agent shared',
              widget.onDeliverables),
          if (widget.onPullRequests != null)
            _prow('git-commit', 'Pull requests', 'Open on this repository',
                widget.onPullRequests,
                value: counts.openPrs > 0 ? '${counts.openPrs}' : null),
          if (!widget.hideShell)
            _prow('terminal', 'Shell', 'A terminal in the workspace',
                () => _leave(back, widget.onTerm)),
          _prow('processes', 'Processes', 'What is running here',
              widget.onProcesses,
              value: counts.processes > 0 ? '${counts.processes}' : null),
        ],
      );

  Widget _history(VoidCallback back) => SettingsGroup(children: [
        if (!widget.hideCheckpoints)
          _prow('history', 'Checkpoints',
              'Restore the workspace to an earlier point',
              widget.onCheckpoints),
        _prow('book-marked', 'Memory', 'What this session remembers',
            widget.onMemory),
        _prow('minimize', 'Compact history',
            'Summarise older turns to free context',
            () => _leave(back, widget.onCompact)),
      ]);

  @override
  Widget build(BuildContext context) {
    if (widget.page) return _pageBuild(context);
    final s = widget.session;
    final goalOn = (s?.goal?.ongoing ?? false) && s?.goal != null;
    final runningLanes = s?.lanes.where((l) => l.running).length ?? 0;
    final showLanes = !widget.hideGoal && (s?.lanes.isNotEmpty ?? false);

    final workRows = <Widget>[
      if (widget.onFileChanges != null && !widget.hideWorkspace)
        _row(
            icon: 'file-code',
            label: 'File changes',
            detail: widget.fileChangeCount == 0
                ? 'Nothing edited yet'
                : '${widget.fileChangeCount} file${widget.fileChangeCount == 1 ? '' : 's'} changed in this session',
            onTap: widget.onFileChanges),
      if (widget.onTasks != null)
        _row(
            icon: 'task',
            label: 'Tasks',
            detail: 'Work on the board and its reviews',
            onTap: widget.onTasks),
      _row(
          icon: 'scheduled',
          label: 'Scheduled',
          detail: 'Recurring jobs on this machine',
          onTap: widget.onRecurring),
    ];
    final historyRows = <Widget>[
      if (!widget.hideCheckpoints)
        _row(
            icon: 'history',
            label: 'Checkpoints',
            detail: 'Restore the workspace to an earlier point',
            onTap: widget.onCheckpoints),
      _row(
          icon: kMobile ? 'book-marked' : 'brain',
          label: 'Memory',
          detail: 'What this session remembers',
          onTap: widget.onMemory),
      _row(
          icon: 'minimize',
          label: 'Compact history',
          detail: 'Summarise older turns to free context',
          onTap: widget.onCompact),
    ];
    final sessionRows = <Widget>[
      if (!widget.hideGoal && !goalOn) _mobileGoalRow(s, false),
      if (widget.onAutonomy != null)
        _row(
            icon: 'activity',
            label: 'Automated wakes',
            detail: 'Keeps the work moving while you are away',
            onTap: widget.onAutonomy),
      if (_autoSettleRow() case final row?) row,
      if (_resumeModeRow() case final row?) row,
      if (widget.onHandOff != null)
        _row(
            icon: 'transfer',
            label: 'Hand off',
            detail: 'Pass this session to another agent',
            onTap: widget.onHandOff),
    ];
    final tiles = <Widget>[
      if (showLanes)
        SessionFaceTile(
            icon: 'layers',
            label: 'Lanes',
            detail: runningLanes > 0
                ? '$runningLanes running'
                : 'All finished',
            onTap: widget.onLanes),
      if (widget.onWakes != null)
        SessionFaceTile(
            icon: 'calendar-clock',
            label: 'Wakes',
            detail: 'Schedule, keep warm',
            onTap: widget.onWakes!),
      if (widget.onFork != null)
        SessionFaceTile(
            icon: 'git-branch',
            label: 'Fork',
            detail: 'From this point',
            onTap: widget.onFork!),
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (widget.header != null) widget.header!,
        if (!widget.hideGoal && goalOn) ...[
          SizedBox(height: S.s8),
          _goalCard(s),
        ],
        if (tiles.isNotEmpty) ...[
          SizedBox(height: S.s8),
          IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < tiles.length; i++) ...[
                  if (i > 0) SizedBox(width: S.s8),
                  Expanded(child: tiles[i]),
                ],
              ],
            ),
          ),
        ],
        if (!widget.hideWorkspace) ...[
          SizedBox(height: S.s8),
          SessionShortcutStrip(
            counts: s?.counts ?? const SessionCounts(),
            onGit: widget.onGit,
            onFiles: widget.onFiles,
            onDeliverables: widget.onDeliverables,
            onPullRequests: widget.onPullRequests,
            onTerm: widget.hideShell ? null : widget.onTerm,
            onProcesses: widget.onProcesses,
          ),
        ],
        _group('Work', workRows),
        _group('History', historyRows),
        _group('Session', sessionRows),
      ],
    );
  }
}

/// Agent character, session title and `Agent · branch` over the actions.
class SessionActionsHeader extends StatelessWidget {
  const SessionActionsHeader({
    super.key,
    required this.agentId,
    required this.title,
    required this.agentName,
    this.branch,
  });

  final String agentId;
  final String title;
  final String agentName;
  final String? branch;

  @override
  Widget build(BuildContext context) {
    final b = (branch ?? '').trim();
    return Row(children: [
      AgentMochi(agentId, size: 40),
      SizedBox(width: S.s12),
      Expanded(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(17, weight: W.title, color: AppColors.fg1)),
            Row(children: [
              Text(agentName, style: sans(12, color: AppColors.fg3)),
              if (b.isNotEmpty) ...[
                SizedBox(width: S.s6),
                AppIcon('git-branch', size: 12, color: AppColors.fg3),
                SizedBox(width: S.s4),
                Flexible(
                  child: Text(b,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: mono(12, color: AppColors.fg3)),
                ),
              ],
            ]),
          ],
        ),
      ),
    ]);
  }
}

/// A face tile: icon, title and a two-line detail on a rounded surface.
class SessionFaceTile extends StatelessWidget {
  const SessionFaceTile({
    super.key,
    required this.icon,
    required this.label,
    required this.detail,
    required this.onTap,
  });

  final String icon;
  final String label;
  final String detail;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => Material(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(R.of(16)),
        child: InkWell(
          borderRadius: BorderRadius.circular(R.of(16)),
          onTap: () {
            tapHaptic();
            onTap();
          },
          child: Container(
            padding: EdgeInsets.all(S.of(12)),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(R.of(16)),
              border: Border.all(color: AppColors.border),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                AppIcon(icon, size: 17, color: AppColors.accent),
                SizedBox(height: S.s8),
                Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(14, weight: W.label, color: AppColors.fg1)),
                SizedBox(height: S.s2),
                Text(detail,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(12, color: AppColors.fg3)),
              ],
            ),
          ),
        ),
      );
}

class SessionShortcutStrip extends StatelessWidget {
  final SessionCounts counts;
  final VoidCallback onGit;
  final VoidCallback onFiles;
  final VoidCallback onDeliverables;
  final VoidCallback? onPullRequests;
  final VoidCallback? onTerm;
  final VoidCallback onProcesses;

  const SessionShortcutStrip({
    super.key,
    required this.counts,
    required this.onGit,
    required this.onFiles,
    required this.onDeliverables,
    this.onPullRequests,
    this.onTerm,
    required this.onProcesses,
  });

  @override
  Widget build(BuildContext context) {
    final shortcuts = <Widget>[
      SessionShortcutTile(
        icon: 'git-branch',
        label: 'Git',
        onTap: onGit,
        count: counts.changedFiles,
      ),
      SessionShortcutTile(icon: 'folder', label: 'Files', onTap: onFiles),
      SessionShortcutTile(
          icon: 'layers', label: 'Shared', onTap: onDeliverables),
      if (onPullRequests != null)
        SessionShortcutTile(
          icon: 'git-commit',
          label: 'PRs',
          onTap: onPullRequests!,
          count: counts.openPrs,
        ),
      if (onTerm != null)
        SessionShortcutTile(icon: 'terminal', label: 'Shell', onTap: onTerm!),
      SessionShortcutTile(
        icon: 'processes',
        label: 'Processes',
        onTap: onProcesses,
        count: counts.processes,
      ),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: shortcuts),
    );
  }
}

class SessionShortcutTile extends StatelessWidget {
  final String icon;
  final String label;
  final VoidCallback onTap;
  final int count;

  const SessionShortcutTile({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.count = 0,
  });

  @override
  Widget build(BuildContext context) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          width: 64,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(children: [
              Stack(
                clipBehavior: Clip.none,
                children: [
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(
                      color: AppColors.surface1,
                      shape: BoxShape.circle,
                      border: Border.all(
                          color: AppColors.fg1.withValues(alpha: 0.08)),
                    ),
                    alignment: Alignment.center,
                    child: AppIcon(icon, size: 19, color: AppColors.fg1),
                  ),
                  if (count > 0)
                    Positioned(
                      right: -2,
                      top: -2,
                      child: Container(
                        constraints: const BoxConstraints(minWidth: 18),
                        height: 18,
                        padding: const EdgeInsets.symmetric(horizontal: 5),
                        decoration: BoxDecoration(
                          color: AppColors.accentFill,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: AppColors.bg, width: 1.5),
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          count > 99 ? '99+' : '$count',
                          style: mono(10,
                              weight: W.label, color: AppColors.accentFg),
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(height: 6),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12, color: AppColors.fg2)),
            ]),
          ),
        ),
      );
}
