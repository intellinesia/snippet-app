import 'package:flutter/foundation.dart';
import '../desktop_look.dart';
import 'package:flutter/material.dart';

import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';
import 'composer_pill.dart';

export 'composer_pill.dart';
export 'composer_queue.dart';

/// The one composer surface: a 52px Duet pill, attach | field | trailing
/// controls. The field grows upward and the controls stay on the last line.
class ComposerCard extends StatelessWidget {
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
      sans(C7.field, height: 22 / C7.field, color: AppColors.fg1);

  static InputDecoration decoration(String hint, {TextStyle? style}) =>
      InputDecoration(
        isCollapsed: true,
        contentPadding: const EdgeInsets.fromLTRB(4, 9, 4, 9),
        border: InputBorder.none,
        hintText: hint,
        hintMaxLines: 1,
        hintStyle: (style ?? TS.body())
            .copyWith(color: AppColors.fg4, overflow: TextOverflow.ellipsis),
      );

  bool _compact(double width, String draft) {
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
  Widget build(BuildContext context) {
    final pill = ComposerPillSurface(
      highlight: highlight,
      child: LayoutBuilder(
        builder: (context, box) => ValueListenableBuilder<TextEditingValue>(
          valueListenable: text ?? ValueNotifier(TextEditingValue.empty),
          builder: (context, v, _) {
            final compact = _compact(box.maxWidth, v.text);
            Widget inSlot(Widget w) =>
                SizedBox(height: C7.btn, child: Center(child: w));
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (banner != null)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(8, 4, 8, 2),
                    child: banner!,
                  ),
                Row(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    if (attach != null) inSlot(attach!),
                    Expanded(
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: C7.btn),
                        child: Align(
                            alignment: Alignment.centerLeft, child: field),
                      ),
                    ),
                    if (trailing != null) inSlot(trailing!(compact)),
                    if (mic != null) inSlot(mic!),
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
    return highlight
        ? pill
        : Tactile(radius: BorderRadius.circular(radius), child: pill);
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
              child: AppIcon(icon, size: 22, color: color ?? AppColors.fg2)),
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
    final fill = !enabled
        ? C7.rowHi
        : stop
            ? AppColors.fg1
            : AppColors.accentFill;
    final ink = !enabled
        ? AppColors.fg4
        : stop
            ? AppColors.bg
            : AppColors.accentFg;
    const ShapeBorder shape = CircleBorder();
    return Material(
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
          dimension: C7.btn,
          child: Center(
            child: sending
                ? Spinner(size: 16, color: ink)
                : AppIcon(stop ? 'stop' : 'arrow-up',
                    size: stop ? 14 : 19, color: ink),
          ),
        ),
      ),
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
        color: selected ? AppColors.accentBg : Colors.transparent,
        borderRadius: BorderRadius.circular(16),
        child: InkWell(
          onTap: () {
            pickHaptic();
            onTap();
          },
          borderRadius: BorderRadius.circular(16),
          child: Container(
            height: 32,
            padding: EdgeInsets.fromLTRB(compact ? S.s8 : (kMobile ? S.of(9) : S.s8), 0,
                compact ? S.s8 : (onClear == null ? (kMobile ? S.s8 : S.of(7)) : S.s4), 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AppIcon(icon,
                    size: 15,
                    color: selected ? AppColors.accent : AppColors.fg3),
                if (!compact) SizedBox(width: S.s6),
                if (!compact)
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: kMobile ? 110 : 140),
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
                      size: 22, iconSize: 12, tooltip: 'Clear', onTap: onClear)
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
      );
}
