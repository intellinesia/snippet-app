import 'package:flutter/material.dart';

import 'theme.dart';
import 'widgets.dart';

/// One column of a desktop settings table: a header label and its share of
/// the width.
class SettingsColumnSpec {
  const SettingsColumnSpec(this.label, {this.flex = 1});
  final String label;
  final int flex;
}

/// One table row. The first cell reads as the row's name (fg1), the rest as
/// values (fg2). [tag] follows the name (for example "Active").
class SettingsTableRowData {
  const SettingsTableRowData({
    required this.cells,
    this.leading,
    this.onTap,
    this.tag,
    this.trailing,
    this.key,
    this.monoFirst = false,
  });
  final List<String> cells;
  final Widget? leading;
  final VoidCallback? onTap;
  final Widget? tag;

  /// A quiet row action at the right edge (for example "Remove").
  final Widget? trailing;
  final Key? key;
  final bool monoFirst;
}

/// Desktop settings table (spec_settings D3): 28-high header in 11/500 fg3,
/// 32-high rows split by hairlines, a chevron on tappable rows and an
/// optional 12/400 fg3 footnote.
class SettingsTable extends StatelessWidget {
  const SettingsTable({
    super.key,
    required this.columns,
    required this.rows,
    this.empty,
    this.footnote,
    this.wrap,
  });
  final List<SettingsColumnSpec> columns;
  final List<SettingsTableRowData> rows;
  final String? empty;
  final String? footnote;

  /// Lets a caller decorate one row (deep-link target plate) by index.
  final Widget Function(int index, Widget row)? wrap;

  static const double _trail = 28;

  @override
  Widget build(BuildContext context) {
    Widget line() => Container(height: 1, color: AppColors.line);
    final header = SizedBox(
      height: 28,
      child: Row(children: [
        for (var i = 0; i < columns.length; i++)
          Expanded(
            flex: columns[i].flex,
            child: Padding(
              // The first column starts on the page edge, in line with captions.
              padding: EdgeInsets.only(left: i == 0 ? 0 : S.s8),
              child: Text(columns[i].label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(11, weight: FontWeight.w500, color: AppColors.fg3)),
            ),
          ),
        const SizedBox(width: _trail),
      ]),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        header,
        line(),
        if (rows.isEmpty && empty != null) ...[
          SizedBox(
            height: 32,
            child: Padding(
              padding: EdgeInsets.zero,
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(empty!, style: sans(12.5, color: AppColors.fg3)),
              ),
            ),
          ),
          line(),
        ],
        for (var i = 0; i < rows.length; i++) ...[
          wrap == null ? _row(rows[i]) : wrap!(i, _row(rows[i])),
          line(),
        ],
        if (footnote != null && footnote!.isNotEmpty)
          Padding(
            padding: EdgeInsets.only(top: S.s8, bottom: S.s16),
            child: Text(footnote!,
                style: sans(12, weight: W.body, color: AppColors.fg3)),
          ),
      ],
    );
  }

  Widget _row(SettingsTableRowData r) {
    final content = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: 38),
      child: Row(children: [
        for (var i = 0; i < columns.length; i++)
          Expanded(
            flex: columns[i].flex,
            child: Padding(
              padding: EdgeInsets.only(left: i == 0 ? 0 : S.s8, right: S.s8),
              child: Row(children: [
                if (i == 0 && r.leading != null) ...[
                  r.leading!,
                  const SizedBox(width: 8),
                ],
                Flexible(
                  child: Text(
                    i < r.cells.length ? r.cells[i] : '',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: i == 0
                        ? (r.monoFirst
                            ? mono(12, color: AppColors.fg1)
                            : sans(12.5, color: AppColors.fg1))
                        : sans(12.5, color: AppColors.fg2),
                  ),
                ),
                // The tag rides with the name so later columns stay aligned.
                if (i == 0 && r.tag != null) ...[
                  SizedBox(width: S.s8),
                  r.tag!,
                ],
              ]),
            ),
          ),
        if (r.trailing != null) r.trailing!,
        SizedBox(
          width: _trail,
          child: r.onTap == null
              ? null
              : Center(
                  child: AppIcon('chevron-right', size: 14, color: AppColors.fg3)),
        ),
      ]),
    );
    if (r.onTap == null) return KeyedSubtree(key: r.key, child: content);
    return _HoverRow(key: r.key, onTap: r.onTap!, child: content);
  }
}

class _HoverRow extends StatelessWidget {
  const _HoverRow({super.key, required this.onTap, required this.child});
  final VoidCallback onTap;
  final Widget child;

  @override
  Widget build(BuildContext context) => MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: onTap,
          child: child,
        ),
      );
}

/// Quiet "Active" tag for a table row: s3 chip, 11 fg2.
class SettingsTag extends StatelessWidget {
  const SettingsTag(this.label, {super.key});
  final String label;

  @override
  Widget build(BuildContext context) => Container(
        height: 20,
        padding: const EdgeInsets.symmetric(horizontal: 8),
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: AppColors.surface3,
          borderRadius: BorderRadius.circular(6),
        ),
        child: Text(label, style: sans(11, color: AppColors.fg2)),
      );
}
