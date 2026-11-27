import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../desk_attention.dart';
import '../theme.dart';
import '../widgets.dart';
import '../tap_detector.dart';
import 'slash_menu.dart';

/// Desktop composer surfaces: one calm card, pinned cards above it. The phone
/// keeps the pill in composer_card.dart.
const double _kCardRadius = 12;

/// Flat s1 composer surface. Focus is carried by the text caret only; the
/// card never grows a focus ring.
BoxDecoration _cardDecoration(
        {bool focus = false, bool hairline = true, double? radius}) =>
    BoxDecoration(
      color: AppColors.surface1,
      borderRadius: BorderRadius.circular(R.of(radius ?? _kCardRadius)),
      border: Border.all(
          color: hairline ? AppColors.line : Colors.transparent,
          width: AppColors.hairline),
    );

String deskEffortLabel(String effort) => switch (effort) {
      'low' => 'Low',
      'medium' => 'Medium',
      'high' => 'High',
      'xhigh' => 'X-High',
      _ => effort,
    };

/// A 28-high hit target whose visible chip is the locked 26-high tonal plate.
class DeskTonalChip extends StatefulWidget {
  const DeskTonalChip({
    super.key,
    required this.child,
    required this.onTap,
    this.tooltip,
  });

  final Widget child;
  final VoidCallback? onTap;
  final String? tooltip;

  @override
  State<DeskTonalChip> createState() => _DeskTonalChipState();
}

class _DeskTonalChipState extends State<DeskTonalChip> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final on = widget.onTap != null;
    Widget w = MouseRegion(
      cursor: on ? SystemMouseCursors.click : MouseCursor.defer,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: SizedBox(
          height: 28,
          child: Center(
            child: Container(
              height: 26,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: on && _hover ? AppColors.surface3 : AppColors.surface2,
                borderRadius: BorderRadius.circular(R.of(6)),
              ),
              child: widget.child,
            ),
          ),
        ),
      ),
    );
    if (widget.tooltip != null) w = Tooltip(message: widget.tooltip!, child: w);
    return w;
  }
}

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
      child: TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: widget.onTap,
        child: Container(
          width: widget.size,
          height: widget.size ?? widget.height,
          padding: widget.padding,
          // A bare alignment would stretch a sizeless button to the full row.
          alignment: widget.size == null ? null : Alignment.center,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(widget.radius ?? R.of(6)),
            border: widget.border == null
                ? null
                : Border.fromBorderSide(widget.border!),
          ),
          child: widget.size == null
              ? Align(widthFactor: 1, child: widget.child)
              : widget.child,
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

/// 28px square action in the quiet tonal language; state is the icon and
/// enabled/disabled ink, never a bright plate.
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
    if (icon == 'arrow-up' || icon == 'mic' || icon == 'stop') {
      fill = AppColors.accent;
      // Ink its blue action black; a dark accent (quiet-light) needs its own ink.
      ink = AppColors.accent.computeLuminance() > 0.18
          ? const Color(0xFF000000)
          : AppColors.accentFg;
    } else if (on || soft || danger) {
      fill = AppColors.surface3;
      ink = AppColors.fg1;
    } else {
      fill = AppColors.surface3;
      ink = AppColors.fg3;
    }
    return DeskButton(
      size: 26,
      radius: R.of(7),
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

// ChatComposer builds this leaf before the card, so only the leaf is rebuilt.
Widget _desktopComposerField(Widget child) {
  if (child is CallbackShortcuts) {
    return CallbackShortcuts(
      key: child.key,
      bindings: child.bindings,
      child: _desktopComposerField(child.child),
    );
  }
  if (child is SlashKeys) {
    return SlashKeys(
      key: child.key,
      controller: child.controller,
      child: _desktopComposerField(child.child),
    );
  }
  if (child is! TextField || child.maxLines != 4) return child;
  return TextField(
    key: child.key,
    controller: child.controller,
    focusNode: child.focusNode,
    contentInsertionConfiguration: child.contentInsertionConfiguration,
    minLines: child.minLines,
    maxLines: 8,
    cursorWidth: child.cursorWidth,
    cursorColor: child.cursorColor,
    onChanged: child.onChanged,
    onSubmitted: child.onSubmitted,
    style: child.style,
    decoration: child.decoration,
    keyboardType: child.keyboardType,
    textInputAction: child.textInputAction,
    strutStyle: child.strutStyle,
    textAlignVertical: child.textAlignVertical,
    enabled: child.enabled,
  );
}

/// Session metadata rendered under the desktop composer when a host supplies it.
class DeskComposerMeta extends InheritedWidget {
  const DeskComposerMeta({
    super.key,
    required super.child,
    this.machine = '',
    this.project = '',
    this.branch = '',
    this.online = false,
  });

  final String machine;
  final String project;
  final String branch;
  final bool online;

  bool get hasParts =>
      machine.trim().isNotEmpty ||
      project.trim().isNotEmpty ||
      branch.trim().isNotEmpty;

  static DeskComposerMeta? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<DeskComposerMeta>();

  @override
  bool updateShouldNotify(DeskComposerMeta old) =>
      machine != old.machine ||
      project != old.project ||
      branch != old.branch ||
      online != old.online;
}

/// The quiet machine, project and branch line under the desktop composer.
class DeskMachineLine extends StatelessWidget {
  const DeskMachineLine({super.key, this.meta, this.trailing});

  final DeskComposerMeta? meta;

  /// Right-aligned, e.g. context usage.
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final meta = this.meta;
    final parts = meta == null
        ? ''
        : [
            meta.machine.trim(),
            meta.project.trim(),
            meta.branch.trim(),
          ].where((p) => p.isNotEmpty).join(' · ');
    if (parts.isEmpty && trailing == null) return const SizedBox.shrink();
    return Padding(
      // Aligned with the card's content.
      padding: const EdgeInsets.fromLTRB(12, 8, 6, 0),
      child: Row(children: [
        Expanded(
            child: Row(children: [
          if (parts.isNotEmpty) ...[
            AppIcon('laptop', size: 13, color: AppColors.fg3),
            const SizedBox(width: 7),
            Flexible(
              child: Text(parts,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(12, height: 16 / 12, color: AppColors.fg3)),
            ),
            if (meta!.online) ...[
              const SizedBox(width: 7),
              Container(
                width: 5,
                height: 5,
                decoration:
                    BoxDecoration(shape: BoxShape.circle, color: AppColors.ok),
              ),
            ],
          ],
        ])),
        if (trailing != null) trailing!,
      ]),
    );
  }
}

/// The composer card: attachments and quiet status sit outside it; inside are
/// The text, then a toolbar with attach, model and chips left, mic/action right.
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
    this.recipient,
    this.usage,
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

  /// Context usage, at the right of the line under the card.
  final Widget? usage;

  /// Cold-cache chip, after the model chip.
  final Widget? cold;
  final Widget? hint;
  final Widget? mic;

  /// Recipient label or chip immediately left of the send/stop button.
  final Widget? recipient;
  final FocusNode? focus;
  final bool highlight;

  /// The session on screen, left out of the attention bar.
  final String? attentionExclude;

  static TextStyle get fieldStyle =>
      sans(13, height: 19 / 13, color: AppColors.fg1);

  static Color get hintColor => AppColors.fg4.withValues(alpha: 0.5);

  static InputDecoration decoration(String hint) => InputDecoration(
        isCollapsed: true,
        contentPadding: EdgeInsets.zero,
        border: InputBorder.none,
        hintText: hint,
        hintMaxLines: 1,
        // The placeholder sits far back, near the card's edge tone.
        hintStyle: fieldStyle.copyWith(
            color: hintColor, overflow: TextOverflow.ellipsis),
      );

  @override
  Widget build(BuildContext context) {
    Widget card(bool focused) => Container(
          padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
          decoration: _cardDecoration(
              focus: focused || highlight, hairline: true, radius: 10),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (banner != null)
                Padding(
                  padding: const EdgeInsets.only(bottom: 8),
                  child: Align(alignment: Alignment.centerLeft, child: banner),
                ),
              _desktopComposerField(field),
              const SizedBox(height: 10),
              SizedBox(
                height: 28,
                child: Row(children: [
                  if (attach != null) ...[attach!, const SizedBox(width: 8)],
                  Expanded(
                    child: Row(children: [
                      if (model != null)
                        Flexible(fit: FlexFit.loose, child: model!),
                      if (cold != null) ...[
                        const SizedBox(width: 8),
                        Flexible(fit: FlexFit.loose, child: cold!),
                      ],
                      if (hint != null) ...[
                        const SizedBox(width: 8),
                        Flexible(fit: FlexFit.loose, child: hint!),
                      ],
                      if (recipient != null) ...[
                        const SizedBox(width: 8),
                        Flexible(fit: FlexFit.loose, child: recipient!),
                      ],
                    ]),
                  ),
                  if (mic != null) ...[mic!, const SizedBox(width: 2)],
                  action,
                ]),
              ),
            ],
          ),
        );
    final meta = DeskComposerMeta.maybeOf(context);
    Widget body(bool focused) => Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DeskAttentionBar(exclude: attentionExclude),
            if (attachments != null)
              Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: attachments!,
              ),
            card(focused),
            if ((meta != null && meta.hasParts) || usage != null)
              DeskMachineLine(
                  meta: meta != null && meta.hasParts ? meta : null,
                  trailing: usage),
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
      this.icon,
      required this.label,
      required this.onTap,
      this.effort});

  final String? icon;
  final String label;
  final String? effort;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => DeskButton(
        onTap: onTap,
        tooltip: 'Model',
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          if ((icon ?? '').isNotEmpty) ...[
            AppIcon(icon!, size: 12, color: AppColors.accent),
            const SizedBox(width: 5),
          ],
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 150),
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(12, height: 16 / 12, color: AppColors.fg3)),
          ),
          if ((effort ?? '').trim().isNotEmpty) ...[
            const SizedBox(width: 5),
            Text(effort!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(12, height: 16 / 12, color: AppColors.fg4)),
          ],
          const SizedBox(width: 3),
          AppIcon('chevron-down', size: 11, color: AppColors.fg4),
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
        height: 26,
        padding: const EdgeInsets.fromLTRB(5, 0, 5, 0),
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(R.of(6)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          TapDetector(
            onTap: onTap,
            child: MouseRegion(
              cursor: SystemMouseCursors.click,
              child: Row(mainAxisSize: MainAxisSize.min, children: [
                leading,
                const SizedBox(width: 5),
                ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 160),
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(11,
                          weight: FontWeight.w500,
                          height: 15 / 11,
                          color: AppColors.fg2)),
                ),
              ]),
            ),
          ),
          const SizedBox(width: 4),
          SizedBox(
            width: 24,
            height: 24,
            child: TapDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onClear,
              child: MouseRegion(
                cursor: SystemMouseCursors.click,
                child:
                    Center(child: AppIcon('x', size: 11, color: AppColors.fg3)),
              ),
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

  // One compact s1 strip: a single summary line only when several are held,
  // then one dense row per message.
  @override
  Widget build(BuildContext context) {
    if (entries.isEmpty) return const SizedBox.shrink();
    final n = entries.length;
    Widget link(String label, VoidCallback onTap, Color ink) => DeskButton(
          height: 22,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          onTap: onTap,
          child: Text(label, style: sans(11.5, height: 15 / 11.5, color: ink)),
        );
    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      padding: const EdgeInsets.fromLTRB(10, 3, 3, 3),
      decoration: BoxDecoration(
        color: AppColors.surface1,
        borderRadius: BorderRadius.circular(R.of(8)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (n > 1)
            SizedBox(
              height: 24,
              child: Row(children: [
                Expanded(
                  child: Text('$n queued, sent in order when this turn ends',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style:
                          sans(11.5, height: 15 / 11.5, color: AppColors.fg3)),
                ),
                link('Clear', onClear, AppColors.fg3),
                link('Send all', onSendAll, AppColors.fg2),
              ]),
            ),
          ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxHeight),
            child: SingleChildScrollView(
              reverse: true,
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                for (var i = 0; i < n; i++) _row(entries[i], single: n == 1),
              ]),
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(DeskQueueEntry e, {required bool single}) => SizedBox(
        height: 26,
        child: Row(children: [
          AppIcon('clock', size: 12, color: AppColors.fg4),
          const SizedBox(width: 8),
          if (e.lead != null) ...[e.lead!, const SizedBox(width: 6)],
          Expanded(
            child: Text(e.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(12,
                    height: 17 / 12,
                    color: e.muted ? AppColors.fg3 : AppColors.fg2)),
          ),
          if (single) ...[
            const SizedBox(width: 8),
            Text('Queued',
                style: sans(11, height: 15 / 11, color: AppColors.fg4)),
            const SizedBox(width: 4),
          ],
          if (e.extra != null) ...[const SizedBox(width: 6), e.extra!],
          DeskIconButton('arrow-up',
              size: 24, tooltip: 'Send now', onTap: e.onSendNow, iconSize: 12),
          DeskIconButton('edit',
              size: 24,
              tooltip: 'Edit queued message',
              onTap: e.onEdit,
              iconSize: 12),
          DeskIconButton('x',
              size: 24,
              tooltip: 'Remove queued message',
              onTap: e.onRemove,
              iconSize: 12),
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
        decoration: _cardDecoration(hairline: false),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Text(label, style: sans(12, color: AppColors.fg2)),
            ),
            Row(children: [
              if (recording)
                Container(
                  width: 8,
                  height: 8,
                  margin: const EdgeInsets.only(right: 12),
                  decoration: BoxDecoration(
                    color: AppColors.fg1,
                    shape: BoxShape.circle,
                  ),
                )
              else
                Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: DeskIconButton(playing ? 'pause' : 'play',
                      tooltip: playing ? 'Pause' : 'Play', onTap: onPlay),
                ),
              Text(time,
                  style: mono(13,
                      weight: FontWeight.w500,
                      height: 18 / 13,
                      color: AppColors.fg1)),
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
                    icon: 'stop', tooltip: 'Stop recording', onTap: onStop),
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
              padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
              child: SizedBox(
                  height: 20,
                  child: Row(children: [
                    AppIcon(icon, size: 14, color: AppColors.fg2),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(eyebrow,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              sans(13, weight: W.label, color: AppColors.fg2)),
                    ),
                    if (trailing != null) trailing!,
                  ])),
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
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title,
                style: sans(14, weight: FontWeight.w600, color: AppColors.fg1)),
            if (why != null && why!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Text(why!,
                    style: sans(13, height: 1.45, color: AppColors.fg2)),
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
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        child: Row(children: [
          for (var i = 0; i < buttons.length; i++) ...[
            if (i > 0) const SizedBox(width: 8),
            buttons[i],
          ],
          const SizedBox(width: 12),
          Expanded(
              child: Align(
                  alignment: Alignment.centerRight,
                  child: left ?? const SizedBox.shrink())),
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
            ? AppColors.fg2
            : AppColors.fg1;
    return DeskButton(
      height: 32,
      onTap: busy ? null : onTap,
      fill: primary ? AppColors.fg1 : Colors.transparent,
      hoverFill: primary
          ? AppColors.fg1.withValues(alpha: 0.88)
          : AppColors.fg1.withValues(alpha: 0.06),
      border:
          kind == DeskBtnKind.outline ? BorderSide(color: AppColors.fg4) : null,
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

String _deskRunningElapsed(DateTime? at) {
  if (at == null) return '';
  final d = DateTime.now().difference(at.toLocal());
  if (d.isNegative) return '';
  if (d.inMinutes < 1) return ' ${d.inSeconds}s';
  if (d.inHours < 1) return ' ${d.inMinutes}m';
  return ' ${d.inHours}h ${d.inMinutes % 60}m';
}

/// Quiet running status above the composer, with queued work counted at the right.
class DeskComposerRunningLine extends StatefulWidget {
  const DeskComposerRunningLine({
    super.key,
    this.startedAt,
    this.step,
    this.queued = 0,
  });

  final DateTime? startedAt;
  final String? step;
  final int queued;

  @override
  State<DeskComposerRunningLine> createState() =>
      _DeskComposerRunningLineState();
}

class _DeskComposerRunningLineState extends State<DeskComposerRunningLine> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(
        const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final step = (widget.step ?? '').trim();
    final label =
        'Running${_deskRunningElapsed(widget.startedAt)}${step.isEmpty ? '' : ' · $step'}';
    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 0, 0, 8),
      child: SizedBox(
        height: 22,
        child: Row(children: [
          SizedBox(
            width: 14,
            height: 14,
            child: Center(child: Spinner(size: 12, color: AppColors.fg3)),
          ),
          const SizedBox(width: 7),
          Expanded(
            child: Text(label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: sans(12,
                    height: 16 / 12, color: AppColors.fg2, tabular: true)),
          ),
          if (widget.queued > 0) ...[
            const SizedBox(width: 8),
            Container(
              height: 22,
              padding: const EdgeInsets.symmetric(horizontal: 8),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: AppColors.surface2,
                borderRadius: BorderRadius.circular(R.of(6)),
              ),
              child: Text(
                widget.queued == 1 ? '1 queued' : '${widget.queued} queued',
                maxLines: 1,
                style: sans(11.5, height: 15 / 11.5, color: AppColors.fg2),
              ),
            ),
          ],
        ]),
      ),
    );
  }
}

/// Running state in the control row: `Running 12s`. The header already names the agent.
class DeskRunningLabel extends StatefulWidget {
  const DeskRunningLabel({super.key, this.startedAt});

  final DateTime? startedAt;

  @override
  State<DeskRunningLabel> createState() => _DeskRunningLabelState();
}

class _DeskRunningLabelState extends State<DeskRunningLabel> {
  Timer? _tick;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(
        const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String get _elapsed => _deskRunningElapsed(widget.startedAt);

  @override
  Widget build(BuildContext context) => Text(
        'Running$_elapsed',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
        style: sans(11, color: AppColors.fg3, tabular: true),
      );
}
