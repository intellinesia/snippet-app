import 'package:flutter/material.dart';

import '../api.dart';
import '../chat/chat_card.dart';
import '../models.dart';
import '../theme.dart';
import '../transcript_card.dart';
import '../widgets.dart';

/// A relayed `ask_user` batch: every question in the ask, answerable in place.
///
/// Rendered for question events whose `payload.question.questions` is a list;
/// older single-question payloads keep the read-only path in
/// agent_thread_cards.dart.
class AgentQuestionsCard extends StatefulWidget {
  const AgentQuestionsCard({
    super.key,
    required this.event,
    required this.question,
    required this.client,
    this.events = const [],
    this.chatStyle = false,
  });

  final CoordinationEvent event;
  final Map<dynamic, dynamic> question;
  final DaemonClient client;
  final List<CoordinationEvent> events;
  final bool chatStyle;

  @override
  State<AgentQuestionsCard> createState() => _AgentQuestionsCardState();
}

class _QChoice {
  final String value;
  final String label;
  final String description;
  final bool recommended;

  const _QChoice({
    required this.value,
    required this.label,
    required this.description,
    required this.recommended,
  });
}

class _AgentQuestionsCardState extends State<AgentQuestionsCard> {
  final Map<String, TextEditingController> _texts = {};
  final Map<String, String> _single = {};
  final Map<String, Set<String>> _multi = {};
  String? _error;
  bool _sending = false;
  bool _locked = false;
  Map<String, dynamic>? _sentAnswers;

  List<Map<String, dynamic>> get _questions {
    final raw = widget.question['questions'];
    if (raw is! List) return const [];
    return [for (final q in raw.whereType<Map>()) q.cast<String, dynamic>()];
  }

  static String _kindOf(Map<String, dynamic> q) {
    final ak = q['answer_kind'];
    if (ak is! Map) return 'free_text';
    return '${ak['kind'] ?? 'free_text'}';
  }

  static Map<dynamic, dynamic> _answerKind(Map<String, dynamic> q) {
    final ak = q['answer_kind'];
    return ak is Map ? ak : const {};
  }

  static String _key(Map<String, dynamic> q, int i) {
    final id = '${q['id'] ?? ''}'.trim();
    return id.isNotEmpty ? id : '$i';
  }

  List<_QChoice> _choicesFor(Map<String, dynamic> q) {
    String labelOr(String k, String fallback) {
      final v = '${_answerKind(q)[k] ?? ''}'.trim();
      return v.isEmpty ? fallback : v;
    }

    switch (_kindOf(q)) {
      case 'yes_no':
        return const [
          _QChoice(
            value: 'yes',
            label: 'Yes',
            description: '',
            recommended: false,
          ),
          _QChoice(
            value: 'no',
            label: 'No',
            description: '',
            recommended: false,
          ),
        ];
      case 'confirm':
        return [
          _QChoice(
            value: 'confirm',
            label: labelOr('confirm_label', 'Confirm'),
            description: '',
            recommended: false,
          ),
          _QChoice(
            value: 'cancel',
            label: labelOr('cancel_label', 'Cancel'),
            description: '',
            recommended: false,
          ),
        ];
      case 'single_choice':
      case 'multi_choice':
        final raw = _answerKind(q)['choices'];
        if (raw is! List) return const [];
        return [
          for (final c in raw.whereType<Map>())
            () {
              final value = '${c['value'] ?? ''}'.trim();
              final label = '${c['label'] ?? c['value'] ?? ''}'.trim();
              return _QChoice(
                value: value,
                label: label.isEmpty ? value : label,
                description: '${c['description'] ?? ''}'.trim(),
                recommended: c['recommended'] == true,
              );
            }(),
        ];
    }
    return const [];
  }

  @override
  void initState() {
    super.initState();
    final qs = _questions;
    for (var i = 0; i < qs.length; i++) {
      final q = qs[i];
      final kind = _kindOf(q);
      if (kind != 'single_choice' && kind != 'multi_choice') continue;
      final key = _key(q, i);
      for (final c in _choicesFor(q).where((c) => c.recommended)) {
        if (kind == 'multi_choice') {
          _multi.putIfAbsent(key, () => <String>{}).add(c.value);
        } else {
          _single[key] = c.value;
        }
      }
    }
  }

  @override
  void dispose() {
    for (final c in _texts.values) {
      c.dispose();
    }
    super.dispose();
  }

  TextEditingController _controllerFor(String key) =>
      _texts.putIfAbsent(key, () {
        final c = TextEditingController();
        c.addListener(() {
          if (mounted) setState(() {});
        });
        return c;
      });

  /// The answer event for this question, if one exists later in the thread,
  /// plus whether the question went stale (a later agent event, no answer).
  ({Map<String, dynamic>? answers, bool answered, bool closed, String? body})
      _resolve() {
    final id = widget.event.eventId;
    Map<String, dynamic>? answers;
    String? body;
    var answered = false;
    var closed = false;
    var seen = id.isEmpty;
    for (final e in widget.events) {
      if (!seen) {
        if (e.eventId == id) seen = true;
        continue;
      }
      if (e.payload['answer_to'] == id) {
        answered = true;
        final a = e.payload['answers'];
        if (a is Map) answers = a.cast<String, dynamic>();
        final b = e.body.trim();
        if (b.isNotEmpty) body = b;
        continue;
      }
      if (e.actorKind != 'human') closed = true;
    }
    if (!answered && _sentAnswers != null) {
      answered = true;
      answers = _sentAnswers;
    }
    return (
      answers: answers,
      answered: answered,
      closed: closed && !answered,
      body: body,
    );
  }

  static const _kSkipped = 'user skipped the question';

  bool _wasSkipped(Map<String, dynamic>? answers, String? body) {
    if (body != null && body.contains(_kSkipped)) return true;
    return answers?.values.any((v) => '$v' == _kSkipped) ?? false;
  }

  Object? _answerFor(
    Map<String, dynamic> q,
    int i,
    Map<String, dynamic>? answers,
  ) {
    if (answers == null) return null;
    final id = '${q['id'] ?? ''}'.trim();
    for (final k in [_key(q, i), id, '$i']) {
      if (k.isNotEmpty && answers.containsKey(k)) return answers[k];
    }
    return null;
  }

  static Set<String> _tokens(Object? raw, {required bool multi}) {
    if (raw == null) return const {};
    if (raw is List) {
      return {
        for (final item in raw)
          if (item != null && '$item'.trim().isNotEmpty) '$item'.trim(),
      };
    }
    if (raw is Map) {
      final v = (raw['value'] ?? raw['label'] ?? raw['text'] ?? '')
          .toString()
          .trim();
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

  static bool _choiceMatches(_QChoice c, Set<String> tokens) {
    if (tokens.isEmpty) return false;
    final combined = '${c.label} (${c.value})';
    return tokens.contains(c.value) ||
        tokens.contains(c.label) ||
        tokens.contains(combined);
  }

  /// How a choice reads in the composed answer text — mirrors `_QOption.answer`
  /// in session_approval.dart.
  static String _optionAnswer(String label, String value) {
    String norm(String x) =>
        x.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
    return norm(value) == norm(label) ? label : '$label ($value)';
  }

  /// The in-progress answer for one question, or null while it has no value.
  ({String text, Object? value})? _draft(Map<String, dynamic> q, int i) {
    final key = _key(q, i);
    switch (_kindOf(q)) {
      case 'free_text':
        final t = _controllerFor(key).text.trim();
        return t.isEmpty ? null : (text: t, value: t);
      case 'multi_choice':
        final picked = _multi[key];
        if (picked == null || picked.isEmpty) return null;
        final chosen = [
          for (final o in _choicesFor(q))
            if (picked.contains(o.value)) o,
        ];
        if (chosen.isEmpty) return null;
        return (
          text: chosen.map((o) => _optionAnswer(o.label, o.value)).join(', '),
          value: [for (final o in chosen) o.value],
        );
      default:
        final v = _single[key];
        if (v == null) return null;
        String? label;
        for (final o in _choicesFor(q)) {
          if (o.value == v) {
            label = o.label;
            break;
          }
        }
        final l = label ?? v;
        return (text: _optionAnswer(l, v), value: v);
    }
  }

  bool get _allAnswered {
    final qs = _questions;
    if (qs.isEmpty) return false;
    for (var i = 0; i < qs.length; i++) {
      if (_draft(qs[i], i) == null) return false;
    }
    return true;
  }

  String _questionText(Map<String, dynamic> q) {
    final t = '${q['text'] ?? ''}'.trim();
    return t.isNotEmpty ? t : widget.event.body.trim();
  }

  Future<void> _post(Map<String, dynamic> answers, List<String> parts) async {
    final session = '${widget.question['session'] ?? ''}';
    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.client.answerAgentQuestion(
        session: session,
        questionEventId: widget.event.eventId,
        text: parts.join('\n\n'),
        answers: answers,
      );
      if (!mounted) return;
      setState(() {
        _sending = false;
        _sentAnswers = answers;
      });
    } on QuestionAnswerConflict catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _locked = true;
        _error = e.message.isNotEmpty
            ? e.message
            : 'This question is no longer waiting';
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = 'Could not send the answer.';
      });
    }
  }

  Future<void> _send() async {
    if (_sending || _locked) return;
    final qs = _questions;
    final drafts = [for (var i = 0; i < qs.length; i++) _draft(qs[i], i)];
    if (drafts.any((d) => d == null)) return;
    final answers = <String, dynamic>{};
    final parts = <String>[];
    for (var i = 0; i < qs.length; i++) {
      final d = drafts[i]!;
      answers[_key(qs[i], i)] = d.value;
      parts.add('${_questionText(qs[i])}\n→ ${d.text}');
    }
    await _post(answers, parts);
  }

  /// Skip the whole ask: every question gets the skip marker so the agent
  /// stops waiting, without a bubble echoing the question text back.
  Future<void> _skip() async {
    if (_sending || _locked) return;
    final qs = _questions;
    final answers = <String, dynamic>{
      for (var i = 0; i < qs.length; i++) _key(qs[i], i): _kSkipped,
    };
    final parts = [
      for (var i = 0; i < qs.length; i++)
        '${_questionText(qs[i])}\n→ $_kSkipped',
    ];
    await _post(answers, parts);
  }

  void _pick(int i, _QChoice c, bool multi) {
    final key = _key(_questions[i], i);
    setState(() {
      if (multi) {
        final set = _multi.putIfAbsent(key, () => <String>{});
        set.contains(c.value) ? set.remove(c.value) : set.add(c.value);
      } else {
        _single[key] = c.value;
      }
    });
  }

  int _step = 0;

  @override
  Widget build(BuildContext context) {
    final qs = _questions;
    if (qs.isEmpty) return const SizedBox.shrink();
    final st = _resolve();
    final closed = st.closed || (_locked && !st.answered);
    final interactive = !st.answered && !closed && !_sending;
    final skipped = st.answered && _wasSkipped(st.answers, st.body);
    if (st.answered) return _resolved(qs, st.answers, skipped);
    final step = _step.clamp(0, qs.length - 1);
    final q = qs[step];
    final last = step == qs.length - 1;
    final header = '${q['header'] ?? ''}'.trim();
    final showActions = !(closed && _error == null);
    final canNext = interactive && _draft(q, step) != null;
    final canSend = interactive && _allAnswered;
    return ChatCard(children: [
      ChatCardHeader(
        eyebrow: qs.length > 1
            ? ChatCardSteps(index: step, total: qs.length)
            : null,
        title: _questionText(q),
        subtitle: header,
        trailing: closed ? const ChatCardPill('Closed') : null,
      ),
      _inputFor(q, step, interactive: interactive),
      if (_error != null)
        ChatCardBody(
          child: Text(_error!,
              style: sans(TranscriptCard.metaSize, color: AppColors.danger)),
        ),
      if (showActions)
        ChatCardActions(
          buttons: [
            if (step > 0)
              ChatCardButton('Back',
                  kind: ChatCardButtonKind.secondary,
                  onTap: interactive ? () => setState(() => _step = step - 1) : null),
            if (last)
              ChatCardButton('Send',
                  busy: _sending, onTap: canSend ? _send : null)
            else
              ChatCardButton('Next',
                  onTap: canNext ? () => setState(() => _step = step + 1) : null),
          ],
          link: 'Skip',
          onLink: interactive ? _skip : null,
        )
      else
        const SizedBox(height: 2),
    ]);
  }

  Widget _resolved(List<Map<String, dynamic>> qs, Map<String, dynamic>? answers,
      bool skipped) {
    if (skipped) {
      return ChatCardResolved(
        title: qs.length > 1 ? '${qs.length} questions' : _questionText(qs[0]),
        subtitle: 'Skipped',
        approved: false,
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < qs.length; i++) ...[
          if (i > 0) const SizedBox(height: S.s6),
          Builder(builder: (_) {
            final label = _answeredLabel(qs[i], i, answers);
            return ChatCardResolved(
              title: _questionText(qs[i]),
              subtitle: label.isEmpty ? 'Answered' : 'Answered: $label',
              approved: true,
            );
          }),
        ],
      ],
    );
  }

  /// How an answered question reads in the collapsed card.
  String _answeredLabel(
      Map<String, dynamic> q, int i, Map<String, dynamic>? answers) {
    final v = _answerFor(q, i, answers);
    if (v == null) return '';
    if ('$v' == _kSkipped) return _kSkipped;
    final kind = _kindOf(q);
    if (kind == 'single_choice' ||
        kind == 'multi_choice' ||
        kind == 'yes_no' ||
        kind == 'confirm') {
      final tokens = _tokens(v, multi: kind == 'multi_choice');
      final labels = [
        for (final c in _choicesFor(q))
          if (_choiceMatches(c, tokens)) c.label,
      ];
      if (labels.isNotEmpty) return labels.join(', ');
      return tokens.join(', ');
    }
    return v is List ? v.join(', ') : '$v';
  }

  Widget _inputFor(
    Map<String, dynamic> q,
    int i, {
    required bool interactive,
  }) {
    final key = _key(q, i);
    final kind = _kindOf(q);
    switch (kind) {
      case 'single_choice':
      case 'multi_choice':
      case 'yes_no':
      case 'confirm':
        final multi = kind == 'multi_choice';
        final choices = _choicesFor(q);
        return Padding(
          padding: const EdgeInsets.only(bottom: S.s12),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final c in choices) ...[
                const ChatCardDivider(),
                ChatCardOption(
                  label: c.label,
                  detail: c.description.isEmpty ? null : c.description,
                  recommended: c.recommended,
                  multi: multi,
                  selected: multi
                      ? (_multi[key]?.contains(c.value) ?? false)
                      : _single[key] == c.value,
                  onTap: interactive ? () => _pick(i, c, multi) : null,
                ),
              ],
              const ChatCardDivider(),
            ],
          ),
        );
      default:
        return ChatCardBody(
          child: AppField(
            controller: _controllerFor(key),
            hint: 'Write your answer',
            minLines: 1,
            maxLines: 4,
            enabled: interactive,
          ),
        );
    }
  }
}


/// The centred line a relayed-question answer collapses to in the thread, or
/// null when [e] is an ordinary message. The question card already shows the
/// answer, so the composed "question\n→ answer" text must not echo as a bubble.
String? questionAnswerSystemLine(CoordinationEvent e) {
  if (e.actorKind != 'human') return null;
  final auto = '${e.payload['auto'] ?? ''}';
  if (auto != 'answer' && e.payload['answer_to'] == null) return null;
  final answers = e.payload['answers'];
  final skipped = e.body.contains('user skipped the question') ||
      (answers is Map &&
          answers.values.any((v) => '$v' == 'user skipped the question'));
  return skipped ? 'Skipped' : 'Answered';
}

/// The question card frame on the shared chat card: a quiet label with an
/// optional right-side pill (or "N questions" from [count]), body and footer.
class QuestionCardV5 extends StatelessWidget {
  const QuestionCardV5({
    super.key,
    required this.child,
    this.meta,
    this.count,
    this.footer,
    this.icon = 'help-circle',
    this.label = 'Question',
    this.iconColor,
  });

  final String icon;
  final String label;
  final Color? iconColor;
  final Widget child;
  final String? meta;
  final int? count;
  final Widget? footer;

  @override
  Widget build(BuildContext context) {
    final side = meta != null && meta!.isNotEmpty
        ? meta!
        : (count == null ? '' : count! > 1 ? '$count questions' : '1 of 1');
    return ChatCard(children: [
      ChatCardHeader(
        title: label,
        large: false,
        trailing: side.isEmpty ? null : ChatCardPill(side),
      ),
      ChatCardBody(bottom: footer != null, child: child),
      if (footer != null) ChatCardBody(child: footer!),
    ]);
  }
}
