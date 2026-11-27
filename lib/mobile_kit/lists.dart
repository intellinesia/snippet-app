import 'package:flutter/material.dart';

import '../tap_detector.dart';
import '../theme.dart';
import '../widgets.dart';
import 'tokens.dart';

/// Section label above a list: 13 in the third ink on iPhone, 14 medium
/// in the second ink on Android. [trailing] sits on the right ("1 finished
/// today", a count).
class MkSection extends StatelessWidget {
  const MkSection(this.label, {super.key, this.trailing, this.onTrailing});
  final String label;
  final String? trailing;
  final VoidCallback? onTrailing;

  @override
  Widget build(BuildContext context) {
    final a = kAndroidLook;
    final style = a
        ? sans(14, weight: W.label, color: AppColors.fg2)
        : sans(13, color: AppColors.fg3);
    return Semantics(
      header: true,
      child: Padding(
        padding: a
            ? const EdgeInsets.fromLTRB(28, 20, 28, 8)
            : const EdgeInsets.fromLTRB(20, 22, 20, 6),
        child: Row(children: [
          Expanded(child: Text(label, style: style)),
          if (trailing != null)
            TapDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onTrailing,
              child: Text(trailing!, style: sans(13, color: AppColors.fg3)),
            ),
        ]),
      ),
    );
  }
}

/// The list row every phone list uses: 40 leading, title and time on the
/// first line, one subtitle line, a hairline under the text column
/// (iPhone). On Android rows live inside [MkList] segments instead.
class MkRow extends StatelessWidget {
  const MkRow({
    super.key,
    required this.title,
    this.leading,
    this.subtitle,
    this.subtitleWidget,
    this.time,
    this.trailing,
    this.onTap,
    this.onLongPress,
    this.mono = false,
    this.divider = true,
    this.titleColor,
    this.semanticLabel,
  });
  final String title;
  final Widget? leading;
  final String? subtitle;

  /// Replaces [subtitle] when it needs mixed styling (bold matches).
  final Widget? subtitleWidget;
  final String? time;
  final Widget? trailing;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;

  /// Subtitle is a branch, path or command.
  final bool mono;

  /// Hairline under the text column; off for the last row.
  final bool divider;
  final Color? titleColor;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final a = kAndroidLook;
    final sub = subtitleWidget ??
        (subtitle == null || subtitle!.isEmpty
            ? null
            : Text(subtitle!,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mono ? mkMonoSub() : mkRowSub()));
    final text = Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(children: [
          Expanded(
            child: Text(title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: mkRowTitle(color: titleColor)),
          ),
          if (time != null) ...[
            const SizedBox(width: 8),
            Text(time!, style: mkTime()),
          ],
        ]),
        if (sub != null) ...[const SizedBox(height: 2), sub],
      ],
    );
    final body = Row(children: [
      if (leading != null) ...[
        SizedBox(
            width: MK.rowAvatar,
            height: MK.rowAvatar,
            child: Center(child: leading)),
        SizedBox(width: a ? 14 : 12),
      ],
      Expanded(
        child: Container(
          constraints: BoxConstraints(minHeight: a ? 68 : MK.rowMin),
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            border: !a && divider
                ? Border(bottom: BorderSide(color: MK.hairline, width: 0.5))
                : null,
          ),
          alignment: Alignment.centerLeft,
          child: Row(children: [
            Expanded(child: text),
            if (trailing != null) ...[const SizedBox(width: 10), trailing!],
          ]),
        ),
      ),
    ]);
    return Semantics(
      button: onTap != null,
      label: semanticLabel,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        splashFactory: a ? InkRipple.splashFactory : NoSplash.splashFactory,
        highlightColor: AppColors.fg1.withValues(alpha: 0.04),
        child: Padding(
          padding: EdgeInsets.symmetric(horizontal: a ? 16 : MK.gutter),
          child: body,
        ),
      ),
    );
  }
}

/// A run of rows. iPhone: plain rows on the page with hairlines.
/// Android: segmented list, each row its own surface1 tile with 4 inner
/// and 20 outer corners and 2 between.
class MkList extends StatelessWidget {
  const MkList({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    if (!kAndroidLook) return Column(children: children);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Column(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(height: 2),
          ClipRRect(
            borderRadius: _segment(i, children.length),
            child: ColoredBox(color: AppColors.surface1, child: children[i]),
          ),
        ]
      ]),
    );
  }
}

BorderRadius _segment(int i, int n) {
  const o = Radius.circular(20), r = Radius.circular(4);
  if (n == 1) return const BorderRadius.all(o);
  if (i == 0) return const BorderRadius.vertical(top: o, bottom: r);
  if (i == n - 1) return const BorderRadius.vertical(top: r, bottom: o);
  return const BorderRadius.all(r);
}

/// Settings-style group. iPhone: inset group (surface1, 22 corners) with
/// hairlines. Android: segmented tiles like [MkList].
class MkGroup extends StatelessWidget {
  const MkGroup({super.key, required this.children, this.header, this.footer});
  final List<Widget> children;
  final String? header;
  final String? footer;

  @override
  Widget build(BuildContext context) {
    final a = kAndroidLook;
    final rows = <Widget>[
      for (var i = 0; i < children.length; i++)
        _GroupIndex(last: i == children.length - 1, child: children[i]),
    ];
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (header != null)
          Padding(
            padding: a
                ? const EdgeInsets.fromLTRB(28, 20, 28, 8)
                : const EdgeInsets.fromLTRB(32, 20, 32, 6),
            child: Text(header!,
                style: a
                    ? sans(14, weight: W.label, color: AppColors.fg2)
                    : sans(13, color: AppColors.fg3)),
          ),
        if (a)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Column(children: [
              for (var i = 0; i < rows.length; i++) ...[
                if (i > 0) const SizedBox(height: 2),
                ClipRRect(
                  borderRadius: _segment(i, rows.length),
                  child: ColoredBox(color: AppColors.surface1, child: rows[i]),
                ),
              ]
            ]),
          )
        else
          Container(
            margin: const EdgeInsets.fromLTRB(16, 8, 16, 0),
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
                color: AppColors.surface1,
                borderRadius: BorderRadius.circular(MK.groupRadius)),
            child: Column(children: rows),
          ),
        if (footer != null)
          Padding(
            padding: EdgeInsets.fromLTRB(a ? 28 : 32, 8, a ? 28 : 32, 0),
            child: Text(footer!, style: sans(13, color: AppColors.fg4)),
          ),
      ],
    );
  }
}

class _GroupIndex extends InheritedWidget {
  const _GroupIndex({required this.last, required super.child});
  final bool last;
  static bool isLast(BuildContext c) =>
      c.dependOnInheritedWidgetOfExactType<_GroupIndex>()?.last ?? true;
  @override
  bool updateShouldNotify(_GroupIndex old) => old.last != last;
}

/// A row inside [MkGroup]: icon tile, label, value, chevron (iPhone) or
/// tonal icon circle with a two-line label (Android, no chevron).
class MkGroupRow extends StatelessWidget {
  const MkGroupRow({
    super.key,
    required this.label,
    this.icon,
    this.value,
    this.trailing,
    this.onTap,
    this.chevron = true,
    this.destructive = false,
    this.valueMono = false,
  });
  final String label;
  final String? icon;
  final String? value;
  final Widget? trailing;
  final VoidCallback? onTap;
  final bool chevron;
  final bool destructive;
  final bool valueMono;

  @override
  Widget build(BuildContext context) {
    final a = kAndroidLook;
    final last = _GroupIndex.isLast(context);
    final ink = destructive ? AppColors.danger : AppColors.fg1;
    final valueStyle = valueMono
        ? mono(12.5, color: AppColors.fg3)
        : sans(a ? 13.5 : 14.5, color: AppColors.fg3);
    final iconBox = icon == null
        ? null
        : Container(
            width: a ? 40 : 30,
            height: a ? 40 : 30,
            decoration: BoxDecoration(
              color: AppColors.surface3,
              shape: a ? BoxShape.circle : BoxShape.rectangle,
              borderRadius: a ? null : BorderRadius.circular(9),
            ),
            child: Center(
                child: AppIcon(icon!, size: a ? 19 : 17, color: AppColors.fg2)),
          );
    final Widget content;
    if (a) {
      content = Row(children: [
        if (iconBox != null) ...[iconBox, const SizedBox(width: 14)],
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(label, style: mkRowTitle(color: ink)),
              if (value != null && value!.isNotEmpty)
                Text(value!,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: valueStyle),
            ],
          ),
        ),
        if (trailing != null) trailing!,
      ]);
    } else {
      content = Row(children: [
        if (iconBox != null) ...[iconBox, const SizedBox(width: 12)],
        Expanded(
          child: Container(
            constraints: const BoxConstraints(minHeight: 52),
            decoration: BoxDecoration(
              border: last
                  ? null
                  : Border(bottom: BorderSide(color: MK.hairline, width: 0.5)),
            ),
            child: Row(children: [
              Expanded(
                  child: Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(15.5, color: ink))),
              if (value != null && value!.isNotEmpty)
                Flexible(
                  child: Text(value!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.right,
                      style: valueStyle),
                ),
              if (trailing != null) ...[const SizedBox(width: 8), trailing!],
              if (chevron && onTap != null && trailing == null) ...[
                const SizedBox(width: 6),
                AppIcon('chevron-right', size: 14, color: AppColors.fg4),
              ],
              const SizedBox(width: 2),
            ]),
          ),
        ),
      ]);
    }
    return Semantics(
      button: onTap != null,
      child: InkWell(
        onTap: onTap,
        splashFactory: a ? InkRipple.splashFactory : NoSplash.splashFactory,
        highlightColor: AppColors.fg1.withValues(alpha: 0.04),
        child: Padding(
          padding: a
              ? const EdgeInsets.symmetric(horizontal: 16, vertical: 12)
              : const EdgeInsets.only(left: 16, right: 14),
          child: content,
        ),
      ),
    );
  }
}
