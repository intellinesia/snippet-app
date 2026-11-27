import 'package:flutter/material.dart';

import '../platform.dart';
import '../theme.dart';
import '../tap_detector.dart';

/// Preview and Source toggle. Each segment is a [kTapTarget] tall hit area
/// around a 28 high visual on phones; desktop uses the 28 pt pane pill itself.
class ArtifactSourceToggle extends StatelessWidget {
  const ArtifactSourceToggle(
      {super.key, required this.source, required this.onChanged});

  final bool source;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    final hit = kMobile ? kTapTarget : PaneRow.pill;
    return Container(
      decoration: BoxDecoration(
        color: kMobile ? AppColors.surface2 : Colors.transparent,
        borderRadius:
            BorderRadius.circular(kMobile ? R.md : PaneRow.radius),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        for (final (src, label) in [(false, 'Preview'), (true, 'Source')])
          TapDetector(
            behavior: HitTestBehavior.opaque,
            onTap: () => onChanged(src),
            child: Semantics(
              button: true,
              selected: source == src,
              label: label,
              excludeSemantics: true,
              child: SizedBox(
                height: hit,
                child: Center(
                  child: Container(
                    height: kMobile ? 34 : PaneRow.pill,
                    margin: EdgeInsets.symmetric(horizontal: kMobile ? 3 : 1),
                    padding: EdgeInsets.symmetric(
                        horizontal: kMobile ? S.s12 : 10),
                    alignment: Alignment.center,
                    constraints: BoxConstraints(
                        minWidth: kMobile ? kTapTarget - 6 : 0),
                    decoration: BoxDecoration(
                      color: source == src
                          ? (kMobile ? AppColors.surface3 : PaneRow.plate)
                          : null,
                      borderRadius: BorderRadius.circular(
                          kMobile ? R.sm : PaneRow.radius),
                    ),
                    child: Text(label,
                        style: sans(kMobile ? 13 : PaneRow.label,
                            weight: source == src ? W.label : W.body,
                            color: source == src
                                ? (kMobile ? AppColors.fg1 : PaneRow.labelOn)
                                : (kMobile
                                    ? AppColors.fg3
                                    : PaneRow.labelOff))),
                  ),
                ),
              ),
            ),
          ),
      ]),
    );
  }
}

/// "Version 3 . 5m ago" with a chevron when there is more than one version.
class ArtifactVersionLine extends StatelessWidget {
  const ArtifactVersionLine(
      {super.key, required this.text, required this.multi, this.onTap});

  final String text;
  final bool multi;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => TapDetector(
        behavior: HitTestBehavior.opaque,
        onTap: multi ? onTap : null,
        child: ConstrainedBox(
          constraints: BoxConstraints(
              minHeight: kMobile ? kTapTarget : PaneRow.pill),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(kMobile ? 13 : 12,
                      color: kMobile ? AppColors.fg3 : AppColors.fg4)),
            ),
            if (multi) ...[
              SizedBox(width: S.s4),
              Icon(Icons.expand_more,
                  size: kMobile ? 14 : 12,
                  color: kMobile ? AppColors.fg3 : AppColors.fg4),
            ],
          ]),
        ),
      );
}

/// A text action sized to [kTapTarget] on phones; desktop keeps the compact
/// 28 pt toolbar step.
class ArtifactActionButton extends StatelessWidget {
  const ArtifactActionButton(
      {super.key, required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) => TextButton(
        onPressed: onPressed,
        style: TextButton.styleFrom(
          visualDensity: VisualDensity.standard,
          tapTargetSize: kMobile
              ? MaterialTapTargetSize.padded
              : MaterialTapTargetSize.shrinkWrap,
          minimumSize: kMobile
              ? Size(kTapTarget, kTapTarget)
              : const Size(0, PaneRow.pill),
          padding: EdgeInsets.symmetric(horizontal: kMobile ? S.s16 : 12),
          foregroundColor: kMobile ? null : PaneRow.labelOn,
          backgroundColor: kMobile ? null : PaneRow.plate,
          shape: RoundedRectangleBorder(
              borderRadius:
                  BorderRadius.circular(kMobile ? R.sm : PaneRow.radius)),
        ),
        child: Text(label,
            style: kMobile
                ? null
                : sans(PaneRow.label, weight: W.label, color: PaneRow.labelOn)),
      );
}
