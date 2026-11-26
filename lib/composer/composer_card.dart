import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import '../tap_detector.dart' show HitArea;

import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'composer_pill.dart';

export 'composer_pill.dart';
export 'composer_queue.dart';
export 'desktop_composer.dart';

/// The one composer surface: a 52px Duet pill, attach | field | trailing
/// controls. The field grows upward and the controls stay on the last line.
class ComposerCard extends StatefulWidget {
  const ComposerCard({
    super.key,
    required this.field,
    required this.send,
    this.text,
    this.banner,
    this.attach,
    this.trailing,
    this.mic,
    this.highlight = false,
  });

  final Widget field;
  final Widget send;

  /// Draft text; wide text collapses the trailing chips to their icons.
  final ValueListenable<TextEditingValue>? text;
  final Widget? banner;
  final Widget? attach;

  /// Builds the trailing chips; `compact` asks for icon-only chips.
  final Widget Function(bool compact)? trailing;
  final Widget? mic;
  final bool highlight;

  static double get radius => C7.pillRadius;

  /// The draft's type in the pill; one 22px line fills the 40px slot.
  static TextStyle get fieldStyle =>
      sans(C7.field, height: C7.line / C7.field, color: AppColors.fg1);

  static InputDecoration decoration(String hint,
          {TextStyle? style, Color? hintColor}) =>
      InputDecoration(
        isCollapsed: true,
        contentPadding: const EdgeInsets.fromLTRB(4, 9, 4, 9),
        border: InputBorder.none,
        hintText: hint,
        hintMaxLines: 1,
        hintStyle: (style ?? TS.body()).copyWith(
            color: hintColor ?? AppColors.fg3, overflow: TextOverflow.ellipsis),
      );

  static bool _wraps(double width, String draft, BuildContext context) {
    if (draft.isEmpty) return false;
    if (draft.contains('\n')) return true;
    final p = TextPainter(
      text: TextSpan(text: draft, style: fieldStyle),
      textDirection: TextDirection.ltr,
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    // Room beside attach (48) and voice plus send (96).
    return p.width > width - 8 - 48 - 96 - 8;
  }

  static bool _compact(double width, String draft) {
    if (width < 380) return true;
    if (draft.isEmpty || draft.contains('\n')) return false;
    final p = TextPainter(
      text: TextSpan(text: draft, style: fieldStyle),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return p.width > width - 300;
  }

  @override
  State<ComposerCard> createState() => _ComposerCardState();
}

class _ComposerCardState extends State<ComposerCard> {
  // Keeps the field's state when the layout flips between one line and many.
  final _fieldKey = GlobalKey();

  ComposerCard get _w => widget;

  @override
  Widget build(BuildContext context) {
    final field = KeyedSubtree(key: _fieldKey, child: _w.field);
    final banner = _w.banner,
        attach = _w.attach,
        trailing = _w.trailing,
        mic = _w.mic,
        send = _w.send,
        text = _w.text,
        highlight = _w.highlight;
    final pill = ComposerPillSurface(
      highlight: highlight,
      child: LayoutBuilder(
        builder: (context, box) => ValueListenableBuilder<TextEditingValue>(
          valueListenable: text ?? ValueNotifier(TextEditingValue.empty),
          builder: (context, v, _) {
            final compact = ComposerCard._compact(box.maxWidth, v.text);
            Widget inSlot(Widget w) => ConstrainedBox(
                constraints: BoxConstraints(minHeight: C7.btn),
                child: Center(child: w));
            // Phone: past one line the field takes the width and the controls
            // drop to a footer row (attach, chips, voice, send).
            if (kMobile && ComposerCard._wraps(box.maxWidth, v.text, context)) {
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (banner != null)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
                      child: banner,
                    ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(10, 1, 10, 0),
                    child: field,
                  ),
                  Row(children: [
                    if (attach != null) inSlot(attach),
                    if (trailing != null) inSlot(trailing(false)),
                    const Spacer(),
                    if (mic != null) inSlot(mic),
                    inSlot(send),
                  ]),
                ],
              );
            }
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (banner != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
                    child: banner,
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (attach != null) inSlot(attach),
                    Expanded(
                      child: ConstrainedBox(
                        constraints: BoxConstraints(minHeight: C7.btn),
                        child: Align(
                            alignment: Alignment.centerLeft, child: field),
                      ),
                    ),
                    if (trailing != null) inSlot(trailing(compact)),
                    if (mic != null) inSlot(mic),
                    const SizedBox(width: 4),
                    inSlot(send),
                  ],
                ),
              ],
            );
          },
        ),
      ),
    );
    return pill;
  }
}

class ComposerIconButton extends StatelessWidget {
  const ComposerIconButton(this.icon,
      {super.key, required this.tooltip, required this.onTap, this.color});

  final String icon;
  final String tooltip;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final w = Material(
      color: Colors.transparent,
      shape: const CircleBorder(),
      child: InkWell(
        onTap: () {
          tapHaptic();
          onTap();
        },
        customBorder: const CircleBorder(),
        child: SizedBox.square(
          dimension: C7.btn,
          child: Center(
              child: AppIcon(icon,
                  size: kMobile ? 20 : 22, color: color ?? AppColors.fg2)),
        ),
      ),
    );
    return kMobile ? w : Tooltip(message: tooltip, child: w);
  }
}

class ComposerSendButton extends StatelessWidget {
  const ComposerSendButton(
      {super.key,
      required this.enabled,
      this.sending = false,
      this.stop = false,
      this.onTap});

  final bool enabled;
  final bool sending;
  final bool stop;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final fill = !kMobile
        ? (!enabled
            ? AppColors.fg1.withValues(alpha: 0.07)
            : stop
                ? AppColors.fg1.withValues(alpha: 0.11)
                : AppColors.accentFill)
        : stop
            ? AppColors.fg1
            : AppColors.surface3;
    final ink = !kMobile
        ? (!enabled
            ? AppColors.fg4
            : stop
                ? AppColors.fg1
                : AppColors.accentFg)
        : stop
            ? AppColors.bg
            : enabled
                ? AppColors.fg1
                : AppColors.fg3;
    final ShapeBorder shape = kMobile
        ? const CircleBorder()
        : RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.of(6)));
    final button = Material(
      color: fill,
      shape: shape,
      child: InkWell(
        customBorder: shape,
        onTap: stop && onTap != null
            ? () {
                tapHaptic();
                onTap!();
              }
            : onTap,
        child: SizedBox.square(
          dimension: 28,
          child: Center(
            child: sending
                ? Spinner(size: 16, color: ink)
                : AppIcon(stop ? 'stop' : 'arrow-up',
                    size: stop ? 14 : 19, color: ink),
          ),
        ),
      ),
    );
    if (!kMobile) return button;
    // A 28 circle inside a 48 target; always visible, announced when off.
    return Semantics(
      button: true,
      enabled: enabled,
      label: stop
          ? 'Stop'
          : enabled
              ? 'Send'
              : 'Send, unavailable',
      excludeSemantics: true,
      child: SizedBox.square(dimension: 48, child: Center(child: button)),
    );
  }
}

/// A control-row chip. With [onClear] set it shows a chosen value and the
/// trailing affordance clears it instead of opening the picker.
class ComposerChip extends StatelessWidget {
  const ComposerChip({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.onClear,
    this.selected = false,
    this.compact = false,
  });

  final bool compact;
  final String icon;
  final String label;
  final VoidCallback onTap;
  final VoidCallback? onClear;
  final bool selected;

  @override
  Widget build(BuildContext context) => Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () {
            pickHaptic();
            onTap();
          },
          borderRadius: BorderRadius.circular(16),
          child: HitArea(
            alignment: Alignment.center,
            child: Container(
              height: 32,
              decoration: BoxDecoration(
                color: selected ? AppColors.accentBg : Colors.transparent,
                borderRadius: BorderRadius.circular(16),
              ),
              padding: EdgeInsets.fromLTRB(
                  compact ? S.s8 : (kMobile ? S.of(9) : S.s8),
                  0,
                  compact
                      ? S.s8
                      : (onClear == null ? (kMobile ? S.s8 : S.of(7)) : S.s4),
                  0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  AppIcon(icon,
                      size: 14,
                      color: selected ? AppColors.accent : AppColors.fg2),
                  if (!compact) SizedBox(width: S.s6),
                  if (!compact)
                    ConstrainedBox(
                      constraints:
                          BoxConstraints(maxWidth: kMobile ? 110 : 140),
                      child: Text(label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: sans(14,
                              color:
                                  selected ? AppColors.accent : AppColors.fg3)),
                    ),
                  if (compact)
                    const SizedBox.shrink()
                  else if (onClear != null)
                    IconBtn('x',
                        size: 22,
                        iconSize: 12,
                        tooltip: 'Clear',
                        onTap: onClear)
                  else ...[
                    SizedBox(width: S.of(5)),
                    AppIcon('chevron-down',
                        size: 13,
                        color: selected ? AppColors.accent : AppColors.fg4),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
}
