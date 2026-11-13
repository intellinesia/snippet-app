import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../glass.dart';
import '../mochi.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'agent_cluster.dart';

/// Chat palette for agent and group chats. Values measured from
/// the reference screenshots; the received grey follows the theme brightness.
class ChatColors {
  static bool get light => AppColors.bg.computeLuminance() > 0.18;

  /// Primary actions only (one per view): the theme accent, never a fixed hue.
  static Color get action => AppColors.accent;
  static Color get onAction => AppColors.accentFg;
  @Deprecated('Use action')
  static Color get blue => action;
  // Grey, not accent: the accent stays for the few main actions.
  static Color get sent => const Color(0xFF3A3A3C);
  static Color get sentText => const Color(0xFFFFFFFF);
  static Color get received =>
      light ? const Color(0xFFE9E9EB) : const Color(0xFF26262A);
  static Color get receivedText =>
      light ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
  static Color get card =>
      light ? const Color(0xFFF2F2F7) : const Color(0xFF1C1C1E);
  static Color get cardButton =>
      light ? const Color(0xFFE5E5EA) : const Color(0xFF2C2C2E);
  static const meta = Color(0xFF8E8E93);
  static Color get glass =>
      light ? const Color(0xF2F2F2F7) : const Color(0xCC2C2C2E);

  static double get fontSize => kMobile ? 16 : 13.5;
  static double get radius => kMobile ? 18 : 16;

  /// Gap between bubbles in one run, and between runs.
  static const runGap = 2.0;
  static const groupGap = 10.0;

  /// Widest a bubble may grow, as a share of the transcript width.
  static double get maxShare => kMobile ? 0.78 : 0.66;
}

TextStyle chatText({required bool mine}) => sans(ChatColors.fontSize,
    height: 1.3, color: mine ? ChatColors.sentText : ChatColors.receivedText);

/// Markdown inside a bubble: the base sheet recoloured for the bubble fill.
MarkdownStyleSheet chatMarkdownStyle(BuildContext context,
    {required bool mine}) {
  final base = mine ? markdownStyle(context) : agentMarkdownStyle(context);
  final prose = chatText(mine: mine);
  final soft = prose.copyWith(color: prose.color!.withValues(alpha: 0.72));
  return base.copyWith(
    p: prose,
    strong: prose.copyWith(fontWeight: weightFor(W.strong)),
    em: prose.copyWith(fontStyle: FontStyle.italic),
    a: prose.copyWith(
        color: mine ? ChatColors.sentText : ChatColors.action,
        decoration: TextDecoration.underline,
        decorationColor: (mine ? ChatColors.sentText : ChatColors.action)
            .withValues(alpha: 0.5)),
    listBullet: soft,
    blockquote: soft.copyWith(fontStyle: FontStyle.italic),
    h1: prose.copyWith(
        fontSize: ChatColors.fontSize + 3, fontWeight: weightFor(W.strong)),
    h2: prose.copyWith(
        fontSize: ChatColors.fontSize + 2, fontWeight: weightFor(W.strong)),
    h3: prose.copyWith(
        fontSize: ChatColors.fontSize + 1, fontWeight: weightFor(W.strong)),
  );
}

/// One chat bubble. [tail] draws the curl on the last bubble of a run.
class ChatBubble extends StatelessWidget {
  const ChatBubble({
    super.key,
    required this.mine,
    required this.child,
    this.tail = true,
    this.color,
  });

  final bool mine;
  final bool tail;
  final Widget child;

  /// Overrides the fill, for a tinted bubble such as an error.
  final Color? color;

  static const _tailW = 5.0;

  @override
  Widget build(BuildContext context) {
    final fill = color ?? (mine ? ChatColors.sent : ChatColors.received);
    final h = kMobile ? 12.0 : 11.0;
    final v = kMobile ? 8.0 : 6.0;
    return CustomPaint(
      painter: _BubblePainter(
          color: fill, mine: mine, tail: tail, radius: ChatColors.radius),
      child: Padding(
        padding: EdgeInsets.fromLTRB(
            h + (!mine ? _tailW : 0), v, h + (mine ? _tailW : 0), v + 1),
        child: DefaultTextStyle.merge(
          style: chatText(mine: mine),
          textWidthBasis: TextWidthBasis.longestLine,
          child: child,
        ),
      ),
    );
  }
}

class _BubblePainter extends CustomPainter {
  _BubblePainter(
      {required this.color,
      required this.mine,
      required this.tail,
      required this.radius});

  final Color color;
  final bool mine;
  final bool tail;
  final double radius;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = color;
    const t = ChatBubble._tailW;
    final w = size.width;
    final h = size.height;
    final r = math.min(radius, h / 2);
    if (!tail) {
      final body =
          mine ? Rect.fromLTWH(0, 0, w - t, h) : Rect.fromLTWH(t, 0, w - t, h);
      canvas.drawRRect(
          RRect.fromRectAndRadius(body, Radius.circular(r)), paint);
      return;
    }
    // Drawn for a right-hand tail, mirrored for the left.
    final k = r * 0.45;
    final p = Path()
      ..moveTo(r, 0)
      ..lineTo(w - t - r, 0)
      ..cubicTo(w - t - k, 0, w - t, k, w - t, r)
      ..lineTo(w - t, h - r * 0.6)
      ..cubicTo(w - t, h - 2, w - 1, h - 0.5, w, h)
      ..cubicTo(w - 6, h + 0.5, w - t - 4, h - 1.5, w - t - 6, h - 3)
      ..cubicTo(w - t - 9, h - 0.5, w - t - 13, h, w - t - r, h)
      ..lineTo(r, h)
      ..cubicTo(k, h, 0, h - k, 0, h - r)
      ..lineTo(0, r)
      ..cubicTo(0, k, k, 0, r, 0)
      ..close();
    if (!mine) {
      canvas.save();
      canvas.translate(w, 0);
      canvas.scale(-1, 1);
      canvas.drawPath(p, paint);
      canvas.restore();
    } else {
      canvas.drawPath(p, paint);
    }
  }

  @override
  bool shouldRepaint(_BubblePainter old) =>
      old.color != color ||
      old.mine != mine ||
      old.tail != tail ||
      old.radius != radius;
}

/// Caps a bubble's width at [ChatColors.maxShare] of the transcript and aligns it.
class ChatBubbleRow extends StatelessWidget {
  const ChatBubbleRow({
    super.key,
    required this.mine,
    required this.child,
    this.avatar,
    this.avatarSlot = false,
  });

  final bool mine;
  final Widget child;

  /// A received run's sender, beside its last bubble (groups only).
  final Widget? avatar;

  /// Reserve the avatar column even when this bubble has none, so a run lines up.
  final bool avatarSlot;

  static double get avatarSize => kMobile ? 28 : 24;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (_, box) {
        final max =
            box.maxWidth.isFinite ? box.maxWidth * ChatColors.maxShare : 520.0;
        final bubble = ConstrainedBox(
            constraints: BoxConstraints(maxWidth: max), child: child);
        if (mine) {
          return Align(alignment: Alignment.centerRight, child: bubble);
        }
        if (!avatarSlot && avatar == null) {
          return Align(alignment: Alignment.centerLeft, child: bubble);
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            SizedBox(width: avatarSize, height: avatarSize, child: avatar),
            const SizedBox(width: 6),
            Flexible(child: bubble),
          ],
        );
      });
}

/// Sender name above a received run in a group.
class ChatSenderName extends StatelessWidget {
  const ChatSenderName(this.name, {super.key, this.indent = 0});

  final String name;
  final double indent;

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.only(left: indent + 14, bottom: 2, top: 2),
        child: Text(name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: sans(kMobile ? 12 : 11, color: ChatColors.meta)),
      );
}

/// Centred grey line: day stamps, "Read 18:59", handoffs, tool summaries.
class ChatSystemLine extends StatelessWidget {
  const ChatSystemLine(this.text,
      {super.key, this.bold, this.align = Alignment.center, this.action});

  final String text;

  /// Leading emphasised part, such as "Today" in "Today 18:58".
  final String? bold;
  final Alignment align;

  /// Optional trailing tappable word in blue, such as "Show".
  final (String, VoidCallback)? action;

  @override
  Widget build(BuildContext context) {
    final style = sans(kMobile ? 12 : 11, color: ChatColors.meta);
    return Align(
      alignment: align,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Text.rich(
          TextSpan(style: style, children: [
            if (bold != null)
              TextSpan(
                  text: '$bold ',
                  style: style.copyWith(fontWeight: weightFor(W.label))),
            TextSpan(text: text),
            if (action != null) ...[
              const TextSpan(text: ' · '),
              WidgetSpan(
                alignment: PlaceholderAlignment.baseline,
                baseline: TextBaseline.alphabetic,
                child: GestureDetector(
                  onTap: action!.$2,
                  child: Text(action!.$1,
                      style: style.copyWith(color: ChatColors.action)),
                ),
              ),
            ],
          ]),
          textAlign: TextAlign.center,
        ),
      ),
    );
  }
}

/// Round translucent button used in the floating header.
class ChatGlassButton extends StatelessWidget {
  const ChatGlassButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.badge,
  });

  final String icon;
  final VoidCallback onTap;
  final String tooltip;
  final int? badge;

  @override
  Widget build(BuildContext context) {
    final size = kMobile ? 40.0 : 30.0;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Pressable(
          kind: PressKind.button,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onTap,
            child: Stack(clipBehavior: Clip.none, children: [
              Glass(
                radius: null,
                child: SizedBox(
                  width: size,
                  height: size,
                  child: Center(
                    child: AppIcon(icon,
                        size: kMobile ? 18 : 15,
                        color: ChatColors.receivedText),
                  ),
                ),
              ),
              if (badge != null && badge! > 0)
                Positioned(
                  right: -3,
                  top: -3,
                  child: Container(
                    constraints:
                        const BoxConstraints(minWidth: 17, minHeight: 17),
                    padding: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                        color: ChatColors.action,
                        borderRadius: BorderRadius.circular(9)),
                    alignment: Alignment.center,
                    child: Text('${badge!}',
                        style: sans(11,
                            weight: W.label, color: ChatColors.onAction)),
                  ),
                ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// The chat header: centred avatar over a name pill and one status line,
/// floating over the transcript. Back sits left, one action right.
///
/// Place it in a [Stack] above the transcript and pad the transcript's top by
/// [ChatHeader.overlap]; the header fades the canvas behind itself.
class ChatHeader extends StatelessWidget {
  const ChatHeader({
    super.key,
    required this.agentIds,
    required this.title,
    this.status,
    this.onTitleTap,
    this.titleHint,
    this.onBack,
    this.backCount,
    this.trailing,
    this.leading,
  });

  /// One id for a direct chat; a group renders them as a cluster.
  final List<String> agentIds;
  final String title;

  /// One line under the pill (state, typing). Text or a row with dots.
  final Widget? status;
  final VoidCallback? onTitleTap;
  final String? titleHint;

  /// Null hides the back pill.
  final VoidCallback? onBack;

  /// Unread elsewhere, shown in the back pill as on iOS.
  final int? backCount;
  final Widget? trailing;

  /// Desktop only: a left button where the back pill would be.
  final Widget? leading;

  static double get overlap => kMobile ? 106 : 80;

  static Widget statusText(String text) => Text(text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: sans(kMobile ? 12 : 11, color: ChatColors.meta));

  Widget _avatar() {
    final big = kMobile ? 44.0 : 32.0;
    if (agentIds.length < 2) {
      return MochiDisc(id: agentIds.isEmpty ? '' : agentIds.first, size: big);
    }
    return AgentCluster(ids: agentIds, size: big);
  }

  Widget _pill() => Glass(
        radius: BorderRadius.circular(999),
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: kMobile ? 11 : 10, vertical: kMobile ? 4 : 3),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(kMobile ? 13 : 12,
                      weight: W.label, color: ChatColors.receivedText)),
            ),
            if (onTitleTap != null) ...[
              const SizedBox(width: 3),
              AppIcon('chevron-right',
                  size: kMobile ? 11 : 10, color: ChatColors.meta),
            ],
          ]),
        ),
      );

  Widget _back() => Semantics(
        button: true,
        label: 'Back',
        child: Pressable(
          kind: PressKind.button,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onBack,
            child: Glass(
              radius: BorderRadius.circular(20),
              child: Container(
                height: 40,
                constraints: const BoxConstraints(minWidth: 40),
                padding: EdgeInsets.symmetric(
                    horizontal: backCount != null && backCount! > 0 ? 12 : 0),
                alignment: Alignment.center,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  AppIcon('chevron-left',
                      size: 18, color: ChatColors.receivedText),
                  if (backCount != null && backCount! > 0) ...[
                    const SizedBox(width: 2),
                    Text('${backCount!}',
                        style: sans(15, color: ChatColors.receivedText)),
                  ],
                ]),
              ),
            ),
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final bg = readingBg;
    final centre = Semantics(
      button: onTitleTap != null,
      label: title,
      hint: titleHint,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTitleTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          _avatar(),
          Transform.translate(
              offset: Offset(0, kMobile ? -4 : -3), child: _pill()),
          if (status != null)
            Padding(
              padding: EdgeInsets.only(top: kMobile ? 0 : 0),
              child: status!,
            ),
        ]),
      ),
    );
    final body = SizedBox(
      height: overlap - GlassTopFrame.fade,
      child: Padding(
          padding: EdgeInsets.fromLTRB(
              kMobile ? 16 : 12, kMobile ? 6 : 8, kMobile ? 16 : 12, 0),
          child: Stack(children: [
            Align(alignment: Alignment.topCenter, child: centre),
            if (onBack != null || leading != null)
              Positioned(left: 0, top: 0, child: leading ?? _back()),
            if (trailing != null)
              Positioned(right: 0, top: 0, child: trailing!),
          ]),
        ),
    );
    if (!kMobile) {
      return SizedBox(
        height: overlap,
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              stops: const [0, 0.78, 1],
              colors: [bg, bg, bg.withValues(alpha: 0)],
            ),
          ),
          child: Align(alignment: Alignment.topCenter, child: body),
        ),
      );
    }
    return SizedBox(
        height: overlap, child: GlassTopFrame(color: bg, child: body));
  }
}

class MochiDisc extends StatelessWidget {
  const MochiDisc(
      {super.key, required this.id, required this.size, this.ring = false});

  final String id;
  final double size;
  final bool ring;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: ChatColors.cardButton,
          shape: BoxShape.circle,
          border: ring ? Border.all(color: readingBg, width: 2) : null,
        ),
        alignment: Alignment.center,
        child: AgentMochi(id, size: size * 0.6),
      );
}

/// Groups consecutive messages into runs: same sender, under five minutes
/// apart. Returns, per index, whether it starts and whether it ends a run.
List<({bool first, bool last})> chatRuns<T>(
  List<T> items, {
  required String Function(T) sender,
  required DateTime? Function(T) at,
  bool Function(T)? breaks,
}) {
  const gap = Duration(minutes: 5);
  bool joins(int a, int b) {
    if (breaks != null && (breaks(items[a]) || breaks(items[b]))) return false;
    if (sender(items[a]) != sender(items[b])) return false;
    final ta = at(items[a]);
    final tb = at(items[b]);
    if (ta == null || tb == null) return true;
    return tb.difference(ta).abs() < gap;
  }

  return [
    for (var i = 0; i < items.length; i++)
      (
        first: i == 0 || !joins(i - 1, i),
        last: i == items.length - 1 || !joins(i, i + 1),
      )
  ];
}
