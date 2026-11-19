import 'package:flutter/material.dart';

import '../theme.dart';
import '../widgets.dart';

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
      height: 32,
      padding: EdgeInsets.symmetric(horizontal: S.of(10)),
      child: Row(children: [
        AppIcon(e.icon, size: 14, color: AppColors.fg3),
        SizedBox(width: S.of(9)),
        Expanded(
          child: Text(e.label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: sans(13, color: AppColors.fg1)),
        ),
        if (e.meta != null)
          Text(e.meta!, style: sans(12, color: AppColors.fg4, tabular: true)),
        if (e.chevron) ...[
          SizedBox(width: S.s4),
          AppIcon('chevron-right', size: 12, color: AppColors.fg4),
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
      child: Text(text, style: sans(11, color: AppColors.fg4)),
    );

/// The "+" menu of a session's pane row: the session title, the views it can
/// open beside the chat, then terminals.
Future<void> showPaneAddMenu(
  BuildContext anchor, {
  required String title,
  required List<PaneAddEntry> views,
  required List<PaneAddEntry> terminals,
}) async {
  final fn = await showAppMenu<VoidCallback>(
    anchor,
    anchor: anchor,
    below: true,
    minWidth: 264,
    maxWidth: 300,
    color: AppColors.surface2,
    shape:
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(R.of(10))),
    items: [
      _label(title.trim().isEmpty ? 'Session' : title.trim(), height: 30),
      for (final e in views) _row(e),
      const PopupMenuDivider(height: 9),
      _label('Terminals'),
      for (final e in terminals) _row(e),
    ],
  );
  fn?.call();
}
