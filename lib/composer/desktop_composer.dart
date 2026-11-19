import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../desk_attention.dart';
import '../theme.dart';
import '../widgets.dart';

/// Desktop composer surfaces: one calm card, pinned cards above it. The phone
/// keeps the pill in composer_card.dart.
const double _kCardRadius = 8;

/// Hairline at rest, one step up on mouse focus, an accent ring only for
/// keyboard focus; the border is always 1px so nothing shifts.
BoxDecoration _cardDecoration(
        {bool focus = false, bool keyboard = false, bool hairline = true}) =>
    BoxDecoration(
      color: AppColors.surface2,
      borderRadius: BorderRadius.circular(R.of(_kCardRadius)),
      border: hairline
          ? Border.all(
              color: keyboard && focus
                  ? AppColors.accent
                  : AppColors.fg1.withValues(alpha: focus ? 0.11 : 0.07))
          : null,
    );

/// Small hover-aware square or pill button used across the desktop cards.
class DeskButton extends StatefulWidget {
  const DeskButton({
    super.key,
    required this.child,
    required this.onTap,
    this.fill,
    this.hoverFill,
    this.size,
    this.height = 28,
    this.padding = EdgeInsets.zero,
    this.border,
    this.tooltip,
    this.radius,
  });

  final Widget child;

  /// Corner radius; null keeps the small default.
  final double? radius;
  final VoidCallback? onTap;
  final Color? fill;
  final Color? hoverFill;
  final double? size;
  final double height;
  final EdgeInsets padding;
  final BorderSide? border;
  final String? tooltip;

  @override
  State<DeskButton> createState() => _DeskButtonState();
}

class _DeskButtonState extends State<DeskButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final on = widget.onTap != null;
    final base = widget.fill ?? Colors.transparent;
    final bg = on && _hover ? (widget.hoverFill ?? AppColors.surface3) : base;
    Widget w = MouseRegion(
      cursor: on ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          width: widget.size,
          height: widget.size ?? widget.height,
          padding: widget.padding,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(widget.radius ?? R.of(6)),
            border: widget.border == null
                ? null
                : Border.fromBorderSide(widget.border!),
          ),
          child: widget.child,
        ),
      ),
    );
    if (widget.tooltip != null) w = Tooltip(message: widget.tooltip!, child: w);
    return w;
  }
}

/// Bare icon button: 28px, muted icon.
class DeskIconButton extends StatelessWidget {
  const DeskIconButton(this.icon,
      {super.key,
      required this.tooltip,
      required this.onTap,
      this.size = 28,
      this.iconSize = 15,
      this.color});

  final String icon;
  final String tooltip;
  final VoidCallback? onTap;
  final double size;
  final double iconSize;
  final Color? color;

  @override
  Widget build(BuildContext context) => DeskButton(
        size: size,
        tooltip: tooltip,
        onTap: onTap,
        child: AppIcon(icon, size: iconSize, color: color ?? AppColors.fg3),
      );
}

/// 28px square action: send (light fill, grey when off) or stop (soft fill).
class DeskActionButton extends StatelessWidget {
  const DeskActionButton({
    super.key,
    required this.icon,
    required this.onTap,
    required this.tooltip,
    this.on = true,
    this.soft = false,
    this.danger = false,
    this.busy = false,
  });

  final String icon;
  final VoidCallback? onTap;
  final String tooltip;
  final bool on;
  final bool soft;
  final bool danger;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final Color fill;
    final Color ink;
    if (danger) {
      fill = AppColors.dangerBg;
      ink = AppColors.danger;
    } else if (soft) {
      fill = AppColors.fg1.withValues(alpha: 0.11);
      ink = AppColors.fg1;
    } else if (on) {
      fill = AppColors.accentFill;
      ink = AppColors.accentFg;
    } else {
      fill = AppColors.fg1.withValues(alpha: 0.07);
      ink = AppColors.fg4;
    }
    return DeskButton(
      size: 28,
      radius: R.of(6),
      fill: fill,
      hoverFill: on || soft || danger ? fill.withValues(alpha: 0.85) : fill,
      tooltip: tooltip,
      onTap: on || soft || danger ? onTap : null,
      child: busy
          ? Spinner(size: 14, color: ink)
          : AppIcon(icon, size: icon == 'stop' ? 13 : 15, color: ink),
    );
  }
}

/// Key cap, e.g. the Enter hint beside a label.
class DeskKbd extends StatelessWidget {
  const DeskKbd(this.label, {super.key, this.color});
  final String label;
  final Color? color;

  @override
  Widget build(BuildContext context) => Container(
        height: 16,
        padding: const EdgeInsets.symmetric(horizontal: 4),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: AppColors.lineStrong),
        ),
        child: Text(label, style: mono(10.5, color: color ?? AppColors.fg4)),
      );
}

/// The key hints that show beside the send button while typing.
class DeskHint extends StatelessWidget {
  const DeskHint(this.parts, {super.key});

  /// Alternating key and label: `[('↵', 'queue'), ('⌘↵', 'interrupt')]`.
  final List<(String, String)> parts;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(right: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          for (var i = 0; i < parts.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            DeskKbd(parts[i].$1),
            const SizedBox(width: 6),
            Text(parts[i].$2, style: sans(11.5, color: AppColors.fg4)),
          ],
        ]),
      );
}

/// The composer card: [banner] and [attachments] above the text, then a
/// toolbar row with attach and the model chip on the left, hints, mic and
/// the action on the right.
class DeskComposerCard extends StatelessWidget {
  const DeskComposerCard({
    super.key,
    required this.field,
    required this.action,
    this.banner,
    this.attachments,
    this.attach,
    this.model,
    this.cold,
    this.hint,
    this.mic,
    this.focus,
    this.highlight = false,
    this.attentionExclude,
  });

  final Widget field;
  final Widget action;
  final Widget? banner;
  final Widget? attachments;
  final Widget? attach;
  final Widget? model;

  /// Cold-cache chip, after the model chip.
  final Widget? cold;
  final Widget? hint;
  final Widget? mic;
  final FocusNode? focus;
  final bool highlight;

  /// The session on screen, left out of the attention bar.
  final String? attentionExclude;

  static TextStyle get fieldStyle =>
      sans(13.5, height: 22 / 13.5, color: AppColors.fg1);

  static InputDecoration decoration(String hint) => InputDecoration(
        isCollapsed: true,
        contentPadding: EdgeInsets.zero,
        border: InputBorder.none,
        hintText: hint,
        hintMaxLines: 1,
        hintStyle: fieldStyle.copyWith(
            color: AppColors.fg4, overflow: TextOverflow.ellipsis),
      );

  @override
  Widget build(BuildContext context) {
    Widget card(bool focused) => Container(
          padding: const EdgeInsets.fromLTRB(12, 11, 6, 6),
          // Typing flips Flutter into keyboard mode, so a focus ring here
          // would show whenever you write; focus stays a faint hairline.
          decoration: _cardDecoration(hairline: false),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (banner != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Align(alignment: Alignment.centerLeft, child: banner),
                ),
              if (attachments != null) attachments!,
              Padding(
                padding: const EdgeInsets.fromLTRB(0, 0, 6, 4),
                child: field,
              ),
              Row(children: [
                Transform.translate(
                  offset: const Offset(-6, 0),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    if (attach != null) attach!,
                    if (model != null) ...[const SizedBox(width: 2), model!],
                    if (cold != null) ...[const SizedBox(width: 4), cold!],
                  ]),
                ),
                const Spacer(),
                if (hint != null) hint!,
                if (mic != null) ...[mic!, const SizedBox(width: 2)],
                action,
              ]),
            ],
          ),
        );
    // One flat card, no tray or outline around it.
    Widget body(bool focused) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DeskAttentionBar(exclude: attentionExclude),
            card(focused),
          ],
        );
    if (focus == null) return body(false);
    return ListenableBuilder(
      listenable: focus!,
      builder: (_, __) => body(focus!.hasFocus),
    );
  }
}

/// Model chip: provider mark, label and chevron, 28px.
class DeskModelChip extends StatelessWidget {
  const DeskModelChip(
      {super.key,
      required this.icon,
      required this.label,
      required this.onTap});

  final String icon;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => DeskButton(
        onTap: onTap,
        tooltip: 'Model',
        hoverFill: AppColors.fg1.withValues(alpha: 0.07),
        padding: const EdgeInsets.symmetric(horizontal: 8),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AppIcon(icon, size: 14, color: AppColors.fg2),
          const SizedBox(width: 6),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 180),
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(12.5, color: AppColors.fg2)),
          ),
          const SizedBox(width: 4),
          AppIcon('chevron-down', size: 12, color: AppColors.fg4),
        ]),
      );
}

/// Recipient chip above the text: tinted, with a clear button.
class DeskRecipientChip extends StatelessWidget {
  const DeskRecipientChip(
      {super.key,
      required this.leading,
      required this.label,
      required this.onTap,
      required this.onClear});

  final Widget leading;
  final String label;
  final VoidCallback onTap;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) => Container(
        height: 24,
        padding: const EdgeInsets.fromLTRB(4, 0, 6, 0),
        decoration: BoxDecoration(
          color: AppColors.accentBg,
          borderRadius: BorderRadius.circular(R.of(6)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          GestureDetector(
            onTap: onTap,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                leading,
                const SizedBox(width: 6),
                Text(label, style: sans(12, color: AppColors.accent)),
              ]),
            ),
          ),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: onClear,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: AppIcon('x', size: 11, color: AppColors.accent),
            ),
          ),
        ]),
      );
}

/// One held message in [DeskQueueCard].
class DeskQueueEntry {
  const DeskQueueEntry({
    required this.label,
    required this.onSendNow,
    required this.onEdit,
    required this.onRemove,
    this.muted = false,
    this.lead,
    this.extra,
  });

  final String label;
  final bool muted;
  final Widget? lead;
  final Widget? extra;
  final VoidCallback onSendNow;
  final VoidCallback onEdit;
  final VoidCallback onRemove;
}

/// Held messages above the composer: header with Clear / Send all now, then
/// one soft row per message with send now, edit and remove.
class DeskQueueCard extends StatelessWidget {
  const DeskQueueCard({
    super.key,
    required this.entries,
    required this.onClear,
    required this.onSendAll,
    this.maxHeight = 176,
  });

  final List<DeskQueueEntry> entries;
  final VoidCallback onClear;
  final VoidCallback onSendAll;
  final double maxHeight;

  // Soft rows tucked on top of the composer card, inset from its sides.
  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final many = entries.length > 1;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 14),
      child: ClipRRect(
        borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (many)
              Container(
                height: 32,
                color: AppColors.surface2,
                margin: const EdgeInsets.only(bottom: 2),
                padding: const EdgeInsets.fromLTRB(12, 0, 6, 0),
                child: Row(children: [
                  Expanded(
                    child: Text('${entries.length} queued, sent in order',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: sans(12, color: AppColors.fg4)),
                  ),
                  _textBtn('Clear', onClear),
                  _textBtn('Send all now', onSendAll),
                ]),
              ),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: maxHeight),
              child: SingleChildScrollView(
                reverse: true,
                child: Column(mainAxisSize: MainAxisSize.min, children: [
                  for (var i = 0; i < entries.length; i++) _row(i, entries[i]),
                ]),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _textBtn(String label, VoidCallback onTap) => DeskButton(
        height: 26,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        onTap: onTap,
        child: Text(label, style: sans(12, color: AppColors.fg3)),
      );

  Widget _row(int i, DeskQueueEntry e) => Container(
        constraints: const BoxConstraints(minHeight: 38),
        margin: const EdgeInsets.only(bottom: 2),
        padding: const EdgeInsets.fromLTRB(12, 0, 6, 0),
        color: AppColors.surface2,
        child: Row(children: [
          SizedBox(
            width: 16,
            child: Text('${i + 1}', style: mono(11, color: AppColors.fg4)),
          ),
          const SizedBox(width: 6),
          if (e.lead != null) ...[e.lead!, const SizedBox(width: 6)],
          Expanded(
            child: Text(e.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style:
                    sans(13, color: e.muted ? AppColors.fg4 : AppColors.fg2)),
          ),
          if (e.extra != null) ...[const SizedBox(width: 8), e.extra!],
          const SizedBox(width: 6),
          Tooltip(
              message: 'Interrupt and send',
              child: _textBtn('Send now', e.onSendNow)),
          _textBtn('Edit', e.onEdit),
          DeskIconButton('x',
              tooltip: 'Remove', onTap: e.onRemove, iconSize: 12),
        ]),
      );
}

/// The voice-note card: timer and wave replace the toolbar.
class DeskVoiceCard extends StatelessWidget {
  const DeskVoiceCard({
    super.key,
    required this.recording,
    required this.sending,
    required this.playing,
    required this.label,
    required this.time,
    required this.wave,
    required this.onDiscard,
    required this.onPlay,
    required this.onStop,
    required this.onSend,
    this.onMore,
  });

  final bool recording;
  final bool sending;
  final bool playing;
  final String label;
  final String time;
  final Widget wave;
  final VoidCallback onDiscard;
  final VoidCallback onPlay;
  final VoidCallback onStop;
  final VoidCallback onSend;
  final VoidCallback? onMore;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 10, 10),
        decoration: _cardDecoration(focus: true),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(label, style: sans(12.5, color: AppColors.fg4)),
            ),
            Row(children: [
              if (recording)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: AppColors.danger,
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(color: AppColors.dangerBg, spreadRadius: 4)
                    ],
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: DeskIconButton(playing ? 'pause' : 'play',
                      tooltip: playing ? 'Pause' : 'Play', onTap: onPlay),
                ),
              Text(time, style: mono(12, color: AppColors.fg2)),
              const SizedBox(width: 12),
              Expanded(child: SizedBox(height: 28, child: wave)),
              const SizedBox(width: 10),
              if (onMore != null)
                DeskButton(
                  padding: const EdgeInsets.symmetric(horizontal: 10),
                  onTap: onMore,
                  child:
                      Text('Add more', style: sans(12.5, color: AppColors.fg3)),
                ),
              DeskButton(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                onTap: onDiscard,
                child: Text('Cancel', style: sans(12.5, color: AppColors.fg3)),
              ),
              const SizedBox(width: 10),
              if (recording) ...[
                DeskActionButton(
                    icon: 'stop',
                    tooltip: 'Stop recording',
                    danger: true,
                    onTap: onStop),
                const SizedBox(width: 10),
              ],
              DeskActionButton(
                  icon: 'arrow-up',
                  tooltip: 'Send',
                  busy: sending,
                  onTap: sending ? null : onSend),
            ]),
          ],
        ),
      );
}

/// Frame for the cards pinned above the composer (approval, question).
class DeskPinCard extends StatelessWidget {
  const DeskPinCard({
    super.key,
    required this.icon,
    required this.iconColor,
    required this.eyebrow,
    required this.children,
    this.trailing,
  });

  final String icon;
  final Color iconColor;
  final String eyebrow;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Container(
        margin: const EdgeInsets.only(bottom: 8),
        decoration: _cardDecoration(hairline: false),
        clipBehavior: Clip.antiAlias,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 0),
              child: Row(children: [
                AppIcon(icon, size: 13, color: iconColor),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(eyebrow,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(12, color: AppColors.fg3)),
                ),
                if (trailing != null) trailing!,
              ]),
            ),
            // The body scrolls inside the bar's height cap; the action bar stays put.
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final c in children)
                      if (c is! DeskPinBar) c,
                  ],
                ),
              ),
            ),
            for (final c in children)
              if (c is DeskPinBar) c,
          ],
        ),
      );
}

class DeskPinTitle extends StatelessWidget {
  const DeskPinTitle(this.title, {super.key, this.why});
  final String title;
  final String? why;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 14, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: sans(14, weight: FontWeight.w600, color: AppColors.fg1)),
            if (why != null && why!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 2),
                child: Text(why!,
                    style: sans(13, height: 1.45, color: AppColors.fg3)),
              ),
          ],
        ),
      );
}

/// Bottom row of a pinned card: [left] fills, then buttons.
class DeskPinBar extends StatelessWidget {
  const DeskPinBar({super.key, this.left, required this.buttons});
  final Widget? left;
  final List<Widget> buttons;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        child: Row(children: [
          Expanded(child: left ?? const SizedBox.shrink()),
          for (var i = 0; i < buttons.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            buttons[i],
          ],
        ]),
      );
}

enum DeskBtnKind { primary, outline, ghost }

/// 28px text button for pinned cards; [kbd] draws the key cap after the label.
class DeskTextButton extends StatelessWidget {
  const DeskTextButton(this.label,
      {super.key,
      required this.onTap,
      this.kind = DeskBtnKind.outline,
      this.kbd,
      this.busy = false});

  final String label;
  final VoidCallback? onTap;
  final DeskBtnKind kind;
  final String? kbd;
  final bool busy;

  @override
  Widget build(BuildContext context) {
    final primary = kind == DeskBtnKind.primary;
    final ink = primary
        ? AppColors.bg
        : kind == DeskBtnKind.ghost
            ? AppColors.fg3
            : AppColors.fg2;
    return DeskButton(
      height: 28,
      onTap: busy ? null : onTap,
      fill: primary ? AppColors.fg1 : Colors.transparent,
      hoverFill:
          primary ? AppColors.fg1.withValues(alpha: 0.88) : AppColors.surface3,
      border: kind == DeskBtnKind.outline
          ? BorderSide(color: AppColors.lineStrong)
          : null,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (busy) ...[Spinner(size: 12, color: ink), const SizedBox(width: 6)],
        Text(label,
            style: sans(12.5,
                weight: primary ? FontWeight.w600 : null, color: ink)),
        if (kbd != null) ...[
          const SizedBox(width: 6),
          DeskKbd(kbd!, color: primary ? AppColors.fg4 : null),
        ],
      ]),
    );
  }
}

/// Square checkbox with a label, for "Always allow ...".
class DeskCheck extends StatelessWidget {
  const DeskCheck(
      {super.key,
      required this.checked,
      required this.label,
      required this.onTap});
  final bool checked;
  final String label;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: checked ? AppColors.fg1 : Colors.transparent,
                borderRadius: BorderRadius.circular(4),
                border: Border.all(
                    color: checked ? AppColors.fg1 : AppColors.fg4, width: 1.5),
              ),
              child: checked
                  ? AppIcon('check', size: 10, color: AppColors.bg)
                  : null,
            ),
            const SizedBox(width: 8),
            Flexible(
              child: Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12.5, color: AppColors.fg3)),
            ),
          ]),
        ),
      );
}

/// Numbered answer row of the question card.
class DeskOption extends StatelessWidget {
  const DeskOption({
    super.key,
    required this.keyLabel,
    required this.label,
    required this.selected,
    required this.onTap,
    this.detail,
    this.dashed = false,
    this.muted = false,
    this.icon,
  });

  final String keyLabel;
  final String label;
  final String? detail;
  final bool selected;
  final bool dashed;
  final bool muted;
  final String? icon;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: Container(
            margin: const EdgeInsets.symmetric(horizontal: 8),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            decoration: BoxDecoration(
              color: selected ? AppColors.surface2 : Colors.transparent,
              borderRadius: BorderRadius.circular(R.of(8)),
            ),
            child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Container(
                width: 20,
                height: 20,
                margin: const EdgeInsets.only(top: 1),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: selected ? AppColors.fg1 : Colors.transparent,
                  borderRadius: BorderRadius.circular(5),
                  border: Border.all(
                      color: selected ? AppColors.fg1 : AppColors.lineStrong),
                ),
                child: icon != null
                    ? AppIcon(icon!, size: 11, color: AppColors.fg3)
                    : Text(keyLabel,
                        style: mono(11,
                            color: selected ? AppColors.bg : AppColors.fg3)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(label,
                        style: sans(13.5,
                            color: muted ? AppColors.fg3 : AppColors.fg1)),
                    if (detail != null && detail!.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(top: 1),
                        child: Text(detail!,
                            style: sans(12, color: AppColors.fg4)),
                      ),
                  ],
                ),
              ),
            ]),
          ),
        ),
      );
}

/// "1 of 2" with the progress dashes.
class DeskSteps extends StatelessWidget {
  const DeskSteps({super.key, required this.index, required this.total});
  final int index;
  final int total;

  @override
  Widget build(BuildContext context) =>
      Row(mainAxisSize: MainAxisSize.min, children: [
        Text('${index + 1} of $total', style: sans(12, color: AppColors.fg4)),
        const SizedBox(width: 8),
        for (var i = 0; i < total; i++)
          Container(
            width: 14,
            height: 3,
            margin: EdgeInsets.only(left: i == 0 ? 0 : 4),
            decoration: BoxDecoration(
              color: i == index ? AppColors.fg2 : AppColors.surface3,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
      ]);
}

/// True when a text field has the primary focus, so a global Enter does not
/// steal typing.
bool deskTypingFocused() {
  final ctx = FocusManager.instance.primaryFocus?.context;
  if (ctx == null) return false;
  return ctx.widget is EditableText ||
      ctx.findAncestorWidgetOfExactType<EditableText>() != null;
}

bool deskPlainEnter(KeyEvent e) =>
    e is KeyDownEvent &&
    (e.logicalKey == LogicalKeyboardKey.enter ||
        e.logicalKey == LogicalKeyboardKey.numpadEnter) &&
    !HardwareKeyboard.instance.isMetaPressed &&
    !HardwareKeyboard.instance.isControlPressed &&
    !HardwareKeyboard.instance.isShiftPressed &&
    !HardwareKeyboard.instance.isAltPressed;
