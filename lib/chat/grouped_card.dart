import 'package:flutter/material.dart';

import '../platform.dart';
import '../settings_form.dart' show Grouped;
import '../theme.dart';
import '../widgets.dart';

BorderRadius groupedSegmentRadius({required bool first, required bool last}) {
  final end = Radius.circular(R.of(Grouped.radiusEnd));
  final inner = Radius.circular(R.of(Grouped.radiusInner));
  return BorderRadius.only(
    topLeft: first ? end : inner,
    topRight: first ? end : inner,
    bottomLeft: last ? end : inner,
    bottomRight: last ? end : inner,
  );
}

/// A chat card as grouped segments, 2px apart: pass the segments in order and
/// the first and last round at the group ends.
class GroupedCard extends StatelessWidget {
  const GroupedCard({super.key, required this.segments});
  final List<Widget> segments;

  @override
  Widget build(BuildContext context) => Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (var i = 0; i < segments.length; i++)
            Padding(
              padding: EdgeInsets.only(top: i == 0 ? 0 : Grouped.gap),
              child: Container(
                decoration: BoxDecoration(
                  color: Grouped.row,
                  borderRadius: groupedSegmentRadius(
                      first: i == 0, last: i == segments.length - 1),
                ),
                clipBehavior: Clip.antiAlias,
                child: segments[i],
              ),
            ),
        ],
      );
}

/// The header segment: leading line icon, title, sub line, trailing state.
class GroupedCardHeader extends StatelessWidget {
  const GroupedCardHeader({
    super.key,
    required this.icon,
    required this.title,
    this.sub = '',
    this.subLead = '',
    this.subLeadColor,
    this.iconColor,
    this.trailing,
    this.onTap,
  });

  final String icon;
  final String title;
  final String sub;

  /// A status word that opens the sub line in its own colour.
  final String subLead;
  final Color? subLeadColor;
  final Color? iconColor;
  final Widget? trailing;
  final VoidCallback? onTap;

  static Widget chevron() =>
      AppIcon('chevron-right', size: Grouped.chevron, color: AppColors.fg4);

  @override
  Widget build(BuildContext context) {
    final row = Container(
      constraints: BoxConstraints(minHeight: kMobile ? 64 : 56),
      padding: EdgeInsets.symmetric(
          horizontal: Grouped.padX, vertical: Grouped.padY),
      alignment: Alignment.centerLeft,
      child: Row(children: [
        AppIcon(icon, size: Grouped.icon, color: iconColor ?? AppColors.fg2),
        SizedBox(width: Grouped.iconGap),
        Expanded(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(kMobile ? 16 : 14,
                      height: kMobile ? 22 / 16 : 20 / 14,
                      color: AppColors.fg1)),
              if (sub.isNotEmpty || subLead.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text.rich(
                      TextSpan(children: [
                        if (subLead.isNotEmpty)
                          TextSpan(
                              text: subLead,
                              style: TextStyle(
                                  color: subLeadColor ?? AppColors.fg3)),
                        if (subLead.isNotEmpty && sub.isNotEmpty)
                          const TextSpan(text: ' \u00b7 '),
                        TextSpan(text: sub),
                      ]),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: sans(kMobile ? 14 : 13,
                          height: kMobile ? 20 / 14 : 18 / 13,
                          color: AppColors.fg3)),
                ),
            ],
          ),
        ),
        if (trailing != null) ...[SizedBox(width: S.s8), trailing!],
      ]),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}

/// A body segment: padding 12/16 around [child], or a muted preview [text].
class GroupedCardBody extends StatelessWidget {
  const GroupedCardBody({super.key, this.text, this.child, this.maxLines = 3, this.onTap})
      : assert(text != null || child != null);
  final String? text;
  final Widget? child;
  final int maxLines;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final body = Padding(
      padding: EdgeInsets.symmetric(horizontal: Grouped.padX, vertical: 12),
      child: Align(
        alignment: Alignment.centerLeft,
        heightFactor: 1,
        child: child ??
            Text(text!,
                maxLines: maxLines,
                overflow: TextOverflow.ellipsis,
                style: sans(kMobile ? 14 : 13,
                    height: kMobile ? 20 / 14 : 18 / 13,
                    color: AppColors.fg3)),
      ),
    );
    if (onTap == null) return SizedBox(width: double.infinity, child: body);
    return SizedBox(
        width: double.infinity, child: InkWell(onTap: onTap, child: body));
  }
}
