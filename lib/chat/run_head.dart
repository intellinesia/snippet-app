import 'package:flutter/material.dart';
import 'chat_style.dart';
import '../phosphor_icons.dart';

import '../mochi.dart';
import '../platform.dart';
import '../theme.dart';
import '../tap_detector.dart';
import '../widgets.dart';

/// Desktop posts (MSG-02/03): avatar column plus gap, so text, cards and
/// chips start at x+36.
const double kSoftIndent = 36;
const double _avatar = 24;

/// Desktop post body width is the column minus this (MSG-02).
const double kPostBodyInset = 40;

/// Desktop: your bubble is at most this wide (MSG-01).
const double kUserBubbleMax = 360;

/// Desktop chat body: 13/400 on a 19 line.
TextStyle deskBody({Color? color}) =>
    sans(13, height: 19 / 13, color: color ?? AppColors.fg1);

/// Desktop: your message sits in an s2 bubble (radius 12, pad 12, max 360);
/// agent prose has no bubble.
class SoftBubble extends StatelessWidget {
  const SoftBubble({
    super.key,
    required this.child,
    this.mine = false,
    this.first = true,
    this.last = true,
    this.selected = false,
  });

  final Widget child;
  final bool mine;
  final bool first;
  final bool last;

  /// MSG-01 selected: s3 fill and the one allowed fg3 outline.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    if (!mine) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 3),
        child: child,
      );
    }
    final fill = selected ? AppColors.surface3 : AppColors.surface2;
    return LayoutBuilder(builder: (_, box) {
      final cap = box.maxWidth.isFinite
          ? (box.maxWidth - 36).clamp(0.0, kUserBubbleMax).toDouble()
          : kUserBubbleMax;
      return ConstrainedBox(
        constraints: BoxConstraints(maxWidth: cap),
        child: Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: fill,
            borderRadius: BorderRadius.circular(12),
            border: selected ? Border.all(color: AppColors.fg3) : null,
          ),
          child: ChatBubbleFill(
            fill: fill,
            child: DefaultTextStyle.merge(style: deskBody(), child: child),
          ),
        ),
      );
    });
  }
}

/// Desktop: an agent's post. Avatar 24 heads the run; name 13/500 and time
/// 11/400 fg3 sit beside it; the body starts at x+36, column minus 40 wide.
class SoftLane extends StatelessWidget {
  const SoftLane({
    super.key,
    required this.agentId,
    required this.child,
    this.name,
    this.time,
    this.lead = false,
    this.first = true,
    this.last = true,
    this.share = 1,
    this.streaming = false,
    this.selected = false,
    this.muted = false,
  });

  final String agentId;
  final Widget child;

  /// Shown beside the avatar on the first message of a run when set.
  final String? name;
  final String? time;
  final bool lead;
  final bool first;
  final bool last;

  /// Widest the content may grow, as a share of the body width.
  final double share;

  /// Adds the 2 px fg1 caret after the text while the reply streams.
  final bool streaming;

  /// MSG-02/03 selected: an s2 plate, radius 10, 10 out on every side.
  final bool selected;

  /// MSG-03 muted sender: name and body fg2 plus a Muted pill.
  final bool muted;

  @override
  Widget build(BuildContext context) {
    final head = first && name != null;
    final ink = muted ? AppColors.fg2 : AppColors.fg1;
    return LayoutBuilder(builder: (_, box) {
      // MSG-02/03: body width is column minus 40. [share] is retained for
      // source compatibility with the older soft-bubble lane, but the locked
      // desktop measure is not proportional.
      final max = box.maxWidth.isFinite
          ? (box.maxWidth - kPostBodyInset)
              .clamp(0.0, double.infinity)
              .toDouble()
          : 640.0;
      Widget body = streaming
          ? Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Flexible(child: child),
                const Padding(
                  padding: EdgeInsets.only(left: 2, bottom: 5),
                  child: StreamingCaret(),
                ),
              ],
            )
          : child;
      if (muted) {
        body =
            DefaultTextStyle.merge(style: TextStyle(color: ink), child: body);
      }
      Widget post = Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: _avatar,
            child: first ? AgentMochi(agentId, size: _avatar) : null,
          ),
          const SizedBox(width: kSoftIndent - _avatar),
          Flexible(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (head)
                  SizedBox(
                    height: _avatar,
                    child: Row(mainAxisSize: MainAxisSize.min, children: [
                      Flexible(
                        child: Text(name!,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: sans(kMobile ? 13 : 13,
                                height: kMobile ? 18 / 13 : 18 / 13,
                                weight: FontWeight.w500,
                                color: ink)),
                      ),
                      if (lead) ...[
                        const SizedBox(width: 6),
                        Text('lead', style: sans(11, color: AppColors.fg3)),
                      ],
                      if (time != null) ...[
                        const SizedBox(width: 6),
                        Text(time!,
                            style: sans(kMobile ? 11.5 : 11,
                                color: AppColors.fg3, tabular: true)),
                      ],
                      if (muted) ...[
                        const SizedBox(width: 8),
                        const MutedPill(),
                      ],
                    ]),
                  ),
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: max),
                  child: body,
                ),
              ],
            ),
          ),
        ],
      );
      if (selected) {
        post = kMobile ? PhoneSelectedPlate(child: post) : SelectedPlate(child: post);
      }
      return post;
    });
  }
}

/// MSG-02/03 selected post: an s2 plate, radius 10, drawn 10 out from the
/// post on every side so the text does not move.
class SelectedPlate extends StatelessWidget {
  const SelectedPlate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -10,
            top: -10,
            right: -10,
            bottom: -10,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(10),
              ),
            ),
          ),
          child,
        ],
      );
}

/// v19 phone selection: surface3 plate, radius 8, with a 2 px fg2 left bar.
class PhoneSelectedPlate extends StatelessWidget {
  const PhoneSelectedPlate({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            left: -8,
            top: -6,
            right: -8,
            bottom: -6,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.surface3,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          Positioned(
            left: -8,
            top: -6,
            bottom: -6,
            child: Container(width: 2, color: AppColors.fg2),
          ),
          child,
        ],
      );
}

/// MSG-03 muted sender: s2 pill, mute icon 13, "Muted" 11/500 fg2.
class MutedPill extends StatelessWidget {
  const MutedPill({super.key});

  @override
  Widget build(BuildContext context) => Container(
        height: 18,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(9),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(PhIcons.bellSlash, size: 13, color: AppColors.fg2),
          const SizedBox(width: 4),
          Text('Muted',
              style: sans(11, weight: FontWeight.w500, color: AppColors.fg2)),
        ]),
      );
}

/// The 2 px fg1 caret after streaming text, one body line tall.
class StreamingCaret extends StatefulWidget {
  const StreamingCaret({super.key});

  @override
  State<StreamingCaret> createState() => _StreamingCaretState();
}

class _StreamingCaretState extends State<StreamingCaret>
    with SingleTickerProviderStateMixin {
  late final _blink = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1000));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (reduceMotion(context)) {
      _blink.stop();
      _blink.value = 1;
    } else if (!_blink.isAnimating) {
      _blink.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Semantics(
        label: 'Writing',
        child: FadeTransition(
          opacity: CurvedAnimation(parent: _blink, curve: Curves.easeInOut),
          child: Container(width: 2, height: 14, color: AppColors.fg1),
        ),
      );
}

enum ChatButtonKind { primary, secondary, ghost }

/// Desktop chat action button (locked): 28 high, radius 6, label 12/500,
/// 12 a side. Secondary is one tonal step up from [on].
class ChatButton extends StatelessWidget {
  const ChatButton({
    super.key,
    required this.label,
    required this.onTap,
    this.kind = ChatButtonKind.secondary,
    this.icon,
    this.on,
  });

  final String label;
  final VoidCallback? onTap;
  final ChatButtonKind kind;
  final IconData? icon;

  /// The surface the button sits on; secondary takes the next step up.
  final Color? on;

  Color get _fill {
    final parent = on ?? AppColors.bg;
    if (kind == ChatButtonKind.ghost) return Colors.transparent;
    if (kind == ChatButtonKind.primary && onTap != null) return AppColors.fg1;
    if (parent == AppColors.surface2) return AppColors.surface3;
    if (parent == AppColors.surface1) return AppColors.surface2;
    if (parent == AppColors.surface3) return AppColors.line;
    return AppColors.surface2;
  }

  @override
  Widget build(BuildContext context) {
    final fg = onTap == null || kind == ChatButtonKind.ghost
        ? AppColors.fg2
        : kind == ChatButtonKind.primary
            ? AppColors.bg
            : AppColors.fg1;
    final fill = _fill;
    return Semantics(
      button: true,
      enabled: onTap != null,
      child: HoverSurface(
        radius: 6,
        rest: fill,
        hoverColor:
            Color.alphaBlend(AppColors.fg1.withValues(alpha: 0.06), fill),
        onTap: onTap,
        child: SizedBox(
          height: 28,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              if (icon != null) ...[
                Icon(icon, size: 13, color: fg),
                const SizedBox(width: 6),
              ],
              Text(label,
                  style: sans(12,
                      height: 16 / 12, weight: FontWeight.w500, color: fg)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// Where your message is on its way (MSG-01 meta line).
enum SendState { sending, sent, read, failed }

/// Desktop: the meta line under your last message, right-aligned, 11/400 fg3.
/// Sending: spinner. Sent: check and time. Read: check_circle fg2 and the
/// read line. Failed: x, "Not delivered" 11/500 fg2 and a Retry button.
class SentMeta extends StatelessWidget {
  const SentMeta({
    super.key,
    required this.time,
    this.delivered = false,
    this.read,
    this.state,
    this.onRetry,
    this.selected = false,
  });

  final String time;
  final bool delivered;

  /// "Read 9:01 am" or "Read by Snippet 11:14"; null while unread.
  final String? read;

  /// Overrides the state read from [delivered] and [read].
  final SendState? state;
  final VoidCallback? onRetry;

  /// MSG-01 selected: "Selected" 11/500 after the meta.
  final bool selected;

  @override
  Widget build(BuildContext context) {
    final meta = sans(11, color: AppColors.fg3, tabular: true);
    final s = state ?? (read != null ? SendState.read : SendState.sent);
    final children = <Widget>[
      switch (s) {
        SendState.sending => SizedBox.square(
            dimension: 11,
            child: CircularProgressIndicator(
                strokeWidth: 1.4,
                strokeCap: StrokeCap.round,
                color: AppColors.fg3)),
        SendState.sent => Icon(PhIcons.check, size: 13, color: AppColors.fg3),
        SendState.read =>
          Icon(PhIcons.checkCircle, size: 13, color: AppColors.fg2),
        SendState.failed => Icon(PhIcons.x, size: 13, color: AppColors.fg2),
      },
      const SizedBox(width: 4),
      switch (s) {
        SendState.sending => Text('Sending', style: meta),
        SendState.sent => Text(time, style: meta),
        SendState.read => Text(read ?? 'Read $time', style: meta),
        SendState.failed => Text('Not delivered',
            style: sans(kMobile ? 14 : 11,
                weight: kMobile ? FontWeight.w400 : FontWeight.w500,
                color: AppColors.fg2)),
      },
      if (s == SendState.failed && onRetry != null) ...[
        const SizedBox(width: 8),
        kMobile
            ? TapDetector(
                onTap: onRetry,
                child: Container(
                  width: 73,
                  height: 32,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.surface3,
                    borderRadius: BorderRadius.circular(16),
                  ),
                  child: Text('Retry',
                      style: sans(13,
                          weight: FontWeight.w500, color: AppColors.fg1)),
                ),
              )
            : ChatButton(label: 'Retry', onTap: onRetry),
      ],
      if (selected) ...[
        const SizedBox(width: 8),
        Text('Selected',
            style: sans(11, weight: FontWeight.w500, color: AppColors.fg1)),
      ],
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }
}

/// MSG-10: "Read by Snippet 11:14", 11/400 fg3, right-aligned under the last
/// message of a burst.
class ReadReceiptLine extends StatelessWidget {
  const ReadReceiptLine(this.text, {super.key});

  final String text;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.centerRight,
        child: Padding(
          padding: const EdgeInsets.only(top: 4),
          child:
              Text(text, style: sans(11, color: AppColors.fg3, tabular: true)),
        ),
      );
}
