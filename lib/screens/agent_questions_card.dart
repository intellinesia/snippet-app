import 'package:flutter/material.dart';

import '../api.dart';
import '../models.dart';
import '../platform.dart';
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
  });

  final CoordinationEvent event;
  final Map<dynamic, dynamic> question;
  final DaemonClient client;
  final List<CoordinationEvent> events;

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
  ({Map<String, dynamic>? answers, bool answered, bool closed}) _resolve() {
    final id = widget.event.eventId;
    Map<String, dynamic>? answers;
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
        continue;
      }
      if (e.actorKind != 'human') closed = true;
    }
    if (!answered && _sentAnswers != null) {
      answered = true;
      answers = _sentAnswers;
    }
    return (answers: answers, answered: answered, closed: closed && !answered);
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

  @override
  Widget build(BuildContext context) {
    final qs = _questions;
    final st = _resolve();
    final closed = st.closed || (_locked && !st.answered);
    final interactive = !st.answered && !closed && !_sending;
    return TranscriptCard(
      kind: 'Question',
      icon: 'help-circle',
      tone: st.answered ? Tone.ok : (closed ? Tone.neutral : Tone.accent),
      status: st.answered ? 'Answered' : (closed ? 'Closed' : null),
      footer: st.answered || (closed && _error == null)
          ? null
          : _footer(interactive),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var i = 0; i < qs.length; i++) ...[
            if (i > 0) const SizedBox(height: S.s12),
            _section(
              qs[i],
              i,
              answered: st.answered,
              interactive: interactive,
              answers: st.answers,
            ),
          ],
        ],
      ),
    );
  }

  Widget _section(
    Map<String, dynamic> q,
    int i, {
    required bool answered,
    required bool interactive,
    required Map<String, dynamic>? answers,
  }) {
    final header = '${q['header'] ?? ''}'.trim();
    final text = '${q['text'] ?? ''}'.trim();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (header.isNotEmpty)
          Text(
            header,
            style: sans(
              TranscriptCard.bodySize,
              weight: W.label,
              height: 1.4,
              color: AppColors.fg1,
            ),
          ),
        if (text.isNotEmpty) ...[
          if (header.isNotEmpty) const SizedBox(height: S.s4),
          Text(
            text,
            style: sans(
              TranscriptCard.bodySize,
              height: 1.4,
              color: AppColors.fg2,
            ),
          ),
        ],
        const SizedBox(height: S.s8),
        _inputFor(
          q,
          i,
          answered: answered,
          interactive: interactive,
          answers: answers,
        ),
      ],
    );
  }

  Widget _footer(bool interactive) {
    final canSend = interactive && _allAnswered;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Btn('Send', full: true, icon: 'send', disabled: !canSend, onTap: _send),
        if (_error != null) ...[
          const SizedBox(height: S.s6),
          Text(
            _error!,
            style: sans(TranscriptCard.metaSize, color: AppColors.danger),
          ),
        ],
      ],
    );
  }

  Widget _inputFor(
    Map<String, dynamic> q,
    int i, {
    required bool answered,
    required bool interactive,
    required Map<String, dynamic>? answers,
  }) {
    final key = _key(q, i);
    final kind = _kindOf(q);
    final choices = _choicesFor(q);
    final isChoice =
        kind == 'single_choice' ||
        kind == 'multi_choice' ||
        kind == 'yes_no' ||
        kind == 'confirm';
    if (answered) {
      if (!isChoice) {
        final v = _answerFor(q, i, answers);
        final s = v == null ? '' : (v is List ? v.join(', ') : '$v');
        if (s.isEmpty) return const SizedBox.shrink();
        return Text(
          s,
          style: sans(
            TranscriptCard.bodySize,
            height: 1.4,
            color: AppColors.fg1,
          ),
        );
      }
      final multi = kind == 'multi_choice';
      final tokens = _tokens(_answerFor(q, i, answers), multi: multi);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          for (var j = 0; j < choices.length; j++) ...[
            if (j > 0) const SizedBox(height: S.s6),
            _choiceRow(
              choices[j],
              selected: _choiceMatches(choices[j], tokens),
              multi: multi,
              readOnly: true,
              onTap: null,
            ),
          ],
        ],
      );
    }
    switch (kind) {
      case 'single_choice':
      case 'multi_choice':
        final multi = kind == 'multi_choice';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            for (var j = 0; j < choices.length; j++) ...[
              if (j > 0) const SizedBox(height: S.s6),
              _choiceRow(
                choices[j],
                selected: multi
                    ? (_multi[key]?.contains(choices[j].value) ?? false)
                    : _single[key] == choices[j].value,
                multi: multi,
                readOnly: false,
                onTap: interactive ? () => _pick(i, choices[j], multi) : null,
              ),
            ],
          ],
        );
      case 'yes_no':
        return Wrap(
          spacing: 8,
          children: [
            for (final o in choices)
              _pill(
                o.label,
                selected: _single[key] == o.value,
                enabled: interactive,
                onTap: () => setState(() => _single[key] = o.value),
              ),
          ],
        );
      case 'confirm':
        return Wrap(
          spacing: 8,
          children: [
            for (final o in choices)
              Btn(
                o.label,
                variant: BtnVariant.secondary,
                disabled: !interactive,
                onTap: () => setState(() => _single[key] = o.value),
              ),
          ],
        );
      default:
        return AppField(
          controller: _controllerFor(key),
          hint: 'Write your answer',
          minLines: 1,
          maxLines: 4,
          enabled: interactive,
        );
    }
  }

  Widget _choiceRow(
    _QChoice c, {
    required bool selected,
    required bool multi,
    required bool readOnly,
    VoidCallback? onTap,
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
                width: 1.5,
              ),
            ),
            child: selected
                ? AppIcon('check', size: 11, color: AppColors.accentFg)
                : null,
          )
        : SelectCheck(selected, size: 16);
    final body = Container(
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
                      c.label,
                      style: sans(
                        kMobile ? 14 : 13,
                        weight: W.label,
                        color: selected ? AppColors.fg1 : AppColors.fg2,
                      ),
                    ),
                    if (selected) const Tag('Chosen', tone: Tone.accent),
                    if (!readOnly && c.recommended)
                      Text(
                        'recommended',
                        style: sans(
                          TranscriptCard.metaSize,
                          color: AppColors.fg3,
                        ),
                      ),
                  ],
                ),
                if (c.description.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    c.description,
                    style: sans(
                      kMobile ? 13 : 12,
                      height: 1.4,
                      color: AppColors.fg3,
                    ),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
    if (readOnly || onTap == null) return body;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: onTap,
      child: body,
    );
  }

  Widget _pill(
    String label, {
    required bool selected,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return Material(
      color: selected ? AppColors.accentBg : AppColors.hover,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(kMobile ? R.pill : R.sm),
        side: BorderSide(
          color: selected ? AppColors.accent : Colors.transparent,
          width: 1.2,
        ),
      ),
      child: InkWell(
        onTap: enabled ? onTap : null,
        borderRadius: BorderRadius.circular(kMobile ? R.pill : R.sm),
        child: Padding(
          padding: EdgeInsets.symmetric(
            horizontal: S.s16,
            vertical: kMobile ? 11 : 7,
          ),
          child: Text(
            label,
            style: TS.label(selected ? AppColors.accent : AppColors.fg2),
          ),
        ),
      ),
    );
  }
}
