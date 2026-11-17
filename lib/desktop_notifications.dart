import 'dart:async';

import 'package:flutter/material.dart';

import 'markdown_preview.dart';
import 'mochi.dart';
import 'notification_card.dart' show CardAction, cardActionFor;
import 'notification_stack.dart' show needsYou;
import 'notification_text.dart';
import 'notifications.dart' show onNotifTap;
import 'session_quick_send.dart';
import 'theme.dart';
import 'widgets.dart';

/// Desktop-only history behind the title-bar bell. Toasts come and go; the bell
/// keeps every notification until it is answered, opened or cleared.
class DesktopNotificationFeed {
  DesktopNotificationFeed._();
  static final items = ValueNotifier<List<Map<String, dynamic>>>(const []);

  static void add(Map<String, dynamic> p) {
    final next = [
      for (final o in items.value)
        if (!toastSuperseded(o, p)) o,
      p,
    ];
    items.value = next.length > 40 ? next.sublist(next.length - 40) : next;
  }

  static void remove(Map<String, dynamic> p) => items.value = [
        for (final o in items.value)
          if (!identical(o, p)) o
      ];

  static void clear() => items.value = const [];
}

String _ago(Object? createdAt) {
  final DateTime? t = switch (createdAt) {
    final int s => DateTime.fromMillisecondsSinceEpoch(s * 1000),
    _ => DateTime.tryParse('${createdAt ?? ''}'),
  };
  if (t == null) return '';
  final d = DateTime.now().difference(t);
  if (d.inMinutes < 1) return 'now';
  if (d.inHours < 1) return '${d.inMinutes}m';
  if (d.inDays < 1) return '${d.inHours}h';
  return '${d.inDays}d';
}

String _bodyOf(Map<String, dynamic> p) => plainPreview(
    '${(p['body'] ?? '').toString().trim().isNotEmpty ? p['body'] : p['message'] ?? ''}');

String _agentOf(Map<String, dynamic> p) {
  for (final k in const ['agent', 'agent_id']) {
    final v = '${p[k] ?? ''}';
    if (v.isNotEmpty) return v;
  }
  // The agent working in the session, never a character hashed from its id.
  final s = '${p['session'] ?? ''}';
  if (s.startsWith('inbox-')) return s.substring(6);
  return sessionAgents[s] ?? 'snippet';
}

class _Field extends StatelessWidget {
  const _Field({
    required this.controller,
    required this.hint,
    required this.busy,
    required this.onSubmit,
  });
  final TextEditingController controller;
  final String hint;
  final bool busy;
  final VoidCallback onSubmit;

  @override
  Widget build(BuildContext context) {
    final canSend = !busy && controller.text.trim().isNotEmpty;
    return Container(
      height: 32,
      margin: EdgeInsets.only(left: 26, top: S.s8),
      padding: EdgeInsets.only(left: S.s8, right: S.s4),
      decoration: BoxDecoration(
        color: AppColors.bg,
        borderRadius: BorderRadius.circular(R.md),
        border: Border.all(color: AppColors.lineStrong),
      ),
      child: Row(children: [
        Expanded(
          child: TextField(
            controller: controller,
            enabled: !busy,
            onSubmitted: (_) => onSubmit(),
            style: sans(12.5, color: AppColors.fg1),
            decoration: InputDecoration(
              isCollapsed: true,
              border: InputBorder.none,
              hintText: hint,
              hintStyle: sans(12.5, color: AppColors.fg4),
            ),
          ),
        ),
        GestureDetector(
          onTap: canSend ? onSubmit : null,
          child: Container(
            width: 24,
            height: 24,
            decoration: BoxDecoration(
              color: AppColors.surface3,
              borderRadius: BorderRadius.circular(R.xs),
            ),
            child: busy
                ? Padding(
                    padding: const EdgeInsets.all(6),
                    child: CircularProgressIndicator(strokeWidth: 1.4))
                : Center(
                    child: AppIcon('arrow-up',
                        size: 12,
                        color: canSend ? AppColors.fg1 : AppColors.fg4)),
          ),
        ),
      ]),
    );
  }
}

/// One notification: header, body and the actions its kind allows. Used by the
/// bell popover (framed) and the toast (`toast: true`).
class DesktopNotificationCard extends StatefulWidget {
  const DesktopNotificationCard({
    super.key,
    required this.payload,
    required this.onResolved,
    this.onClose,
    this.onHold,
    this.toast = false,
  });
  final Map<String, dynamic> payload;

  /// Called after an answer, approval, or Open chat: the item is done.
  final VoidCallback onResolved;
  final VoidCallback? onClose;
  final ValueChanged<bool>? onHold;
  final bool toast;

  @override
  State<DesktopNotificationCard> createState() =>
      _DesktopNotificationCardState();
}

class _DesktopNotificationCardState extends State<DesktopNotificationCard> {
  final _text = TextEditingController();
  final _focus = FocusNode();
  bool _busy = false;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _text.addListener(() => setState(() {}));
    _focus.addListener(() => widget.onHold?.call(_focus.hasFocus));
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  Future<void> _send(QuickAction a) async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _failed = false;
    });
    widget.onHold?.call(true);
    final ok = await quickSendForPayload(widget.payload, a);
    if (!mounted) return;
    if (ok) {
      widget.onResolved();
    } else {
      widget.onHold?.call(false);
      setState(() {
        _busy = false;
        _failed = true;
      });
    }
  }

  void _open() {
    widget.onResolved();
    onNotifTap?.call(widget.payload);
  }

  void _submit(CardAction action) {
    final t = _text.text.trim();
    if (t.isEmpty) return;
    _send(action == CardAction.answer
        ? QuickAnswer(answerText(widget.payload['attention'], t),
            via: 'notification')
        : QuickReply(t, via: 'notification'));
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.payload;
    final title = '${p['title'] ?? ''}'.trim();
    final body = _bodyOf(p);
    final action = cardActionFor(p);
    final attention = p['attention'];
    final tool = attention is Map ? '${attention['tool'] ?? ''}' : '';
    final label = attention is Map ? '${attention['label'] ?? ''}'.trim() : '';
    final approval =
        action == CardAction.approval ? approvalOf(attention) : null;
    final kind = '${p['kind'] ?? ''}'.split('.').last;
    final done = const {'done', 'completed'}.contains(kind);
    final failed = const {'error', 'failed'}.contains(kind);
    final choices =
        action == CardAction.answer ? answerChoices(attention) : const [];
    final ago = _ago(p['created_at']);

    final text = approval != null
        ? (label.isNotEmpty ? label : approval.headline(tool))
        : body;
    final tag = done
        ? ('Completed', AppColors.ok)
        : failed
            ? ('Failed', AppColors.danger)
            : null;

    final header = Row(children: [
      AgentMochi(_agentOf(p), size: 18),
      SizedBox(width: S.s8),
      Expanded(
        child: Row(children: [
          Flexible(
            child: Text(title.isEmpty ? 'Snippet' : title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(13, weight: W.title, color: AppColors.fg1)),
          ),
          if (tag != null) ...[
            SizedBox(width: S.s8),
            Container(
              height: 18,
              padding: const EdgeInsets.symmetric(horizontal: 7),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: tag.$2.withValues(alpha: .13),
                borderRadius: BorderRadius.circular(R.xs),
              ),
              child: Text(tag.$1, style: sans(11, color: tag.$2)),
            ),
          ],
        ]),
      ),
      if (ago.isNotEmpty && !widget.toast)
        Text(ago, style: sans(11, color: AppColors.fg4)),
      if (widget.onClose != null)
        GestureDetector(
          onTap: widget.onClose,
          behavior: HitTestBehavior.opaque,
          child: Padding(
            padding: const EdgeInsets.only(left: 6),
            child: AppIcon('x', size: 12, color: AppColors.fg4),
          ),
        ),
    ]);

    final children = <Widget>[
      header,
      if (text.isNotEmpty)
        Padding(
          padding: EdgeInsets.only(left: 26, top: S.s4),
          child: Text(text,
              maxLines: 6,
              overflow: TextOverflow.ellipsis,
              style: sans(12.5, height: 1.5, color: AppColors.fg2)),
        ),
      if (approval != null && approval.shownCommand.isNotEmpty)
        Container(
          margin: EdgeInsets.only(left: 26, top: S.s8),
          padding:
              EdgeInsets.symmetric(horizontal: S.of(10), vertical: S.of(7)),
          decoration: BoxDecoration(
            color: AppColors.bg,
            borderRadius: BorderRadius.circular(R.sm),
          ),
          child: Text(approval.shownCommand,
              maxLines: 5,
              overflow: TextOverflow.ellipsis,
              style: codeMono(12, color: AppColors.fg2)),
        ),
      if (choices.isNotEmpty)
        Padding(
          padding: EdgeInsets.only(left: 26, top: S.s8),
          child: Wrap(spacing: S.s6, runSpacing: S.s6, children: [
            for (final c in choices)
              Btn(c.$1,
                  small: true,
                  variant: BtnVariant.ghost,
                  disabled: _busy,
                  onTap: () => _send(QuickAnswer(
                      answerText(attention, choiceAnswer(c)),
                      via: 'notification'))),
          ]),
        ),
      if (action == CardAction.answer || action == CardAction.reply)
        _Field(
          controller: _text,
          hint: action == CardAction.answer ? 'Answer…' : 'Reply…',
          busy: _busy,
          onSubmit: () => _submit(action),
        ),
      if (action == CardAction.approval ||
          action == CardAction.view ||
          (!widget.toast &&
              (action == CardAction.answer || action == CardAction.reply)))
        Padding(
          padding: EdgeInsets.only(left: 26, top: S.s8),
          child: Row(children: [
            if (_failed)
              Expanded(
                child: Text("Couldn't send. Open the chat",
                    style: sans(11.5, color: AppColors.danger)),
              )
            else
              const Spacer(),
            Btn('Open chat',
                small: true, variant: BtnVariant.ghost, onTap: _open),
            if (action == CardAction.approval) ...[
              SizedBox(width: S.s6),
              Btn('Deny',
                  small: true,
                  variant: BtnVariant.ghost,
                  disabled: _busy,
                  onTap: () => _send(const QuickDeny(via: 'notification'))),
              SizedBox(width: S.s6),
              Btn('Approve',
                  small: true,
                  disabled: _busy,
                  onTap: () => _send(const QuickApprove(via: 'notification'))),
            ],
          ]),
        ),
    ];

    final col = Column(
        crossAxisAlignment: CrossAxisAlignment.start, children: children);
    if (widget.toast) return col;
    return Container(
      margin: const EdgeInsets.only(bottom: 2),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: AppColors.surface2,
        borderRadius: BorderRadius.circular(R.md),
      ),
      child: col,
    );
  }
}

/// Bottom-right toast clear of the composer; the bell keeps the item afterwards.
class DesktopToast extends StatelessWidget {
  const DesktopToast({
    super.key,
    required this.payload,
    required this.onClose,
    required this.onResolved,
    required this.onHold,
    this.extra = 0,
  });
  final Map<String, dynamic> payload;
  final VoidCallback onClose;
  final VoidCallback onResolved;
  final ValueChanged<bool> onHold;

  /// Other toasts waiting behind this one.
  final int extra;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(R.lg),
        side: BorderSide(color: AppColors.lineStrong),
      ),
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: .4),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 12, 12),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          DesktopNotificationCard(
            payload: payload,
            toast: true,
            onClose: onClose,
            onHold: onHold,
            onResolved: onResolved,
          ),
          if (extra > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: Padding(
                padding: const EdgeInsets.only(left: 26, top: 8),
                child: Text('+$extra more in the bell',
                    style: sans(11, color: AppColors.fg4)),
              ),
            ),
        ]),
      ),
    );
  }
}

/// Title-bar bell with the count badge; opens the notifications popover.
class NotificationBell extends StatefulWidget {
  const NotificationBell({super.key});
  @override
  State<NotificationBell> createState() => _NotificationBellState();
}

class _NotificationBellState extends State<NotificationBell> {
  bool _hover = false;
  bool _open = false;
  final _key = GlobalKey();

  Future<void> _toggle() async {
    final box = _key.currentContext?.findRenderObject() as RenderBox?;
    if (box == null) return;
    final origin = box.localToGlobal(Offset.zero);
    final size = MediaQuery.of(context).size;
    // Open from the bell's own edge: left-aligned when it sits in the left
    // half (the sidebar), right-aligned otherwise, always inside the window.
    final w = 420.0.clamp(240.0, size.width - 20);
    final fromLeft = origin.dx + box.size.width / 2 < size.width / 2;
    final left = (fromLeft ? origin.dx : origin.dx + box.size.width - w)
        .clamp(10.0, (size.width - w - 10).clamp(10.0, size.width));
    setState(() => _open = true);
    await showGeneralDialog(
      context: context,
      barrierDismissible: true,
      barrierLabel: 'notifications',
      barrierColor: Colors.transparent,
      transitionDuration: Motion.press,
      pageBuilder: (ctx, _, __) => Stack(children: [
        Positioned(
          left: left,
          top: origin.dy + box.size.height + 4,
          width: w,
          child: _BellPopover(onClose: () => Navigator.of(ctx).pop()),
        ),
      ]),
    );
    if (mounted) setState(() => _open = false);
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<List<Map<String, dynamic>>>(
      valueListenable: DesktopNotificationFeed.items,
      builder: (_, items, __) {
        final n = items.length;
        return Tooltip(
          message: n > 0 ? '$n notifications' : 'Notifications',
          child: MouseRegion(
            cursor: SystemMouseCursors.click,
            onEnter: (_) => setState(() => _hover = true),
            onExit: (_) => setState(() => _hover = false),
            child: GestureDetector(
              key: _key,
              behavior: HitTestBehavior.opaque,
              onTap: _toggle,
              // Inbox, not an alarm: what came back, with its count beside it.
              child: Container(
                height: 28,
                constraints: const BoxConstraints(minWidth: 28),
                padding: EdgeInsets.symmetric(horizontal: n > 0 ? 7 : 0),
                decoration: BoxDecoration(
                  color:
                      _open || _hover ? AppColors.surface2 : Colors.transparent,
                  borderRadius: BorderRadius.circular(R.md),
                ),
                child: Row(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      AppIcon('inbox',
                          size: 15,
                          color:
                              _hover || _open ? AppColors.fg1 : AppColors.fg3),
                      if (n > 0) ...[
                        const SizedBox(width: 5),
                        Container(
                          height: 16,
                          padding: const EdgeInsets.symmetric(horizontal: 5),
                          alignment: Alignment.center,
                          decoration: BoxDecoration(
                            color: AppColors.run.withValues(alpha: 0.13),
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(n > 99 ? '99+' : '$n',
                              style: mono(11,
                                  weight: FontWeight.w500,
                                  color: AppColors.run)),
                        ),
                      ],
                    ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _BellPopover extends StatelessWidget {
  const _BellPopover({required this.onClose});
  final VoidCallback onClose;

  Widget _label(String t, {Color? color, double top = 4}) => Padding(
        padding: EdgeInsets.fromLTRB(10, top, 10, 4),
        child: Text(t,
            style: sans(11, weight: W.title, color: color ?? AppColors.fg4)),
      );

  @override
  Widget build(BuildContext context) {
    return Material(
      color: AppColors.surface1,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(R.lg),
        side: BorderSide(color: AppColors.lineStrong),
      ),
      elevation: 6,
      shadowColor: Colors.black.withValues(alpha: .4),
      clipBehavior: Clip.antiAlias,
      child: ValueListenableBuilder<List<Map<String, dynamic>>>(
        valueListenable: DesktopNotificationFeed.items,
        builder: (context, items, _) {
          final newest = items.reversed.toList();
          final need = newest.where(needsYou).toList();
          final rest = newest.where((p) => !needsYou(p)).toList();
          final maxH = MediaQuery.of(context).size.height - 100;
          Widget card(Map<String, dynamic> p) => DesktopNotificationCard(
                key: ObjectKey(p),
                payload: p,
                onResolved: () => DesktopNotificationFeed.remove(p),
              );
          return ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxH),
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              Container(
                height: 46,
                padding: const EdgeInsets.only(left: 16, right: 10),
                child: Row(children: [
                  Text('Notifications',
                      style: sans(13.5, weight: W.title, color: AppColors.fg1)),
                  if (items.isNotEmpty) ...[
                    SizedBox(width: S.s8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6),
                      height: 18,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: AppColors.surface3,
                        borderRadius: BorderRadius.circular(R.xs),
                      ),
                      child: Text('${items.length}',
                          style: mono(10.5, color: AppColors.fg3)),
                    ),
                  ],
                  const Spacer(),
                  if (items.isNotEmpty)
                    Btn('Clear all',
                        small: true,
                        variant: BtnVariant.ghost,
                        onTap: DesktopNotificationFeed.clear),
                ]),
              ),
              Flexible(
                child: items.isEmpty
                    ? Padding(
                        padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
                        child: Text('Nothing needs you right now.',
                            style: sans(12.5, color: AppColors.fg4)),
                      )
                    : ListView(
                        shrinkWrap: true,
                        padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                        children: [
                          if (need.isNotEmpty) ...[
                            _label('Needs you', color: AppColors.run),
                            for (final p in need) card(p),
                          ],
                          if (rest.isNotEmpty) ...[
                            _label('Updates', top: need.isEmpty ? 4 : 12),
                            for (final p in rest) card(p),
                          ],
                        ],
                      ),
              ),
            ]),
          );
        },
      ),
    );
  }
}
