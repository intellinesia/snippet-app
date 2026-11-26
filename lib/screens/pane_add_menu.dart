import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';
import '../tap_detector.dart';

/// One row of the pane "+" menu.
class PaneAddEntry {
  const PaneAddEntry({
    required this.icon,
    required this.label,
    required this.onTap,
    this.meta,
    this.chevron = false,
    this.checked = false,
  });

  final String icon;
  final String label;
  final VoidCallback onTap;

  /// Quiet right-hand value: a count, or a running total.
  final String? meta;
  final bool chevron;
  final bool checked;
}

PopupMenuItem<VoidCallback> _row(PaneAddEntry e) => PopupMenuItem<VoidCallback>(
      value: e.onTap,
      height: 28,
      padding: EdgeInsets.symmetric(horizontal: S.of(10)),
      child: Row(children: [
        AppIcon(e.icon, size: 14, color: AppColors.fg4),
        SizedBox(width: S.of(9)),
        Expanded(
          child: Text(e.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(12.5,
                  color: Color.lerp(AppColors.fg1, AppColors.fg2, 0.3))),
        ),
        if (e.meta != null)
          Text(e.meta!, style: sans(12, color: AppColors.fg4, tabular: true)),
        if (e.chevron) ...[
          SizedBox(width: S.s4),
          AppIcon('chevron-right', size: 12, color: AppColors.fg3),
        ],
        if (e.checked) ...[
          SizedBox(width: S.s8),
          AppIcon('check', size: 14, color: AppColors.fg2),
        ],
      ]),
    );

PopupMenuItem<VoidCallback> _label(String text, {double height = 26}) =>
    PopupMenuItem<VoidCallback>(
      enabled: false,
      height: height,
      padding: EdgeInsets.symmetric(horizontal: S.of(10)),
      child: Text(text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: sans(11, color: AppColors.fg4)),
    );

/// The "+" menu of a session's pane row: the session title, the views it can
/// open beside the chat, then terminals.
Future<void> showPaneAddMenu(
  BuildContext anchor, {
  required String title,
  required List<PaneAddEntry> views,
  List<PaneAddEntry> crew = const [],
  List<PaneAddEntry> terminals = const [],
}) async {
  final fn = await showAppMenu<VoidCallback>(
    anchor,
    anchor: anchor,
    below: true,
    minWidth: 320,
    maxWidth: 320,
    color: AppColors.surface1,
    shape: RoundedRectangleBorder(
        side: BorderSide(color: AppColors.border),
        borderRadius: BorderRadius.circular(R.of(8))),
    items: [
      _label(title.trim().isEmpty ? 'Session' : title.trim(), height: 30),
      for (final e in views) _row(e),
      if (crew.isNotEmpty) ...[
        const PopupMenuDivider(height: 9),
        _label('Crew'),
        for (final e in crew) _row(e),
      ],
      if (terminals.isNotEmpty) ...[
        const PopupMenuDivider(height: 9),
        _label('Terminals'),
        for (final e in terminals) _row(e),
      ],
    ],
  );
  fn?.call();
}

/// A 26 px filled square on the pane row, the "+" beside the chips.
class StripSquareButton extends StatefulWidget {
  const StripSquareButton(
      {super.key, required this.icon, required this.tooltip, this.onTap});

  final String icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  State<StripSquareButton> createState() => _StripSquareButtonState();
}

class _StripSquareButtonState extends State<StripSquareButton> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => Tooltip(
        message: widget.tooltip,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          onEnter: (_) => setState(() => _hover = true),
          onExit: (_) => setState(() => _hover = false),
          child: TapDetector(
            onTap: widget.onTap,
            child: Container(
              width: 26,
              height: 26,
              margin: EdgeInsets.symmetric(horizontal: S.s2),
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: _hover
                    ? Color.alphaBlend(
                        AppColors.fg1.withValues(alpha: 0.06), AppColors.surface3)
                    : AppColors.surface3,
                borderRadius: BorderRadius.circular(R.of(7)),
              ),
              child: AppIcon(widget.icon,
                  size: 14, color: _hover ? AppColors.fg1 : AppColors.fg2),
            ),
          ),
        ),
      );
}

/// A pinned, always-active chip on the pane row (the panel's "Overview").
class StripChip extends StatelessWidget {
  const StripChip({super.key, required this.icon, required this.label});

  final String icon;
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        height: 26,
        margin: EdgeInsets.symmetric(horizontal: S.s2),
        padding: EdgeInsets.fromLTRB(S.of(9), 0, S.of(10), 0),
        decoration: BoxDecoration(
          color: AppColors.surface3,
          borderRadius: BorderRadius.circular(R.of(7)),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          AppIcon(icon, size: 12, color: AppColors.fg1),
          SizedBox(width: S.s6),
          Text(label, style: sans(12, color: AppColors.fg1)),
        ]),
      );
}

/// A Capy-style tab pill for a pane row (chat header, session panel).
class PanePill extends StatefulWidget {
  const PanePill(
      {super.key,
      required this.icon,
      required this.label,
      required this.active,
      this.onTap,
      this.onClose,
      this.leading});

  final String icon;

  /// Replaces the icon, e.g. an agent avatar on a chat's own pill.
  final Widget? leading;
  final String label;
  final bool active;
  final VoidCallback? onTap;
  final VoidCallback? onClose;

  @override
  State<PanePill> createState() => _PanePillState();
}

class _PanePillState extends State<PanePill> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) => MouseRegion(
        onEnter: (_) => setState(() => _hover = true),
        onExit: (_) => setState(() => _hover = false),
        cursor: widget.onTap == null
            ? MouseCursor.defer
            : SystemMouseCursors.click,
        child: TapDetector(
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Container(
            height: PaneRow.pill,
            padding: EdgeInsets.fromLTRB(
                10, 0, widget.onClose == null ? 12 : 4, 0),
            decoration: BoxDecoration(
              color: widget.active
                  ? AppColors.surface2
                  : _hover
                      ? AppColors.hoverPlate
                      : null,
              borderRadius: BorderRadius.circular(PaneRow.radius),
            ),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              widget.leading ??
                  AppIcon(widget.icon,
                      size: PaneRow.icon,
                      color: widget.active
                          ? AppColors.fg2
                          : PaneRow.labelOff),
              const SizedBox(width: 8),
              Flexible(
                child: Text(widget.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: sans(PaneRow.label,
                        color: widget.active
                            ? AppColors.fg1
                            : PaneRow.labelOff)),
              ),
              if (widget.onClose != null) ...[
                const SizedBox(width: 2),
                Opacity(
                  opacity: widget.active || _hover ? 1 : 0,
                  child: IconBtn('x',
                      size: 20,
                      iconSize: 11,
                      tooltip: 'Close tab',
                      onTap: widget.onClose),
                ),
              ],
            ]),
          ),
        ),
      );
}
