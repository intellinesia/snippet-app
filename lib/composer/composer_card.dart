import 'package:flutter/foundation.dart';
import '../desktop_look.dart';
import 'package:flutter/material.dart';

import '../glass.dart';
import '../platform.dart';
import '../theme.dart';
import '../widgets.dart';

/// The one composer surface: a single row, attach | field | trailing controls.
/// The field grows upward and the controls stay on the last line.
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

  static double get radius => kMobile ? 20 : 16;

  static EdgeInsets get _padding => kMobile
      ? const EdgeInsets.fromLTRB(6, 6, 6, 6)
      : const EdgeInsets.fromLTRB(6, 5, 6, 5);

  static InputDecoration decoration(String hint) => InputDecoration(
        isCollapsed: true,
        // One line fills the button slot exactly, so the controls sit centred.
        contentPadding:
            EdgeInsets.fromLTRB(4, kMobile ? 6 : 5, 4, kMobile ? 6 : 5),
        border: InputBorder.none,
        hintText: hint,
        hintMaxLines: 1,
        hintStyle: TS.body(AppColors.fg4)
            .copyWith(overflow: TextOverflow.ellipsis),
      );

  bool _compact(double width, String draft) {
    if (width < 380) return true;
    if (draft.isEmpty || draft.contains('\n')) return false;
    final p = TextPainter(
      text: TextSpan(text: draft, style: TS.body(AppColors.fg1)),
      textDirection: TextDirection.ltr,
      maxLines: 1,
    )..layout();
    return p.width > width - 300;
  }

  @override
  Widget build(BuildContext context) {
    final card = Glass(
      radius: BorderRadius.circular(radius),
      tint: AppColors.surface1.withValues(alpha: 0.78),
      border: !highlight,
      child: Container(
        padding: _padding,
        child: LayoutBuilder(
          builder: (context, box) => ValueListenableBuilder<TextEditingValue>(
            valueListenable: text ?? ValueNotifier(TextEditingValue.empty),
            builder: (context, v, _) {
              final compact = _compact(box.maxWidth, v.text);
              final slot = kMobile ? 36.0 : 32.0;
              Widget inSlot(Widget w) =>
                  SizedBox(height: slot, child: Center(child: w));
              return Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (banner != null) banner!,
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      if (attach != null) inSlot(attach!),
                      Expanded(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(minHeight: slot),
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
      ),
    );
    if (!highlight) {
      return Tactile(radius: BorderRadius.circular(radius), child: card);
    }
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(radius),
        border: Border.all(color: AppColors.accent, width: 1.5),
      ),
      child: card,
    );
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
      borderRadius: BorderRadius.circular(R.sm),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(R.sm),
        child: SizedBox.square(
          dimension: kMobile ? 34 : 30,
          child: Center(
              child: AppIcon(icon,
                  size: kMobile ? 18 : 17, color: color ?? AppColors.fg3)),
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
        ? AppColors.hover
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
        onTap: onTap,
        child: SizedBox.square(
          dimension: kMobile ? 36 : 32,
          child: Center(
            child: sending
                ? Spinner(size: 14, color: ink)
                : AppIcon(stop ? 'stop' : 'arrow-up',
                    size: stop ? 13 : 16, color: ink),
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
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(9),
          child: Container(
            height: 28,
            padding: EdgeInsets.fromLTRB(compact ? 8 : (kMobile ? 9 : 8), 0,
                compact ? 8 : (onClear == null ? (kMobile ? 8 : 7) : 4), 0),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AppIcon(icon,
                    size: 13.5,
                    color: selected ? AppColors.accent : AppColors.fg3),
                if (!compact) const SizedBox(width: 6),
                if (!compact)
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: kMobile ? 110 : 140),
                    child: Text(label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(12,
                            color:
                                selected ? AppColors.accent : AppColors.fg3)),
                  ),
                if (compact)
                  const SizedBox.shrink()
                else if (onClear != null)
                  IconBtn('x',
                      size: 22, iconSize: 12, tooltip: 'Clear', onTap: onClear)
                else ...[
                  const SizedBox(width: 5),
                  AppIcon('chevron-down',
                      size: 12,
                      color: selected ? AppColors.accent : AppColors.fg4),
                ],
              ],
            ),
          ),
        ),
      );
}
