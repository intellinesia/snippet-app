import 'package:flutter/material.dart';

import '../platform.dart';
import '../theme.dart';
import '../tap_detector.dart';

/// Preview and Source toggle. Each segment is a [kTapTarget] tall hit area
/// around a 28 high visual.
class ArtifactSourceToggle extends StatelessWidget {
  const ArtifactSourceToggle(
      {super.key, required this.source, required this.onChanged});

  final bool source;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) => Container(
        decoration: BoxDecoration(
          color: AppColors.surface2,
          borderRadius: BorderRadius.circular(R.md),
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
                  height: kTapTarget,
                  child: Center(
                    child: Container(
                      height: kMobile ? 34 : 28,
                      margin: const EdgeInsets.symmetric(horizontal: 3),
                      padding: EdgeInsets.symmetric(horizontal: S.s12),
                      alignment: Alignment.center,
                      constraints: BoxConstraints(minWidth: kTapTarget - 6),
                      decoration: BoxDecoration(
                        color: source == src ? AppColors.surface3 : null,
                        borderRadius: BorderRadius.circular(R.sm),
                      ),
                      child: Text(label,
                          style: sans(13,
                              weight: source == src ? W.label : W.body,
                              color: source == src
                                  ? AppColors.fg1
                                  : AppColors.fg3)),
                    ),
                  ),
                ),
              ),
            ),
        ]),
      );
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
          constraints: BoxConstraints(minHeight: kTapTarget),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
              child: Text(text,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: sans(13, color: AppColors.fg3)),
            ),
            if (multi) ...[
              SizedBox(width: S.s4),
              Icon(Icons.expand_more, size: 14, color: AppColors.fg3),
            ],
          ]),
        ),
      );
}

/// A text action sized to [kTapTarget] on every platform, whatever the
/// ambient visual density says.
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
          tapTargetSize: MaterialTapTargetSize.padded,
          minimumSize: Size(kTapTarget, kTapTarget),
          padding: EdgeInsets.symmetric(horizontal: S.s16),
        ),
        child: Text(label),
      );
}
