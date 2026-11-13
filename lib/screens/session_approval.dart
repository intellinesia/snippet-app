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
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: ChatCardResolved(
            title: q.isEmpty ? 'Question' : q,
            subtitle: shown(a),
            approved: answers.isNotEmpty),
      );
    }
    final p = ChatCard.pad;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: ChatCard(dimmed: true, children: [
        for (var i = 0; i < rows.length; i++) ...[
          if (i > 0) const ChatCardDivider(),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: p, vertical: 10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(rows[i].$1,
                    style: sans(kMobile ? 15 : 13,
                        weight: W.strong, color: AppColors.fg2)),
                const SizedBox(height: 2),
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
  const ApprovalBar(
      {super.key,
      required this.events,
      required this.onSend,
      this.showApproveAll = false});
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
    final headline = callLabel.isNotEmpty ? callLabel : action;
    final isShell = tool == 'bash' || customTool != null;

    final canAlways = widget.showApproveAll &&
        !isVault &&
        laneName == null &&
        !parsed.newCustomTool;
    final isKnownTool = tool == 'bash' || tool == 'change_files';
    final subtitle = laneName != null
        ? 'Lane «$laneName»'
        : customTool != null
            ? 'Custom tool'
            : tool.isEmpty || (callLabel.isEmpty && isKnownTool)
                ? null
                : toolTitle(tool);

    return Padding(
      padding: const EdgeInsets.fromLTRB(0, S.s4, 0, S.s6),
      child: ChatCard(children: [
        Flexible(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ChatCardHeader(
                  title: headline,
                  subtitle: subtitle,
                  trailing: total > 1 ? ChatCardPill('$index of $total') : null,
                ),
                if (detail.isNotEmpty)
                  ChatCardBody(
                    child: Container(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 6),
                      decoration: BoxDecoration(
                        color: AppColors.bg,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: AppColors.line),
                      ),
                      child: ApprovalCode(code: detail, shell: isShell),
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
          stack: tool != 'change_files',
          buttons: [
            ChatCardButton('Deny',
                kind: ChatCardButtonKind.secondary,
                onTap: _sent ? null : () => _decide({'kind': 'deny'})),
            ChatCardButton('Approve',
                busy: _sent, onTap: () => _decide({'kind': 'approve'})),
          ],
          link: canAlways ? 'Always allow' : null,
          onLink: _sent ? null : () => _decide({'kind': 'approve_all'}),
        ),
      ]),
    );
  }
}

/// The agent's plan as a compact checklist: done steps recede, the step in
/// progress is highlighted, and the optional explanation says why it changed.
class _PlanCard extends StatelessWidget {
  final List<Map> steps;
  final String explanation;
  const _PlanCard(this.steps, this.explanation);

  @override
  Widget build(BuildContext context) {
    final done = steps
        .where((s) => s['status'] == 'done' || s['status'] == 'completed')
        .length;
    if (kMobile) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('PLAN  ·  $done/${steps.length}',
                style: sans(12,
                    weight: W.label, spacing: 0.7, color: AppColors.fg4)),
            if (explanation.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(explanation, style: sans(14, color: AppColors.fg3)),
            ],
            const SizedBox(height: 8),
            for (final step in steps)
              Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 3),
                      child: switch (step['status']?.toString()) {
                        'done' ||
                        'completed' =>
                          AppIcon('check', size: 14, color: AppColors.ok),
                        'in_progress' => Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                                color: AppColors.accent,
                                shape: BoxShape.circle),
                          ),
                        _ => Container(
                            width: 14,
                            height: 14,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              border:
                                  Border.all(color: AppColors.fg4, width: 1.5),
                            ),
                          ),
                      },
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Text(step['step']?.toString() ?? '',
                          style: sans(15,
                              height: 20 / 15,
                              color: const {'done', 'completed'}
                                      .contains(step['status'])
                                  ? AppColors.fg4
                                  : step['status'] == 'in_progress'
                                      ? AppColors.fg1
                                      : AppColors.fg2)),
                    ),
                  ],
                ),
              ),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
        decoration: BoxDecoration(
          color: AppColors.surface1,
          border: Border.all(color: AppColors.border),
          borderRadius: BorderRadius.circular(R.md),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('Plan · $done of ${steps.length} done',
                style: mono(10, color: AppColors.fg3)),
            if (explanation.isNotEmpty) ...[
              const SizedBox(height: 4),
              Text(explanation, style: sans(12, color: AppColors.fg2)),
            ],
            const SizedBox(height: 6),
            for (final step in steps) _row(step),
          ],
        ),
      ),
    );
  }

  Widget _row(Map step) {
    final status = step['status']?.toString() ?? 'pending';
    final (icon, color) = switch (status) {
      'done' => (Icons.check_circle, AppColors.ok),
      'in_progress' => (Icons.radio_button_checked, AppColors.accent),
      _ => (Icons.radio_button_unchecked, AppColors.fg4),
    };
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 2),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Icon(icon, size: 13, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              step['step']?.toString() ?? '',
              style: sans(13,
                  color: status == 'done' ? AppColors.fg3 : AppColors.fg1,
                  weight: status == 'in_progress' ? W.label : W.body),
            ),
          ),
        ],
      ),
    );
  }
}

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
              ChatCard.pad, k == 'free_text' ? 0 : 10, ChatCard.pad, 4),
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
                  EdgeInsets.symmetric(horizontal: ChatCard.pad, vertical: 10),
              child:
                  Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(_header(_questions[i], i), style: TS.meta()),
                      const SizedBox(height: 2),
                      Text(_answerFor(_questions[i]),
                          style: sans(kMobile ? 15 : 13,
                              height: 1.4, color: AppColors.fg1)),
                    ],
                  ),
                ),
                const SizedBox(width: 8),
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
        padding: const EdgeInsets.fromLTRB(0, S.s4, 0, S.s6),
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
              padding: EdgeInsets.fromLTRB(ChatCard.pad, 8, ChatCard.pad, 0),
              child: Text(last ? 'Enter to submit' : 'Enter for next',
                  style: TS.caption(AppColors.fg4)),
            ),
          const SizedBox(height: 10),
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
  const _SessionActionsPanel({
    required this.session,
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
  });

  @override
  State<_SessionActionsPanel> createState() => _SessionActionsPanelState();
}

class _SessionActionsPanelState extends State<_SessionActionsPanel> {
  String? _open;
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
      ActionGroup(label: label, rows: rows);

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
        expandable: id != null,
        open: id != null && _open == id,
        onTap: onTap ?? (id != null ? () => _toggle(id) : null),
        trailing: trailing,
        child: child,
      );

  Widget _shortcut(String icon, String label, VoidCallback onTap) => InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(18),
        child: SizedBox(
          width: 72,
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(children: [
              Container(
                width: 52,
                height: 52,
                decoration: BoxDecoration(
                  color: AppColors.surface1,
                  shape: BoxShape.circle,
                  border:
                      Border.all(color: AppColors.fg1.withValues(alpha: 0.08)),
                ),
                alignment: Alignment.center,
                child: AppIcon(icon, size: 21, color: AppColors.fg1),
              ),
              const SizedBox(height: 8),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13, color: AppColors.fg2)),
            ]),
          ),
        ),
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
          const SizedBox(height: 10),
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
            padding: const EdgeInsets.only(right: 6),
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

  Widget _mobileBuild(HarnessState? s, bool goalOn, List<Widget> workRows,
      List<Widget> historyRows) {
    final sessionRows = <Widget>[
      if (!widget.hideGoal) _mobileGoalRow(s, goalOn),
      if (widget.onAutonomy != null)
        _row(
            icon: 'activity',
            label: 'Automated wakes',
            detail: 'Keeps the work moving while you are away',
            onTap: widget.onAutonomy),
      if (widget.onWakes != null)
        _row(
            icon: 'calendar-clock',
            label: 'Wakes and keep warm',
            detail: 'Scheduled wakes and prompt cache',
            onTap: widget.onWakes),
      if (_autoSettleRow() case final row?) row,
      if (_resumeModeRow() case final row?) row,
    ];
    final shortcuts = <Widget>[
      _shortcut('git-branch', 'Git', widget.onGit),
      _shortcut('folder', 'Files', widget.onFiles),
      _shortcut('layers', 'Shared', widget.onDeliverables),
      if (widget.onPullRequests != null)
        _shortcut('git-commit', 'PRs', widget.onPullRequests!),
      if (!widget.hideShell) _shortcut('terminal', 'Shell', widget.onTerm),
      _shortcut('processes', 'Processes', widget.onProcesses),
    ];
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (!widget.hideWorkspace)
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(children: shortcuts),
          ),
        _group('Session', sessionRows),
        _group('Work', workRows),
        _group('History', historyRows),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.session;
    final goalOn = s?.goal?.ongoing ?? false;
    if (kMobile) {
      final runningLanes = s?.lanes.where((l) => l.running).length ?? 0;
      final workRows = <Widget>[
        if (widget.onFileChanges != null && !widget.hideWorkspace)
          _row(
              icon: 'file-code',
              label: 'File changes',
              detail: widget.fileChangeCount == 0
                  ? 'Nothing edited yet'
                  : '${widget.fileChangeCount} file${widget.fileChangeCount == 1 ? '' : 's'} changed in this session',
              onTap: widget.onFileChanges),
        if (!widget.hideGoal && (s?.lanes.isNotEmpty ?? false))
          _row(
              icon: 'layers',
              label: 'Lanes',
              detail: runningLanes > 0
                  ? '$runningLanes working in the background'
                  : 'Background work, finished',
              onTap: widget.onLanes),
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
      return _mobileBuild(s, goalOn, workRows, historyRows);
    }

    final sessionRows = <Widget>[
      if (widget.onAutonomy != null)
        _row(
            icon: 'activity',
            label: 'Automated wakes',
            detail:
                'Wakes on a schedule, keeps work moving and pings you while you are away',
            onTap: widget.onAutonomy),
      if (!widget.hideGoal)
        _row(
          icon: 'goal',
          label: goalOn ? 'Goal' : 'Set a goal',
          detail: goalOn
              ? 'The agent is driving toward this autonomously'
              : 'Give the agent something to work toward on its own',
          id: 'goal',
          value: goalOn ? (s!.goal!.paused ? 'paused' : 'running') : null,
          child: goalOn
              ? Btn(s!.goal!.paused ? 'Resume goal' : 'Cancel goal',
                  variant: BtnVariant.secondary,
                  onTap: s.goal!.paused
                      ? widget.onResumeGoal
                      : widget.onCancelGoal)
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    AppField(
                        controller: _goalCtl,
                        hint: 'What should the agent work toward?',
                        minLines: 2,
                        maxLines: 4),
                    const SizedBox(height: 8),
                    Btn('Set goal', onTap: () {
                      final t = _goalCtl.text.trim();
                      if (t.isEmpty) return;
                      widget.onSetGoal(t);
                      _goalCtl.clear();
                    }),
                  ],
                ),
        ),
      if (kMobile && !widget.hideGoal && (s?.lanes.isNotEmpty ?? false))
        _row(
            icon: 'layers',
            label: 'Lanes',
            detail: 'Background work running in parallel',
            onTap: widget.onLanes),
      if (widget.onWakes != null)
        _row(
            icon: 'calendar-clock',
            label: 'Wakes and keep warm',
            detail: 'Scheduled wakes and prompt cache',
            onTap: widget.onWakes),
      _row(
          icon: 'scheduled',
          label: 'Scheduled',
          detail: 'Recurring jobs on this machine',
          onTap: widget.onRecurring),
      if (_autoSettleRow() case final row?) row,
      if (_resumeModeRow() case final row?) row,
    ];

    final workspaceRows = <Widget>[
      if (kMobile)
        _row(
            icon: 'git-branch',
            label: 'Git',
            detail: 'Status, diffs, stage and commit',
            onTap: widget.onGit),
      _row(
          icon: 'folder',
          label: 'Files',
          detail: 'Browse the workspace',
          onTap: widget.onFiles),
      _row(
          icon: 'layers',
          label: 'Artifacts & files',
          detail: 'What the agent handed over',
          onTap: widget.onDeliverables),
      if (widget.onPullRequests != null)
        _row(
            icon: 'git-branch',
            label: 'Pull requests',
            detail: 'Review and merge on GitHub',
            onTap: widget.onPullRequests!),
      if (!widget.hideShell)
        _row(
            icon: 'terminal',
            label: 'Session shell',
            detail: 'A terminal in this workspace',
            onTap: widget.onTerm),
      _row(
          icon: 'list',
          label: 'Processes',
          detail: 'What is running on the machine',
          onTap: widget.onProcesses),
    ];

    final historyRows = <Widget>[
      _row(
          icon: 'minimize',
          label: 'Compact history',
          detail: 'Summarise older turns to free context',
          onTap: widget.onCompact),
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
    ];

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _group('Session', sessionRows),
        if (!widget.hideWorkspace) _group('Workspace', workspaceRows),
        _group('History', historyRows),
      ],
    );
  }
}
