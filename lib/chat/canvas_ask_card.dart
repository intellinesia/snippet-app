import 'package:flutter/material.dart';

import '../api.dart';
import '../canvas/canvas_nav.dart';
import '../theme.dart';
import 'ask_kit.dart';
import 'decided_card.dart';

/// Desktop renderer for a revision-pinned canvas question.
///
/// Payload shape follows the v16 canvas.ask contract:
/// `{id, canvas_id, kind, prompt, options:[{id,label,ref,thumb}], status,
/// answer:{decision|option_ids|text,note}, rev}`. Unknown or incomplete
/// payloads intentionally render nothing rather than a contradictory shell.
class CanvasAskCard extends StatefulWidget {
  const CanvasAskCard(
    this.ask, {
    super.key,
    this.session,
    this.onAnswer,
    this.onOpenCanvas,
    this.client,
  });

  final Map<String, dynamic> ask;
  final DaemonClient? client;
  final String? session;

  /// Called with the answer value and should return whether it was accepted.
  final Future<bool> Function(String value, {String? decision})? onAnswer;
  final VoidCallback? onOpenCanvas;

  static Map<String, dynamic>? payloadOf(Map<String, dynamic> payload) {
    final nested = payload['canvas_ask'];
    if (nested is Map) return Map<String, dynamic>.from(nested);
    final kind = '${payload['kind'] ?? payload['type'] ?? ''}';
    final looksLikeAsk = payload['prompt'] is String ||
        payload['question'] is String ||
        payload['options'] is List;
    if ((payload['canvas_id'] != null || payload['canvasId'] != null) &&
        looksLikeAsk &&
        !kind.startsWith('approval_')) {
      return payload;
    }
    return null;
  }

  @override
  State<CanvasAskCard> createState() => _CanvasAskCardState();
}

class _CanvasAskCardState extends State<CanvasAskCard> {
  final _text = TextEditingController();
  final Set<String> _selected = {};
  bool _busy = false;
  String? _localOutcome;
  String? _localAnswer;

  String get _kind => '${widget.ask['kind'] ?? 'choose_one'}';
  String get _prompt =>
      '${widget.ask['prompt'] ?? widget.ask['question'] ?? 'Canvas question'}';
  String get _status => (_localOutcome ?? '${widget.ask['status'] ?? ''}')
      .replaceAll('-', '_')
      .toLowerCase();
  int? get _rev =>
      (widget.ask['rev'] as num?)?.toInt() ??
      (widget.ask['revision'] as num?)?.toInt() ??
      ((widget.ask['answer'] is Map)
          ? ((widget.ask['answer'] as Map)['rev'] as num?)?.toInt()
          : null);

  List<Map<String, dynamic>> get _options => [
        for (final raw in (widget.ask['options'] as List? ?? const []))
          if (raw is Map) Map<String, dynamic>.from(raw),
      ];

  bool get _open => _status.isEmpty || _status == 'open' || _status == 'draft';

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  Future<void> _answer(String value, {String? decision}) async {
    final sender = widget.onAnswer;
    if (sender == null || _busy) return;
    setState(() => _busy = true);
    final ok = await sender(value, decision: decision);
    if (!mounted) return;
    setState(() {
      _busy = false;
      if (ok) {
        _localOutcome = decision == 'reject'
            ? 'rejected'
            : decision == 'approve'
                ? 'answered'
                : 'answered';
        _localAnswer = value;
      }
    });
  }

  void _openCanvas() {
    if (widget.onOpenCanvas != null) {
      widget.onOpenCanvas!();
      return;
    }
    openCanvas(
      context,
      canvasId: '${widget.ask['canvas_id'] ?? widget.ask['canvasId'] ?? ''}',
      frameId: widget.ask['frame_id']?.toString(),
      elId: widget.ask['el_id']?.toString(),
      rev: _rev,
    );
  }

  Widget _thumb(Map<String, dynamic> option) {
    final thumb = '${option['thumb'] ?? ''}';
    Widget child;
    if (thumb.startsWith('http://') || thumb.startsWith('https://')) {
      child = Image.network(
        thumb,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    } else if (thumb.isNotEmpty && widget.client != null) {
      child = Image(
        image: widget.client!.canvasImage(thumb, rev: _rev),
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => const SizedBox.shrink(),
      );
    } else {
      child = Center(
        child: Icon(Icons.crop_square_rounded, size: 18, color: AppColors.fg3),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(5),
      child: Container(
        width: 80,
        height: 64,
        color: AppColors.surface3,
        child: child,
      ),
    );
  }

  Widget _choiceGrid() {
    final options = _options;
    if (options.isEmpty) return const SizedBox.shrink();
    final cards = <AskOptionCard>[];
    for (final option in options) {
      final id = '${option['id'] ?? option['label'] ?? ''}';
      final label = '${option['label'] ?? id}';
      final selected = _selected.contains(id);
      cards.add(AskOptionCard(
        key: ValueKey('canvas-option-$id'),
        title: label,
        subtitle: option['sub']?.toString() ?? option['subtitle']?.toString(),
        selected: selected,
        thumbnail: _thumb(option),
        onTap: _busy
            ? null
            : () => setState(() {
                  if (_kind == 'choose_many') {
                    if (selected) {
                      _selected.remove(id);
                    } else {
                      _selected.add(id);
                    }
                  } else {
                    _selected
                      ..clear()
                      ..add(id);
                  }
                }),
      ));
    }
    return AskOptionGrid(options: cards);
  }

  Widget _multiChoiceRows() {
    final options = _options;
    if (options.isEmpty) return const SizedBox.shrink();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final option in options) ...[
          Builder(builder: (context) {
            final id = '${option['id'] ?? option['label'] ?? ''}';
            final label = '${option['label'] ?? id}';
            final selected = _selected.contains(id);
            return AskCheckboxRow(
              key: ValueKey('canvas-multi-$id'),
              label: label,
              selected: selected,
              onTap: _busy
                  ? null
                  : () => setState(() {
                        if (selected) {
                          _selected.remove(id);
                        } else {
                          _selected.add(id);
                        }
                      }),
            );
          }),
        ],
        const SizedBox(height: 4),
        Text('${_selected.length} of ${options.length} selected',
            style: sans(11.5, height: 15 / 11.5, color: AppColors.fg2)),
      ],
    );
  }

  Widget _payload() {
    switch (_kind) {
      case 'approve_reject':
      case 'approval':
        final note = '${widget.ask['note'] ?? ''}';
        return note.isEmpty
            ? const SizedBox.shrink()
            : Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Text(note,
                    style: sans(12, height: 16 / 12, color: AppColors.fg2)),
              );
      case 'free_text':
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: AskTextInput(
            key: const ValueKey('canvas-ask-text'),
            controller: _text,
            hint: 'Type an answer',
            onSubmitted: (value) => _answer(value.trim()),
          ),
        );
      case 'choose_many':
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _multiChoiceRows(),
        );
      case 'choose_one':
      default:
        return Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: _choiceGrid(),
        );
    }
  }

  List<Widget> _actions() {
    final open = AskButton(
      'Open on canvas',
      key: const ValueKey('canvas-open-button'),
      variant: AskButtonVariant.ghost,
      icon: 'external-link',
      onTap: _busy ? null : _openCanvas,
    );
    final wideGap = const AskActionWideGap();
    switch (_kind) {
      case 'approve_reject':
      case 'approval':
        return [
          AskButton(
            'Reject',
            onTap: widget.onAnswer == null
                ? null
                : () => _answer('reject', decision: 'reject'),
          ),
          AskButton(
            'Approve',
            variant: AskButtonVariant.primary,
            onTap: widget.onAnswer == null
                ? null
                : () => _answer('approve', decision: 'approve'),
          ),
          wideGap,
          open,
        ];
      case 'free_text':
        return [
          AskButton(
            'Send',
            variant: AskButtonVariant.primary,
            busy: _busy,
            onTap: widget.onAnswer == null
                ? null
                : () => _answer(_text.text.trim()),
          ),
          wideGap,
          open,
        ];
      case 'choose_many':
      case 'choose_one':
      default:
        return [
          AskButton(
            'Answer',
            key: const ValueKey('canvas-answer-button'),
            variant: AskButtonVariant.primary,
            busy: _busy,
            onTap: widget.onAnswer == null || _selected.isEmpty
                ? null
                : () => _answer(_selected.join(', ')),
          ),
          wideGap,
          open,
        ];
    }
  }

  String _answerSummary() {
    if (_localAnswer != null && _localAnswer!.isNotEmpty) return _localAnswer!;
    final answer = widget.ask['answer'];
    if (answer is Map) {
      final text = '${answer['text'] ?? answer['decision'] ?? ''}';
      if (text.isNotEmpty) return text;
      final ids = answer['option_ids'];
      if (ids is List && ids.isNotEmpty) {
        final labels = [
          for (final option in _options)
            if (ids.contains(option['id']))
              '${option['label'] ?? option['id']}',
        ];
        if (labels.isNotEmpty) return labels.join(', ');
        return ids.join(', ');
      }
    }
    return _status == 'rejected' ? 'rejected' : 'answered';
  }

  @override
  Widget build(BuildContext context) {
    if (!_open) {
      final title = switch (_status) {
        'rejected' || 'denied' => 'Rejected',
        'expired' => 'Expired',
        'cancelled' => 'Cancelled',
        'superseded' => 'Superseded',
        _ => 'Answered',
      };
      final pinned = _rev == null ? '' : 'pinned at r$_rev';
      final summary = switch (_status) {
        'rejected' ||
        'denied' =>
          pinned.isEmpty ? 'Rejected' : 'Rejected · $pinned',
        'expired' => pinned.isEmpty ? 'Expired' : 'Expired · $pinned',
        'cancelled' => pinned.isEmpty ? 'Cancelled' : 'Cancelled · $pinned',
        'superseded' => () {
            final by =
                widget.ask['superseded_by'] ?? widget.ask['superseded_by_ask'];
            final nextRev = (widget.ask['superseded_rev'] as num?)?.toInt();
            if (by != null && '$by'.isNotEmpty) {
              return 'Superseded by Ask $by${nextRev == null ? '' : ' at r$nextRev'}';
            }
            return pinned.isEmpty ? 'Superseded' : 'Superseded · $pinned';
          }(),
        _ =>
          pinned.isEmpty ? _answerSummary() : '${_answerSummary()} · $pinned',
      };
      return DecidedCard(
        key: ValueKey('canvas-ask-decided-${widget.ask['id'] ?? 'unknown'}'),
        kind: switch (_status) {
          'rejected' || 'denied' => DecidedKind.denied,
          'expired' => DecidedKind.expired,
          'cancelled' => DecidedKind.skipped,
          'superseded' => DecidedKind.superseded,
          _ => DecidedKind.answered,
        },
        title: title,
        subtitle: summary,
      );
    }

    final actor = '${widget.ask['asked_by'] ?? widget.ask['askedBy'] ?? ''}';
    final meta = [
      if (actor.isNotEmpty) actor,
      if (_rev != null) 'r$_rev',
    ].join(' · ');
    return DesktopAskCard(
      key: ValueKey('canvas-ask-${widget.ask['id'] ?? 'unknown'}'),
      needsYou: true,
      meta: meta,
      title: _prompt,
      payload: _payload(),
      actions: _actions(),
    );
  }
}

/// Small pinned badge used at the top of a canvas while questions are open.
class CanvasAskPinBadge extends StatelessWidget {
  const CanvasAskPinBadge({
    super.key,
    required this.count,
    this.onTap,
  });

  final int count;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    if (count <= 0) return const SizedBox.shrink();
    return Material(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(11),
      child: InkWell(
        key: const ValueKey('canvas-ask-pin-badge'),
        borderRadius: BorderRadius.circular(11),
        onTap: onTap,
        child: SizedBox(
          height: 22,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 9),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Container(
                width: 6,
                height: 6,
                decoration:
                    BoxDecoration(color: AppColors.run, shape: BoxShape.circle),
              ),
              const SizedBox(width: 6),
              Text(
                'Question',
                style: sans(11,
                    height: 14 / 11,
                    weight: FontWeight.w500,
                    color: AppColors.fg2),
              ),
              const SizedBox(width: 4),
              Text(
                '$count',
                style: sans(11,
                    height: 14 / 11,
                    weight: FontWeight.w500,
                    color: AppColors.fg2),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}
