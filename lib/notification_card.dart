import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'mochi.dart';
import 'notification_banner.dart';
import 'notification_text.dart';
import 'platform.dart';
import 'session_quick_send.dart';
import 'theme.dart';
import 'widgets.dart';

enum _Send { idle, sending, failed }

enum CardAction { none, approval, answer, reply, view }

CardAction cardActionFor(Map<String, dynamic> p) {
  final kind = '${p['kind'] ?? ''}'.split('.').last;
  final attention = p['attention'];
  final attentionType = attention is Map ? '${attention['type']}' : '';
  final dest = p['destination'];
  final destType = dest is Map ? '${dest['type']}' : '';
  final hasSession = '${p['session'] ?? ''}'.isNotEmpty ||
      (dest is Map && '${dest['id'] ?? ''}'.isNotEmpty && destType != 'task');
  if (kind == 'waiting') {
    if (!hasSession) return CardAction.none;
    if (attentionType == 'approval') return CardAction.approval;
    // A question is only answerable when the daemon supplied its payload. A
    // bare waiting event has no ask shape, so it can only open the session.
    if (attention is Map &&
        (attentionType == 'question' ||
            '${attention['text'] ?? ''}'.trim().isNotEmpty ||
            attention['choices'] is List)) {
      return CardAction.answer;
    }
    return CardAction.none;
  }
  if ((kind == 'term' || kind == 'message' || destType == 'conversation') &&
      hasSession) {
    return CardAction.reply;
  }
  if (const {'done', 'completed', 'error', 'failed'}.contains(kind)) {
    return CardAction.view;
  }
  return CardAction.none;
}

/// NT-02: a needs-you or message banner expanded in place. Desktop uses the
/// locked compact card: surface2 radius 14, a 36 reply field, and 28-high flat
/// buttons. Mobile keeps the roomier touch geometry.
class NotificationMessageCard extends StatefulWidget {
  const NotificationMessageCard({
    super.key,
    required this.payload,
    required this.onOpen,
    required this.onDismiss,
    required this.onHold,
    required this.onSent,
    this.send = quickSendForPayload,
    this.initiallyExpanded = true,
    this.embedded = false,
    this.lifted = false,
  });

  final Map<String, dynamic> payload;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;
  final ValueChanged<bool> onHold;
  final VoidCallback onSent;
  final Future<bool> Function(Map<String, dynamic>, QuickAction) send;
  final bool initiallyExpanded;
  final bool embedded;
  final bool lifted;

  @override
  State<NotificationMessageCard> createState() =>
      _NotificationMessageCardState();
}

class _NotificationMessageCardState extends State<NotificationMessageCard> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  var _state = _Send.idle;
  String _sending = 'Sending...';

  @override
  void initState() {
    super.initState();
    _focus.addListener(() => widget.onHold(_focus.hasFocus));
    _text.addListener(() => setState(() {}));
    widget.onHold(true);
    if (cardActionFor(widget.payload) != CardAction.approval) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _focus.requestFocus();
      });
    }
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send(QuickAction action, String busyLabel, String done) async {
    if (_state == _Send.sending) return;
    setState(() {
      _state = _Send.sending;
      _sending = busyLabel;
    });
    widget.onHold(true);
    final ok = await widget.send(widget.payload, action);
    if (!mounted) return;
    if (ok) {
      HapticFeedback.lightImpact();
      toast(context, done);
      widget.onSent();
    } else {
      setState(() => _state = _Send.failed);
    }
  }

  void _submitText(CardAction action) {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    _send(
        action == CardAction.answer
            ? QuickAnswer(answerText(widget.payload['attention'], t),
                via: 'notification')
            : QuickReply(t, via: 'notification'),
        'Sending...',
        'Sent');
  }

  @override
  Widget build(BuildContext context) {
    Theme.of(context);
    final compact = !kMobile;
    final p = widget.payload;
    final title = '${p['title'] ?? ''}'.trim();
    final name = title.isEmpty ? 'Snippet' : title;
    final attention = p['attention'];
    final label = attention is Map ? '${attention['label'] ?? ''}'.trim() : '';
    var body = notificationBody(p);
    if (body.isEmpty) body = label;
    final action = cardActionFor(p);
    final needs = notificationKind(p) == 'waiting';
    final busy = _state == _Send.sending;
    final choices = action == CardAction.answer
        ? answerChoices(attention)
        : const <(String, String)>[];
    final scale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final stacked = scale >= 1.75;
    final mq = MediaQuery.of(context);
    final tight = mq.size.height <= 640 || mq.viewInsets.bottom > 0;
    final maxLines = tight ? 2 : 4;
    final controlH = compact ? 28.0 : 48.0;
    final labelSize = compact ? 12.0 : 14.0;
    final amber = AppColors.run;

    final needsMark = compact
        ? const NeedsYouMark(fontSize: 12)
        : Row(mainAxisSize: MainAxisSize.min, children: [
            AppIcon('hand', size: 14, color: amber),
            const SizedBox(width: 4),
            Text('Needs you', style: sans(12, weight: W.label, color: amber)),
          ]);

    final header = Row(children: [
      Container(
        width: 36,
        height: 36,
        decoration: BoxDecoration(
            color: AppColors.surface2, borderRadius: BorderRadius.circular(18)),
        clipBehavior: Clip.antiAlias,
        child: AgentMochi('${p['agent_id'] ?? 'snippet'}', size: 36),
      ),
      const SizedBox(width: 10),
      Expanded(
        child: Wrap(
          crossAxisAlignment: WrapCrossAlignment.center,
          spacing: 8,
          children: [
            Text(name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(14, weight: W.label, color: AppColors.fg1)),
            if (needs) needsMark,
          ],
        ),
      ),
      const SizedBox(width: 8),
      Text(notificationAgo(p['created_at']),
          style: sans(11, color: AppColors.fg2)),
    ]);

    final more = Builder(builder: (context) {
      final style = compact
          ? sans(13, height: 19 / 13, color: AppColors.fg1)
          : sans(13.5, height: 19 / 13.5, color: AppColors.fg1);
      final painter = TextPainter(
        text: TextSpan(text: body, style: style),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: maxLines,
      )..layout(maxWidth: (MediaQuery.sizeOf(context).width - 32 - 24));
      final over = painter.didExceedMaxLines;
      painter.dispose();
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(body,
              maxLines: maxLines,
              overflow: TextOverflow.ellipsis,
              style: style),
          if (over)
            InkWell(
              onTap: widget.onOpen,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                    minHeight: compact ? 28 : 48, minWidth: compact ? 24 : 48),
                child: Align(
                  alignment: Alignment.centerLeft,
                  widthFactor: 1,
                  child: Text('More',
                      style: sans(compact ? 12 : 13,
                          weight: W.label, color: AppColors.fg2)),
                ),
              ),
            ),
        ],
      );
    });

    Widget button(String text, VoidCallback? onTap, {required bool primary}) {
      final disabled = onTap == null;
      final fill = disabled
          ? AppColors.surface3
          : primary
              ? AppColors.fg1
              : compact
                  ? AppColors.surface3
                  : AppColors.surface2;
      final fg = disabled
          ? AppColors.fg2
          : primary
              ? AppColors.bg
              : AppColors.fg1;
      return Semantics(
        button: true,
        enabled: !disabled,
        label: text,
        excludeSemantics: true,
        onTap: onTap,
        child: Material(
          color: fill,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(6),
            side: primary || compact || disabled
                ? BorderSide.none
                : BorderSide(color: AppColors.border),
          ),
          child: InkWell(
            onTap: onTap,
            customBorder:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(6)),
            child: Container(
              constraints: BoxConstraints(
                  minHeight: controlH, minWidth: compact ? 0 : 48),
              padding: EdgeInsets.symmetric(horizontal: compact ? 12 : 8),
              alignment: Alignment.center,
              child: Text(text,
                  textAlign: TextAlign.center,
                  style: sans(labelSize, weight: W.label, color: fg)),
            ),
          ),
        ),
      );
    }

    final hint = 'Reply to $name...';
    final canSend = !busy && _text.text.trim().isNotEmpty;
    final hasText = _text.text.trim().isNotEmpty;
    final fieldH = compact ? 36.0 : 48.0;
    final innerH = compact ? 36.0 : 44.0;
    final sendTarget = compact ? 28.0 : 48.0;
    final sendInset = compact ? 4.0 : 0.0;
    final field = SizedBox(
      height: fieldH,
      child: Stack(children: [
        Positioned(
          left: 0,
          right: 0,
          top: compact ? 0 : 2,
          height: innerH,
          child: Container(
            key: const ValueKey('reply-field'),
            padding: EdgeInsets.only(
                left: compact ? 12 : 16,
                right: hasText ? (compact ? 40 : 48) : (compact ? 12 : 16)),
            decoration: BoxDecoration(
                color: AppColors.surface1,
                borderRadius: BorderRadius.circular(compact ? 8 : 22)),
            alignment: Alignment.centerLeft,
            child: TextField(
              controller: _text,
              focusNode: _focus,
              enabled: !busy,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submitText(action),
              style: sans(compact ? 13 : 14, color: AppColors.fg1),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: action == CardAction.answer ? 'Answer...' : hint,
                hintStyle: sans(compact ? 13 : 14, color: AppColors.fg3),
              ),
            ),
          ),
        ),
        if (hasText)
          Positioned(
            right: sendInset,
            top: sendInset,
            width: sendTarget,
            height: sendTarget,
            child: IconButton(
              tooltip: 'Send',
              padding: EdgeInsets.zero,
              constraints: BoxConstraints.tightFor(
                  width: sendTarget, height: sendTarget),
              onPressed: canSend ? () => _submitText(action) : null,
              icon: Container(
                width: compact ? 28 : 36,
                height: compact ? 28 : 36,
                decoration: BoxDecoration(
                    color: canSend ? AppColors.fg1 : AppColors.surface3,
                    borderRadius: compact ? BorderRadius.circular(6) : null,
                    shape: compact ? BoxShape.rectangle : BoxShape.circle),
                child: Center(
                    child: AppIcon('arrow-up',
                        size: compact ? 13 : 16,
                        color: canSend ? AppColors.bg : AppColors.fg4)),
              ),
            ),
          ),
      ]),
    );

    final canAct = action != CardAction.none;
    final canReply = action == CardAction.approval ||
        action == CardAction.answer ||
        action == CardAction.reply;
    final primary = action == CardAction.approval
        ? button(
            busy ? 'Approving...' : 'Approve',
            busy
                ? null
                : () => _send(const QuickApprove(via: 'notification'),
                    'Approving...', 'Approved'),
            primary: true)
        : canReply
            ? button('Reply', busy ? null : _focus.requestFocus, primary: true)
            : null;
    final open = button('Open', widget.onOpen, primary: false);

    final Widget actions;
    if (choices.isNotEmpty) {
      if (compact) {
        actions = Wrap(spacing: 8, runSpacing: 8, children: [
          for (final (i, c) in choices.indexed)
            button(
                c.$1,
                busy
                    ? null
                    : () => _send(
                        QuickAnswer(answerText(attention, choiceAnswer(c)),
                            via: 'notification'),
                        'Sending...',
                        'Sent'),
                primary: i == 0),
          open,
        ]);
      } else {
        actions = Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            for (final (i, c) in choices.indexed) ...[
              if (i > 0) const SizedBox(height: 8),
              button(
                  c.$1,
                  busy
                      ? null
                      : () => _send(
                          QuickAnswer(answerText(attention, choiceAnswer(c)),
                              via: 'notification'),
                          'Sending...',
                          'Sent'),
                  primary: i == 0),
            ],
            const SizedBox(height: 8),
            open,
          ],
        );
      }
    } else if (!canAct || primary == null) {
      actions = open;
    } else if (!compact && stacked) {
      actions = Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [primary, const SizedBox(height: 8), open],
      );
    } else if (compact) {
      actions = Row(mainAxisSize: MainAxisSize.min, children: [
        open,
        const SizedBox(width: 8),
        primary,
      ]);
    } else {
      actions = Row(children: [
        Expanded(child: open),
        const SizedBox(width: 8),
        Expanded(child: primary),
      ]);
    }

    return Semantics(
      container: true,
      label: '$name, ${needs ? 'needs you' : 'message'}, $body',
      child: Material(
        color: needs && !compact ? AppColors.attentionTint : AppColors.surface2,
        borderRadius: BorderRadius.circular(14),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              if (body.isNotEmpty)
                Padding(padding: const EdgeInsets.only(top: 8), child: more),
              if (canReply && choices.isEmpty)
                Padding(
                    padding: EdgeInsets.only(top: compact ? 8 : 6),
                    child: field),
              Padding(
                  padding: EdgeInsets.only(top: compact ? 10 : 12),
                  child: actions),
              if (_state == _Send.failed)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text('Could not send. Try again.',
                      style: sans(12, color: AppColors.fg2)),
                ),
              if (busy)
                Semantics(
                    liveRegion: true,
                    label: _sending,
                    child: const SizedBox.shrink()),
            ],
          ),
        ),
      ),
    );
  }
}

/// Terminal-state colour is deliberately neutral in chat chrome; the words and
/// icons carry failed/done state.
Color notificationTone(Map<String, dynamic> p) =>
    switch ('${p['kind'] ?? ''}'.split('.').last) {
      'waiting' => AppColors.fg2,
      'done' || 'completed' => AppColors.fg2,
      'error' || 'failed' => AppColors.fg2,
      'idle' => AppColors.fg3,
      _ => AppColors.fg4,
    };
