import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../glass.dart';
import '../mochi.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'agent_cluster.dart';
import '../tap_detector.dart';

/// Provides the active peer agent colour to descendant [ChatBubble]s when
/// `chat.sent` is `"agent"`.
class ChatAgentScope extends InheritedWidget {
  const ChatAgentScope({
    super.key,
    required this.agentColor,
    required super.child,
  });

  final Color agentColor;

  static Color? colorOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChatAgentScope>()?.agentColor;

  @override
  bool updateShouldNotify(ChatAgentScope oldWidget) =>
      agentColor != oldWidget.agentColor;
}

/// Provides a [ChatBubble]'s resolved background fill so nested text and media
/// can pick contrasting ink when `chat.sentText` is `"auto"`.
class ChatBubbleFill extends InheritedWidget {
  const ChatBubbleFill({super.key, required this.fill, required super.child});

  final Color fill;

  static Color? of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<ChatBubbleFill>()?.fill;

  @override
  bool updateShouldNotify(ChatBubbleFill oldWidget) => fill != oldWidget.fill;
}

/// Chat palette for agent and group chats, read from the active theme.
class ChatColors {
  static ThemeChatTokens get _tokens => ThemeManager.instance.resolved.chat;

  static bool get light => AppColors.bg.computeLuminance() > 0.18;

  /// Primary actions only (one per view): the theme accent, never a fixed hue.
  static Color get action => AppColors.accent;
  static Color get onAction => AppColors.accentFg;
  @Deprecated('Use action')
  static Color get blue => action;

  static Color sentFor([Color? agentColor]) {
    final t = _tokens;
    switch (t.sentRaw) {
      case 'agent':
        return agentColor ?? AppColors.accent;
      case 'accent':
        return AppColors.accent;
      case 'grey':
        return const Color(0xFF3A3A3C);
      default:
        return t.sentColor ?? const Color(0xFF3A3A3C);
    }
  }

  static Color get sent => sentFor();
  static Color sentIn(BuildContext context) =>
      sentFor(ChatAgentScope.colorOf(context));

  static Color sentTextFor([Color? bubbleFill]) {
    final t = _tokens;
    if (t.sentTextRaw == 'auto') {
      final bg = bubbleFill ?? sent;
      return bg.computeLuminance() > 0.179
          ? const Color(0xFF0A0A0A)
          : const Color(0xFFFFFFFF);
    }
    return t.sentTextColor ?? const Color(0xFFFFFFFF);
  }

  static Color get sentText => sentTextFor();
  // Your bubble is s2 in every theme, so its ink is the primary text token.
  static Color sentTextIn(BuildContext context) => AppColors.fg1;

  static Color get received => _tokens.received;
  static Color get receivedText => _tokens.receivedText;
  static Color get card => _tokens.card;
  static Color get cardButton => _tokens.cardButton;
  static Color get meta => _tokens.meta;
  static Color get glass => _tokens.glass;

  static double get fontSize => _tokens.fontSize.current;
  static double get radius => _tokens.bubbleRadius.current;

  /// Gap between bubbles in one run, and between runs.
  static double get runGap => _tokens.runGap;
  static double get groupGap => _tokens.groupGap;

  /// Widest a bubble may grow, as a share of the transcript width.
  static double get maxShare => _tokens.maxShare.current;
}

TextStyle chatText({required bool mine, BuildContext? context}) =>
    sans(ChatColors.fontSize,
        height: 1.3,
        color: mine
            ? (context != null
                ? ChatColors.sentTextIn(context)
                : ChatColors.sentText)
            : AppColors.fg1);

/// Markdown inside a bubble: the base sheet recoloured for the bubble fill.
MarkdownStyleSheet chatMarkdownStyle(BuildContext context,
    {required bool mine}) {
  final base = mine ? markdownStyle(context) : agentMarkdownStyle(context);
  final prose = chatText(mine: mine, context: context);
  final soft = prose.copyWith(color: prose.color!.withValues(alpha: 0.72));
  final linkColor = mine ? ChatColors.sentTextIn(context) : ChatColors.action;
  return base.copyWith(
    p: prose,
    strong: prose.copyWith(fontWeight: weightFor(W.strong)),
    em: prose.copyWith(fontStyle: FontStyle.italic),
    a: prose.copyWith(
        color: linkColor,
        decoration: TextDecoration.underline,
        decorationColor: linkColor.withValues(alpha: 0.5)),
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
    this.flat = false,
  });

  final bool mine;
  final bool tail;
  final Widget child;

  /// Desktop: a plain 8 px card with no tail, 7/11 padding.
  final bool flat;

  /// Overrides the fill, for a tinted bubble such as an error.
  final Color? color;

  static const _tailW = 5.0;

  @override
  Widget build(BuildContext context) {
    // Agent replies are plain prose on the canvas; yours sits on s2.
    if (!mine && color == null) {
      return ChatBubbleFill(
        fill: AppColors.bg,
        child: Builder(
          builder: (bubbleCtx) => DefaultTextStyle.merge(
            style: chatText(mine: false, context: bubbleCtx),
            textWidthBasis: TextWidthBasis.longestLine,
            child: child,
          ),
        ),
      );
    }
    final fill = color ?? (mine ? AppColors.surface2 : ChatColors.received);
    final h = kMobile ? 12.0 : 11.0;
    final v = kMobile ? 8.0 : 6.0;
    if (flat && !kMobile) {
      return ChatBubbleFill(
        fill: fill,
        child: Builder(
          builder: (bubbleCtx) => Container(
            padding: const EdgeInsets.fromLTRB(11, 7, 11, 7),
            decoration: BoxDecoration(
              color: fill,
              borderRadius: BorderRadius.circular(R.of(8)),
            ),
            child: DefaultTextStyle.merge(
              style: chatText(mine: mine, context: bubbleCtx),
              textWidthBasis: TextWidthBasis.longestLine,
              child: child,
            ),
          ),
        ),
      );
    }
    return ChatBubbleFill(
      fill: fill,
      child: Builder(
        builder: (bubbleCtx) => CustomPaint(
          painter: _BubblePainter(
              // Desktop bubbles are plain rounded rects, as in the desk.
              color: fill,
              mine: mine,
              tail: false,
              radius: ChatColors.radius),
          child: Padding(
            padding: EdgeInsets.fromLTRB(
                h + (!mine ? _tailW : 0), v, h + (mine ? _tailW : 0), v + 1),
            child: DefaultTextStyle.merge(
              style: chatText(mine: mine, context: bubbleCtx),
              textWidthBasis: TextWidthBasis.longestLine,
              child: child,
            ),
          ),
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
    this.fill = false,
  });

  final bool mine;
  final Widget child;

  /// Take the whole bubble lane, for cards, so they match a full bubble's width.
  final bool fill;

  /// A received run's sender, beside its last bubble (groups only).
  final Widget? avatar;

  /// Reserve the avatar column even when this bubble has none, so a run lines up.
  final bool avatarSlot;

  static double get avatarSize =>
      ThemeManager.instance.resolved.chat.avatarSize.current;

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (_, box) {
        final max =
            box.maxWidth.isFinite ? box.maxWidth * ChatColors.maxShare : 520.0;
        final bubble = fill
            ? SizedBox(width: max, child: child)
            : ConstrainedBox(
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
            SizedBox(width: S.s6),
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
        padding: EdgeInsets.only(left: indent + 14, bottom: S.s2, top: S.s2),
        child: Text(name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: sans(kMobile ? 12 : 11, color: AppColors.fg3)),
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
    final style = sans(kMobile ? 12 : 11, color: AppColors.fg3);
    return Align(
      alignment: align,
      child: Padding(
        padding: EdgeInsets.symmetric(vertical: S.s4, horizontal: S.s4),
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
                child: TapDetector(
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
          child: TapDetector(
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
                        color: AppColors.fg1),
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
                    padding: EdgeInsets.symmetric(horizontal: S.s4),
                    decoration: BoxDecoration(
                        color: ChatColors.action,
                        borderRadius: BorderRadius.circular(R.of(9))),
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

  static double get overlap => kMobile ? 92 : 94;

  static Widget statusText(String text) => Text(text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      textAlign: TextAlign.center,
      style: sans(kMobile ? 12 : 11, color: AppColors.fg3));

  Widget _avatar() {
    const big = 36.0;
    if (agentIds.length < 2) {
      return AgentDisc(id: agentIds.isEmpty ? '' : agentIds.first, size: big);
    }
    return AgentCluster(ids: agentIds, size: big);
  }

  Widget _pill() => Glass(
        radius: BorderRadius.circular(R.pill),
        child: Padding(
          padding: EdgeInsets.symmetric(
              horizontal: kMobile ? S.of(11) : S.of(10),
              vertical: kMobile ? S.s4 : S.of(3)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              child: Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13,
                      weight: W.label, color: AppColors.fg1)),
            ),
            if (onTitleTap != null) ...[
              SizedBox(width: S.of(3)),
              AppIcon('chevron-right',
                  size: kMobile ? 11 : 10, color: AppColors.fg3),
            ],
          ]),
        ),
      );

  Widget _back() => Semantics(
        button: true,
        label: 'Back',
        child: Pressable(
          kind: PressKind.button,
          child: TapDetector(
            behavior: HitTestBehavior.opaque,
            onTap: onBack,
            child: Glass(
              radius: BorderRadius.circular(R.of(20)),
              child: Container(
                height: 40,
                constraints: const BoxConstraints(minWidth: 40),
                padding: EdgeInsets.symmetric(
                    horizontal:
                        backCount != null && backCount! > 0 ? S.s12 : 0),
                alignment: Alignment.center,
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  AppIcon('chevron-left',
                      size: 18, color: AppColors.fg1),
                  if (backCount != null && backCount! > 0) ...[
                    SizedBox(width: S.s2),
                    Text('${backCount!}',
                        style: sans(15, color: AppColors.fg1)),
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
      child: TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTitleTap,
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Stack(
            alignment: Alignment.topCenter,
            clipBehavior: Clip.none,
            children: [
              _avatar(),
              Padding(
                padding:
                    EdgeInsets.only(top: 36.0 - (kMobile ? S.s4 : S.of(3))),
                child: _pill(),
              ),
            ],
          ),
          if (status != null) status!,
        ]),
      ),
    );
    final body = SizedBox(
      height: overlap - GlassTopFrame.fade,
      child: Padding(
        padding: EdgeInsets.fromLTRB(kMobile ? S.s16 : S.s12,
            kMobile ? S.s4 : S.s8, kMobile ? S.s16 : S.s12, 0),
        child: Stack(children: [
          Align(alignment: Alignment.topCenter, child: centre),
          if (onBack != null || leading != null)
            Positioned(left: 0, top: 0, child: leading ?? _back()),
          if (trailing != null) Positioned(right: 0, top: 0, child: trailing!),
        ]),
      ),
    );
    if (!kMobile) {
      return SizedBox(
        height: overlap,
        child: Align(alignment: Alignment.topCenter, child: body),
      );
    }
    return SizedBox(
        height: overlap, child: GlassTopFrame(color: bg, child: body));
  }
}

class AgentDisc extends StatelessWidget {
  const AgentDisc(
      {super.key, required this.id, required this.size, this.ring = false});

  final String id;
  final double size;
  final bool ring;

  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        decoration: avatarDecoration(size,
            color: ChatColors.cardButton,
            side: ring
                ? BorderSide(color: readingBg, width: 2)
                : BorderSide.none),
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
