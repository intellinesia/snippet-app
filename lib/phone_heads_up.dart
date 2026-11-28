import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

import 'mobile_kit.dart' show MK, MkPill, MkPillTone, kAndroidLook;
import 'mochi.dart';
import 'notification_banner.dart';
import 'notification_card.dart' show CardAction, cardActionFor;
import 'session_quick_send.dart';
import 'theme.dart';
import 'toast.dart';

/// The phone's one in-app notification: a compact heads-up at the top, in
/// the system style. Face, who and one line; a "+N" when more are queued.
/// Tap opens, swipe up or sideways dismisses. Approvals carry two small
/// actions on a second line, as Android notification actions do.
class PhoneHeadsUp extends StatefulWidget {
  const PhoneHeadsUp({
    super.key,
    required this.payload,
    required this.more,
    required this.onOpen,
    required this.onDismiss,
    required this.onHold,
    this.onMore,
    this.send = quickSendForPayload,
  });

  final Map<String, dynamic> payload;

  /// How many more are waiting behind this one.
  final int more;
  final VoidCallback onOpen;
  final VoidCallback onDismiss;
  final ValueChanged<bool> onHold;

  /// Opens the full list from the "+N" count.
  final VoidCallback? onMore;
  final Future<bool> Function(Map<String, dynamic>, QuickAction) send;

  @override
  State<PhoneHeadsUp> createState() => _PhoneHeadsUpState();
}

class _PhoneHeadsUpState extends State<PhoneHeadsUp> {
  String? _busy;
  double _drag = 0;

  Future<void> _decide(bool approve) async {
    if (_busy != null) return;
    setState(() => _busy = approve ? 'Approving' : 'Declining');
    widget.onHold(true);
    final ok = await widget.send(
        widget.payload,
        approve
            ? const QuickApprove(via: 'notification')
            : const QuickDeny(via: 'notification'));
    if (!mounted) return;
    widget.onHold(false);
    if (ok) {
      HapticFeedback.lightImpact();
      toast(context, approve ? 'Approved' : 'Declined');
      widget.onDismiss();
    } else {
      setState(() => _busy = null);
      toast(context, 'Could not send. Open it to answer.', danger: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final p = widget.payload;
    final kind = notificationKind(p);
    final needs = kind == 'waiting';
    final raw = '${p['title'] ?? ''}'.trim();
    final who = notificationShortName(
        raw.isEmpty ? (needs ? 'Snippet' : informationTitle(p)) : raw);
    final body = notificationBody(p).replaceAll(RegExp(r'\s+'), ' ');
    final String? line = body.isNotEmpty
        ? body
        : needs
            ? 'Needs you'
            : (informationTitle(p) == who ? null : informationTitle(p));
    final ago = notificationAgo(p['created_at']);
    final approval = cardActionFor(p) == CardAction.approval;
    final a = kAndroidLook;
    final radius = a ? 28.0 : 22.0;

    final face = SizedBox(
      width: 40,
      height: 40,
      child: Stack(clipBehavior: Clip.none, children: [
        Container(
          width: 40,
          height: 40,
          decoration:
              BoxDecoration(color: AppColors.surface3, shape: BoxShape.circle),
          clipBehavior: Clip.antiAlias,
          child: AgentMochi('${p['agent_id'] ?? 'snippet'}', size: 40),
        ),
        if (needs)
          Positioned(
            right: -1,
            bottom: 0,
            child: Container(
              width: 12,
              height: 12,
              decoration: BoxDecoration(
                color: MK.amber,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.surface2, width: 2),
              ),
            ),
          ),
      ]),
    );

    final card = Material(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(radius),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: _busy == null ? widget.onOpen : null,
        child: Padding(
          padding: EdgeInsets.fromLTRB(12, 12, 14, approval ? 8 : 12),
          child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(children: [
                  face,
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(children: [
                            Flexible(
                              child: Text(who,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: sans(14.5, color: AppColors.fg1)),
                            ),
                            Text('  ·  $ago',
                                style: sans(13, color: AppColors.fg3)),
                          ]),
                          if (line != null) ...[
                            const SizedBox(height: 2),
                            Text(line,
                                maxLines: needs ? 2 : 1,
                                overflow: TextOverflow.ellipsis,
                                style: sans(14, color: AppColors.fg2)),
                          ],
                        ]),
                  ),
                  if (widget.more > 0) ...[
                    const SizedBox(width: 8),
                    Semantics(
                      button: true,
                      label: 'Show all ${widget.more + 1}',
                      excludeSemantics: true,
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: widget.onMore,
                        // 44 target around the small count.
                        child: Container(
                          key: const ValueKey('heads-up-more'),
                          constraints:
                              const BoxConstraints(minWidth: 44, minHeight: 44),
                          alignment: Alignment.center,
                          child: Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 3),
                            decoration: BoxDecoration(
                                color: AppColors.surface3,
                                borderRadius: BorderRadius.circular(10)),
                            child: Text('+${widget.more}',
                                style: sans(12.5, color: AppColors.fg2)),
                          ),
                        ),
                      ),
                    ),
                  ],
                ]),
                if (approval)
                  Padding(
                    padding: const EdgeInsets.only(left: 52, top: 4),
                    child: Row(children: [
                      MkPill(_busy == 'Declining' ? 'Declining' : 'Not yet',
                          onTap: _busy == null ? () => _decide(false) : null),
                      const SizedBox(width: 8),
                      MkPill(_busy == 'Approving' ? 'Approving' : 'Go ahead',
                          tone: MkPillTone.primary,
                          onTap: _busy == null ? () => _decide(true) : null),
                    ]),
                  ),
              ]),
        ),
      ),
    );

    final lifted = DecoratedBox(
      decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius), boxShadow: toastShadow),
      child: card,
    );

    // Up flicks it away; sideways is the Dismissible.
    return Semantics(
      container: true,
      label: [
        who,
        needs ? 'needs you' : 'notification',
        if (line != null) line,
        ago
      ].join(', '),
      onDismiss: widget.onDismiss,
      customSemanticsActions: {
        const CustomSemanticsAction(label: 'Dismiss'): widget.onDismiss,
      },
      child: GestureDetector(
        onVerticalDragUpdate: (d) =>
            setState(() => _drag = (_drag + d.delta.dy).clamp(-120.0, 0.0)),
        onVerticalDragEnd: (d) {
          if (_drag < -28 || d.velocity.pixelsPerSecond.dy < -400) {
            HapticFeedback.selectionClick();
            widget.onDismiss();
          } else {
            setState(() => _drag = 0);
          }
        },
        child: Transform.translate(
          offset: Offset(0, _drag),
          child: Opacity(
            opacity: (1 + _drag / 120).clamp(0.0, 1.0),
            child: Dismissible(
              key: ObjectKey(widget.payload),
              direction: DismissDirection.horizontal,
              onDismissed: (_) => widget.onDismiss(),
              child: lifted,
            ),
          ),
        ),
      ),
    );
  }
}
