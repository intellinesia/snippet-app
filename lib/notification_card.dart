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
  bool _replyExpanded = false;
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

  Widget _phoneChip({
    required String label,
    required String icon,
    required VoidCallback? onTap,
    bool primary = false,
    double? width,
  }) {
    final fill = primary ? AppColors.fg1 : AppColors.surface3;
    final fg = primary ? AppColors.bg : AppColors.fg1;
    return Semantics(
      button: true,
      enabled: onTap != null,
      label: label,
      child: Material(
        color: fill,
        borderRadius: BorderRadius.circular(6),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(6),
          child: SizedBox(
            width: width,
            height: 36,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                AppIcon(icon, size: 14, color: fg),
                const SizedBox(width: 4),
                Flexible(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(13,
                          weight: FontWeight.w500, height: 1, color: fg)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

  Widget _phoneReplyField(String hint) {
    final canSend = _state != _Send.sending && _text.text.trim().isNotEmpty;
    return SizedBox(
      height: 36,
      child: Row(children: [
        Expanded(
          child: Container(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            decoration: BoxDecoration(
              color: AppColors.surface1,
              borderRadius: BorderRadius.circular(18),
            ),
            alignment: Alignment.centerLeft,
            child: TextField(
              controller: _text,
              focusNode: _focus,
              enabled: _state != _Send.sending,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _submitText(cardActionFor(widget.payload)),
              style: sans(14, color: AppColors.fg1),
              decoration: InputDecoration(
                isCollapsed: true,
                border: InputBorder.none,
                hintText: hint,
                hintStyle: sans(14, color: AppColors.fg3),
              ),
            ),
          ),
        ),
        if (_text.text.trim().isNotEmpty) ...[
          const SizedBox(width: 6),
          SizedBox(
            width: 36,
            height: 36,
            child: IconButton(
              padding: EdgeInsets.zero,
              tooltip: 'Send',
              onPressed: canSend
                  ? () => _submitText(cardActionFor(widget.payload))
                  : null,
              icon: Container(
                width: 28,
                height: 28,
                decoration: BoxDecoration(
                  color: canSend ? AppColors.fg1 : AppColors.surface3,
                  shape: BoxShape.circle,
                ),
                child: Center(
                  child: AppIcon('arrow-up',
                      size: 13, color: canSend ? AppColors.bg : AppColors.fg4),
                ),
              ),
            ),
          ),
        ],
      ]),
    );
  }

  /// RC-18 phone cards are fixed-height notification messages, not the desktop
  /// expanded quick-action form. Reply composition is revealed only after the
  /// 36-high Reply chip is tapped, so the idle measurement stays exact.
  Widget _buildPhone(BuildContext context) {
    final p = widget.payload;
    final title = '${p['title'] ?? ''}'.trim();
    final name = title.isEmpty ? 'Snippet' : title;
    final attention = p['attention'];
    var body = notificationBody(p);
    if (body.isEmpty && attention is Map) {
      body = '${attention['label'] ?? attention['text'] ?? ''}'.trim();
    }
    final action = cardActionFor(p);
    final needs = notificationKind(p) == 'waiting';
    final busy = _state == _Send.sending;
    final failed = _state == _Send.failed;
    final choices = action == CardAction.answer
        ? answerChoices(attention)
        : const <(String, String)>[];
    final height = switch (action) {
      CardAction.none => 73.0,
      CardAction.approval || CardAction.answer => 153.0,
      CardAction.reply || CardAction.view => 152.0,
    };
    final textScale = MediaQuery.textScalerOf(context).scale(14) / 14;
    final fixedHeight = textScale <= 1.01;
    final twoLineBody = action == CardAction.reply || action == CardAction.view;

    Widget statusOrActions() {
      if (busy) {
        return Row(children: [
          Spinner(size: 14, color: AppColors.fg2),
          const SizedBox(width: 8),
          Text(_sending, style: sans(13, color: AppColors.fg2)),
        ]);
      }
      if (failed) {
        return Row(children: [
          AppIcon('x', size: 14, color: AppColors.fg1),
          const SizedBox(width: 8),
          Expanded(
            child: Text('Could not send',
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(13, color: AppColors.fg1)),
          ),
          SizedBox(
            width: 73,
            child: _phoneChip(
              label: 'Retry',
              icon: 'refresh',
              onTap: () => setState(() => _state = _Send.idle),
            ),
          ),
        ]);
      }
      return switch (action) {
        CardAction.none => const SizedBox.shrink(),
        CardAction.view => Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 70,
              child:
                  _phoneChip(label: 'View', icon: 'eye', onTap: widget.onOpen),
            ),
          ),
        CardAction.reply => Align(
            alignment: Alignment.centerLeft,
            child: SizedBox(
              width: 70,
              child: _phoneChip(
                label: 'Reply',
                icon: 'reply',
                onTap: () {
                  setState(() => _replyExpanded = true);
                  _focus.requestFocus();
                },
              ),
            ),
          ),
        CardAction.approval => Row(children: [
            _phoneChip(
              label: busy ? 'Approving...' : 'Approve',
              icon: 'check',
              primary: true,
              onTap: busy
                  ? null
                  : () => _send(const QuickApprove(via: 'notification'),
                      'Approving...', 'Approved'),
            ),
            const SizedBox(width: 8),
            _phoneChip(
              label: 'Deny',
              icon: 'x',
              onTap: busy
                  ? null
                  : () => _send(const QuickDeny(via: 'notification'),
                      'Denying...', 'Denied'),
            ),
          ]),
        CardAction.answer => Row(children: [
            for (final (i, choice) in choices.indexed) ...[
              if (i > 0) const SizedBox(width: 8),
              _phoneChip(
                label: choice.$1,
                icon: 'check',
                onTap: busy
                    ? null
                    : () => _send(
                        QuickAnswer(answerText(attention, choiceAnswer(choice)),
                            via: 'notification'),
                        'Sending answer...',
                        'Sent'),
              ),
            ],
          ]),
      };
    }

    return Semantics(
      container: true,
      label: '$name, ${needs ? 'needs you' : 'message'}, $body',
      child: Container(
        width: double.infinity,
        height: fixedHeight && !(_replyExpanded && action == CardAction.reply)
            ? height
            : null,
        constraints:
            !fixedHeight || (_replyExpanded && action == CardAction.reply)
                ? BoxConstraints(minHeight: height)
                : null,
        clipBehavior: Clip.antiAlias,
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(8),
        ),
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          SizedBox(
            height: 20,
            child: Row(children: [
              Container(
                width: 20,
                height: 20,
                clipBehavior: Clip.antiAlias,
                decoration: BoxDecoration(
                  color: AppColors.surface3,
                  borderRadius: BorderRadius.circular(10),
                ),
                child: AgentMochi('${p['agent_id'] ?? 'snippet'}', size: 20),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(13,
                        weight: FontWeight.w500, color: AppColors.fg1)),
              ),
              Text(notificationAgo(p['created_at']),
                  style: sans(12, color: AppColors.fg2)),
            ]),
          ),
          if (needs) ...[
            const SizedBox(height: 6),
            SizedBox(
              height: 18,
              child: Row(children: [
                Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                      color: AppColors.run, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Text('Needs you',
                    style: sans(13,
                        weight: FontWeight.w500, color: AppColors.fg2)),
              ]),
            ),
            const SizedBox(height: 4),
          ] else
            const SizedBox(height: 6),
          Text(body,
              maxLines: twoLineBody ? 2 : 1,
              overflow: TextOverflow.ellipsis,
              style: sans(15, height: 21 / 15, color: AppColors.fg1)),
          if (action != CardAction.none || busy || failed) ...[
            SizedBox(height: twoLineBody ? 10 : 8),
            SizedBox(height: 36, child: statusOrActions()),
          ],
          if (_replyExpanded && action == CardAction.reply && !busy) ...[
            const SizedBox(height: 8),
            _phoneReplyField('Reply to $name...'),
          ],
        ]),
      ),
    );
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
    if (!compact) return _buildPhone(context);
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
    final controlH = compact ? 28.0 : 36.0;
    final labelSize = compact ? 12.0 : 12.5;
    final needsMark = compact
        ? const NeedsYouMark(fontSize: 12)
        : Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 6,
              height: 6,
              decoration:
                  BoxDecoration(color: AppColors.run, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text('Needs you',
                style: sans(13, weight: FontWeight.w500, color: AppColors.fg2)),
          ]);

    final header = Row(children: [
      Container(
        width: compact ? 36 : 20,
        height: compact ? 36 : 20,
        decoration: BoxDecoration(
            color: AppColors.surface2,
            borderRadius: BorderRadius.circular(compact ? 18 : 10)),
        clipBehavior: Clip.antiAlias,
        child: AgentMochi('${p['agent_id'] ?? 'snippet'}',
            size: compact ? 36 : 20),
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
                style: sans(compact ? 14 : 13,
                    weight: W.label, color: AppColors.fg1)),
            if (needs) needsMark,
          ],
        ),
      ),
      const SizedBox(width: 8),
      Text(notificationAgo(p['created_at']),
          style: sans(compact ? 11 : 12, color: AppColors.fg2)),
    ]);

    final more = LayoutBuilder(builder: (context, constraints) {
      final style = compact
          ? sans(13, height: 19 / 13, color: AppColors.fg1)
          : sans(15, height: 21 / 15, color: AppColors.fg1);
      final width = constraints.hasBoundedWidth
          ? constraints.maxWidth
          : MediaQuery.sizeOf(context).width - 32 - 24;
      final painter = TextPainter(
        text: TextSpan(text: body, style: style),
        textDirection: TextDirection.ltr,
        textScaler: MediaQuery.textScalerOf(context),
        maxLines: maxLines,
      )..layout(maxWidth: width);
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
            borderRadius: BorderRadius.circular(compact ? 6 : 8),
            side: primary || compact || disabled
                ? BorderSide.none
                : BorderSide(color: AppColors.border),
          ),
          child: InkWell(
            onTap: onTap,
            customBorder: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(compact ? 6 : 8)),
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
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(compact ? 14 : 8),
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
